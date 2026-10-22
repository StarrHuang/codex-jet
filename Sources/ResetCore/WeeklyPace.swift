import Foundation

public enum WeeklyPaceState: String, Sendable {
    case ahead, balanced, surplus, exhausted, unknown, stale, waitingForReset
}

/// Subscription-window guidance: compare consumed quota with elapsed window time,
/// keeping recent measured velocity as a separate signal in the dashboard.
public struct WeeklyPace: Sendable {
    public let state: WeeklyPaceState
    public let expectedUsedPercent: Double?
    public let deltaPercent: Double?
    public let averageRatePerHour: Double?
    public let projectedRemainingAtReset: Double?
    public let exhaustionAt: Date?
    public let hoursEarly: Double?
    public let safeSpeedMultiplier: Double?

    public static func evaluate(window: QuotaWindow, observedAt: Date, now: Date) -> WeeklyPace {
        func result(_ state: WeeklyPaceState) -> WeeklyPace {
            WeeklyPace(state: state, expectedUsedPercent: nil, deltaPercent: nil,
                       averageRatePerHour: nil, projectedRemainingAtReset: nil,
                       exhaustionAt: nil, hoursEarly: nil, safeSpeedMultiplier: nil)
        }
        let age = now.timeIntervalSince(observedAt)
        guard age >= 0, age <= ForecastEngine.maximumAge else { return result(.stale) }
        guard let reset = window.resetsAt else { return result(.unknown) }
        guard reset > now else { return result(.waitingForReset) }
        if window.usedPercent >= 100 { return result(.exhausted) }
        guard let minutes = window.durationMinutes, minutes > 0 else { return result(.unknown) }
        let duration = Double(minutes) * 60
        let observedRemaining = reset.timeIntervalSince(observedAt)
        guard observedRemaining > 0, observedRemaining <= duration else { return result(.unknown) }
        let elapsed = duration - observedRemaining
        let expected = elapsed / duration * 100
        // Like CodexBar, avoid a strong pace verdict at the very start of a window.
        guard expected >= 3 else { return result(.unknown) }
        let rate = window.usedPercent / (elapsed / 3600)
        let remainingHours = reset.timeIntervalSince(now) / 3600
        let remaining = 100 - window.usedPercent
        let projectedRemaining = max(0, remaining - rate * remainingHours)
        let exhaustion = rate > 0 ? now.addingTimeInterval(remaining / rate * 3600) : nil
        let delta = window.usedPercent - expected
        let state: WeeklyPaceState = abs(delta) <= 2 ? .balanced : delta > 2 ? .ahead : .surplus
        return WeeklyPace(
            state: state, expectedUsedPercent: expected, deltaPercent: delta,
            averageRatePerHour: rate, projectedRemainingAtReset: projectedRemaining,
            exhaustionAt: exhaustion,
            hoursEarly: exhaustion.map { max(0, reset.timeIntervalSince($0) / 3600) },
            safeSpeedMultiplier: rate > 0 ? remaining / (rate * remainingHours) : nil)
    }
}
