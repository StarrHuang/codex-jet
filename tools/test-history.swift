import Foundation
import ResetCore

private enum CheckFailure: Error {
    case failed(String)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw CheckFailure.failed(message) }
}

private func snapshot(
    _ time: TimeInterval,
    account: String = "account-a",
    windowID: String = "main:primary",
    bucketID: String = "main",
    used: Double,
    reset: Date?) -> QuotaSnapshot
{
    let window = QuotaWindow(id: windowID, bucketID: bucketID, label: "Main", usedPercent: used, durationMinutes: nil, resetsAt: reset)
    return QuotaSnapshot(sampledAt: Date(timeIntervalSince1970: time), accountKey: account, plan: nil, windows: [window])
}

private func analyze(
    _ history: [QuotaSnapshot],
    at now: TimeInterval = 20_000,
    account: String = "account-a",
    windowID: String = "main:primary",
    bucketID: String = "main",
    horizonHours: Double? = nil) -> QuotaHistoryAnalysis
{
    QuotaHistoryAnalysis.analyze(
        history: history,
        accountKey: account,
        windowID: windowID,
        bucketID: bucketID,
        now: Date(timeIntervalSince1970: now),
        horizonHours: horizonHours)
}

@main
private struct HistoryChecks {
    static func main() throws {
        let reset = Date(timeIntervalSince1970: 30_000)
        try testNoHistoryAndIsolation(reset: reset)
        try testMinuteDedupeAndHorizon(reset: reset)
        try testCyclesAndResetClassification()
        try testGapAndMaximumDrop(reset: reset)
        try testHorizonBoundsChangesAndMaximumDrop(reset: reset)
        print("PASS: quota history identities, minute dedupe, cycle observations, gaps, horizon, and maximum depletion rate")
    }

    private static func testNoHistoryAndIsolation(reset: Date) throws {
        try expect(analyze([]).points.isEmpty, "empty history has no graph")
        try expect(analyze([]).recentChanges.isEmpty && analyze([]).cycles.isEmpty, "empty history has no inferred changes or cycles")
        try expect(analyze([]).maximumDrop == nil, "empty history has no maximum drop")

        let history = [
            snapshot(19_000, account: "account-b", used: 90, reset: reset),
            snapshot(19_000, bucketID: "other", used: 80, reset: reset),
            snapshot(19_000, windowID: "other:primary", used: 70, reset: reset),
            snapshot(19_000, used: 25, reset: reset),
            snapshot(20_001, used: 99, reset: reset),
        ]
        let result = analyze(history)
        try expect(result.points.count == 1 && result.points[0].remainingPercent == 75, "exact account/window/bucket match excludes other identities and future samples")
    }

    private static func testMinuteDedupeAndHorizon(reset: Date) throws {
        let history = [
            snapshot(19_020, used: 10, reset: reset),
            snapshot(19_035, used: 15, reset: reset),
            snapshot(19_100, used: 20, reset: reset),
        ]
        let full = analyze(history, at: 20_000)
        try expect(full.points.count == 2, "same-minute samples collapse to one graph point")
        try expect(full.points[0].sampledAt == Date(timeIntervalSince1970: 19_035), "minute dedupe keeps the latest sample")
        try expect(full.cycles.count == 1 && full.cycles[0].initialUsedPercent == 15, "cycle analytics use the same deduplicated series")

        let filtered = analyze(history, at: 20_000, horizonHours: 0.25)
        try expect(filtered.points.count == 1 && filtered.points[0].sampledAt == Date(timeIntervalSince1970: 19_100), "horizon filters graph points")
        try expect(filtered.cycles.count == full.cycles.count && filtered.cycles[0].firstSeen == full.cycles[0].firstSeen, "horizon does not erase observed cycle history")
    }

