import Foundation
import ResetCore

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

private enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case let .failed(message): message
        }
    }
}

private struct Timing {
    let wallSeconds: Double
    let cpuSeconds: Double?
}

private func snapshot(index: Int, account: String = "account-a") -> QuotaSnapshot {
    let date = Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 60 + 0.123)
    let window = QuotaWindow(
        id: "main:primary",
        bucketID: "main",
        label: "Main · Primary",
        usedPercent: Double(index % 100),
        durationMinutes: 300,
        resetsAt: date.addingTimeInterval(86_400.456))
    return QuotaSnapshot(sampledAt: date, accountKey: account, plan: "Plus", windows: [window])
}

private func encode(_ snapshots: [QuotaSnapshot]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(snapshots)
}

private func assert(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    guard condition() else { throw CheckFailure.failed(message) }
}

private func verifyReturnedHistoryAndAccountFiltering(artifacts: URL) throws {
    let directory = artifacts.appendingPathComponent("regression-returned-history", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try QuotaHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
    let first = snapshot(index: 1)
    let otherAccount = snapshot(index: 2, account: "account-b")
    let added = snapshot(index: 3)
    _ = try store.append(first)
    _ = try store.append(otherAccount)
    let returned = try store.append(added)
    let persisted = try store.load()

    try assert(returned == persisted, "append return value differs from the persisted all-account history")
    try assert(returned.count == 3 && returned.map(\.accountKey) == ["account-a", "account-b", "account-a"], "append return value omitted, reordered, or changed account history")
    try assert(returned.filter { $0.accountKey == "account-a" } == persisted.filter { $0.accountKey == "account-a" }, "account filtering returned the wrong account history")
    print("PASS append returns exact persisted all-account history and supports account filtering")
}

private func verifyFailedAppendLeavesExistingHistoryUnmodified(artifacts: URL) throws {
    let directory = artifacts.appendingPathComponent("regression-failed-append", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let fileURL = directory.appendingPathComponent("history.json")
    let original = [snapshot(index: 10)]
    try encode(original).write(to: fileURL, options: .atomic)
    let originalBytes = try Data(contentsOf: fileURL)
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

    var failed = false
    do {
        _ = try QuotaHistoryStore(fileURL: fileURL).append(snapshot(index: 11))
    } catch {
        failed = true
    }
    try assert(failed, "append unexpectedly succeeded in a non-writable history directory")
    let afterFailureBytes = try Data(contentsOf: fileURL)
    try assert(afterFailureBytes == originalBytes, "failed append changed the prior history bytes")
    print("PASS failed append preserves the prior history bytes")
}

private func cpuSeconds() -> Double? {
    #if canImport(Darwin) || canImport(Glibc)
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
    let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
    let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    return user + system
    #else
    return nil
    #endif
}

private func measure(_ body: () throws -> Void) throws -> Timing {
    let cpuStart = cpuSeconds()
    let wallStart = ProcessInfo.processInfo.systemUptime
    try body()
    return Timing(
        wallSeconds: ProcessInfo.processInfo.systemUptime - wallStart,
        cpuSeconds: cpuStart.flatMap { start in cpuSeconds().map { $0 - start } })
}

private func benchmark(historyCount: Int, artifacts: URL) throws {
    let directory = artifacts.appendingPathComponent("benchmark-\(historyCount)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("history.json")
    var fixture = (0..<historyCount).map { snapshot(index: $0, account: $0.isMultiple(of: 3) ? "account-b" : "account-a") }
    try encode(fixture).write(to: fileURL, options: .atomic)
    let appended = snapshot(index: historyCount + 1)
    let store = try QuotaHistoryStore(fileURL: fileURL)

    let oldPattern = try measure {
        try store.append(appended) // The pre-change API's call site ignored append's result.
        let accountHistory = try store.load(accountKey: appended.accountKey)
        try assert(accountHistory.last?.accountKey == appended.accountKey, "old append+load pattern returned an unexpected result")
    }
    try encode(fixture).write(to: fileURL, options: .atomic)

    let returnedHistory = try measure {
        let allHistory = try store.append(appended)
        let accountHistory = allHistory.filter { $0.accountKey == appended.accountKey }
        try assert(accountHistory.last?.accountKey == appended.accountKey, "returned-history pattern returned an unexpected result")
    }

    let payloadBytes = (try Data(contentsOf: fileURL)).count
    let oldCPU = oldPattern.cpuSeconds.map { String(format: "%.4f", $0) } ?? "unavailable"
    let newCPU = returnedHistory.cpuSeconds.map { String(format: "%.4f", $0) } ?? "unavailable"
    print("\(historyCount) samples: JSON bytes=\(payloadBytes); logical history I/O old=read/decode 2x + encode/write 1x, new=read/decode 1x + encode/write 1x")
    print("  old append+load: wall=\(String(format: "%.4f", oldPattern.wallSeconds))s CPU=\(oldCPU)s")
    print("  append-return+filter: wall=\(String(format: "%.4f", returnedHistory.wallSeconds))s CPU=\(newCPU)s")
    fixture.removeAll(keepingCapacity: false)
}

do {
    guard let artifactPath = CommandLine.arguments.last, CommandLine.arguments.count >= 2 else {
        throw CheckFailure.failed("pass a persistent artifact directory; benchmark fixtures are retained")
    }
    let artifacts = URL(fileURLWithPath: artifactPath, isDirectory: true)
    try FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
    try verifyReturnedHistoryAndAccountFiltering(artifacts: artifacts)
    try verifyFailedAppendLeavesExistingHistoryUnmodified(artifacts: artifacts)
    try benchmark(historyCount: 5_000, artifacts: artifacts)
    try benchmark(historyCount: 50_000, artifacts: artifacts)
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(EXIT_FAILURE)
}
