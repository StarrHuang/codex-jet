import Foundation
import Darwin

/// Reads recent token activity from local Codex session metadata. This is not
/// linked to the account used by the live quota API.
public actor LocalTokenUsageReader {
    private let sessionsRoot: URL
    private let archivedSessionsRoot: URL
    private let fileManager: FileManager
    private let calendar: Calendar
    private var fileCache: [URL: CachedSessionFile] = [:]

    public init() {
        let environment = ProcessInfo.processInfo.environment
        let codexRoot: URL
        if let configuredRoot = environment["CODEX_HOME"], !configuredRoot.isEmpty {
            codexRoot = URL(fileURLWithPath: configuredRoot, isDirectory: true)
        } else {
            codexRoot = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        self.init(
            sessionsRoot: codexRoot.appendingPathComponent("sessions", isDirectory: true),
            archivedSessionsRoot: codexRoot.appendingPathComponent("archived_sessions", isDirectory: true))
    }

    /// Explicit roots and a calendar keep reader behavior testable with temporary fixtures.
    public init(sessionsRoot: URL, archivedSessionsRoot: URL,
                calendar: Calendar? = nil, fileManager: FileManager = .default) {
        self.sessionsRoot = sessionsRoot
        self.archivedSessionsRoot = archivedSessionsRoot
        self.calendar = calendar ?? Self.shanghaiCalendar
        self.fileManager = fileManager
    }

    public func read(now: Date = Date()) throws -> LocalTokenReport {
        let cutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        var warnings: [String] = []
        var candidates: [URL: FileMetadata] = [:]

        if fileManager.fileExists(atPath: sessionsRoot.path) {
            guard let enumerator = fileManager.enumerator(
                at: sessionsRoot,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]) else {
                throw LocalTokenUsageError.cannotEnumerate(sessionsRoot.path)
            }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
                guard values.isRegularFile == true,
                      let modified = values.contentModificationDate,
                      modified >= cutoff else { continue }
                candidates[url.standardizedFileURL] = FileMetadata(
                    size: Int64(values.fileSize ?? 0), modified: modified,
                    identity: try fileIdentity(url))
            }
        } else {
            warnings.append("未找到本机 Codex 会话日志目录。")
        }

        if fileManager.fileExists(atPath: archivedSessionsRoot.path) {
            let urls = try fileManager.contentsOfDirectory(
                at: archivedSessionsRoot, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles])
            for url in urls where url.pathExtension == "jsonl" {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
                guard values.isRegularFile == true,
                      let modified = values.contentModificationDate else { continue }
                guard modified >= cutoff || archiveFilenameIsRecent(url, cutoff: cutoff, now: now) else { continue }
                candidates[url.standardizedFileURL] = FileMetadata(
                    size: Int64(values.fileSize ?? 0), modified: modified,
                    identity: try fileIdentity(url))
            }
        }

        var selected: [URL: CachedSessionFile] = [:]
        for url in candidates.keys.sorted(by: { $0.path < $1.path }) {
            guard let metadata = candidates[url] else { continue }
            if let cached = fileCache[url], cached.metadata == metadata, cached.retainedFrom <= cutoff {
                selected[url] = cached
            } else if let cached = fileCache[url], cached.metadata.identity == metadata.identity,
                      metadata.size > cached.metadata.size, cached.retainedFrom <= cutoff,
                      !cached.hasUnterminatedTail,
                      prefixMatches(url, offset: cached.readOffset, expectedTail: cached.boundaryTail) {
                let appended = try parseFile(url, metadata: metadata, cutoff: cutoff, offset: cached.readOffset)
                selected[url] = CachedSessionFile(
                    metadata: metadata, retainedFrom: cached.retainedFrom,
                    modelsByTurn: merge(cached.modelsByTurn, appended.modelsByTurn),
                    records: cached.records + appended.records,
                    incompleteUsageCount: cached.incompleteUsageCount + appended.incompleteUsageCount,
                    malformedLineCount: cached.malformedLineCount + appended.malformedLineCount,
                    legacyTokenCount: cached.legacyTokenCount + appended.legacyTokenCount,
                    readOffset: appended.readOffset, boundaryTail: appended.boundaryTail,
                    hasUnterminatedTail: appended.hasUnterminatedTail)
            } else {
                let parsed = try parseFile(url, metadata: metadata, cutoff: cutoff, offset: 0)
                fileCache[url] = parsed
                selected[url] = parsed
            }
            if let parsed = selected[url] { fileCache[url] = parsed }
        }
        fileCache = fileCache.filter { url, _ in candidates[url] != nil }

        var warningsCounts = WarningCounts()
        var latestEventAt: Date?
        var seenResponseIDs = Set<String>()
        var aggregates: [HourlyModelTokensKey: HourlyModelTokens] = [:]
        for file in selected.keys.sorted(by: { $0.path < $1.path }) {
            guard let parsed = selected[file] else { continue }
            warningsCounts.incomplete += parsed.incompleteUsageCount
            warningsCounts.malformed += parsed.malformedLineCount
            warningsCounts.legacy += parsed.legacyTokenCount > 0 && parsed.records.isEmpty ? 1 : 0
            for record in parsed.records where record.timestamp >= cutoff && record.timestamp <= now {
                guard seenResponseIDs.insert(record.responseID).inserted else {
                    warningsCounts.duplicates += 1
                    continue
                }
                if latestEventAt == nil || record.timestamp > latestEventAt! {
                    latestEventAt = record.timestamp
                }
                guard let models = parsed.modelsByTurn[record.turnID], models.count == 1,
                      let model = models.first else {
                    warningsCounts.unknownModel += 1
                    add(record, model: "未知模型", to: &aggregates)
                    continue
                }
                add(record, model: model, to: &aggregates)
            }
        }

        if warningsCounts.unknownModel > 0 {
            warnings.append("\(warningsCounts.unknownModel) 条记录无法确认对应模型，已归入“未知模型”。")
        }
        if warningsCounts.duplicates > 0 {
            warnings.append("已跳过 \(warningsCounts.duplicates) 条重复的响应记录。")
        }
        if warningsCounts.incomplete > 0 {
            warnings.append("已排除 \(warningsCounts.incomplete) 条计数器不完整或无效的记录。")
        }
        if warningsCounts.malformed > 0 {
            warnings.append("已忽略 \(warningsCounts.malformed) 条格式错误的用量元数据。")
        }
        if warningsCounts.legacy > 0 {
            warnings.append("\(warningsCounts.legacy) 个近期日志只有累计计数，没有逐次增量记录，未换算为小时用量。")
        }

        let rows = aggregates.values.sorted {
            if $0.hour != $1.hour { return $0.hour < $1.hour }
            return $0.model.localizedStandardCompare($1.model) == .orderedAscending
        }
        return LocalTokenReport(generatedAt: now, rows: rows, filesRead: candidates.count,
                                latestEventAt: latestEventAt, warnings: warnings)
    }

    private func add(_ record: PendingUsage, model: String,
                     to aggregates: inout [HourlyModelTokensKey: HourlyModelTokens]) {
        let hour = calendar.dateInterval(of: .hour, for: record.timestamp)?.start ?? record.timestamp
        let key = HourlyModelTokensKey(hour: hour, model: model)
        var row = aggregates[key] ?? HourlyModelTokens(
            hour: hour, model: model, inputTokens: 0, cachedInputTokens: 0,
            outputTokens: 0, reasoningOutputTokens: 0, totalTokens: 0, eventCount: 0)
        row.inputTokens += record.usage.inputTokens
        row.cachedInputTokens += record.usage.cachedInputTokens
        row.outputTokens += record.usage.outputTokens
        row.reasoningOutputTokens += record.usage.reasoningOutputTokens
        row.totalTokens += record.usage.totalTokens
        row.eventCount += 1
        aggregates[key] = row
    }

    private func parseFile(_ url: URL, metadata: FileMetadata, cutoff: Date,
                           offset: Int64) throws -> CachedSessionFile {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        var modelsByTurn: [String: Set<String>] = [:]
        var records: [PendingUsage] = []
        var incompleteUsageCount = 0
        var malformedLineCount = 0
        var legacyTokenCount = 0
        var readOffset = offset
        var hasUnterminatedTail = false
        let stream = url.withUnsafeFileSystemRepresentation { path -> UnsafeMutablePointer<FILE>? in
            guard let path else { return nil }
            return fopen(path, "rb")
        }
        guard let stream else { throw LocalTokenUsageError.cannotOpen(url.path) }
        defer { fclose(stream) }
        if offset > 0 && fseeko(stream, off_t(offset), SEEK_SET) != 0 {
            throw LocalTokenUsageError.cannotSeek(url.path)
        }
        var linePointer: UnsafeMutablePointer<CChar>?
        var lineCapacity = 0
        defer { if let linePointer { free(linePointer) } }

        func consume(_ bytes: UnsafePointer<UInt8>, length: Int) {
            let envelopeType = topLevelType(bytes, length: length)
            if let envelopeType,
               envelopeType != "turn_context" && envelopeType != "token_usage_record" && envelopeType != "event_msg" {
                return
            }
            let data = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes),
                            count: length, deallocator: .none)
            guard let parsed = try? decoder.decode(SessionMetadataLine.self, from: data),
                  let payload = parsed.payload else {
                malformedLineCount += 1
                return
            }
            if parsed.type == "turn_context" {
                if let turnID = payload.turnID, let model = payload.model, !model.isEmpty {
                    modelsByTurn[turnID, default: []].insert(model)
                }
                return
            }
            if parsed.type == "event_msg", payload.eventType == "token_count" {
                legacyTokenCount += 1
                return
            }
            guard parsed.type == "token_usage_record" else { return }
            guard let turnID = payload.turnID, let responseID = payload.responseID,
                  let partialUsage = payload.usage,
                  let usage = partialUsage.completeUsage,
                  usage.isValid,
                  let timestampString = parsed.timestamp,
                  let timestamp = formatter.date(from: timestampString) ?? fallbackFormatter.date(from: timestampString)
            else {
                incompleteUsageCount += 1
                return
            }
            guard timestamp >= cutoff else { return }
            records.append(PendingUsage(turnID: turnID, responseID: responseID,
                                        timestamp: timestamp, usage: usage))
        }

        while true {
            let bytesRead = getline(&linePointer, &lineCapacity, stream)
            guard bytesRead >= 0, let linePointer else { break }
            let length = Int(bytesRead)
            let bytes = UnsafeRawPointer(linePointer).assumingMemoryBound(to: UInt8.self)
            guard length > 0 else { break }
            if bytes[length - 1] != 0x0A {
                consume(bytes, length: length)
                hasUnterminatedTail = true
                break
            }
            consume(bytes, length: length)
            readOffset += Int64(length)
        }
        if ferror(stream) != 0 { throw LocalTokenUsageError.cannotRead(url.path) }
        let tail = lastCompleteLineTail(fileSize: readOffset, stream: stream)
        return CachedSessionFile(metadata: metadata, retainedFrom: cutoff,
                                 modelsByTurn: modelsByTurn, records: records,
                                 incompleteUsageCount: incompleteUsageCount,
                                 malformedLineCount: malformedLineCount,
                                 legacyTokenCount: legacyTokenCount,
                                 readOffset: readOffset, boundaryTail: tail,
                                 hasUnterminatedTail: hasUnterminatedTail)
    }

    private func topLevelType(_ bytes: UnsafePointer<UInt8>, length: Int) -> String? {
        var index = 0
        skipWhitespace(bytes, length: length, index: &index)
        guard index < length, bytes[index] == 0x7B else { return nil }
        index += 1
        while index < length {
            skipWhitespace(bytes, length: length, index: &index)
            guard index < length, bytes[index] == 0x22,
                  let (keyStart, keyEnd) = scanString(bytes, length: length, index: &index) else { return nil }
            skipWhitespace(bytes, length: length, index: &index)
            guard index < length, bytes[index] == 0x3A else { return nil }
            index += 1
            skipWhitespace(bytes, length: length, index: &index)
            if stringEquals(bytes, start: keyStart, end: keyEnd, value: "type") {
                guard index < length, bytes[index] == 0x22,
                      let (valueStart, valueEnd) = scanString(bytes, length: length, index: &index) else { return nil }
                for offset in valueStart..<valueEnd where bytes[offset] == 0x5C { return nil }
                return String(decoding: UnsafeBufferPointer(start: bytes.advanced(by: valueStart), count: valueEnd - valueStart), as: UTF8.self)
            }
            // Current Codex JSONL places `type` before the potentially large
            // payload. If a future envelope changes that order, use JSONDecoder
            // below as the compatibility fallback.
            if stringEquals(bytes, start: keyStart, end: keyEnd, value: "payload") { return nil }
            guard skipScalar(bytes, length: length, index: &index) else { return nil }
            skipWhitespace(bytes, length: length, index: &index)
            guard index < length else { return nil }
            if bytes[index] == 0x2C { index += 1; continue }
            if bytes[index] == 0x7D { return nil }
            return nil
        }
        return nil
    }

    private func scanString(_ bytes: UnsafePointer<UInt8>, length: Int,
                            index: inout Int) -> (Int, Int)? {
        guard index < length, bytes[index] == 0x22 else { return nil }
        index += 1
        let start = index
        var escaped = false
        while index < length {
            let byte = bytes[index]
            if escaped { escaped = false }
            else if byte == 0x5C { escaped = true }
            else if byte == 0x22 {
                let end = index
                index += 1
                return (start, end)
            }
            index += 1
        }
        return nil
    }

    private func stringEquals(_ bytes: UnsafePointer<UInt8>, start: Int, end: Int, value: StaticString) -> Bool {
        let expected = value.utf8Start
        let count = Int(value.utf8CodeUnitCount)
        guard end - start == count else { return false }
        for offset in 0..<count where bytes[start + offset] != expected[offset] { return false }
        return true
    }

    private func skipScalar(_ bytes: UnsafePointer<UInt8>, length: Int, index: inout Int) -> Bool {
        guard index < length else { return false }
        if bytes[index] == 0x22 { return scanString(bytes, length: length, index: &index) != nil }
        while index < length && bytes[index] != 0x2C && bytes[index] != 0x7D { index += 1 }
        return index > 0
    }

    private func skipWhitespace(_ bytes: UnsafePointer<UInt8>, length: Int, index: inout Int) {
        while index < length && (bytes[index] == 0x20 || bytes[index] == 0x09 || bytes[index] == 0x0A || bytes[index] == 0x0D) {
            index += 1
        }
    }

    private func lastCompleteLineTail(fileSize: Int64, stream: UnsafeMutablePointer<FILE>) -> [UInt8] {
        let tailLength = Int(min(128, fileSize))
        guard tailLength > 0 else { return [] }
        var tail = [UInt8](repeating: 0, count: tailLength)
        let read = tail.withUnsafeMutableBytes { buffer in
            pread(fileno(stream), buffer.baseAddress, tailLength, off_t(fileSize - Int64(tailLength)))
        }
        guard read == tailLength else { return [] }
        return tail
    }

    private func merge(_ lhs: [String: Set<String>], _ rhs: [String: Set<String>]) -> [String: Set<String>] {
        var result = lhs
        for (turnID, models) in rhs { result[turnID, default: []].formUnion(models) }
        return result
    }

    private func fileIdentity(_ url: URL) throws -> String {
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else { throw LocalTokenUsageError.cannotStat(url.path) }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard Darwin.fstat(descriptor, &info) == 0 else { throw LocalTokenUsageError.cannotStat(url.path) }
        return "\(info.st_dev):\(info.st_ino)"
    }

    private func prefixMatches(_ url: URL, offset: Int64, expectedTail: [UInt8]) -> Bool {
        guard offset > 0, !expectedTail.isEmpty else { return true }
        let descriptor = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return Darwin.open(path, O_RDONLY)
        }
        guard descriptor >= 0 else { return false }
        defer { Darwin.close(descriptor) }
        var current = [UInt8](repeating: 0, count: expectedTail.count)
        let count = current.withUnsafeMutableBytes { buffer in
            pread(descriptor, buffer.baseAddress, expectedTail.count,
                  off_t(offset - Int64(expectedTail.count)))
        }
        return count == expectedTail.count && current == expectedTail
    }

    private func archiveFilenameIsRecent(_ url: URL, cutoff: Date, now: Date) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("rollout-"), let separator = name.firstIndex(of: "T") else { return false }
        let dateString = String(name[name.index(name.startIndex, offsetBy: "rollout-".count)..<separator])
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString),
              let day = calendar.dateInterval(of: .day, for: date)?.start else { return false }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        return nextDay > cutoff && day <= now
    }

    private static var shanghaiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }
}

