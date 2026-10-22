import Foundation
import CryptoKit
import ResetCore

private enum HarnessFailure: Error {
    case assertion(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw HarnessFailure.assertion(message) }
}

private func close(_ actual: Double?, _ expected: Double, tolerance: Double = 0.0001) -> Bool {
    guard let actual else { return false }
    return abs(actual - expected) <= tolerance
}

private func makeWindow(
    id: String = "main:primary",
    bucket: String = "main",
    used: Double,
    duration: Int? = 300,
    reset: Date?) -> QuotaWindow
{
    QuotaWindow(id: id, bucketID: bucket, label: "Main · Primary", usedPercent: used, durationMinutes: duration, resetsAt: reset)
}

private func makeHistory(
    account: String,
    window: QuotaWindow,
    now: Date,
    values: [(TimeInterval, Double)]) -> [QuotaSnapshot]
{
    let end = values.map(\.0).max() ?? 0
    return values.map { offset, percent in
        let point = QuotaWindow(
            id: window.id, bucketID: window.bucketID, label: window.label,
            usedPercent: percent, durationMinutes: window.durationMinutes, resetsAt: window.resetsAt)
        return QuotaSnapshot(sampledAt: now.addingTimeInterval(offset - end), accountKey: account, plan: nil, windows: [point])
    }
}

