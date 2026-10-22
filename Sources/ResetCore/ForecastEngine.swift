import Foundation

public enum ForecastEngine {
    public static let minimumSamples = 3
    public static let minimumSpan: TimeInterval = 15 * 60
    public static let maximumAge: TimeInterval = 10 * 60
    public static let recentHorizon: TimeInterval = 24 * 60 * 60

    public static func cycleSamples(
        window: QuotaWindow,
        history: [QuotaSnapshot],
        accountKey: String) -> [QuotaSnapshot]
    {
        let series = history.filter { snapshot in
            snapshot.accountKey == accountKey
                && snapshot.windows.contains(where: { $0.id == window.id && $0.bucketID == window.bucketID && sameQuotaResetTime($0.resetsAt, window.resetsAt) })
        }.sorted { $0.sampledAt < $1.sampledAt }
        var cycle: [QuotaSnapshot] = []
        for snapshot in series {
            let usage = snapshot.windows.first(where: { $0.id == window.id && $0.bucketID == window.bucketID })!.usedPercent
            if let previous = cycle.last,
               usage < previous.windows.first(where: { $0.id == window.id && $0.bucketID == window.bucketID })!.usedPercent
            {
                cycle = [snapshot]
            } else {
                cycle.append(snapshot)
            }
        }
        return cycle
    }

    public static func forecast(
        window: QuotaWindow,
        history: [QuotaSnapshot],
        accountKey: String,
        now: Date = .now) -> WindowForecast
    {
        let series = history.compactMap { snapshot -> (Date, QuotaWindow)? in
            guard snapshot.accountKey == accountKey,
                  let match = snapshot.windows.first(where: { $0.id == window.id && $0.bucketID == window.bucketID }),
                  sameQuotaResetTime(match.resetsAt, window.resetsAt)
            else { return nil }
            return (snapshot.sampledAt, match)
        }.sorted { $0.0 < $1.0 }

        let snapshotsInCycle = cycleSamples(window: window, history: history, accountKey: accountKey)
        let cycle = snapshotsInCycle.compactMap { snapshot -> (Date, QuotaWindow)? in
            guard let matching = snapshot.windows.first(where: { $0.id == window.id && $0.bucketID == window.bucketID }) else { return nil }
            return (snapshot.sampledAt, matching)
        }

        let cycleSamples = cycle.map { QuotaSamplePoint(sampledAt: $0.0, usedPercent: $0.1.usedPercent) }
        let latestSampleAt = series.last?.0 ?? now
        let baselineRate = window.durationMinutes.flatMap { duration -> Double? in
            guard duration > 0, let reset = window.resetsAt else { return nil }
            let total = TimeInterval(duration * 60)
            let elapsed = min(total, total - reset.timeIntervalSince(latestSampleAt))
            guard elapsed > 0 else { return nil }
            return window.usedPercent / (elapsed / 3600)
        }

        guard let reset = window.resetsAt, reset > now else {
            return WindowForecast(state: .waitingForReset, baselineRatePerHour: baselineRate, cycleSamples: cycleSamples)
        }
        let hoursUntilReset = reset.timeIntervalSince(now) / 3600
        let requiredRate = max(0, 100 - window.usedPercent) / hoursUntilReset
        guard let latest = series.last else {
            return WindowForecast(
                state: .insufficientHistory,
                baselineRatePerHour: baselineRate,
                requiredRatePerHour: requiredRate)
        }
        let latestAge = now.timeIntervalSince(latest.0)
        guard latestAge >= 0, latestAge <= maximumAge else {
            return WindowForecast(state: .stale, cycleSamples: cycleSamples)
        }

        let recentCycle = cycle.filter { $0.0 >= now.addingTimeInterval(-recentHorizon) }

        guard recentCycle.count >= minimumSamples,
              let first = recentCycle.first,
              let last = recentCycle.last,
              last.0.timeIntervalSince(first.0) >= minimumSpan
        else {
            return WindowForecast(
                state: .insufficientHistory,
                baselineRatePerHour: baselineRate,
                requiredRatePerHour: requiredRate,
                cycleSamples: cycleSamples)
        }

        let spanHours = last.0.timeIntervalSince(first.0) / 3600
        let recentRate = (last.1.usedPercent - first.1.usedPercent) / spanHours
        let exhaustion = recentRate > 0
            ? now.addingTimeInterval(max(0, 100 - window.usedPercent) / recentRate * 3600)
            : nil
        let projection = window.usedPercent + recentRate * hoursUntilReset
        let multiplier = baselineRate.flatMap { $0 > 0 ? recentRate / $0 : nil }

        return WindowForecast(
            state: .ready,
            baselineRatePerHour: baselineRate,
            recentRatePerHour: recentRate,
            requiredRatePerHour: requiredRate,
            estimatedExhaustionAt: exhaustion,
            projectedUsedAtReset: projection,
            recentToBaselineMultiplier: multiplier,
            cycleSamples: cycleSamples)
    }
}