private struct CachedSessionFile {
    let metadata: FileMetadata
    let retainedFrom: Date
    let modelsByTurn: [String: Set<String>]
    let records: [PendingUsage]
    let incompleteUsageCount: Int
    let malformedLineCount: Int
    let legacyTokenCount: Int
    let readOffset: Int64
    let boundaryTail: [UInt8]
    let hasUnterminatedTail: Bool
}

private struct FileMetadata: Equatable {
    let size: Int64
    let modified: Date
    let identity: String
}

private struct PendingUsage {
    let turnID: String
    let responseID: String
    let timestamp: Date
    let usage: TokenUsage
}

private struct HourlyModelTokensKey: Hashable {
    let hour: Date
    let model: String
}

private struct WarningCounts {
    var unknownModel = 0
    var duplicates = 0
    var incomplete = 0
    var malformed = 0
    var legacy = 0
}

private struct SessionMetadataLine: Decodable {
    let timestamp: String?
    let type: String
    let payload: SessionMetadataPayload?
}

private struct SessionMetadataPayload: Decodable {
    let turnID: String?
    let model: String?
    let responseID: String?
    let usage: PartialTokenUsage?
    let eventType: String?

    enum CodingKeys: String, CodingKey {
        case turnID = "turn_id"
        case model
        case responseID = "response_id"
        case usage
        case eventType = "type"
    }
}