private func testForecasts() throws {
    let now = Date(timeIntervalSince1970: 10_000)
    let baselineWindow = makeWindow(used: 30, reset: now.addingTimeInterval(4 * 3600))
    let empty = ForecastEngine.forecast(window: baselineWindow, history: [], accountKey: "account-a", now: now)
    try expect(empty.state == .insufficientHistory, "empty history is insufficient")
    try expect(close(empty.baselineRatePerHour, 30), "window baseline uses elapsed time, not full duration")
    try expect(close(empty.requiredRatePerHour, 17.5), "required pace is available before enough history")
    try expect(empty.recentRatePerHour == nil, "empty history has no measured rate")

    let window = makeWindow(used: 40, reset: now.addingTimeInterval(3600))
    let fastHistory = makeHistory(account: "account-a", window: window, now: now, values: [(-1800, 20), (-900, 35), (0, 40)])
    let slowHistory = makeHistory(account: "account-a", window: window, now: now, values: [(-1800, 38), (-900, 39), (0, 40)])
    let fast = ForecastEngine.forecast(window: window, history: fastHistory, accountKey: "account-a", now: now)
    let slow = ForecastEngine.forecast(window: window, history: slowHistory, accountKey: "account-a", now: now)
    try expect(fast.state == .ready, "three samples over thirty minutes qualify")
    try expect(close(fast.recentRatePerHour, 40), "fast observed rate")
    try expect(close(slow.recentRatePerHour, 4), "slow observed rate")
    try expect(close(fast.requiredRatePerHour, 60), "required pace")
    try expect(close(fast.projectedUsedAtReset, 80), "fast projection")
    try expect(close(slow.projectedUsedAtReset, 44), "slow projection")
    try expect(fast.cycleSamples.count == 3, "graph samples are exposed")

    let jitterWindow = makeWindow(used: 40, reset: window.resetsAt!.addingTimeInterval(-1))
    let jitter = ForecastEngine.forecast(window: jitterWindow, history: fastHistory, accountKey: "account-a", now: now)
    try expect(close(jitter.recentRatePerHour, 40), "one-second server rounding preserves measured cycle pace")
    let shiftedWindow = makeWindow(used: 40, reset: window.resetsAt!.addingTimeInterval(-2))
    try expect(ForecastEngine.cycleSamples(window: shiftedWindow, history: fastHistory, accountKey: "account-a").isEmpty,
               "larger reset-time changes remain separate")
    let jitterHistory = fastHistory + [QuotaSnapshot(sampledAt: now.addingTimeInterval(60), accountKey: "account-a", plan: nil, windows: [jitterWindow])]
    let analysis = QuotaHistoryAnalysis.analyze(history: jitterHistory, accountKey: "account-a", windowID: window.id, bucketID: window.bucketID, now: now.addingTimeInterval(60))
    try expect(analysis.cycles.count == 1 && analysis.recentChanges.allSatisfy { $0.kind != .reset }, "one-second reset jitter does not invent a reset event")
    try expect(!sameQuotaResetTime(nil, window.resetsAt), "missing reset time remains distinct")

    let short = makeHistory(account: "account-a", window: window, now: now, values: [(-600, 35), (0, 40)])
    try expect(ForecastEngine.forecast(window: window, history: short, accountKey: "account-a", now: now).state == .insufficientHistory,
               "fewer than three samples do not qualify")
    let stale = makeHistory(account: "account-a", window: window, now: now.addingTimeInterval(-601), values: [(-1800, 20), (-900, 30), (0, 40)])
    try expect(ForecastEngine.forecast(window: window, history: stale, accountKey: "account-a", now: now).state == .stale,
               "sample older than ten minutes is stale")
    let future = makeHistory(account: "account-a", window: window, now: now.addingTimeInterval(1), values: [(-1800, 20), (-900, 30), (0, 40)])
    try expect(ForecastEngine.forecast(window: window, history: future, accountKey: "account-a", now: now).state == .stale,
               "future sample timestamps are stale")

    let droppedHistory = makeHistory(account: "account-a", window: window, now: now,
                                     values: [(-3600, 30), (-2700, 50), (-1800, 5), (-900, 6), (0, 7)])
        + makeHistory(account: "other-account", window: window, now: now,
                      values: [(-1800, 1), (-900, 2), (0, 3)])
    let dropped = ForecastEngine.forecast(window: makeWindow(used: 7, reset: window.resetsAt), history: droppedHistory, accountKey: "account-a", now: now)
    try expect(dropped.state == .ready, "drop starts an eligible new cycle")
    try expect(dropped.cycleSamples.map(\.usedPercent) == [5, 6, 7], "drop removes samples from the old cycle")
    let historyCycle = ForecastEngine.cycleSamples(window: window, history: droppedHistory, accountKey: "account-a")
    try expect(historyCycle.count == 3, "cycle snapshot helper isolates account and reset cycle")
    try expect(historyCycle.allSatisfy { $0.accountKey == "account-a" }, "cycle helper excludes other accounts")

    let zeroHistory = makeHistory(account: "account-a", window: window, now: now, values: [(-1800, 40), (-900, 40), (0, 40)])
    let zero = ForecastEngine.forecast(window: window, history: zeroHistory, accountKey: "account-a", now: now)
    try expect(zero.recentRatePerHour == 0, "zero pace is represented as zero")
    try expect(zero.estimatedExhaustionAt == nil, "zero pace has no exhaustion estimate")
    try expect(zero.recentToBaselineMultiplier == 0, "zero pace multiplier is zero when baseline exists")

    let oldWindow = makeWindow(used: 100, reset: now.addingTimeInterval(-1))
    try expect(ForecastEngine.forecast(window: oldWindow, history: zeroHistory, accountKey: "account-a", now: now).state == .waitingForReset,
               "expired reset waits for server refresh")
    let unknownReset = makeWindow(used: 30, reset: nil)
    try expect(ForecastEngine.forecast(window: unknownReset, history: [], accountKey: "account-a", now: now).state == .waitingForReset,
               "unknown reset does not fabricate a forecast")

    let longHistory = makeHistory(account: "account-a", window: window, now: now,
                                  values: [(-108_000, 1), (-43_200, 50), (-21_600, 60), (0, 70)])
    let recentOnly = ForecastEngine.forecast(window: makeWindow(used: 70, reset: window.resetsAt), history: longHistory, accountKey: "account-a", now: now)
    try expect(close(recentOnly.recentRatePerHour, 20.0 / 12), "measured pace uses only the latest 24 hours")
}

