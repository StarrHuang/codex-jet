import Foundation
import ResetCore

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main struct QuotaFlowTests {
    static func main() {
        let missing = QuotaFlowState(remainingPercent: nil, ratePerHour: 60)
        check(missing.remainingPercent == nil && missing.fillFraction == nil && missing.flowSpeed == 0,
              "missing quota must not invent fill or measured flow")

        let stale = QuotaFlowState(remainingPercent: 72, stale: true, ratePerHour: 60)
        check(stale.remainingPercent == nil && stale.fillFraction == nil && stale.flowSpeed == 0,
              "stale quota must not infer current fill or animate measured flow")

        let empty = QuotaFlowState(remainingPercent: 0, ratePerHour: 60)
        let partial = QuotaFlowState(remainingPercent: 35)
        let full = QuotaFlowState(remainingPercent: 100)
        check(empty.remainingPercent == 0 && empty.fillFraction == 0 && empty.flowSpeed == 0,
              "zero quota has an empty fill and no flow animation")
        check(partial.remainingPercent == 35 && partial.fillFraction == 0.35,
              "fill fraction must directly represent the observed remaining percentage")
        check(full.fillFraction == 1, "full quota must fill the full meter")

        check(QuotaFlowState(remainingPercent: -5).remainingPercent == 0,
              "negative observations clamp to zero")
        check(QuotaFlowState(remainingPercent: 125).remainingPercent == 100,
              "observations above one hundred clamp to one hundred")
        check(QuotaFlowState(remainingPercent: .nan).fillFraction == nil,
              "non-finite quota remains unknown")
        check(QuotaFlowState(remainingPercent: 50, ratePerHour: .infinity).flowSpeed == 0,
              "non-finite measured rates stop flow")
        check(QuotaFlowState(remainingPercent: 50, ratePerHour: -1).flowSpeed == 0,
              "negative measured rates stop flow")

        let slow = QuotaFlowState(remainingPercent: 60, ratePerHour: 2)
        let medium = QuotaFlowState(remainingPercent: 60, ratePerHour: 10)
        let fast = QuotaFlowState(remainingPercent: 60, ratePerHour: 60)
        check(slow.flowSpeed == 0.25 && medium.flowSpeed == 0.75,
              "flow speed uses the documented percentage-points-per-hour compression")
        check(slow.flowSpeed < medium.flowSpeed && medium.flowSpeed < fast.flowSpeed,
              "higher measured usage produces faster flow")
        check(slow.fillFraction == medium.fillFraction && medium.fillFraction == fast.fillFraction,
              "measured flow speed never changes quota fill")

        let zeroRate = QuotaFlowState(remainingPercent: 60, ratePerHour: 0)
        check(zeroRate.flowSpeed == 0 && zeroRate.fillFraction == 0.6,
              "known zero usage preserves observed fill but stops flow")
        print("PASS: direct quota fill, unknown/stale handling, and measured flow mapping")
    }
}
