import SwiftUI
import ResetCore

/// Compares recent measured quota pace with the selected deadline target.
struct PaceRideView: View {
    let pace: DeadlinePace?
    var targetLabel = L("正常订阅重置")
    var compact = false
    var bankedCount = 0
    var quotaRemaining: Double? = nil
    var quotaStale = false
    var resetAnnounced = false
    var runwayLight: DeadlinePace.RunwayLight? = nil

    private var ride: RidePace { RidePace(pace) }
    private var tint: Color {
        switch ride.state {
        case .fast: .orange
        case .waiting, .stale, .finished: ink.secondary
        default: ink.accent
        }
    }
    private var title: String {
        switch ride.state {
        case .parked: L("当前没有额度下降")
        case .slow: L("当前节奏偏慢，可以使劲蹬")
        case .steady: L("当前节奏正合适")
        case .fast: bankedCount > 0 ? L("本轮消耗偏快，可用储备卡衔接") : L("当前节奏偏快，留一点后劲")
        case .stale: L("读数已过期，先刷新一下")
        case .finished: pace?.state == .exhausted ? L("额度已用完，等账户重置") : pace?.state == .resetBeforeDeadline ? L("正常重置更早，先看账户窗口") : L("目标已到，以账户确认读数为准")
        case .waiting: L("等待有效速度读数")
        }
    }
    private var detail: String {
        switch ride.state {
        case .parked: return L("近期实测没有额度下降；目标前可能用不完。")
        case .slow:
            if let multiplier = ride.multiplier { return String(format: L("想在目标前用尽，接下来约需 %.1f× 当前速度。"), multiplier) }
            return L("近期实测低于目标速度，可以加快安排手头任务。")
        case .steady: return L("当前实测接近目标速度，保持现在的节奏就好。")
        case .fast:
            let time = pace?.estimatedExhaustionAt.map { L("按现速约 {{0}} 用尽。", String(describing: stamp($0))) } ?? L("现速可能提前用尽。")
            let separator = AppLanguage.isEnglish ? " " : ""
            if bankedCount > 0 { return time + separator + L("另有 {{0}} 次手动重置机会，结合下方卡到期安排决定是否兑换；此处目标速度仅针对当前这一轮。", String(describing: bankedCount)) }
            return time + separator + (ride.multiplier.map { String(format: L("想撑到目标，可放到约 %.2f× 当前速度。"), $0) } ?? L("放慢一点。"))
        case .stale: return L("超过 10 分钟没有有效读数，暂停速度判断。")
        case .finished: return L("不再按这个目标提示加速，以新账户读数为准。")
        case .waiting: return L("没有可靠目标或速度样本不足，不估算加速倍数。")
        }
    }

    var body: some View {
        HStack(spacing: compact ? 14 : 22) {
            flight.frame(width: compact ? 190 : 220, height: compact ? 96 : 105)
            VStack(alignment: .leading, spacing: compact ? 8 : 11) {
                Text(L("近期实测 → {{0}}", String(describing: targetLabel))).font(.system(size: compact ? 10 : 12)).foregroundStyle(ink.secondary)
                Text(title).font(.system(size: compact ? 15 : 19, weight: .semibold)).foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.system(size: compact ? 11 : 12)).foregroundStyle(ink.secondary)
                    .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                HStack(spacing: compact ? 12 : 20) {
                    rate(L("当前"), ride.rate)
                    rate(L("目标"), ride.required)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("本轮目标时预计剩余")).font(.system(size: compact ? 9 : 11)).foregroundStyle(ink.secondary)
                        Text(ride.remaining.map { String(format: "%.0f%%", $0) } ?? "—")
                            .font(.system(size: compact ? 15 : 19, weight: .medium, design: .rounded)).monospacedDigit()
                    }
                }
                if let horizon = pace?.horizonHours, ride.rate != nil {
                    Text(L("最近 {{0}}h · 速度单位：百分点 / 小时", String(describing: Int(horizon))))
                        .font(.system(size: compact ? 9 : 10)).foregroundStyle(ink.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var flight: some View {
        QuotaFlowView(remainingPercent: quotaRemaining,
                           ratePerHour: pace?.state == .stale ? nil : pace?.recentRatePerHour,
                           stale: quotaStale, announced: resetAnnounced,
                           runwayLight: runwayLight ?? pace?.runwayLight ?? .unknown)
    }

    private func rate(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: compact ? 9 : 11)).foregroundStyle(ink.secondary)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: compact ? 15 : 19, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}
