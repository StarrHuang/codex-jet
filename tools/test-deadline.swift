import Foundation
import ResetCore

private enum HarnessFailure: Error { case assertion(String) }
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
    used: Double = 40,
    reset: Date?) -> QuotaWindow
{
    QuotaWindow(id: id, bucketID: bucket, label: "Main", usedPercent: used, durationMinutes: 300, resetsAt: reset)
}

private func history(
    account: String = "account-a",
    window: QuotaWindow,
    now: Date,
    points: [(TimeInterval, Double)]) -> [QuotaSnapshot]
{
    points.map { offset, used in
        let point = QuotaWindow(id: window.id, bucketID: window.bucketID, label: window.label,
                                usedPercent: used, durationMinutes: window.durationMinutes, resetsAt: window.resetsAt)
        return QuotaSnapshot(sampledAt: now.addingTimeInterval(offset), accountKey: account, plan: nil, windows: [point])
    }
}

private func run() throws {
    let now = Date(timeIntervalSince1970: 100_000)
    let deadline = now.addingTimeInterval(3600)
    let window = makeWindow(reset: now.addingTimeInterval(3 * 3600))
    let fast = history(window: window, now: now, points: [(-1800, 0), (-900, 20), (0, 40)])
    let slow = history(window: window, now: now, points: [(-1800, 38), (-900, 39), (0, 40)])
    let fastPace = DeadlinePace.evaluate(window: window, observedAt: now, history: fast, accountKey: "account-a", deadline: deadline, now: now)
    let slowPace = DeadlinePace.evaluate(window: window, observedAt: now, history: slow, accountKey: "account-a", deadline: deadline, now: now)
    try expect(fastPace.state == .tooFast && close(fastPace.recentRatePerHour, 80), "faster measured pace classification")
    try expect(close(fastPace.requiredRatePerHour, 60) && close(fastPace.projectedRemainingAtDeadline, 0), "deadline requirement and remaining projection")
    try expect(close(fastPace.speedMultiplier, 0.75), "required to measured multiplier")
    try expect(slowPace.state == .tooSlow && close(slowPace.projectedRemainingAtDeadline, 56), "slower measured pace classification")

    let onTrackWindow = makeWindow(used: 40, reset: window.resetsAt)
    let onTrackHistory = history(window: onTrackWindow, now: now, points: [(-1800, 20), (-900, 30), (0, 40)])
    let onTrackDeadline = now.addingTimeInterval(5400)
    let onTrack = DeadlinePace.evaluate(window: onTrackWindow, observedAt: now, history: onTrackHistory,
                                        accountKey: "account-a", deadline: onTrackDeadline, now: now)
    try expect(onTrack.state == .onTrack, "on-track band spans measured pace within ten percent")

    let zeroHistory = history(window: window, now: now, points: [(-1800, 40), (-900, 40), (0, 40)])
    let zero = DeadlinePace.evaluate(window: window, observedAt: now, history: zeroHistory,
                                     accountKey: "account-a", deadline: deadline, now: now)
    try expect(zero.state == .tooSlow && zero.recentRatePerHour == 0 && zero.estimatedExhaustionAt == nil,
               "zero pace is measured but has no exhaustion or speed multiplier")
    try expect(zero.speedMultiplier == nil, "zero pace does not divide by zero")

    let noDeadline = DeadlinePace.evaluate(window: window, observedAt: now, history: fast, accountKey: "account-a", deadline: nil, now: now)
    try expect(noDeadline.state == .unknown && noDeadline.recentRatePerHour != nil, "missing deadline preserves measured rate")
    let expired = DeadlinePace.evaluate(window: window, observedAt: now, history: fast, accountKey: "account-a", deadline: now, now: now)
    try expect(expired.state == .expired, "past or current target is expired")

    let stale = DeadlinePace.evaluate(window: window, observedAt: now.addingTimeInterval(-601), history: fast,
                                      accountKey: "account-a", deadline: deadline, now: now)
    try expect(stale.state == .stale && stale.recentRatePerHour != nil, "stale live observation keeps independently measured history")
    let staleWithoutDeadline = DeadlinePace.evaluate(window: window, observedAt: now.addingTimeInterval(-601), history: fast,
                                                     accountKey: "account-a", deadline: nil, now: now)
    try expect(staleWithoutDeadline.state == .stale && staleWithoutDeadline.recentRatePerHour != nil,
               "stale live observation remains visible without a deadline")
    let staleHistory = history(window: window, now: now, points: [(-2400, 10), (-1800, 20), (-601, 40)])
    try expect(DeadlinePace.evaluate(window: window, observedAt: now, history: staleHistory, accountKey: "account-a", deadline: deadline, now: now).state == .stale,
               "stale latest history is rejected")

    let noSamples = DeadlinePace.evaluate(window: window, observedAt: now, history: [], accountKey: "account-a", deadline: deadline, now: now)
    try expect(noSamples.state == .unknown && noSamples.measurements.allSatisfy { $0.ratePerHour == nil }, "missing history stays unknown")
    try expect(close(noSamples.requiredRatePerHour, 60) && close(noSamples.hoursUntilDeadline, 1),
               "known target requirement remains available without measured pace")
    let sparse = history(window: window, now: now, points: [(-600, 35), (0, 40)])
    let sparsePace = DeadlinePace.evaluate(window: window, observedAt: now, history: sparse, accountKey: "account-a", deadline: deadline, now: now)
    try expect(sparsePace.state == .unknown && sparsePace.recentRatePerHour == nil, "fewer than three samples do not qualify")
    let shortSpan = history(window: window, now: now, points: [(-600, 30), (-300, 35), (0, 40)])
    try expect(DeadlinePace.evaluate(window: window, observedAt: now, history: shortSpan, accountKey: "account-a", deadline: deadline, now: now).recentRatePerHour == nil,
               "sample span under fifteen minutes is not measured")
    let future = history(window: window, now: now, points: [(-1800, 20), (-900, 30), (30, 40)])
    let futurePace = DeadlinePace.evaluate(window: window, observedAt: now, history: future, accountKey: "account-a", deadline: deadline, now: now)
    try expect(futurePace.measurements.allSatisfy { $0.ratePerHour == nil }, "future snapshots are excluded")
    let futureDrop = history(window: window, now: now, points: [(-1800, 20), (-900, 30), (0, 40), (30, 1)])
    let futureDropPace = DeadlinePace.evaluate(window: window, observedAt: now, history: futureDrop,
                                               accountKey: "account-a", deadline: deadline, now: now)
    try expect(close(futureDropPace.recentRatePerHour, 40), "future usage drops cannot segment the present cycle")

    let otherAccount = history(account: "account-b", window: window, now: now, points: [(-1800, 20), (-900, 30), (0, 40)])
    let wrongAccount = DeadlinePace.evaluate(window: window, observedAt: now, history: otherAccount, accountKey: "account-a", deadline: deadline, now: now)
    try expect(wrongAccount.recentRatePerHour == nil, "account history is isolated")
    let otherBucketWindow = makeWindow(bucket: "secondary", reset: window.resetsAt)
    let otherBucketHistory = history(window: otherBucketWindow, now: now, points: [(-1800, 20), (-900, 30), (0, 40)])
    try expect(DeadlinePace.evaluate(window: window, observedAt: now, history: otherBucketHistory, accountKey: "account-a", deadline: deadline, now: now).recentRatePerHour == nil,
               "bucket history is isolated")
    let otherCycleWindow = makeWindow(reset: now.addingTimeInterval(4 * 3600))
    let otherCycleHistory = history(window: otherCycleWindow, now: now, points: [(-1800, 20), (-900, 30), (0, 40)])
    try expect(DeadlinePace.evaluate(window: window, observedAt: now, history: otherCycleHistory, accountKey: "account-a", deadline: deadline, now: now).recentRatePerHour == nil,
               "reset cycle history is isolated")

    let multiWindowSnapshot = fast.map { snapshot in
        let wrong = QuotaWindow(id: window.id, bucketID: "secondary", label: "Other", usedPercent: 99,
                                durationMinutes: 300, resetsAt: window.resetsAt)
        return QuotaSnapshot(sampledAt: snapshot.sampledAt, accountKey: snapshot.accountKey, plan: nil, windows: [wrong] + snapshot.windows)
    }
    try expect(DeadlinePace.evaluate(window: window, observedAt: now, history: multiWindowSnapshot, accountKey: "account-a", deadline: deadline, now: now).recentRatePerHour != nil,
               "matching bucket wins when snapshot has multiple windows")

    let earlyResetWindow = makeWindow(reset: now.addingTimeInterval(1800))
    let earlyResetHistory = history(window: earlyResetWindow, now: now, points: [(-1800, 20), (-900, 30), (0, 40)])
    let resetBefore = DeadlinePace.evaluate(window: earlyResetWindow, observedAt: now, history: earlyResetHistory,
                                            accountKey: "account-a", deadline: deadline, now: now)
    try expect(resetBefore.state == .resetBeforeDeadline && resetBefore.projectedRemainingAtDeadline == nil
               && resetBefore.requiredRatePerHour == nil, "earlier server reset blocks target projection")

    let exhaustedWindow = makeWindow(used: 100, reset: now.addingTimeInterval(3 * 3600))
    let exhaustedHistory = history(window: exhaustedWindow, now: now, points: [(-1800, 90), (-900, 95), (0, 100)])
    let exhausted = DeadlinePace.evaluate(window: exhaustedWindow, observedAt: now, history: exhaustedHistory,
                                          accountKey: "account-a", deadline: deadline, now: now)
    try expect(exhausted.state == .exhausted && exhausted.projectedRemainingAtDeadline == 0, "fully used quota is exhausted")

    print("Deadline pace fixtures passed")
}

@main
private struct DeadlineHarness {
    static func main() {
        do { try run() } catch {
            fputs("Deadline pace fixture failure: \(error)\n", stderr)
            exit(1)
        }
    }
}
