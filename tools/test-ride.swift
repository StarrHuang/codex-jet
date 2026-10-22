import Foundation
import ResetCore

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
private func fixture(rate: Double, age: TimeInterval = 0, deadlineHours: Double = 6, used: Double = 40,
                     accountResetHours: Double = 6) -> DeadlinePace {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reset = now.addingTimeInterval(accountResetHours * 3600)
    let window = QuotaWindow(id: "codex:weekly", bucketID: "codex", label: "Codex", usedPercent: used,
                             durationMinutes: 10080, resetsAt: reset)
    let history = [-1800.0, -900, 0].map { offset in
        QuotaSnapshot(sampledAt: now.addingTimeInterval(offset), accountKey: "test", plan: nil,
                      windows: [QuotaWindow(id: window.id, bucketID: "codex", label: "Codex",
                                            usedPercent: used + offset / 3600 * rate,
                                            durationMinutes: 10080, resetsAt: reset)])
    }
    return DeadlinePace.evaluate(window: window, observedAt: now.addingTimeInterval(-age), history: history,
                                 accountKey: "test", deadline: now.addingTimeInterval(deadlineHours * 3600), now: now)
}
@main struct RideTests {
    static func main() {
        let waiting = RidePace(nil)
        check(waiting.state == .waiting && waiting.position == nil && waiting.cadence == 0, "missing data must park and hide comparison")
        let parked = RidePace(fixture(rate: 0))
        check(parked.state == .parked && parked.rate == 0 && parked.position == 0 && parked.multiplier == nil, "observed zero must differ from missing data; never infinite multiplier")
        let slow = RidePace(fixture(rate: 2))
        check(slow.state == .slow && slow.ratio == 0.2 && slow.position == 0.1, "cat must lag target flag")
        check(slow.multiplier == 5 && slow.remaining == 48, "readout must match deadline model")
        let steady = RidePace(fixture(rate: 10))
        check(steady.state == .steady && steady.position == 0.5, "on target must align with flag")
        let fast = RidePace(fixture(rate: 20))
        check(fast.state == .fast && fast.position == 1, "fast must pass flag")
        let veryFast = RidePace(fixture(rate: 60))
        check(veryFast.position == 1 && veryFast.cadence <= 0.85 && veryFast.ratio == 6, "drawing must clamp without hiding actual speed ratio")
        check(slow.cadence < steady.cadence && steady.cadence <= fast.cadence, "actual measured speed must drive monotonic cadence")
        let stale = RidePace(fixture(rate: 20, age: 601))
        check(stale.state == .stale && stale.rate == nil && stale.position == nil && stale.cadence == 0, "stale data must not drive motion or projection")
        for pace in [fixture(rate: 2, deadlineHours: -1), fixture(rate: 0, used: 100), fixture(rate: 2, accountResetHours: 3)] {
            let ride = RidePace(pace)
            check(ride.state == .finished && ride.position == nil && ride.cadence == 0, "ended/exhausted/earlier reset must not urge acceleration")
        }
        print("PASS: measured cadence, target alignment, zero/unknown/stale distinctions, projection and bounded motion")
    }
}
