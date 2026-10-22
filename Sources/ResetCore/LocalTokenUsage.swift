import Foundation

/// Local session activity, deliberately not attributed to the signed-in quota account.
public struct HourlyModelTokens: Codable, Equatable, Sendable, Identifiable {
    public let hour: Date
    public let model: String
    public var inputTokens: Int64
    public var cachedInputTokens: Int64
    public var outputTokens: Int64
    public var reasoningOutputTokens: Int64
    public var totalTokens: Int64
    public var eventCount: Int
    public var id: String { "\(hour.timeIntervalSince1970)|\(model)" }

    public init(hour: Date, model: String, inputTokens: Int64, cachedInputTokens: Int64,
                outputTokens: Int64, reasoningOutputTokens: Int64, totalTokens: Int64,
                eventCount: Int) {
        self.hour = hour
        self.model = model
        self.inputTokens = inputTokens
        self.cachedInputTokens = cachedInputTokens
        self.outputTokens = outputTokens
        self.reasoningOutputTokens = reasoningOutputTokens
        self.totalTokens = totalTokens
        self.eventCount = eventCount
    }
}

public struct LocalTokenReport: Codable, Sendable {
    public let generatedAt: Date
    public let rows: [HourlyModelTokens]
    public let filesRead: Int
    public let latestEventAt: Date?
    public let warnings: [String]

    public init(generatedAt: Date, rows: [HourlyModelTokens], filesRead: Int,
                latestEventAt: Date?, warnings: [String] = []) {
        self.generatedAt = generatedAt
        self.rows = rows
        self.filesRead = filesRead
        self.latestEventAt = latestEventAt
        self.warnings = warnings
    }
}
