import Foundation

/// Directly maps the latest usable remaining quota to a bar fill and measured flow speed.
public struct QuotaFlowState: Equatable, Sendable {
    /// The observed balance clamped to 0...100, or nil when missing, stale, or non-finite.
    public let remainingPercent: Double?
    /// The observed balance as a 0...1 fill fraction, or nil when it cannot be inferred.
    public let fillFraction: Double?
    /// Compressed measured pace for the visual flow indicator. Zero means no flow animation.
    public let flowSpeed: Double

    public init(remainingPercent: Double?, stale: Bool = false, ratePerHour: Double? = nil) {
        guard !stale, let remainingPercent, remainingPercent.isFinite else {
            self.remainingPercent = nil
            self.fillFraction = nil
            self.flowSpeed = 0
            return
        }

        let bounded = min(100, max(0, remainingPercent))
        self.remainingPercent = bounded
        self.fillFraction = bounded / 100
        if bounded > 0, let ratePerHour, ratePerHour.isFinite, ratePerHour > 0 {
            self.flowSpeed = 1.5 * ratePerHour / (ratePerHour + 10)
        } else {
            self.flowSpeed = 0
        }
    }
}
