import Foundation
import ResetCore

struct ResetReminder: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let title: String
    let detail: String
    let deadline: Date?
    let expiresAt: Date
    let accelerate: Bool
    var isTest = false
    let recentRate: Double?
    let requiredRate: Double?
    let projectedRemaining: Double?
    let multiplier: Double?
    let currentRemaining: Double?
    var eventID: String { id.split(separator: "|").dropLast().joined(separator: "|") }

    private enum CodingKeys: String, CodingKey {
        case id, title, detail, deadline, expiresAt, accelerate, isTest
        case recentRate, requiredRate, projectedRemaining, multiplier, currentRemaining
    }

    init(id: String, title: String, detail: String, deadline: Date?, expiresAt: Date,
         accelerate: Bool, isTest: Bool = false, recentRate: Double? = nil,
         requiredRate: Double? = nil, projectedRemaining: Double? = nil, multiplier: Double? = nil, currentRemaining: Double? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.deadline = deadline
        self.expiresAt = expiresAt
        self.accelerate = accelerate
        self.isTest = isTest
        self.recentRate = recentRate
        self.requiredRate = requiredRate
        self.projectedRemaining = projectedRemaining
        self.multiplier = multiplier
        self.currentRemaining = currentRemaining
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        detail = try values.decode(String.self, forKey: .detail)
        deadline = try values.decodeIfPresent(Date.self, forKey: .deadline)
        expiresAt = try values.decode(Date.self, forKey: .expiresAt)
        accelerate = try values.decode(Bool.self, forKey: .accelerate)
        isTest = try values.decodeIfPresent(Bool.self, forKey: .isTest) ?? false
        recentRate = try values.decodeIfPresent(Double.self, forKey: .recentRate)
        requiredRate = try values.decodeIfPresent(Double.self, forKey: .requiredRate)
        projectedRemaining = try values.decodeIfPresent(Double.self, forKey: .projectedRemaining)
        multiplier = try values.decodeIfPresent(Double.self, forKey: .multiplier)
        currentRemaining = try values.decodeIfPresent(Double.self, forKey: .currentRemaining)
    }

    static func evaluate(advice: ExtraResetAdvice, window: QuotaWindow?, observedAt: Date?,
                         accountKey: String?, temporaryPace: DeadlinePace?, normalPace: DeadlinePace?,
                         now: Date, bankedResets: BankedResetSnapshot? = nil) -> ResetReminder? {
        let fresh = observedAt.map { $0 <= now && now.timeIntervalSince($0) <= 600 } ?? false
        let remaining = fresh ? window.map { max(0, 100 - $0.usedPercent) } : nil
        let isTemporary = [.upcoming, .observation, .announced].contains(advice.state)
        if remaining == 0 && !isTemporary { return nil }
        let deadline: Date?
        let expiry: Date
        let event: String
        let basis: String
        let pace: DeadlinePace?
        if isTemporary {
            deadline = advice.deadline
            guard let announced = advice.announcementAt else { return nil }
            expiry = deadline ?? announced.addingTimeInterval(86400)
            guard expiry > now else { return nil }
            event = "extra-\(advice.sourceURL?.absoluteString ?? String(announced.timeIntervalSince1970))"
            basis = deadline == nil ? L("公告尚未明确到账时间") : advice.targetName + L("，不保证准时到账，以账户实际到账为准")
            pace = temporaryPace
        } else {
            guard fresh, let window, window.bucketID == "codex", let reset = window.resetsAt,
                  reset > now, reset.timeIntervalSince(now) <= 86400 else { return nil }
            deadline = reset
            expiry = reset
            event = "normal-\(accountKey ?? "unknown")-\(window.id)"
            basis = L("正常订阅重置 · 服务端时间")
            pace = normalPace
        }
        let stage = deadline.map { $0.timeIntervalSince(now) <= 1800 ? "30m" : $0.timeIntervalSince(now) <= 7200 ? "2h" : "early" } ?? "announced"
        let targetKey = deadline.map { String(Int(($0.timeIntervalSince1970 / 60).rounded())) } ?? "unknown"
        let canAccelerate = (remaining ?? 0) > 0 && pace?.state == .tooSlow
        let paceIsEligible = fresh && remaining != nil
            && [.tooSlow, .onTrack, .tooFast].contains(pace?.state ?? .unknown)
        let recentRate = paceIsEligible ? pace?.recentRatePerHour : nil
        let requiredRate = paceIsEligible ? pace?.requiredRatePerHour : nil
        let projectedRemaining = paceIsEligible ? pace?.projectedRemainingAtDeadline : nil
        let hasBanked = bankedResets.map { stored in
            stored.accountKey == accountKey && stored.sampledAt <= now && now.timeIntervalSince(stored.sampledAt) <= 600
                && stored.cards.contains { $0.expiresAt > now }
        } ?? false
        let multiplier = paceIsEligible && !(hasBanked && pace?.state == .tooFast) ? pace?.speedMultiplier : nil
        var detail = deadline.map { L("{{0}} · 上海时间\n", String(describing: dateText($0))) } ?? ""
        detail += basis
        if let deadline { detail += L(" · 还有 ") + L(ResetTimeDisplay.remaining(until: deadline, now: now)) }
        if let note = advice.conversionNote { detail += "\n" + note }
        if let remaining { detail += String(format: L("\nCodex 整体额度剩余 %.0f%%。"), remaining) }
        else { detail += L("\n先刷新账户读数，确认剩余额度。") }
        if remaining == 0 {
            detail += L("等待重置到账后再继续任务。")
        } else if canAccelerate, let multiplier {
            detail += String(format: L("按近期实测速率，目标前可能用不完；想用尽需约 %.2f× 当前速度，可以使劲蹬！"), multiplier)
        } else if canAccelerate {
            detail += L("近期消耗较慢，目标前可能用不完，可以使劲蹬！")
        } else if pace?.state == .onTrack {
            detail += L("当前速度接近目标节奏，稳稳蹬。")
        } else if pace?.state == .tooFast {
            detail += hasBanked ? L("本轮预计提前用尽，可结合储备卡到期安排手动衔接。") : L("当前速度预计会提前用尽，留意剩余额度。")
        } else if remaining != nil {
            detail += L("抓紧安排要做的任务；速度样本不足时不估算加速倍数。")
        }
        if let stored = bankedResets, stored.accountKey == accountKey,
           stored.sampledAt <= now, now.timeIntervalSince(stored.sampledAt) <= 600,
           let card = stored.cards.filter({ $0.expiresAt > now }).min(by: { $0.expiresAt < $1.expiresAt }) {
            detail += L("\n另有 {{0}} 张储备卡；最早 {{1}} 到期，距兑换截止还有 {{2}}。用卡恢复到 100%，不与余量相加；全局重置不消耗未用卡。", String(describing: stored.cards.filter { $0.expiresAt > now }.count), String(describing: dateText(card.expiresAt)), String(describing: L(ResetTimeDisplay.remaining(until: card.expiresAt, now: now))))
        }
        let title = canAccelerate ? L("⚡ 重置快到了，使劲蹬！") : isTemporary ? L("⚡ 有临时重置预告，抓紧安排使用") : L("⏰ 正常重置快到了，看看剩余额度")
        return ResetReminder(id: "\(event)|\(targetKey)|\(stage)", title: title, detail: detail,
                             deadline: deadline, expiresAt: expiry, accelerate: canAccelerate,
                             recentRate: recentRate, requiredRate: requiredRate,
                             projectedRemaining: projectedRemaining, multiplier: multiplier, currentRemaining: remaining)
    }

    static func banked(_ stored: BankedResetSnapshot?, accountKey: String?, now: Date) -> ResetReminder? {
        guard let stored, stored.accountKey == accountKey, stored.sampledAt <= now,
              now.timeIntervalSince(stored.sampledAt) <= 600,
              let card = stored.cards.filter({ $0.expiresAt > now }).min(by: { $0.expiresAt < $1.expiresAt }),
              card.expiresAt.timeIntervalSince(now) <= 86400 else { return nil }
        let seconds = card.expiresAt.timeIntervalSince(now)
        let stage = seconds <= 1800 ? "30m" : seconds <= 7200 ? "2h" : "early"
        return ResetReminder(id: "banked-\(stored.accountKey)-\(card.id)|\(Int(card.expiresAt.timeIntervalSince1970))|\(stage)",
            title: L("储备重置卡即将到期，记得安排兑换"),
            detail: L("最早一张 {{0}} 到期（北京时间），还有 {{1}}。\n这是手动兑换截止；兑换后主额度恢复到 100%，不叠加剩余额度。打开额度驾驶舱查看按现速预计的兑换时机；临时全局重置可能覆盖余量，但不会消耗未兑换的卡。", String(describing: dateText(card.expiresAt)), String(describing: L(ResetTimeDisplay.remaining(until: card.expiresAt, now: now)))),
            deadline: card.expiresAt, expiresAt: card.expiresAt, accelerate: false)
    }

    static func test(now: Date) -> ResetReminder {
        ResetReminder(id: "notification-test", title: L("🔔 测试提醒 · 使劲蹬！"),
                      detail: L("这是一条测试通知，用于验证声音、系统通知和常驻提醒窗。\n不是实际重置公告，也不会产生额度消耗。"),
                      deadline: nil, expiresAt: now.addingTimeInterval(900), accelerate: true, isTest: true, currentRemaining: 60)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = L("M月d日 HH:mm")
        return formatter.string(from: date)
    }
}

/// Sent stages and explicit snoozes survive app relaunches; freshness is checked by the caller.
struct ResetReminderLedger: Codable {
    var sent: [String: Date] = [:]
    var snoozed: [String: Date] = [:]

    mutating func shouldPresent(_ reminder: ResetReminder, now: Date) -> Bool {
        sent = sent.filter { $0.value > now }
        snoozed = snoozed.filter { event, _ in sent.keys.contains { $0.hasPrefix(event + "|") } }
        guard reminder.expiresAt > now else { return false }
        if let wake = snoozed[reminder.eventID] { return wake <= now }
        return sent[reminder.id] == nil
    }
    mutating func record(_ reminder: ResetReminder) {
        sent[reminder.id] = reminder.expiresAt
        snoozed.removeValue(forKey: reminder.eventID)
    }
    mutating func acknowledge(_ reminder: ResetReminder) {
        record(reminder)
    }
    mutating func snooze(_ reminder: ResetReminder, now: Date) {
        sent[reminder.id] = reminder.expiresAt
        snoozed[reminder.eventID] = now.addingTimeInterval(900)
    }
}