    private static func testCyclesAndResetClassification() throws {
        let resetA = Date(timeIntervalSince1970: 30_000)
        let resetB = Date(timeIntervalSince1970: 40_000)
        let history = [
            snapshot(19_000, used: 30, reset: resetA),
            snapshot(19_120, used: 40, reset: resetA),
            snapshot(19_240, used: 5, reset: resetA), // usage fell despite unchanged reset time
            snapshot(19_360, used: 10, reset: resetB), // reset timestamp changed
            snapshot(19_480, used: 15, reset: resetA), // timestamp changed back
            snapshot(19_600, used: 2, reset: nil),
            snapshot(19_720, used: 4, reset: nil),
        ]
        let result = analyze(history)
        try expect(result.cycles.count == 5, "drop, reset-time changes, and null transition start observed segments")
        try expect(result.cycles.last?.isCurrent == true && result.cycles.filter(\.isCurrent).count == 1, "only the latest observed segment is current")
        try expect(result.cycles[0].firstSeen == Date(timeIntervalSince1970: 19_000), "cycle firstSeen records first observation")
        try expect(result.cycles[0].durationMinutes == 2, "cycle duration is observed first-to-last span")
        try expect(result.recentChanges.filter { $0.kind == .reset }.count == 4, "observed usage drops and reset timestamp changes are reset events")
        try expect(result.maximumDrop?.kind == .consumption, "reset observations are excluded from maximum consumption")
        try expect(result.recentChanges.first?.sampledAt == Date(timeIntervalSince1970: 19_720), "recent changes are newest first")
    }

    private static func testGapAndMaximumDrop(reset: Date) throws {
        let history = [
            snapshot(19_000, used: 10, reset: reset),
            snapshot(19_300, used: 12, reset: reset),
            snapshot(20_500, used: 20, reset: reset),
            snapshot(20_800, used: 32, reset: reset),
            snapshot(20_800 + 16 * 60, used: 35, reset: reset),
        ]
        let result = analyze(history, at: 22_000)
        try expect(result.cycles.count == 1, "observation gaps alone do not claim a provider cycle reset")
        try expect(result.points[1].segmentID != result.points[2].segmentID, "path breaks when observation gap exceeds 15 minutes")
        try expect(result.points[3].segmentID != result.points[4].segmentID, "each long gap starts a new graph segment")
        try expect(result.maximumDrop?.previousAt == Date(timeIntervalSince1970: 20_500), "maximumDrop selects the fastest qualifying consumption interval")
        try expect(result.maximumDrop?.sampledAt == Date(timeIntervalSince1970: 20_800), "maximumDrop preserves the observed timestamps")
        try expect(result.maximumDrop?.dropPercent == 12 && result.maximumDrop?.intervalMinutes == 5, "maximumDrop reports absolute depletion and interval")
    }

    private static func testHorizonBoundsChangesAndMaximumDrop(reset: Date) throws {
        let history = [
            snapshot(20_800, used: 0, reset: reset),
            snapshot(20_900, used: 30, reset: reset), // fastest interval, fully before the selected horizon
            snapshot(21_000, used: 35, reset: reset),
            snapshot(21_110, used: 55, reset: reset), // endpoint is in range, but pair crosses its start
            snapshot(21_200, used: 56, reset: reset),
            snapshot(21_300, used: 61, reset: reset), // largest fully in-range qualifying drop
            snapshot(21_900, used: 62, reset: reset),
        ]
        let result = analyze(history, at: 22_000, horizonHours: 0.25)
        try expect(result.cycles.count == 1 && result.cycles[0].firstSeen == Date(timeIntervalSince1970: 20_800), "cycles retain observations outside the selected horizon")
        try expect(result.points.first?.sampledAt == Date(timeIntervalSince1970: 21_110), "graph points begin at the selected horizon")
        try expect(result.recentChanges.allSatisfy { $0.sampledAt >= Date(timeIntervalSince1970: 21_100) }, "recent changes use the selected horizon")
        try expect(result.recentChanges.contains { $0.sampledAt == Date(timeIntervalSince1970: 21_110) }, "change events are included when their observation lands in range")
        try expect(result.maximumDrop?.previousAt == Date(timeIntervalSince1970: 21_200), "maximum drop excludes old and horizon-crossing intervals")
        try expect(result.maximumDrop?.sampledAt == Date(timeIntervalSince1970: 21_300), "maximum drop selects the fastest fully in-range interval")
    }
}