private func testPersistence() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try QuotaHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
    let reset = Date(timeIntervalSince1970: 20_000)
    let a = QuotaSnapshot(sampledAt: Date(timeIntervalSince1970: 100), accountKey: "hashed-a", plan: "Plus", windows: [makeWindow(used: 10, reset: reset)])
    let b = QuotaSnapshot(sampledAt: Date(timeIntervalSince1970: 200), accountKey: "hashed-b", plan: "Team", windows: [makeWindow(used: 20, reset: reset)])
    try store.append(a)
    try store.append(b)
    let allSamples = try store.load()
    let accountASamples = try store.load(accountKey: "hashed-a")
    try expect(allSamples.count == 2, "history round-trips")
    try expect(accountASamples == [a], "history filters by account")
    let persisted = try String(contentsOf: store.fileURL, encoding: .utf8)
    try expect(!persisted.contains("private@example.test"), "history contains no raw email")
    try expect(persisted.contains("hashed-a") && persisted.contains("hashed-b"), "history retains distinct hashed account keys")

    let corruptURL = directory.appendingPathComponent("corrupt.json")
    try Data("{broken".utf8).write(to: corruptURL)
    let corruptStore = try QuotaHistoryStore(fileURL: corruptURL)
    do {
        _ = try corruptStore.load()
        throw HarnessFailure.assertion("malformed history must fail visibly")
    } catch is DecodingError {
        // Expected: malformed persisted data is surfaced to the caller.
    }
}

private func testRPCFixture() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("fake-codex")
    let script = #"""
#!/bin/sh
[ "$*" = "-s read-only -a never app-server" ] || exit 9
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r initialized
IFS= read -r account
printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","accountId":"acct-id","email":"private@example.test","planType":"Plus"}}}'
IFS= read -r limits
printf '%s\n' '{"id":3,"result":{"rateLimits":{"limit_id":"legacy","primary":{"used_percent":99,"window_duration_mins":300,"resets_at":2000000000}},"rate_limits_by_limit_id":{"main":{"limit_name":"Main","primary":{"used_percent":20,"window_duration_mins":300,"resets_at":2000000000},"secondary":{"used_percent":null,"window_duration_mins":10080,"resets_at":2000001000}},"model-a":{"limit_name":"Model A","primary":{"used_percent":35,"window_duration_mins":60,"resets_at":2000000300},"secondary":{"used_percent":40,"window_duration_mins":1440,"resets_at":2000000400}},"model-b":{"primary":{"used_percent":8,"resets_at":2000000500}}}}}'
"""#
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    let discoveredExecutable = directory.appendingPathComponent("codex")
    try FileManager.default.copyItem(at: executable, to: discoveredExecutable)
    let discovered = CodexAppServerClient.discoverExecutable(environment: ["PATH": directory.path], homeDirectory: directory)
    try expect(discovered == discoveredExecutable, "custom absolute PATH resolves Codex on another Mac")
    let configured = directory.appendingPathComponent("explicit-codex")
    try expect(CodexAppServerClient.discoverExecutable(environment: ["CODEX_EXECUTABLE": configured.path, "PATH": directory.path], homeDirectory: directory) == configured,
               "an explicit CLI override never silently selects another install")
    // Reproduce a Finder-style PATH and prove the CLI directory is provided
    // even when the parent environment cannot locate its runtime.
    let runtime = directory.appendingPathComponent("quota-fixture-runtime")
    try "#!/bin/sh\nexit 0\n".write(to: runtime, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runtime.path)
    let originalPath = ProcessInfo.processInfo.environment["PATH"]
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1)
    defer {
        if let originalPath { setenv("PATH", originalPath, 1) }
        else { unsetenv("PATH") }
    }
    let pathScript = script.replacingOccurrences(of: "IFS= read -r initialize", with: "quota-fixture-runtime || exit 127\nIFS= read -r initialize")
    try pathScript.write(to: executable, atomically: true, encoding: .utf8)
    let snapshot = try CodexAppServerClient(executableURL: executable).fetchSnapshot(sampledAt: Date(timeIntervalSince1970: 1_900_000_000))
    try expect(snapshot.plan == "Plus", "account plan parsed")
    let expectedKey = SHA256.hash(data: Data("chatgpt:acct-id".utf8)).map { String(format: "%02x", $0) }.joined()
    try expect(snapshot.accountKey == expectedKey && !snapshot.accountKey.contains("private@example.test"), "account ID is preferred and hashed")
    try expect(snapshot.windows.map(\.id) == ["main:primary", "model-a:primary", "model-a:secondary", "model-b:primary"],
               "root and all rateLimitsByLimitId windows stay distinct")
    try expect(snapshot.windows.count == 4, "null usage window is omitted rather than converted to zero")
    try expect(!snapshot.windows.contains(where: { $0.bucketID == "legacy" }), "legacy aggregate is skipped when per-limit map exists")
    try expect(snapshot.windows.last?.durationMinutes == nil, "duration stays optional")
    try expect(snapshot.windows.last?.resetsAt == Date(timeIntervalSince1970: 2_000_000_500), "reset timestamp parsed")

    let missingIdentity = directory.appendingPathComponent("missing-identity-codex")
    let missingScript = #"""
