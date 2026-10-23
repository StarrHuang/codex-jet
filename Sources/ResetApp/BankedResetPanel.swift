import SwiftUI
import ResetCore

struct BankedResetPanel: View {
    @ObservedObject var model: AppModel
    var compact = false
    private var fresh: Bool {
        guard let stored = model.bankedResets, let snapshot = model.snapshot,
              stored.accountKey == snapshot.accountKey else { return false }
        return stored.sampledAt <= model.now && model.now.timeIntervalSince(stored.sampledAt) <= 600
            && snapshot.sampledAt <= model.now && model.now.timeIntervalSince(snapshot.sampledAt) <= 600
            && model.bankedError == nil
    }
    private var globalTarget: Date? { model.hasTemporaryTarget ? model.extraResetAdvice.deadline : nil }
    private func plan(global: Date?) -> BankedResetPlan {
        BankedResetPlan.evaluate(cards: model.bankedResets?.cards ?? [],
            remaining: model.mainWindow.map { 100 - $0.usedPercent } ?? 0,
            rate: fresh && [.tooSlow, .onTrack, .tooFast, .exhausted].contains(model.normalDeadlinePace?.state ?? .unknown)
                ? model.normalDeadlinePace?.recentRatePerHour : nil,
            normalReset: model.mainWindow?.resetsAt, durationMinutes: model.mainWindow?.durationMinutes,
            globalReset: global, now: model.now)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(L("储备重置卡"), systemImage: "rectangle.stack").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(model.bankedResets.map { L("{{0}} 张可用", String(describing: $0.cards.filter { $0.expiresAt > model.now }.count)) } ?? L("尚未读取"))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink.accent)
            }
            if let error = model.bankedError {
                Text(L(error)).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
            }
            if let stored = model.bankedResets, stored.accountKey == model.snapshot?.accountKey {
                let base = plan(global: nil)
                let projected = plan(global: globalTarget)
                if !fresh {
                    Text(L("重置卡或账户读数过期；刷新后再计算使用安排。"))
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
                if projected.entries.isEmpty {
                    Text(L("当前没有可用的 Codex 全额重置卡。"))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                } else {
                    Text(L("当前主额度剩余 {{0}}%；另有 {{1}} 次手动重置机会。每次恢复到 100%，不与剩余额度叠加。", String(describing: number(model.mainWindow.map { 100 - $0.usedPercent })), String(describing: projected.entries.count)))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
                    if let target = globalTarget {
                        Text(L("情景：临时重置在 {{0}} 到账；它会覆盖当时余量，但不消耗未兑换的卡。", String(describing: L(ResetTimeDisplay.shanghai(target)))))
                            .font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(Array(projected.entries.enumerated()), id: \.element.id) { index, entry in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(L("重置卡 {{0}}", String(describing: index + 1))).font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text(L("{{0}} 到期", String(describing: L(ResetTimeDisplay.shanghai(entry.card.expiresAt)))))
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            Text(L("距最晚兑换还有 ") + L(ResetTimeDisplay.remaining(until: entry.card.expiresAt, now: model.now)))
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(index == 0 ? .orange : ink.secondary)
                            if fresh {
                                if let useAt = entry.estimatedRedeemAt {
                                    Text(L("保持现速、每轮耗尽后用卡：预计 {{0}} 需兑换。", String(describing: L(ResetTimeDisplay.shanghai(useAt)))))
                                        .font(.system(size: 12)).foregroundStyle(ink.accent)
                                } else if let balance = entry.remainingAtExpiry {
                                    Text(L("按此情景，到期时主额度约剩 {{0}}%；等耗尽再用可能来不及，需提前决定是否兑换。", String(describing: number(balance))))
                                        .font(.system(size: 12)).foregroundStyle(.orange)
                                } else {
                                    Text(L("速度样本不足，暂不估算兑换时机。"))
                                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                                }
                                if globalTarget != nil, let baseline = base.entries.first(where: { $0.id == entry.id }), baseline != entry {
                                    Text(baseline.estimatedRedeemAt.map { L("若临时重置未到账：预计 {{0}} 需兑换。", String(describing: L(ResetTimeDisplay.shanghai($0)))) }
                                         ?? L("若临时重置未到账：仍需留意到期前的兑换安排。"))
                                        .font(.system(size: 11)).foregroundStyle(ink.secondary)
                                }
                            }
                        }.fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, 8)
                        if index < projected.entries.count - 1 { Divider().overlay(.white.opacity(0.04)) }
                    }
                    Text(L("北京时间 UTC+8 · 到期是兑换截止，兑换后的额度有自己的周期。预测只看主额度并假定速度不变、按到期顺序手动用卡；兑换可能改变正常重置时间，刷新后以服务端为准。"))
                        .font(.system(size: compact ? 11 : 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text(L("账户接口更新 ") + L(ResetTimeDisplay.shanghai(stored.sampledAt)))
                    .font(.system(size: 11)).foregroundStyle(ink.secondary)
            }
            Link(L("查看账户重置卡 ↗"), destination: URL(string: "https://chatgpt.com/codex/settings/usage")!)
                .font(.system(size: 12)).foregroundStyle(ink.blue)
        }.padding(compact ? 15 : 20).card()
    }
}
