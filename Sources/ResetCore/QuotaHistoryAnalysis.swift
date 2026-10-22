import Foundation

public struct HistoryPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let sampledAt: Date
    public let remainingPercent: Double
    public let segmentID: String
    public let resetsAt: Date?

    public init(id: String, sampledAt: Date, remainingPercent: Double, segmentID: String, resetsAt: Date?) {
        self.id = id
        self.sampledAt = sampledAt
        self.remainingPercent = remainingPercent
        self.segmentID = segmentID
        self.resetsAt = resetsAt
    }
}

public struct QuotaChange: Identifiable, Equatable, Sendable {
    /// Describes the observed transition; `.reset` does not assert an externally confirmed reset.
    public enum Kind: String, Sendable {
        case consumption
        case reset
    }

    public let id: String
    public let sampledAt: Date
    public let previousAt: Date
    /// Percentage points of quota used between observations; reset changes carry zero depletion.
    public let dropPercent: Double
    public let intervalMinutes: Double
    public let kind: Kind

    public init(id: String, sampledAt: Date, previousAt: Date, dropPercent: Double, intervalMinutes: Double, kind: Kind) {
        self.id = id
        self.sampledAt = sampledAt
        self.previousAt = previousAt
        self.dropPercent = dropPercent
        self.intervalMinutes = intervalMinutes
        self.kind = kind
    }
}

public struct ObservedCycle: Identifiable, Equatable, Sendable {
    public let id: String
    public let firstSeen: Date
    public let lastSeen: Date
    public let resetsAt: Date?
    public let initialUsedPercent: Double
    public let finalUsedPercent: Double
    public let durationMinutes: Double?
    public let isCurrent: Bool
    public let observedConsumptionPercent: Double

    public init(
        id: String,
        firstSeen: Date,
        lastSeen: Date,
        resetsAt: Date?,
        initialUsedPercent: Double,
        finalUsedPercent: Double,
        durationMinutes: Double?,
        isCurrent: Bool,
        observedConsumptionPercent: Double)
    {
        self.id = id
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.resetsAt = resetsAt
        self.initialUsedPercent = initialUsedPercent
        self.finalUsedPercent = finalUsedPercent
        self.durationMinutes = durationMinutes
        self.isCurrent = isCurrent
        self.observedConsumptionPercent = observedConsumptionPercent
    }
}

public struct QuotaHistoryAnalysis: Equatable, Sendable {
    public let points: [HistoryPoint]
    /// Most recent observed changes first, limited to the latest 12 events.
    public let recentChanges: [QuotaChange]
    /// Observed segments only; firstSeen is the first recorded sample, not a claimed provider cycle start.
    public let cycles: [ObservedCycle]
    public let maximumDrop: QuotaChange?

    public init(points: [HistoryPoint], recentChanges: [QuotaChange], cycles: [ObservedCycle], maximumDrop: QuotaChange?) {
        self.points = points
        self.recentChanges = recentChanges
        self.cycles = cycles
        self.maximumDrop = maximumDrop
    }

    private struct Sample {
        let sampledAt: Date
        let usedPercent: Double
        let resetsAt: Date?
    }

    private struct CycleSlice {
        let samples: [Sample]
    }