#!/bin/sh
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r initialized
IFS= read -r account
printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","planType":"Plus"}}}'
"""#
    try missingScript.write(to: missingIdentity, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: missingIdentity.path)
    do {
        _ = try CodexAppServerClient(executableURL: missingIdentity, timeout: 1).fetchSnapshot()
        throw HarnessFailure.assertion("missing identity must not create an unisolated account key")
    } catch CodexAppServerError.missingAccountIdentity {
        // Expected: do not persist quota history under an ambiguous identity.
    }

    let invalidUsage = directory.appendingPathComponent("invalid-usage-codex")
    let invalidScript = #"""
#!/bin/sh
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r initialized
IFS= read -r account
printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"fixture@example.test"}}}'
IFS= read -r limits
printf '%s\n' '{"id":3,"result":{"rateLimits":{"primary":{"used_percent":101}}}}'
"""#
    try invalidScript.write(to: invalidUsage, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: invalidUsage.path)
    do {
        _ = try CodexAppServerClient(executableURL: invalidUsage, timeout: 1).fetchSnapshot()
        throw HarnessFailure.assertion("out-of-range usage percentage must fail visibly")
    } catch CodexAppServerError.invalidUsageValue {
        // Expected: invalid network data is rejected at the boundary.
    }

    let emailFallback = directory.appendingPathComponent("email-fallback-codex")
    let fallbackScript = #"""
#!/bin/sh
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r initialized
IFS= read -r account
printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"fallback@example.test"}}}'
IFS= read -r limits
printf '%s\n' '{"id":3,"result":{"rateLimits":{"limit_id":"legacy","primary":{"used_percent":0,"window_duration_mins":300,"resets_at":2000000000}},"rate_limits_by_limit_id":{}}}'
"""#
    try fallbackScript.write(to: emailFallback, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: emailFallback.path)
    let fallbackSnapshot = try CodexAppServerClient(executableURL: emailFallback).fetchSnapshot()
    let emailKey = SHA256.hash(data: Data("chatgpt:fallback@example.test".utf8)).map { String(format: "%02x", $0) }.joined()
    try expect(fallbackSnapshot.accountKey == emailKey, "email is hashed only when no account ID is available")
    try expect(fallbackSnapshot.windows.map(\.id) == ["legacy:primary"], "legacy rate limits are used when the per-limit map is empty")

    let timeoutServer = directory.appendingPathComponent("timeout-codex")
    let timeoutScript = #"""
#!/bin/sh
trap '' TERM
IFS= read -r initialize
while :; do
  IFS= read -r blocked || :
