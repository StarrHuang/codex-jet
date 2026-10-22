import Foundation
import ResetCore

@main
struct LocalTokenUsageTests {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codexreset-token-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let archives = root.appendingPathComponent("archived_sessions", isDirectory: true)
        let activeFile = sessions.appendingPathComponent("2026/10/01/active.jsonl")
        let incrementalFile = sessions.appendingPathComponent("2026/10/02/incremental.jsonl")
        let archiveFile = archives.appendingPathComponent("rollout-2026-10-12T00-00-00-copy.jsonl")
        let legacyFile = sessions.appendingPathComponent("2026/09/01/legacy.jsonl")
        try FileManager.default.createDirectory(at: activeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archiveFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: legacyFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        let now = date("2026-10-13T04:30:00Z")
        try FileManager.default.createDirectory(at: incrementalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        var activeLines = [
            turn("alpha-turn", model: "Alpha"),
            usage("alpha-turn", response: "duplicate-response", at: "2026-10-13T02:59:00Z",
                  input: 100, cached: 30, cacheWrite: 10, output: 20, reasoning: 7),
            usage("alpha-turn", response: "alpha-next-hour", at: "2026-10-13T03:01:00Z",
                  input: 50, cached: 20, cacheWrite: 0, output: 10, reasoning: 3),
            usage("alpha-turn", response: "at-cutoff", at: "2026-10-06T04:30:00Z",
                  input: 6, cached: 2, cacheWrite: 1, output: 1, reasoning: 0),
            usage("alpha-turn", response: "before-cutoff", at: "2026-10-06T04:29:59Z",
                  input: 600, cached: 0, cacheWrite: 0, output: 60, reasoning: 0),
            usage("alpha-turn", response: "future", at: "2026-10-13T04:31:00Z",
                  input: 700, cached: 0, cacheWrite: 0, output: 70, reasoning: 0),
            turn("ambiguous-turn", model: "Gamma"),
            turn("ambiguous-turn", model: "Delta"),
            usage("ambiguous-turn", response: "ambiguous-model", at: "2026-10-12T14:15:00Z",
                  input: 8, cached: 1, cacheWrite: 0, output: 2, reasoning: 1),
            usage("missing-context", response: "unknown-model", at: "2026-10-12T14:20:00Z",
                  input: 9, cached: 2, cacheWrite: 0, output: 3, reasoning: 1),
            incompleteUsage("alpha-turn", response: "incomplete", at: "2026-10-12T14:25:00Z"),
        ]
        activeLines.append("{\"type\":\"token_usage_record\"")
        try writeLines(activeLines, to: activeFile)
        try appendRaw(usage("alpha-turn", response: "complete-eof-record", at: "2026-10-13T04:29:00Z",
                            input: 3, cached: 1, cacheWrite: 0, output: 1, reasoning: 0), to: activeFile)
        let escapedUsage = usage("epsilon-turn", response: "escaped-type", at: "2026-10-12T12:05:00Z",
                                 input: 2, cached: 1, cacheWrite: 0, output: 1, reasoning: 0)
            .replacingOccurrences(of: "\"type\":\"token_usage_record\"",
                                  with: "\"type\":\"token_\\u0075sage_record\"")
        try writeLines([
            turn("epsilon-turn", model: "Epsilon"),
            usage("epsilon-turn", response: "epsilon-initial", at: "2026-10-12T12:00:00Z",
                  input: 1, cached: 0, cacheWrite: 0, output: 1, reasoning: 0),
            escapedUsage,
        ], to: incrementalFile)
        try writeLines([
            turn("alpha-turn", model: "Alpha"),
            usage("alpha-turn", response: "duplicate-response", at: "2026-10-13T02:59:00Z",
                  input: 100, cached: 30, cacheWrite: 10, output: 20, reasoning: 7),
            turn("beta-turn", model: "Beta"),
            usage("beta-turn", response: "beta-response", at: "2026-10-13T03:01:00Z",
                  input: 10, cached: 2, cacheWrite: 1, output: 5, reasoning: 2),
        ], to: archiveFile)
        try writeLines([event("token_count")], to: legacyFile)
        for file in [activeFile, incrementalFile, legacyFile] {
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path)
        }

        let reader = LocalTokenUsageReader(sessionsRoot: sessions, archivedSessionsRoot: archives)
        let first = try await reader.read(now: now)
        try expect(first.filesRead == 4, "active older session and recent archive files are discovered")
        try expect(first.rows.reduce(0) { $0 + $1.eventCount } == 9, "duplicate, cutoff, future, and incomplete records are handled")
        try expect(first.rows.reduce(Int64(0)) { $0 + $1.totalTokens } == 233, "usage counters are additive without cumulative snapshots")
        try expect(first.warnings.contains { $0.contains("重复的响应记录") }, "copied response IDs are deduplicated")
        try expect(first.warnings.contains { $0.contains("未知模型") }, "missing and ambiguous models are labeled")
        try expect(first.warnings.contains { $0.contains("计数器不完整") }, "incomplete usage is reported")
        try expect(first.warnings.contains { $0.contains("累计计数") }, "legacy cumulative-only coverage is reported")
        try expect(first.warnings.contains { $0.contains("格式错误") }, "malformed trailing data is reported")

        let alpha10 = try row(first, hour: "2026-10-13T02:00:00Z", model: "Alpha")
        try expect(alpha10.inputTokens == 100 && alpha10.cachedInputTokens == 30
                   && alpha10.outputTokens == 20 && alpha10.reasoningOutputTokens == 7
                   && alpha10.totalTokens == 120 && alpha10.eventCount == 1,
                   "cached and reasoning counters remain subsets of the provided totals")
        let alpha11 = try row(first, hour: "2026-10-13T03:00:00Z", model: "Alpha")
        try expect(alpha11.inputTokens == 50 && alpha11.totalTokens == 60, "Shanghai hour bucketing follows the event timestamp")
        let beta11 = try row(first, hour: "2026-10-13T03:00:00Z", model: "Beta")
        try expect(beta11.totalTokens == 15 && beta11.eventCount == 1, "model switch attribution uses the turn context")
        let unknown = try row(first, hour: "2026-10-12T14:00:00Z", model: "未知模型")
        try expect(unknown.eventCount == 2 && unknown.totalTokens == 22, "unknown and ambiguous context are retained under one label")
        let epsilon = try row(first, hour: "2026-10-12T12:00:00Z", model: "Epsilon")
        try expect(epsilon.eventCount == 2 && epsilon.totalTokens == 5, "escaped top-level type values use the JSON decoder fallback")
        let cutoffHour = try row(first, hour: "2026-10-06T04:00:00Z", model: "Alpha")
        try expect(cutoffHour.totalTokens == 7, "the rolling seven-day cutoff is inclusive")

        let second = try await reader.read(now: now)
        try expect(second.rows == first.rows, "repeated refresh does not add cached records twice")

        try appendRaw("\n", to: activeFile)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(1)], ofItemAtPath: activeFile.path)
        let terminatedTail = try await reader.read(now: now)
        try expect(terminatedTail.rows == first.rows, "a valid EOF record is not double-counted when its newline arrives")

        let afterFutureEvent = try await reader.read(now: now.addingTimeInterval(60))
        let afterFutureTotal = afterFutureEvent.rows.reduce(Int64(0)) { $0 + $1.totalTokens }
        try expect(afterFutureTotal == 996,
                   "a cached future-dated record appears when the clock reaches it (total \(afterFutureTotal))")

        try appendLine(usage("epsilon-turn", response: "new-after-refresh", at: "2026-10-13T03:10:00Z",
                             input: 20, cached: 5, cacheWrite: 0, output: 5, reasoning: 2), to: incrementalFile)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(2)], ofItemAtPath: incrementalFile.path)
        let refreshed = try await reader.read(now: now.addingTimeInterval(60))
        try expect(refreshed.rows.reduce(Int64(0)) { $0 + $1.totalTokens } == 1021,
                   "a changed active file refreshes without replaying stale counters")
        print("Local token usage tests passed")
    }

    private static func row(_ report: LocalTokenReport, hour: String, model: String) throws -> HourlyModelTokens {
        let expectedHour = date(hour)
        guard let row = report.rows.first(where: { $0.hour == expectedHour && $0.model == model }) else {
            throw TestFailure(message: "missing expected hour/model row")
        }
        return row
    }

    private static func turn(_ turnID: String, model: String) -> String {
        json(["type": "turn_context", "payload": ["turn_id": turnID, "model": model]])
    }

    private static func usage(_ turnID: String, response: String, at timestamp: String,
                              input: Int, cached: Int, cacheWrite: Int, output: Int, reasoning: Int) -> String {
        json(["timestamp": timestamp, "type": "token_usage_record", "payload": [
            "turn_id": turnID, "response_id": response,
            "usage": ["input_tokens": input, "cached_input_tokens": cached,
                      "cache_write_input_tokens": cacheWrite, "output_tokens": output,
                      "reasoning_output_tokens": reasoning, "total_tokens": input + output],
        ]])
    }

    private static func incompleteUsage(_ turnID: String, response: String, at timestamp: String) -> String {
        json(["timestamp": timestamp, "type": "token_usage_record", "payload": [
            "turn_id": turnID, "response_id": response,
            "usage": ["input_tokens": 1, "output_tokens": 1, "total_tokens": 2],
        ]])
    }

    private static func event(_ eventType: String) -> String {
        json(["type": "event_msg", "payload": ["type": eventType]])
    }

    private static func json(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func writeLines(_ lines: [String], to url: URL) throws {
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        try data.write(to: url)
    }

    private static func appendLine(_ line: String, to url: URL) throws {
        try appendRaw(line + "\n", to: url)
    }

    private static func appendRaw(_ value: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(value.utf8))
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message: message) }
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
