import Foundation

/// Maps an observed remaining-quota percentage directly to a normalized flight height.
public struct RoadsterFlightState: Equatable, Sendable {
    /// A clamped observed balance, or nil when the balance is missing, stale, or non-finite.
    public let remainingPercent: Double?
    /// 0 means the Roadster rests on the pad; 1 means the configured maximum altitude.
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

/// One bounded refill maneuver: pressure builds, lift accelerates, the vehicle rolls and levels out.
/// The reference is a visual timing study, not a measured model of vehicle physics.
public struct RoadsterLaunchPose: Equatable, Sendable {
    public let liftProgress: Double
    public let rotationDegrees: Double
    public let thrust: Double
    public let scale: Double

    public init(progress: Double, roll: Bool) {
        let t = min(1, max(0, progress))
        func smooth(_ value: Double) -> Double {
            let x = min(1, max(0, value))
            return x * x * x * (x * (x * 6 - 15) + 10)
        }
        liftProgress = smooth((t - 0.10) / 0.82)
        let turn = smooth((t - 0.28) / 0.57)
        let pitch = sin(t * .pi) * 13
        rotationDegrees = (roll ? 360 * turn : 0) + pitch
        thrust = pow(sin(t * .pi), 2)
        scale = 1 - (roll ? 0.32 * pow(sin(turn * .pi), 2) : 0)
    }
}