done
"""#
    try timeoutScript.write(to: timeoutServer, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: timeoutServer.path)
    let start = DispatchTime.now().uptimeNanoseconds
    do {
        _ = try CodexAppServerClient(executableURL: timeoutServer, timeout: 0.15).fetchSnapshot()
        throw HarnessFailure.assertion("blocking server must time out")
    } catch CodexAppServerError.timeout(let method) {
        try expect(method == "initialize", "timeout identifies the blocked RPC")
    }
    let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    try expect(elapsed < 2, "timeout and SIGKILL cleanup remain bounded")
}

private func testWeeklyPace() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func window(_ used: Double) -> QuotaWindow {
        QuotaWindow(id: "codex:primary", bucketID: "codex", label: "Codex", usedPercent: used,
                    durationMinutes: 10080, resetsAt: now.addingTimeInterval(6 * 86400))
    }
    let fast = WeeklyPace.evaluate(window: window(60), observedAt: now, now: now)
    try expect(fast.state == .ahead, "weekly pace warns against early exhaustion")
    try expect(close(fast.averageRatePerHour, 2.5), "weekly pace uses full-window elapsed average")
    try expect(close(fast.expectedUsedPercent, 100.0 / 7), "elapsed window percentage")
    try expect(close(fast.hoursEarly, 128), "early exhaustion relative to subscription reset")
    try expect(close(fast.safeSpeedMultiplier, 1.0 / 9), "safe future multiplier to last until reset")
    let slow = WeeklyPace.evaluate(window: window(10), observedAt: now, now: now)
    try expect(slow.state == .surplus && close(slow.projectedRemainingAtReset, 30), "surplus allows pedaling harder")
    let balanced = WeeklyPace.evaluate(window: window(100.0 / 7), observedAt: now, now: now)
    try expect(balanced.state == .balanced && close(balanced.hoursEarly, 0), "matching time and usage is balanced")
    try expect(WeeklyPace.evaluate(window: window(0), observedAt: now, now: now).state == .surplus, "zero use yields surplus without an exhaustion date")
    try expect(WeeklyPace.evaluate(window: window(100), observedAt: now, now: now).state == .exhausted, "exhausted quota should rest")
    try expect(WeeklyPace.evaluate(window: window(60), observedAt: now.addingTimeInterval(-601), now: now).state == .stale, "stale read never encourages sprinting")
    let newWindow = QuotaWindow(id: "x", bucketID: "codex", label: "Codex", usedPercent: 1, durationMinutes: 10080,
                               resetsAt: now.addingTimeInterval(167 * 3600))
    try expect(WeeklyPace.evaluate(window: newWindow, observedAt: now, now: now).state == .unknown, "new window below 3 percent elapsed has no strong pace verdict")
    let expired = QuotaWindow(id: "x", bucketID: "codex", label: "Codex", usedPercent: 60, durationMinutes: 10080, resetsAt: now)
    try expect(WeeklyPace.evaluate(window: expired, observedAt: now, now: now).state == .waitingForReset, "subscription reset awaits fresh confirmation")
}

private func runTests() throws {
    try testForecasts()
    try testWeeklyPace()
    try testPersistence()
    try testRPCFixture()
    print("PASS: forecasts, boundaries, persistence, stdio parsing, and bounded timeout cleanup")
}

private func runProbe() throws {
    let snapshot = try CodexAppServerClient().fetchSnapshot()
    let formatter = ISO8601DateFormatter()
    let windows: [[String: Any]] = snapshot.windows.map { window in
        var item: [String: Any] = [
            "id": window.id,
            "bucketID": window.bucketID,
            "label": window.label,
            "usedPercent": window.usedPercent,
        ]
        if let duration = window.durationMinutes { item["durationMinutes"] = duration }
        if let reset = window.resetsAt { item["resetsAt"] = formatter.string(from: reset) }
        return item
    }
    let payload: [String: Any] = [
        "sampledAt": formatter.string(from: snapshot.sampledAt),
        "accountKey": snapshot.accountKey,
        "plan": snapshot.plan as Any? ?? NSNull(),
        "windows": windows,
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

@main
private struct CoreHarness {
    static func main() {
        do {
            if CommandLine.arguments.dropFirst().contains("--probe") { try runProbe() }
            else { try runTests() }
        } catch HarnessFailure.assertion(let message) {
            fputs("FAIL: \(message)\n", stderr)
            exit(1)
        } catch let error as CodexAppServerError {
            let category: String
            switch error {
            case .executableNotFound: category = "executableNotFound"
            case .processStart: category = "processStart"
            case .io: category = "io"
            case .timeout: category = "timeout"
            case .rpc: category = "rpc"
            case .malformedResponse: category = "malformedResponse"
            case .noQuotaWindows: category = "noQuotaWindows"
            case .missingAccountIdentity: category = "missingAccountIdentity"
            case .invalidUsageValue: category = "invalidUsageValue"
            }
            fputs("FAIL: Codex app-server error category \(category)\n", stderr)
            exit(1)
        } catch {
            // Error descriptions can contain server-provided text. Keep harness output sanitized.
            fputs("FAIL: core operation threw \(String(reflecting: type(of: error)))\n", stderr)
            exit(1)
        }
    }
}
