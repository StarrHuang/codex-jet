import SwiftUI
import ResetCore

/// Repeatable, explicit CLI fixtures. Monitoring is disabled before any view task can run.
@MainActor
enum PresentationProof {
    static func model(state: String) throws -> AppModel {
        guard ["normal", "balanced", "fast", "temporary", "untimed", "banked", "stale", "waiting"].contains(state) else {
            throw NSError(domain: "PresentationProof", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unknown presentation proof state: " + state])
        }
        let model = AppModel(monitoringEnabled: false)
        let now = Date()
        model.now = now
        guard state != "waiting" else { return model }
        let account = "preview-account"
        let rate = state == "fast" ? 4.2 : state == "temporary" ? 6.1 : state == "balanced" ? 1.05 : 0.9
        let reset = now.addingTimeInterval(60 * 3600)
        let window = QuotaWindow(id: "codex:primary", bucketID: "codex", label: "Codex", usedPercent: 37,
                                 durationMinutes: 10080, resetsAt: reset)
        let age = state == "stale" ? 720.0 : 0.0
        model.snapshot = QuotaSnapshot(sampledAt: now.addingTimeInterval(-age), accountKey: account,
                                       plan: "Pro", windows: [window])
        model.history = [-6.0, -4, -2, -1, -0.5, -0.25, 0].map { hours in
            QuotaSnapshot(sampledAt: now.addingTimeInterval(hours * 3600 - age), accountKey: account, plan: "Pro",
                          windows: [QuotaWindow(id: window.id, bucketID: window.bucketID, label: window.label,
                                                usedPercent: 37 + hours * rate, durationMinutes: 10080, resetsAt: reset)])
        }
        model.selectedWindowID = window.id
        model.bankedResets = BankedResetSnapshot(sampledAt: now.addingTimeInterval(-age), accountKey: account,
            cards: [BankedResetCard(id: "preview-card", grantedAt: now.addingTimeInterval(-86400),
                expiresAt: now.addingTimeInterval((state == "banked" ? 8 : 84) * 3600))])
        let formatter = ISO8601DateFormatter()
        var forecast: [String: Any] = ["updated_at": formatter.string(from: now), "probabilities": [:], "confidence": "low"]
        if state == "temporary" {
            forecast["official_signal"] = ["at": formatter.string(from: now.addingTimeInterval(-600)),
                "summary": "A reset is scheduled within the next four hours.", "url": "https://x.com/thsottiaux/status/preview",
                "window": ["label": "in four hours", "end_at": formatter.string(from: now.addingTimeInterval(4 * 3600))]]
        }
        if state == "untimed" {
            forecast["official_signal"] = ["at": formatter.string(from: now.addingTimeInterval(-600)),
                "signal_type": "promise", "tweet_id": "preview-promise", "summary": "An additional reset has been announced; timing is not yet confirmed.",
                "url": "https://x.com/thsottiaux/status/preview"]
        }
        model.radar = RadarData(forecast: try JSONDecoder().decode(RadarForecast.self, from: JSONSerialization.data(withJSONObject: forecast)),
            timeline: try JSONDecoder().decode(RadarTimeline.self, from: Data(#"{"updated_at":"preview","events":[]}"#.utf8)), fetchedAt: now)
        let hour = Calendar.current.dateInterval(of: .hour, for: now)!.start
        let rows = (0..<24).flatMap { index in
            ["gpt-6-luna", "gpt-6.1-sol"].enumerated().map { modelIndex, name in
                let input = Int64((index * 7919 + modelIndex * 17431) % 240_000 + 12_721)
                let output = input / 7
                return HourlyModelTokens(hour: hour.addingTimeInterval(Double(-index) * 3600), model: name,
                    inputTokens: input, cachedInputTokens: input / 3, outputTokens: output,
                    reasoningOutputTokens: output / 4, totalTokens: input + output, eventCount: index % 5 + 1)
            }
        }
        model.tokenReport = LocalTokenReport(generatedAt: now, rows: rows, filesRead: 12, latestEventAt: now)
        return model
    }
}