private struct PartialTokenUsage: Decodable {
    let inputTokens: Int64?
    let cachedInputTokens: Int64?
    let cacheWriteInputTokens: Int64?
    let outputTokens: Int64?
    let reasoningOutputTokens: Int64?
    let totalTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cachedInputTokens = "cached_input_tokens"
        case cacheWriteInputTokens = "cache_write_input_tokens"
        case outputTokens = "output_tokens"
        case reasoningOutputTokens = "reasoning_output_tokens"
        case totalTokens = "total_tokens"
    }

    var completeUsage: TokenUsage? {
        guard let inputTokens, let cachedInputTokens, let cacheWriteInputTokens, let outputTokens,
              let reasoningOutputTokens, let totalTokens else { return nil }
        return TokenUsage(inputTokens: inputTokens, cachedInputTokens: cachedInputTokens,
                          cacheWriteInputTokens: cacheWriteInputTokens,
                          outputTokens: outputTokens, reasoningOutputTokens: reasoningOutputTokens,
                          totalTokens: totalTokens)
    }
}

private struct TokenUsage {
    let inputTokens: Int64
    let cachedInputTokens: Int64
    let cacheWriteInputTokens: Int64
    let outputTokens: Int64
    let reasoningOutputTokens: Int64
    let totalTokens: Int64

    var isValid: Bool {
        let (sum, overflow) = inputTokens.addingReportingOverflow(outputTokens)
        return !overflow && inputTokens >= 0 && cachedInputTokens >= 0 && cacheWriteInputTokens >= 0
            && outputTokens >= 0 && reasoningOutputTokens >= 0 && totalTokens >= 0
            && cachedInputTokens <= inputTokens && cacheWriteInputTokens <= inputTokens
            && reasoningOutputTokens <= outputTokens && sum == totalTokens
    }
}

private enum LocalTokenUsageError: Error {
    case cannotEnumerate(String)
    case cannotOpen(String)
    case cannotSeek(String)
    case cannotRead(String)
    case cannotStat(String)
}

extension LocalTokenUsageError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .cannotEnumerate: "无法枚举本机 Codex 会话日志。"
        case .cannotOpen: "无法打开本机 Codex 会话日志。"
        case .cannotSeek: "无法定位本机 Codex 会话日志。"
        case .cannotRead: "无法读取本机 Codex 会话日志。"
        case .cannotStat: "无法读取本机 Codex 会话日志元数据。"
        }
    }
}
