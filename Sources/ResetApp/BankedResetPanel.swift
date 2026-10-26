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

    private var lastReadUnexpiredCount: Int {
        guard let stored = model.bankedResets else { return 0 }
        return stored.cards.filter { $0.expiresAt > stored.sampledAt }.count
    }

    private var countSummary: String {
        guard let stored = model.bankedResets else { return L("尚未读取") }
        guard stored.accountKey == model.snapshot?.accountKey else { return L("当前账户暂无匹配储备卡数据") }
        let count = fresh
            ? stored.cards.filter { $0.expiresAt > model.now }.count
            : lastReadUnexpiredCount
        return fresh
            ? L("{{0}} 张可用", String(describing: count))
            : L("上次读取 {{0}} 张未到期卡", String(describing: count))
    }

    private func plan(global: Date?) -> BankedResetPlan {
        BankedResetPlan.evaluate(cards: model.bankedResets?.cards ?? [],
            remaining: model.mainWindow.map { 100 - $0.usedPercent } ?? 0,
            rate: fresh && [.tooSlow, .onTrack, .tooFast, .exhausted].contains(model.normalDeadlinePace?.state ?? .unknown)
                ? model.normalDeadlinePace?.recentRatePerHour : nil,
            normalReset: model.mainWindow?.resetsAt, durationMinutes: model.mainWindow?.durationMinutes,
            globalReset: global, now: model.now)
    }

    var body: some View {
        let base = plan(global: nil)
        let projected = plan(global: globalTarget)

        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label(L("储备重置卡"), systemImage: "rectangle.stack").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(countSummary)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ink.secondary)
            }

            if let error = model.bankedError {
                Text(L(error)).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled)
            }

            if let stored = model.bankedResets, stored.accountKey == model.snapshot?.accountKey {
                if !fresh {
                    Text(L("重置卡或账户读数过期；刷新后再计算使用安排。"))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                }

                if projected.entries.isEmpty {
                    Text(emptyCardsMessage)
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                } else {
                    summary(projected.entries)
                    DisclosureGroup(L("全部储备卡与情景假设")) {
                        VStack(alignment: .leading, spacing: 10) {
                            if let globalTarget {
                                Text(L("情景：临时重置在 {{0}} 到账；它会覆盖当时余量，但不消耗未兑换的卡。", String(describing: L(ResetTimeDisplay.shanghai(globalTarget)))))
                                    .font(.system(size: 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
                            }

                            ForEach(Array(projected.entries.enumerated()), id: \.element.id) { index, entry in
                                cardDetail(index: index, entry: entry, base: base, globalTarget: globalTarget)
                                if index < projected.entries.count - 1 { Divider().overlay(.white.opacity(0.05)) }
                            }

                            Text(L("北京时间 UTC+8 · 到期是兑换截止，兑换后的额度有自己的周期。预测只看主额度并假定速度不变、按到期顺序手动用卡；兑换可能改变正常重置时间，刷新后以服务端为准。"))
                                .font(.system(size: 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
                            Text(L("账户接口更新 ") + L(ResetTimeDisplay.shanghai(stored.sampledAt)))
                                .font(.system(size: 12)).foregroundStyle(ink.secondary)
                        }
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .tint(ink.secondary)
                }
            }

            Link(L("查看账户重置卡 ↗"), destination: URL(string: "https://chatgpt.com/codex/settings/usage")!)
                .font(.system(size: 12)).foregroundStyle(ink.blue)
        }
        .padding(compact ? 15 : 20)
        .card()
    }

    private var emptyCardsMessage: String {
        if fresh { return L("当前没有可用的 Codex 全额重置卡。") }
        if lastReadUnexpiredCount > 0 {
            return L("上次读取记录的未到期卡片已过到期时间；刷新确认当前兑换资格。")
        }
        return L("上次读取时没有未到期储备卡；刷新后确认当前状态。")
    }

    @ViewBuilder
    private func summary(_ entries: [BankedResetPlan.Entry]) -> some View {
        if let first = entries.first {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(fresh
                     ? L("{{0}} 张储备卡", String(describing: entries.count))
                     : L("上次读取 {{0}} 张储备卡", String(describing: entries.count)))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(fresh
                     ? L("最早 {{0}} 到期", String(describing: L(ResetTimeDisplay.shanghai(first.card.expiresAt))))
                     : L("上次记录最早 {{0}} 到期", String(describing: L(ResetTimeDisplay.shanghai(first.card.expiresAt)))))
                    .font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(ink.secondary)
            }
            Text(L("需手动兑换；不会自动回补，也不会把卡额度叠加到当前余量。"))
                .font(.system(size: 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)

            if fresh {
                if let useAt = first.estimatedRedeemAt {
                    Text(L("按此情景预计 {{0}} 需兑换最早到期的卡。", String(describing: L(ResetTimeDisplay.shanghai(useAt)))))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
                } else if let balance = first.remainingAtExpiry {
                    Text(L("按此情景，到期时主额度约剩 {{0}}%；等耗尽再用可能来不及，需提前决定是否兑换。", String(describing: number(balance))))
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(L("速度样本不足，暂不估算最早卡的兑换时机。"))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                }
            } else {
                Text(L("卡片状态已过期；上次读数不能确认当前卡片是否仍可兑换。"))
                    .font(.system(size: 12)).foregroundStyle(ink.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        }
    }

    private func cardDetail(index: Int, entry: BankedResetPlan.Entry,
                            base: BankedResetPlan, globalTarget: Date?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("重置卡 {{0}}", String(describing: index + 1))).font(.system(size: 12, weight: .semibold))
                Spacer()
                Text(L("{{0}} 到期", String(describing: L(ResetTimeDisplay.shanghai(entry.card.expiresAt)))))
                    .font(.system(size: 12, design: .monospaced))
            }
            if fresh {
                Text(L("距最晚兑换还有 ") + L(ResetTimeDisplay.remaining(until: entry.card.expiresAt, now: model.now)))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.secondary)
            } else {
                Text(L("按上次读取记录的到期时间；当前兑换资格需刷新确认。"))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.secondary)
            }

            if fresh {
                if let useAt = entry.estimatedRedeemAt {
                    Text(L("保持现速、每轮耗尽后用卡：预计 {{0}} 需兑换。", String(describing: L(ResetTimeDisplay.shanghai(useAt)))))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                } else if let balance = entry.remainingAtExpiry {
                    Text(L("按此情景，到期时主额度约剩 {{0}}%；等耗尽再用可能来不及，需提前决定是否兑换。", String(describing: number(balance))))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                } else {
                    Text(L("速度样本不足，暂不估算兑换时机。"))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                }
                if globalTarget != nil,
                   let baseline = base.entries.first(where: { $0.id == entry.id }), baseline != entry {
                    Text(baseline.estimatedRedeemAt.map { L("若临时重置未到账：预计 {{0}} 需兑换。", String(describing: L(ResetTimeDisplay.shanghai($0)))) }
                         ?? L("若临时重置未到账：仍需留意到期前的兑换安排。"))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 5)
    }
}
