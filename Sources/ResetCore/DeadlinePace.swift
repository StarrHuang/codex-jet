import Foundation

/// An estimate of whether the measured quota pace is sufficient to reach an
/// arbitrary deadline. Rates are percentage points per hour, not token counts.
public struct DeadlinePace: Equatable, Sendable {
    public struct Measurement: Equatable, Sendable {
        public let horizonHours: Double
        public let ratePerHour: Double?
        public let sampleCount: Int
        public let spanHours: Double

        public init(horizonHours: Double, ratePerHour: Double?, sampleCount: Int, spanHours: Double) {
            self.horizonHours = horizonHours
            self.ratePerHour = ratePerHour
            self.sampleCount = sampleCount
            self.spanHours = spanHours
        }
    }

    public enum State: String, Codable, Sendable {
        case unknown
        case stale
        case expired
        case exhausted
        case resetBeforeDeadline
        case tooSlow
        case onTrack
        case tooFast
    }

    /// Measurements are ordered by 1h, 6h, then 24h horizons.
    public let measurements: [Measurement]
    /// The first eligible measurement in the order above.
    public let recentRatePerHour: Double?
    public let horizonHours: Double?
    public let requiredRatePerHour: Double?
    /// Remaining percentage at the deadline, clamped to 0...100.
    public let projectedRemainingAtDeadline: Double?
    public let estimatedExhaustionAt: Date?
    /// Required rate divided by measured rate. Nil when measured rate is zero or unavailable.
    public let speedMultiplier: Double?
    public let hoursUntilDeadline: Double?
    public let state: State

    private init(
        measurements: [Measurement],
        recentRatePerHour: Double?,
        horizonHours: Double?,
        requiredRatePerHour: Double?,
        projectedRemainingAtDeadline: Double?,
        estimatedExhaustionAt: Date?,
        speedMultiplier: Double?,
        hoursUntilDeadline: Double?,
        state: State)
    {
        self.measurements = measurements
        self.recentRatePerHour = recentRatePerHour
        self.horizonHours = horizonHours
        self.requiredRatePerHour = requiredRatePerHour
        self.projectedRemainingAtDeadline = projectedRemainingAtDeadline
        self.estimatedExhaustionAt = estimatedExhaustionAt
        self.speedMultiplier = speedMultiplier
        self.hoursUntilDeadline = hoursUntilDeadline
        self.state = state
    }

    public static func evaluate(
        window: QuotaWindow,
        observedAt: Date,
        history: [QuotaSnapshot],
        accountKey: String,
        deadline: Date?,
        now: Date) -> DeadlinePace
    {
        // A future point must not be allowed to segment and erase the valid
        // present cycle before it is discarded.
        let nonFutureHistory = history.filter { $0.sampledAt <= now }
        let cycle = ForecastEngine.cycleSamples(window: window, history: nonFutureHistory, accountKey: accountKey)
        let horizons: [Double] = [1, 6, 24]
        let measurements = horizons.map { hours -> Measurement in
            let lowerBound = now.addingTimeInterval(-hours * 3600)
            let samples = cycle.filter { $0.sampledAt >= lowerBound }
            guard samples.count >= ForecastEngine.minimumSamples,
                  let first = samples.first,
                  let last = samples.last
            else {
                return Measurement(horizonHours: hours, ratePerHour: nil, sampleCount: samples.count, spanHours: 0)
            }

            let span = last.sampledAt.timeIntervalSince(first.sampledAt) / 3600
            guard span >= ForecastEngine.minimumSpan / 3600,
                  now.timeIntervalSince(last.sampledAt) <= ForecastEngine.maximumAge
            else {
                return Measurement(horizonHours: hours, ratePerHour: nil, sampleCount: samples.count, spanHours: span)
            }
            let usedFirst = first.windows.first(where: { $0.id == window.id && $0.bucketID == window.bucketID })!.usedPercent
            let usedLast = last.windows.first(where: { $0.id == window.id && $0.bucketID == window.bucketID })!.usedPercent
            return Measurement(horizonHours: hours, ratePerHour: (usedLast - usedFirst) / span, sampleCount: samples.count, spanHours: span)
        }

        let primary = measurements.first(where: { $0.ratePerHour != nil })
        let measured = primary?.ratePerHour
        let observedAge = now.timeIntervalSince(observedAt)
        let latestHistoryAt = cycle.last?.sampledAt
        let historyAge = latestHistoryAt.map { now.timeIntervalSince($0) }
        let isStale = observedAge < 0 || observedAge > ForecastEngine.maximumAge
            || historyAge.map { $0 < 0 || $0 > ForecastEngine.maximumAge } ?? false

        func result(
            state: State,
            required: Double? = nil,
            remaining: Double? = nil,
            exhaustion: Date? = nil,
            multiplier: Double? = nil,
            hours: Double? = nil) -> DeadlinePace
        {
            DeadlinePace(
                measurements: measurements,
                recentRatePerHour: measured,
                horizonHours: primary?.horizonHours,
                requiredRatePerHour: required,
                projectedRemainingAtDeadline: remaining,
                estimatedExhaustionAt: exhaustion,
                speedMultiplier: multiplier,
                hoursUntilDeadline: hours,
                state: state)
        }

        if isStale { return result(state: .stale) }
        guard let deadline else { return result(state: .unknown) }
        guard deadline > now else { return result(state: .expired) }
        if window.usedPercent >= 100 {
            return result(state: .exhausted, remaining: 0, exhaustion: now)
        }
        if let reset = window.resetsAt, reset < deadline {
            return result(state: .resetBeforeDeadline)
        }

        let hours = deadline.timeIntervalSince(now) / 3600
        let required = max(0, 100 - window.usedPercent) / hours
        guard let measured else { return result(state: .unknown, required: required, hours: hours) }
        let remaining = min(100, max(0, 100 - window.usedPercent - measured * hours))
        let exhaustion = measured > 0
            ? now.addingTimeInterval(max(0, 100 - window.usedPercent) / measured * 3600)
            : nil
        let multiplier = measured > 0 ? required / measured : nil
        let ratio = required == 0 ? 0 : measured / required
        let state: State = measured == 0 ? .tooSlow : (ratio < 0.9 ? .tooSlow : (ratio > 1.1 ? .tooFast : .onTrack))
        return result(
            state: state,
            required: required,
            remaining: remaining,
            exhaustion: exhaustion,
            multiplier: multiplier,
            hours: hours)
    }
}
