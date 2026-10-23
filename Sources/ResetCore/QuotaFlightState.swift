import Foundation

/// Maps an observed remaining-quota percentage directly to a normalized flight height.
public struct QuotaFlightState: Equatable, Sendable {
    /// A clamped observed balance, or nil when the balance is missing, stale, or non-finite.
    public let remainingPercent: Double?
    /// 0 means the paper plane rests on the pad; 1 means the configured maximum altitude.
    public let liftFraction: Double?
    /// Scene widths per second. Compresses the measured rate smoothly, without confusing it with quota.
    public let travelSpeed: Double

    public init(remainingPercent: Double?, stale: Bool = false, ratePerHour: Double? = nil) {
        guard !stale, let remainingPercent, remainingPercent.isFinite else {
            self.remainingPercent = nil
            self.liftFraction = nil
            self.travelSpeed = 0
            return
        }
        let bounded = min(100, max(0, remainingPercent))
        self.remainingPercent = bounded
        self.liftFraction = bounded / 100
        if bounded > 0, let ratePerHour, ratePerHour.isFinite, ratePerHour > 0 {
            self.travelSpeed = 1.5 * ratePerHour / (ratePerHour + 10)
        } else { self.travelSpeed = 0 }
    }
}

/// One bounded paper-plane takeoff and bank after an observed refill.
public struct PaperPlaneLaunchPose: Equatable, Sendable {
    public let liftProgress: Double
    public let pitchDegrees: Double
    public let bankDegrees: Double
    public let yawDegrees: Double
    public init(progress: Double, bank: Bool) {
        let t = min(1, max(0, progress))
        let x = min(1, max(0, (t - 0.10) / 0.82))
        liftProgress = x * x * x * (x * (x * 6 - 15) + 10)
        pitchDegrees = sin(t * .pi) * (bank ? 16 : 7)
        bankDegrees = bank ? sin(t * .pi) * 28 : 0
        yawDegrees = bank ? sin(t * .pi) * 9 : 0
    }
}
