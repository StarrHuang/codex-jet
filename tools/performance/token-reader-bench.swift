import CryptoKit
import Darwin
import Foundation

@main
struct TokenReaderBench {
    private static let baseNow = date("2026-10-13T12:00:00Z")
    private static let day: TimeInterval = 24 * 60 * 60

    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else {
            throw BenchFailure(message: "usage: token-reader-bench --prepare ROOT | --run MODE ROOT")
        }
        switch command {
        case "--prepare":
            guard arguments.count == 2 else {
                throw BenchFailure(message: "usage: token-reader-bench --prepare ROOT")
            }
            try prepare(URL(fileURLWithPath: arguments[1], isDirectory: true))
        case "--run":
            guard arguments.count == 3 else {
                throw BenchFailure(message: "usage: token-reader-bench --run MODE ROOT")
            }
            let mode = arguments[1]
            let root = URL(fileURLWithPath: arguments[2], isDirectory: true)
            let result = try await run(mode: mode, root: root)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        default:
            throw BenchFailure(message: "unknown mode")
        }
    }

    private static func prepare(_ root: URL) throws {
        let manager = FileManager.default
        guard !manager.fileExists(atPath: root.path) else {
            throw BenchFailure(message: "fixture path already exists: \(root.path)")
        }
        let session = sessionFile(root)
        try manager.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: archiveRoot(root), withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var output = Data()
        output.reserveCapacity(40 * 1024 * 1024)
        for index in 0..<100_000 {
            if index % 10 == 0 {
                let turn = turnID(index / 10)
                appendLine(jsonLine(type: "turn_context", payload: "\"turn_id\":\"\(turn)\",\"model\":\"model-\((index / 10) % 5)\""), to: &output)
            }
            let turn = turnID(index / 10)
            let seconds = Int64((Double(index) / 100_000.0) * (6.8 * day))
            let timestamp = formatter.string(from: baseNow.addingTimeInterval(-6.8 * day + Double(seconds)))
            appendLine(usageLine(turn: turn, response: "base-\(index)", timestamp: timestamp), to: &output)
            appendLine("{\"type\":\"response_item\",\"payload\":{\"kind\":\"message\",\"text\":\"synthetic fixture padding\"}}", to: &output)
            appendLine("{\"type\":\"response_item\",\"payload\":{\"kind\":\"tool_call\",\"text\":\"synthetic fixture padding\"}}", to: &output)
        }
        try output.write(to: session)
        try manager.setAttributes([.modificationDate: baseNow], ofItemAtPath: session.path)
        let manifest: [String: Any] = [
            "fixture": "deterministic synthetic JSONL; no user session data",
            "base_usage_records": 100_000,
            "turns": 10_000,
            "noise_lines_per_usage": 2,
            "bytes": output.count,
            "sha256": sha256(output),
            "now": ISO8601DateFormatter().string(from: baseNow),
        ]
        let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
        try manifestData.write(to: root.appendingPathComponent("fixture-manifest.json"))
        print(String(decoding: manifestData, as: UTF8.self))
    }

    private static func run(mode: String, root: URL) async throws -> [String: Any] {
        let manager = FileManager.default
        let session = sessionFile(root)
        guard manager.fileExists(atPath: session.path) else {
            throw BenchFailure(message: "missing prepared fixture: \(session.path)")
        }
        let initialBytes = try fileSize(session)
        let initialHash = try sha256(Data(contentsOf: session, options: [.mappedIfSafe]))
        let reader = LocalTokenUsageReader(sessionsRoot: root.appendingPathComponent("sessions", isDirectory: true),
                                           archivedSessionsRoot: archiveRoot(root))
        var reportDigests: [String] = []
        var readMilliseconds: [Double] = []
        var logicalParseBytes = initialBytes
        let wallStart = monotonic()
        let cpuStart = processCPU()
        let first = try await timedRead(reader, now: baseNow)
        readMilliseconds.append(first.milliseconds)
        reportDigests.append(first.digest)
        var appendedBytes: Int64 = 0
        var steadyMilliseconds: [Double] = []
        var warmupReads = 0

        switch mode {
        case "cold":
            break
        case "appendcache", "warm":
            for dayIndex in 0..<40 {
                let appendResult = try appendDailyRecords(dayIndex: dayIndex, to: session)
                appendedBytes += Int64(appendResult)
                let now = baseNow.addingTimeInterval(Double(dayIndex + 1) * day)
                try manager.setAttributes([.modificationDate: now], ofItemAtPath: session.path)
                let measured = try await timedRead(reader, now: now)
                readMilliseconds.append(measured.milliseconds)
                reportDigests.append(measured.digest)
                logicalParseBytes += Int64(appendResult)
            }
            warmupReads = 40
            if mode == "warm" {
                let steadyNow = baseNow.addingTimeInterval(40.0 * day)
                for _ in 0..<20 {
                    let measured = try await timedRead(reader, now: steadyNow)
                    steadyMilliseconds.append(measured.milliseconds)
                    reportDigests.append(measured.digest)
                }
            }
        default:
            throw BenchFailure(message: "unknown benchmark mode: \(mode)")
        }
        let cpuEnd = processCPU()
        let elapsed = monotonic() - wallStart
        let peakRSS = maximumResidentSetSize()
        let reportChain = reportDigests.joined(separator: "\n")
        let finalReport = reportDigests.last ?? ""
        return [
            "mode": mode,
            "fixture_initial_bytes": initialBytes,
            "fixture_final_bytes": try fileSize(session),
            "fixture_initial_sha256": initialHash,
            "fixture_final_sha256": try sha256(Data(contentsOf: session, options: [.mappedIfSafe])),
            "reads": readMilliseconds.count + steadyMilliseconds.count,
            "read_ms_mean": mean(readMilliseconds),
            "read_ms_max": readMilliseconds.max() ?? 0,
            "steady_reads": steadyMilliseconds.count,
            "steady_read_ms_mean": mean(steadyMilliseconds),
            "steady_read_ms_min": steadyMilliseconds.min() ?? 0,
            "logical_parse_bytes_from_fixture_offsets": logicalParseBytes,
            "appended_fixture_bytes": appendedBytes,
            "report_hash_chain_sha256": sha256(Data(reportChain.utf8)),
            "final_report_sha256": finalReport,
            "wall_seconds": elapsed,
            "cpu_seconds": cpuEnd - cpuStart,
            "cpu_percent_one_core": elapsed > 0 ? (cpuEnd - cpuStart) / elapsed * 100 : 0,
            "peak_rss_bytes": peakRSS,
            "initial_read_ms": readMilliseconds.first ?? 0,
            "append_reads": warmupReads,
        ]
    }

    private static func timedRead(_ reader: LocalTokenUsageReader, now: Date) async throws -> (milliseconds: Double, digest: String) {
        let start = monotonic()
        let report = try await reader.read(now: now)
        return ((monotonic() - start) * 1000, try reportDigest(report))
    }

    private static func appendDailyRecords(dayIndex: Int, to file: URL) throws -> Int {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var data = Data()
        for index in 0..<5_000 {
            let id = index % 10_000
            if index % 1_000 == 0 {
                appendLine(jsonLine(type: "turn_context", payload: "\"turn_id\":\"turn-\(id)\",\"model\":\"model-\(id % 5)\""), to: &data)
            }
            let seconds = Double(dayIndex) * day + Double(index) * 10
            let timestamp = formatter.string(from: baseNow.addingTimeInterval(seconds))
            appendLine(usageLine(turn: turnID(id), response: "append-\(dayIndex)-\(index)", timestamp: timestamp), to: &data)
        }
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        return data.count
    }

    private static func reportDigest(_ report: LocalTokenReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return sha256(try encoder.encode(report))
    }

    private static func usageLine(turn: String, response: String, timestamp: String) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"token_usage_record\",\"payload\":{\"turn_id\":\"\(turn)\",\"response_id\":\"\(response)\",\"usage\":{\"input_tokens\":120,\"cached_input_tokens\":30,\"cache_write_input_tokens\":10,\"output_tokens\":20,\"reasoning_output_tokens\":5,\"total_tokens\":140}}}"
    }

    private static func jsonLine(type: String, payload: String) -> String {
        "{\"type\":\"\(type)\",\"payload\":{\(payload)}}"
    }

    private static func appendLine(_ line: String, to data: inout Data) {
        data.append(contentsOf: line.utf8)
        data.append(0x0A)
    }

    private static func sessionFile(_ root: URL) -> URL {
        root.appendingPathComponent("sessions/2026/10/13/synthetic.jsonl")
    }

    private static func archiveRoot(_ root: URL) -> URL {
        root.appendingPathComponent("archived_sessions", isDirectory: true)
    }

    private static func turnID(_ id: Int) -> String {
        "turn-\(id)"
    }

    private static func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func processCPU() -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private static func maximumResidentSetSize() -> UInt64 {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        return UInt64(max(0, usage.ru_maxrss))
    }

    private static func monotonic() -> Double {
        ProcessInfo.processInfo.systemUptime
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private struct BenchFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
