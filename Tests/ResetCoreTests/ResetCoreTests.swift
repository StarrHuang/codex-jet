import Foundation
import XCTest
@testable import ResetCore

final class ResetCoreTests: XCTestCase {
    func testAllRateLimitBucketsAndNullableWindowsAreDecodedFromStdio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("fake-codex")
        let script = #"""
#!/bin/sh
IFS= read -r initialize
printf '%s\n' '{"id":1,"result":{}}'
IFS= read -r initialized
IFS= read -r account
printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"private@example.test","planType":"Plus"}}}'
IFS= read -r limits
printf '%s\n' '{"id":3,"result":{"rateLimits":{"limit_id":"main","limit_name":"Main","primary":{"used_percent":20,"window_duration_mins":300,"resets_at":2000000000},"secondary":{"used_percent":null,"window_duration_mins":10080,"resets_at":2000001000}},"rate_limits_by_limit_id":{"model-a":{"limit_name":"Model A","primary":{"used_percent":35,"window_duration_mins":60,"resets_at":2000000300},"secondary":{"used_percent":40,"window_duration_mins":1440,"resets_at":2000000400}},"model-b":{"primary":{"used_percent":8,"resets_at":2000000500}}}}}'
"""#
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let snapshot = try CodexAppServerClient(executableURL: executable).fetchSnapshot(sampledAt: Date(timeIntervalSince1970: 1_900_000_000))
        XCTAssertEqual(snapshot.plan, "Plus")
        XCTAssertEqual(snapshot.accountKey.count, 64)
        XCTAssertFalse(snapshot.accountKey.contains("private@example.test"))
        XCTAssertEqual(snapshot.windows.map(\.id), ["main:primary", "model-a:primary", "model-a:secondary", "model-b:primary"])
        XCTAssertEqual(snapshot.windows.first?.usedPercent, 20)
        XCTAssertNil(snapshot.windows.last?.durationMinutes)
        XCTAssertEqual(snapshot.windows.last?.resetsAt, Date(timeIntervalSince1970: 2_000_000_500))
    }

    func testHistoryPersistenceAndAccountFiltering() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try QuotaHistoryStore(fileURL: directory.appendingPathComponent("history.json"))
        try store.append(snapshot(account: "a", at: 100, percent: 10))
        try store.append(snapshot(account: "b", at: 110, percent: 20))
        XCTAssertEqual(try store.load().count, 2)
        XCTAssertEqual(try store.load(accountKey: "a").map(\.accountKey), ["a"])
        let persisted = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(persisted.contains("a"))
    }

    func testForecastRequiresRecentSamplesAndExposesWindowAverageWithoutThem() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = quotaWindow(used: 30, duration: 300, reset: now.addingTimeInterval(4 * 3600))
        let forecast = ForecastEngine.forecast(window: window, history: [], accountKey: "a", now: now)
        XCTAssertEqual(forecast.state, .insufficientHistory)
        XCTAssertEqual(forecast.baselineRatePerHour, 30)
        XCTAssertNil(forecast.recentRatePerHour)
        XCTAssertTrue(forecast.cycleSamples.isEmpty)
    }

    func testFastAndSlowMeasuredPacesForecastDifferently() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = quotaWindow(used: 40, duration: 300, reset: now.addingTimeInterval(3600))
        let fast = snapshots(account: "a", window: window, now: now, values: [(0, 20), (900, 35), (1800, 40)])
        let slow = snapshots(account: "a", window: window, now: now, values: [(0, 38), (900, 39), (1800, 40)])
        let fastResult = ForecastEngine.forecast(window: window, history: fast, accountKey: "a", now: now)
        let slowResult = ForecastEngine.forecast(window: window, history: slow, accountKey: "a", now: now)
        XCTAssertEqual(fastResult.state, .ready)
        XCTAssertEqual(fastResult.recentRatePerHour!, 40, accuracy: 0.0001)
        XCTAssertEqual(slowResult.recentRatePerHour!, 4, accuracy: 0.0001)
        XCTAssertEqual(fastResult.requiredRatePerHour!, 60, accuracy: 0.0001)
        XCTAssertEqual(fastResult.projectedUsedAtReset!, 80, accuracy: 0.0001)
        XCTAssertEqual(slowResult.projectedUsedAtReset!, 44, accuracy: 0.0001)
        XCTAssertEqual(fastResult.cycleSamples.count, 3)
    }

    func testUsageDropStartsNewCycleAndAccountAndWindowAreIsolated() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = quotaWindow(used: 7, duration: 300, reset: now.addingTimeInterval(3600))
        let history = snapshots(account: "a", window: window, now: now, values: [(0, 30), (900, 50), (1800, 5), (2700, 6), (3600, 7)])
            + snapshots(account: "other", window: window, now: now, values: [(0, 1), (900, 2), (1800, 3)])
        let forecast = ForecastEngine.forecast(window: window, history: history, accountKey: "a", now: now)
        XCTAssertEqual(forecast.state, .ready)
        XCTAssertEqual(forecast.cycleSamples.map(\.usedPercent), [5, 6, 7])
        let otherWindow = QuotaWindow(id: "other-window", bucketID: "main", label: "Other", usedPercent: 7, durationMinutes: 300, resetsAt: window.resetsAt)
        XCTAssertEqual(ForecastEngine.forecast(window: otherWindow, history: history, accountKey: "a", now: now).state, .insufficientHistory)
    }

    func testStaleExpiredAndZeroPaceStates() {
        let now = Date(timeIntervalSince1970: 10_000)
        let window = quotaWindow(used: 25, duration: 300, reset: now.addingTimeInterval(3600))
        let old = snapshots(account: "a", window: window, now: now.addingTimeInterval(-4000), values: [(0, 10), (900, 15), (1800, 20)])
        XCTAssertEqual(ForecastEngine.forecast(window: window, history: old, accountKey: "a", now: now).state, .stale)
        let zero = snapshots(account: "a", window: window, now: now, values: [(0, 25), (900, 25), (1800, 25)])
        let zeroForecast = ForecastEngine.forecast(window: window, history: zero, accountKey: "a", now: now)
        XCTAssertEqual(zeroForecast.recentRatePerHour, 0)
        XCTAssertNil(zeroForecast.estimatedExhaustionAt)
        let expired = quotaWindow(used: 100, duration: 300, reset: now.addingTimeInterval(-1))
        XCTAssertEqual(ForecastEngine.forecast(window: expired, history: zero, accountKey: "a", now: now).state, .waitingForReset)
    }

    private func snapshots(account: String, window: QuotaWindow, now: Date, values: [(TimeInterval, Double)]) -> [QuotaSnapshot] {
        let finalElapsed = values.map(\.0).max() ?? 0
        return values.map { elapsed, percent in
            let sampledWindow = QuotaWindow(
                id: window.id, bucketID: window.bucketID, label: window.label,
                usedPercent: percent, durationMinutes: window.durationMinutes, resetsAt: window.resetsAt)
            return QuotaSnapshot(sampledAt: now.addingTimeInterval(elapsed - finalElapsed), accountKey: account, plan: nil, windows: [sampledWindow])
        }
    }

    private func snapshot(account: String, at time: TimeInterval, percent: Double) -> QuotaSnapshot {
        QuotaSnapshot(sampledAt: Date(timeIntervalSince1970: time), accountKey: account, plan: "Plus", windows: [quotaWindow(used: percent, duration: 300, reset: Date(timeIntervalSince1970: 20_000))])
    }

    private func quotaWindow(used: Double, duration: Int?, reset: Date?) -> QuotaWindow {
        QuotaWindow(id: "main:primary", bucketID: "main", label: "Main · Primary", usedPercent: used, durationMinutes: duration, resetsAt: reset)
    }
}
