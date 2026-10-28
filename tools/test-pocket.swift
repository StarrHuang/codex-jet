import Foundation
import ResetCore

/// 使用合成账户历史验证 Mac 实际提交的数据，包含截止、速度、作用域和隐私边界。
@main struct PocketChecks {
    static func main() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func snapshot(_ used: Double, at: Date = now, deadline: Date = now.addingTimeInterval(23 * 3600), account: String = "local-account-secret") -> QuotaSnapshot {
            QuotaSnapshot(sampledAt: at, accountKey: account, plan: "fixture",
                windows: [QuotaWindow(id: "codex:secondary", bucketID: "codex", label: "Codex", usedPercent: used,
                                      durationMinutes: 10080, resetsAt: deadline)])
        }
        let latest = snapshot(40)
        let history = [snapshot(39.5, at: now.addingTimeInterval(-1800)), snapshot(39.75, at: now.addingTimeInterval(-900)), latest]
        func candidate(_ snapshot: QuotaSnapshot = latest, samples: [QuotaSnapshot] = history,
                       banked: BankedResetSnapshot? = nil, at: Date = now) -> PocketPersonalReminder? {
            PocketPersonalReminder.make(snapshot: snapshot, history: samples, banked: banked,
                                        accountRef: "random-binding-scope", bindingID: "binding-fixture", now: at)
        }
        guard let result = candidate() else { fatalError("23h / 60% / 1pph should remind") }
        precondition(result.observation.remainingPercent == 60)
        precondition(abs(result.observation.ratePercentPerHour - 1) < 0.001)
        precondition(result.observation.sampleCount == 3 && result.observation.sampleSpanSeconds == 1800)
        precondition(result.event.kind == "weekly")
        precondition(result.expiresAt == now.addingTimeInterval(600))
        precondition(candidate(at: now.addingTimeInterval(601)) == nil, "Stale samples must stop")
        precondition(candidate(samples: Array(history.prefix(2))) == nil, "Three samples are required")
        let fast = [snapshot(38.5, at: now.addingTimeInterval(-1800)), snapshot(39.25, at: now.addingTimeInterval(-900)), latest]
        precondition(candidate(samples: fast) == nil, "3pph will use 60% before 23h")
        let other = history.map { snapshot($0.windows[0].usedPercent, at: $0.sampledAt, account: "other") }
        precondition(candidate(samples: other) == nil, "Do not mix account histories")
        let outside = snapshot(40, deadline: now.addingTimeInterval(25 * 3600))
        precondition(candidate(outside, samples: [outside]) == nil)
        let card = BankedResetSnapshot(sampledAt: now, accountKey: latest.accountKey, cards: [
            BankedResetCard(id: "card-fixture", grantedAt: now.addingTimeInterval(-86400), expiresAt: now.addingTimeInterval(8 * 3600))])
        let cardReminder = candidate(banked: card)!
        precondition(cardReminder.event.kind == "bankedExpiry" && cardReminder.event.deadline == now.addingTimeInterval(8 * 3600))
        let wrongCard = BankedResetSnapshot(sampledAt: now, accountKey: "other", cards: card.cards)
        precondition(candidate(banked: wrongCard)?.event.kind == "weekly")
        let lateCard = BankedResetSnapshot(sampledAt: now, accountKey: latest.accountKey, cards: [
            BankedResetCard(id: "later", grantedAt: now.addingTimeInterval(-86400), expiresAt: now.addingTimeInterval(24 * 3600))])
        precondition(candidate(banked: lateCard)?.event.kind == "weekly", "Prefer earlier automatic reset")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(result)
        let text = String(decoding: encoded, as: UTF8.self)
        precondition(!text.contains(latest.accountKey) && !text.contains("access_token") && !text.contains("plan"))
        let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(json["schemaVersion"] as? Int == 2 && json["isSynthetic"] as? Bool == false)
        precondition(candidate()?.dedupeKey == result.dedupeKey, "Stable cycle key independent of attempt UUID")
        precondition(candidate()?.id != result.id)
        for invalid in ["http://example.com", "https://user:pass@example.com", "https://example.com/?token=x", "https://example.com/other"] {
            do { _ = try PocketRelayClient(server: URL(string: invalid)!, allowLocalHTTP: true); fatalError("Invalid origin accepted") }
            catch PocketRelayError.invalidServer { }
        }
        _ = try PocketRelayClient(server: URL(string: "https://example.com")!)
        _ = try PocketRelayClient(server: URL(string: "http://127.0.0.1:8000")!, allowLocalHTTP: true)
        do { _ = try PocketRelayClient(server: URL(string: "http://127.0.0.1:8000")!); fatalError("Release HTTP accepted") }
        catch PocketRelayError.invalidServer { }
        print("PASS: Mac personal reminder forecast, cycle/account isolation, card deadline, stale/fast suppression, payload privacy, stable dedupe and URL boundaries")
    }
}