    public static func analyze(
        history: [QuotaSnapshot],
        accountKey: String,
        windowID: String,
        bucketID: String,
        now: Date = .now,
        horizonHours: Double? = nil) -> QuotaHistoryAnalysis
    {
        let grouped = Dictionary(grouping: history.compactMap { snapshot -> (Int64, Sample)? in
            guard snapshot.accountKey == accountKey,
                  snapshot.sampledAt <= now,
                  let window = snapshot.windows.first(where: { $0.id == windowID && $0.bucketID == bucketID })
            else { return nil }
            let minute = Int64(floor(snapshot.sampledAt.timeIntervalSince1970 / 60))
            return (minute, Sample(sampledAt: snapshot.sampledAt, usedPercent: window.usedPercent, resetsAt: window.resetsAt))
        }, by: \.0)

        let samples = grouped.values.compactMap { group in
            group.max { lhs, rhs in lhs.1.sampledAt < rhs.1.sampledAt }?.1
        }.sorted { $0.sampledAt < $1.sampledAt }

        guard !samples.isEmpty else {
            return QuotaHistoryAnalysis(points: [], recentChanges: [], cycles: [], maximumDrop: nil)
        }

        var cycleSlices: [CycleSlice] = []
        var active: [Sample] = []
        for sample in samples {
            if let previous = active.last,
               !sameQuotaResetTime(previous.resetsAt, sample.resetsAt) || sample.usedPercent < previous.usedPercent
            {
                cycleSlices.append(CycleSlice(samples: active))
                active = []
            }
            active.append(sample)
        }
        if !active.isEmpty {
            cycleSlices.append(CycleSlice(samples: active))
        }

        let cycles = cycleSlices.enumerated().map { index, slice in
            let first = slice.samples[0]
            let last = slice.samples[slice.samples.count - 1]
            let id = identityPrefix(accountKey: accountKey, windowID: windowID, bucketID: bucketID)
                + "cycle:\(milliseconds(first.sampledAt))"
            return ObservedCycle(
                id: id,
                firstSeen: first.sampledAt,
                lastSeen: last.sampledAt,
                resetsAt: last.resetsAt,
                initialUsedPercent: first.usedPercent,
                finalUsedPercent: last.usedPercent,
                durationMinutes: last.sampledAt.timeIntervalSince(first.sampledAt) / 60,
                isCurrent: index == cycleSlices.count - 1,
                observedConsumptionPercent: max(0, last.usedPercent - first.usedPercent))
        }

        let prefix = identityPrefix(accountKey: accountKey, windowID: windowID, bucketID: bucketID)
        let horizonStart = horizonHours.map { now.addingTimeInterval(-max(0, $0) * 3600) }
        var points: [HistoryPoint] = []
        var graphSegment = 0
        var previousGraphSample: Sample?
        var cycleIndex = 0
        for sample in samples {
            while cycleIndex + 1 < cycleSlices.count,
                  sample.sampledAt >= cycleSlices[cycleIndex + 1].samples[0].sampledAt
            {
                cycleIndex += 1
            }
            if let previousGraphSample,
               sample.sampledAt.timeIntervalSince(previousGraphSample.sampledAt) > 15 * 60
            {
                graphSegment += 1
            }
            if horizonStart.map({ sample.sampledAt >= $0 }) ?? true {
                let segmentID = "\(prefix)segment:\(milliseconds(cycleSlices[cycleIndex].samples[0].sampledAt)):\(graphSegment)"
                points.append(HistoryPoint(
                    id: "\(prefix)point:\(milliseconds(sample.sampledAt))",
                    sampledAt: sample.sampledAt,
                    remainingPercent: 100 - sample.usedPercent,
                    segmentID: segmentID,
                    resetsAt: sample.resetsAt))
            }
            previousGraphSample = sample
        }

        var changes: [QuotaChange] = []
        var maximumDrop: QuotaChange?
        var activeCycle = 0
        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let sample = samples[index]
            let interval = sample.sampledAt.timeIntervalSince(previous.sampledAt)
            guard interval > 0 else { continue }

            while activeCycle + 1 < cycleSlices.count,
                  sample.sampledAt >= cycleSlices[activeCycle + 1].samples[0].sampledAt
            {
                activeCycle += 1
            }
            let cycleBoundary = !sameQuotaResetTime(previous.resetsAt, sample.resetsAt) || sample.usedPercent < previous.usedPercent
            let depletion = max(0, sample.usedPercent - previous.usedPercent)
            let change = QuotaChange(
                id: "\(prefix)change:\(milliseconds(previous.sampledAt)):\(milliseconds(sample.sampledAt))",
                sampledAt: sample.sampledAt,
                previousAt: previous.sampledAt,
                dropPercent: cycleBoundary ? 0 : depletion,
                intervalMinutes: interval / 60,
                kind: cycleBoundary ? .reset : .consumption)
            if (cycleBoundary || depletion > 0),
               horizonStart.map({ sample.sampledAt >= $0 }) ?? true
            {
                changes.append(change)
            }

            if !cycleBoundary, depletion > 0, interval <= 15 * 60,
               horizonStart.map({ previous.sampledAt >= $0 && sample.sampledAt >= $0 }) ?? true,
               maximumDrop.map({ depletion / interval > $0.dropPercent / ($0.intervalMinutes * 60) }) ?? true
            {
                maximumDrop = change
            }
        }

        return QuotaHistoryAnalysis(
            points: points,
            recentChanges: Array(changes.suffix(12).reversed()),
            cycles: cycles,
            maximumDrop: maximumDrop)
    }

    private static func identityPrefix(accountKey: String, windowID: String, bucketID: String) -> String {
        "account:\(accountKey)|window:\(windowID)|bucket:\(bucketID)|"
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
