import SwiftUI
import ResetCore

/// Explicit CLI-only synthetic scenes. Never creates an AppModel, samples history, or sends notifications.
struct RideProofScene: View {
    let state: String
    private let now = Date()
    private var pace: DeadlinePace? {
        if state == "unknown" || state == "waiting" { return nil }
        let rate = state == "parked" ? 0.0 : state == "steady" ? 10 : state == "fast" ? 20 : 2
        let reset = now.addingTimeInterval(21600)
        let window = QuotaWindow(id: "proof", bucketID: "codex", label: "Codex", usedPercent: 40,
                                 durationMinutes: 10080, resetsAt: reset)
        let history = [-1800.0, -900, 0].map { offset in
            QuotaSnapshot(sampledAt: now.addingTimeInterval(offset), accountKey: "synthetic-proof", plan: nil,
                windows: [QuotaWindow(id: "proof", bucketID: "codex", label: "Codex", usedPercent: 40 + offset / 3600 * rate,
                                      durationMinutes: 10080, resetsAt: reset)])
        }
        return DeadlinePace.evaluate(window: window, observedAt: now.addingTimeInterval(state == "stale" ? -601 : 0),
            history: history, accountKey: "synthetic-proof", deadline: reset, now: now)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L("动效验收 · 合成场景 / {{0}}", String(describing: state))).font(.system(size: 13)).foregroundStyle(ink.secondary)
            if state == "temporary" {
                TemporaryResetBanner(advice: ExtraResetAdvice(state: .observation, deadline: now.addingTimeInterval(21600),
                    sourceURL: nil, summary: L("验收用公告；并非当前真实重置预告。"), announcementAt: now,
                    deadlineBasis: .observation), pace: pace, window: nil, now: now, compact: true)
            } else if state == "reminder" {
                ResetReminderCard(reminder: ResetReminder(id: "synthetic-proof", title: L("验收提醒 · 节奏偏慢，使劲蹬"),
                    detail: L("合成行为验收，不是实际重置公告。站点观察目标不保证准时到账。"),
                    deadline: now.addingTimeInterval(21600), expiresAt: now.addingTimeInterval(21600), accelerate: true,
                    isTest: true, recentRate: 2, requiredRate: 10, projectedRemaining: 48, multiplier: 5, currentRemaining: 60),
                    acknowledge: {}, snooze: {}, open: {})
            } else {
                PaceRideView(pace: pace, compact: true, quotaRemaining: state == "unknown" || state == "waiting" ? nil : 60, quotaStale: state == "stale").padding(20).card()
            }
            Text(L("仅验证显示与数据边界，不读取账户、不写历史、不发通知。"))
                .font(.system(size: 11)).foregroundStyle(ink.secondary)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .foregroundStyle(.white).background(ink.background).preferredColorScheme(.dark)
            .environment(\.scenePhase, .active)
    }
}
