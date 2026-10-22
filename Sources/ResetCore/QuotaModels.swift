import Foundation

public struct QuotaWindow: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let bucketID: String
    public let label: String
    public let usedPercent: Double
    public let durationMinutes: Int?
    public let resetsAt: Date?

    public init(
        id: String,
        bucketID: String,
        label: String,
        usedPercent: Double,
        durationMinutes: Int?,
        resetsAt: Date?)
    {
        self.id = id
        self.bucketID = bucketID
        self.label = label
        self.usedPercent = usedPercent
        self.durationMinutes = durationMinutes
        self.resetsAt = resetsAt
    }
}

// The live API has returned the same reset deadline with one-second rounding
// differences. Preserve raw dates, but do not treat that jitter as a new cycle.
public func sameQuotaResetTime(_ lhs: Date?, _ rhs: Date?) -> Bool {
    switch (lhs, rhs) {
    case let (left?, right?): return abs(left.timeIntervalSince(right)) <= 1
    case (nil, nil): return true
    default: return false
    }
}

public struct QuotaSnapshot: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let accountKey: String
    public let plan: String?
    public let windows: [QuotaWindow]

    public init(sampledAt: Date = .now, accountKey: String, plan: String?, windows: [QuotaWindow]) {
        self.sampledAt = sampledAt
        self.accountKey = accountKey
        self.plan = plan
        self.windows = windows
    }
}

public enum ForecastState: String, Codable, Sendable {
    case insufficientHistory
    case stale
    case waitingForReset
    case ready
}

public struct QuotaSamplePoint: Codable, Equatable, Sendable {
    public let sampledAt: Date
    public let usedPercent: Double

    public init(sampledAt: Date, usedPercent: Double) {
        self.sampledAt = sampledAt
        self.usedPercent = usedPercent
    }
}

public struct WindowForecast: Codable, Equatable, Sendable {
    public let state: ForecastState
    /// Provider-window average in percentage points per hour.
    public let baselineRatePerHour: Double?
    /// Measured rate between qualifying samples in percentage points per hour.
    public let recentRatePerHour: Double?
    /// Rate required to consume the remaining quota by reset, in percentage points per hour.
    public let requiredRatePerHour: Double?
    public let estimatedExhaustionAt: Date?
    public let projectedUsedAtReset: Double?
    public let recentToBaselineMultiplier: Double?
    /// Samples from the current reset/drop-segmented cycle, ordered oldest to newest.
    public let cycleSamples: [QuotaSamplePoint]

    public init(
        state: ForecastState,
        baselineRatePerHour: Double? = nil,
        recentRatePerHour: Double? = nil,
        requiredRatePerHour: Double? = nil,
        estimatedExhaustionAt: Date? = nil,
        projectedUsedAtReset: Double? = nil,
        recentToBaselineMultiplier: Double? = nil,
        cycleSamples: [QuotaSamplePoint] = [])
    {
        self.state = state
        self.baselineRatePerHour = baselineRatePerHour
        self.recentRatePerHour = recentRatePerHour
        self.requiredRatePerHour = requiredRatePerHour
        self.estimatedExhaustionAt = estimatedExhaustionAt
        self.projectedUsedAtReset = projectedUsedAtReset
        self.recentToBaselineMultiplier = recentToBaselineMultiplier
        self.cycleSamples = cycleSamples
    }
}
