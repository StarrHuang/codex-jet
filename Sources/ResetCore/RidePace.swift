import Foundation

/// A visual projection of measured pace. The marker is a speed target, not a progress prediction.
public struct RidePace: Equatable, Sendable {
    public enum State: String, Sendable { case waiting, parked, slow, steady, fast, stale, finished }
    public let state: State
    public let rate: Double?
    public let required: Double?
    public let remaining: Double?
    public let multiplier: Double?
    public let ratio: Double?
    /// Decorative flow cadence; deliberately bounded for a calm interface.
    public let cadence: Double

    public init(_ pace: DeadlinePace?) {
        let usable = pace.map { [.tooSlow, .onTrack, .tooFast].contains($0.state) } ?? false
        rate = usable ? pace?.recentRatePerHour : nil
        required = usable ? pace?.requiredRatePerHour : nil
        remaining = usable ? pace?.projectedRemainingAtDeadline : nil
        multiplier = usable ? pace?.speedMultiplier : nil
        ratio = if let rate, let required, required > 0 { rate / required } else { nil }
        cadence = if let rate, rate > 0 { min(0.85, 0.16 + sqrt(rate) * 0.23) } else { 0 }
        state = switch pace?.state {
        case .stale: .stale
        case .expired, .exhausted, .resetBeforeDeadline: .finished
        case .tooSlow: rate == 0 ? .parked : .slow
        case .onTrack: .steady
        case .tooFast: .fast
        default: .waiting
        }
    }

    /// 0...2× the target spans the flow. Nil deliberately hides the position comparison.
    public var position: Double? { ratio.map { min(2, max(0, $0)) / 2 } }
}
