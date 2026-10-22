import Foundation
import ResetCore

@main struct ReminderTests {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = now.addingTimeInterval(6 * 3600)
        let window = QuotaWindow(id: "codex-week", bucketID: "codex", label: "Codex", usedPercent: 20,
                                 durationMinutes: 10080, resetsAt: now.addingTimeInterval(86400 * 3))
        func advice(_ state: ExtraResetAdvice.State, target: Date? = deadline,
                    basis: ExtraResetAdvice.DeadlineBasis? = .observation) -> ExtraResetAdvice {
            ExtraResetAdvice(state: state, deadline: target, sourceURL: URL(string: "https://x.com/source/status/123"),
                summary: "reset promised", announcementAt: now.addingTimeInterval(-600), deadlineBasis: basis)
        }
        let history = [(-3600.0, 18.0), (-1800.0, 19.0), (0.0, 20.0)].map { offset, used in
            QuotaSnapshot(sampledAt: now.addingTimeInterval(offset), accountKey: "account", plan: nil,
                windows: [QuotaWindow(id: window.id, bucketID: "codex", label: "Codex", usedPercent: used,
                                      durationMinutes: 10080, resetsAt: window.resetsAt)])
        }
        let slow = DeadlinePace.evaluate(window: window, observedAt: now, history: history,
                                         accountKey: "account", deadline: deadline, now: now)
        func evaluate(_ a: ExtraResetAdvice, at: Date = now, observed: Date? = now,
                      w: QuotaWindow? = window, pace: DeadlinePace? = slow) -> ResetReminder? {
            ResetReminder.evaluate(advice: a, window: w, observedAt: observed, accountKey: "account",
                                  temporaryPace: pace, normalPace: pace, now: at)
        }
        let initial = evaluate(advice(.observation))!
        try expect(initial.accelerate, "slow recent speed should encourage acceleration")
        try expect(initial.currentRemaining == 80, "flight capacity carries actual current quota, not the forecast")
        try expect(initial.detail.contains("观察目标") && initial.detail.contains("不保证"), "observation caveat")
        try expect(initial.detail.contains("6.67×"), "measured target multiplier")
        try expect(initial.recentRate == 2 && initial.requiredRate.map { abs($0 - 13.333333) < 0.001 } == true,
                   "fresh eligible pace rates are carried as percentages per hour")
        try expect(initial.projectedRemaining.map { abs($0 - 68) < 0.001 } == true
                   && initial.multiplier.map { abs($0 - 6.666667) < 0.001 } == true,
                   "fresh eligible projection and multiplier are carried")
        try expect(initial.id.hasSuffix("early"), "initial stage")
        let urgent = evaluate(advice(.observation), at: deadline.addingTimeInterval(-3600))!
        let final = evaluate(advice(.observation), at: deadline.addingTimeInterval(-600))!
        try expect(urgent.id.hasSuffix("2h") && final.id.hasSuffix("30m"), "urgency thresholds")
        try expect(initial.eventID == urgent.eventID, "same event across stages")
        try expect(evaluate(advice(.elapsed)) == nil, "elapsed extra and distant normal must not notify")
        try expect(evaluate(advice(.stale)) == nil, "stale source must not notify")
        try expect(evaluate(advice(.recent)) == nil, "confirmed event must not be called upcoming")
        try expect(evaluate(advice(.observation), at: deadline) == nil, "no reminder after target")
        let noTime = evaluate(advice(.announced, target: nil, basis: nil), pace: nil)!
        try expect(noTime.deadline == nil && noTime.detail.contains("尚未明确"), "announcement without invented deadline")
        let staleQuota = evaluate(advice(.observation), observed: now.addingTimeInterval(-601))!
        try expect(!staleQuota.accelerate && !staleQuota.detail.contains("剩余 80")
                   && staleQuota.recentRate == nil && staleQuota.requiredRate == nil
                   && staleQuota.projectedRemaining == nil && staleQuota.multiplier == nil && staleQuota.currentRemaining == nil,
                   "stale account cannot expose pace metrics or suggest multiplier")
        let noPace = evaluate(advice(.observation), pace: nil)!
        try expect(noPace.recentRate == nil && noPace.requiredRate == nil
                   && noPace.projectedRemaining == nil && noPace.multiplier == nil,
                   "unknown pace leaves metric fields absent")
        let noWindow = evaluate(advice(.observation), w: nil, pace: slow)!
        try expect(noWindow.recentRate == nil && noWindow.requiredRate == nil
                   && noWindow.projectedRemaining == nil && noWindow.multiplier == nil,
                   "pace metrics require a current quota reading")
        let zeroHistory = [-3600.0, -1800.0, 0.0].map { offset in
            QuotaSnapshot(sampledAt: now.addingTimeInterval(offset), accountKey: "account", plan: nil,
                windows: [QuotaWindow(id: window.id, bucketID: "codex", label: "Codex", usedPercent: 20,
                                      durationMinutes: 10080, resetsAt: window.resetsAt)])
        }
        let zeroPace = DeadlinePace.evaluate(window: window, observedAt: now, history: zeroHistory,
                                             accountKey: "account", deadline: deadline, now: now)
        let zeroRate = evaluate(advice(.observation), pace: zeroPace)!
        try expect(zeroRate.recentRate == 0 && zeroRate.requiredRate != nil
                   && zeroRate.projectedRemaining == 80 && zeroRate.multiplier == nil,
                   "zero measured rate is truthful and does not invent a finite multiplier")
        let empty = QuotaWindow(id: window.id, bucketID: "codex", label: "Codex", usedPercent: 100,
                                durationMinutes: 10080, resetsAt: window.resetsAt)
        try expect(evaluate(advice(.observation), w: empty)?.accelerate == false, "exhausted quota still receives temporary reset news without acceleration")
        let imminent = QuotaWindow(id: window.id, bucketID: "codex", label: "Codex", usedPercent: 20,
                                   durationMinutes: 10080, resetsAt: deadline)
        try expect(evaluate(advice(.waiting), w: imminent)?.detail.contains("正常订阅") == true, "normal within 24 hours")
        try expect(evaluate(advice(.waiting), observed: now.addingTimeInterval(-601), w: imminent) == nil, "stale normal read")
        let card = BankedResetCard(id: "card", grantedAt: now.addingTimeInterval(-86400), expiresAt: deadline)
        let stored = BankedResetSnapshot(sampledAt: now, accountKey: "account", cards: [card])
        let cardNotice = ResetReminder.banked(stored, accountKey: "account", now: now)
        try expect(cardNotice?.deadline == deadline && cardNotice?.accelerate == false, "card expiry is a redemption reminder, not automatic quota consumption")
        try expect(ResetReminder.banked(stored, accountKey: "other", now: now) == nil, "other account cards excluded")
        try expect(ResetReminder.banked(stored, accountKey: "account", now: now.addingTimeInterval(601)) == nil, "stale card list cannot trigger expiry reminder")
        let combined = ResetReminder.evaluate(advice: advice(.observation), window: window, observedAt: now,
            accountKey: "account", temporaryPace: slow, normalPace: slow, now: now, bankedResets: stored)
        try expect(combined?.detail.contains("另有 1 张储备卡") == true, "temporary reminder includes actual card expiry")
        var ledger = ResetReminderLedger()
        try expect(ledger.shouldPresent(initial, now: now), "first event delivered")
        ledger.record(initial)
        try expect(!ledger.shouldPresent(initial, now: now.addingTimeInterval(300)), "no repeated polling alerts")
        let saved = try JSONEncoder().encode(ledger)
        ledger = try JSONDecoder().decode(ResetReminderLedger.self, from: saved)
        try expect(!ledger.shouldPresent(initial, now: now), "dedupe survives restart")
        try expect(ledger.shouldPresent(urgent, now: deadline.addingTimeInterval(-3600)), "new urgency stage")
        ledger.snooze(initial, now: now)
        try expect(!ledger.shouldPresent(initial, now: now.addingTimeInterval(899)), "snooze suppresses early retries")
        try expect(!ledger.shouldPresent(urgent, now: now.addingTimeInterval(899)), "snooze applies across urgency stages")
        try expect(ledger.shouldPresent(initial, now: now.addingTimeInterval(900)), "snooze can reappear after 15 minutes")
        ledger.record(initial)
        try expect(!ledger.shouldPresent(initial, now: now.addingTimeInterval(901)), "resending clears snooze")
        try expect(!ledger.shouldPresent(initial, now: deadline), "expired reminder never resends")
        let encodedReminder = try JSONEncoder().encode(initial)
        let decodedReminder = try JSONDecoder().decode(ResetReminder.self, from: encodedReminder)
        try expect(decodedReminder == initial, "pace metrics survive reminder serialization")
        let legacy = #"{"id":"legacy","title":"old","detail":"old detail","deadline":null,"expiresAt":900000000,"accelerate":false}"#.data(using: .utf8)!
        let legacyReminder = try JSONDecoder().decode(ResetReminder.self, from: legacy)
        try expect(!legacyReminder.isTest && legacyReminder.recentRate == nil
                   && legacyReminder.requiredRate == nil && legacyReminder.projectedRemaining == nil
                   && legacyReminder.multiplier == nil && legacyReminder.currentRemaining == nil, "legacy reminders decode with absent optional fields")
        print("PASS: reset reminders, source/pace boundaries, urgency, dedupe persistence and snooze")
    }
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw NSError(domain: "ReminderTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
}
