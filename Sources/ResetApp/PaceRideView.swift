import SwiftUI
import ResetCore

/// Presents the forecast for the same deadline selected by the menu bar.
struct PaceRideView: View {
    let pace: DeadlinePace?
    var targetLabel = L("正常订阅重置")
    var compact = false
    var bankedCount = 0
    var quotaRemaining: Double? = nil
    var quotaStale = false
    var resetAnnounced = false
    var runwayLight: DeadlinePace.RunwayLight? = nil

    private var light: DeadlinePace.RunwayLight { runwayLight ?? pace?.runwayLight ?? .unknown }
    private var tint: Color { light.color }

    private var conclusion: String {
        switch pace?.state {
        case .tooSlow: L("按近期实测可撑到目标")
        case .onTrack: L("近期实测接近目标速度")
        case .tooFast: L("可能在目标前用尽")
        case .stale: L("额度读数已过期")
        case .exhausted: L("当前额度已用尽")
        case .resetBeforeDeadline: L("正常重置早于最近目标")
        case .expired: L("最近目标时间已到")
        case .unknown: L("暂时无法判断")
        case nil: L("等待有效速度读数")
        }
    }

    private var detail: String {
        switch pace?.state {
        case .tooSlow:
            return L("按近期实测速度，到目标时预计仍有额度。")
        case .onTrack:
            return L("按近期实测速度，额度接近目标时用尽。")
        case .tooFast:
            if let exhaustion = pace?.estimatedExhaustionAt {
                return L("按近期实测速度，预计 {{0}} 用尽。", String(describing: stamp(exhaustion)))
            }
            return L("近期实测速度高于目标速度，额度可能提前用尽。")
        case .stale:
            return L("超过 10 分钟没有有效额度读数，暂不显示当前预测。")
        case .exhausted:
            return L("以新的账户额度读数确认是否已恢复。")
        case .resetBeforeDeadline:
            return L("正常订阅重置早于此目标；不估算跨周期余量或速度。")
        case .expired:
            return L("目标时间已到，以账户读数确认额度状态。")
        case .unknown:
            if pace?.hoursUntilDeadline == nil {
                return L("没有有效的未来截止时间，暂不估算余量或建议速度。")
            }
            return L("有效速度样本不足，暂不估算余量或建议速度。")
        case nil:
            return L("缺少当前额度或最近截止信息，暂不推断速度。")
        }
    }

    private var projectedRemaining: Double? {
        guard let pace, [.tooSlow, .onTrack, .tooFast].contains(pace.state) else { return nil }
        return pace.projectedRemainingAtDeadline
    }

    private var visibleMeasuredRate: Double? {
        pace?.state == .stale ? nil : pace?.recentRatePerHour
    }

    private var visibleRequiredRate: Double? {
        pace?.state == .stale ? nil : pace?.requiredRatePerHour
    }

    private var speedAdjustment: String {
        switch pace?.state {
        case .tooSlow:
            guard let multiplier = pace?.speedMultiplier else { return L("需启动任务，无法计算有限倍数") }
            return String(format: L("若计划在目标前用尽，可加快至约 %.2f× 当前速度"), multiplier)
        case .tooFast:
            guard let multiplier = pace?.speedMultiplier else { return L("需启动任务，无法计算有限倍数") }
            return String(format: L("若要撑到目标，建议放慢至约 %.2f× 当前速度"), multiplier)
        case .onTrack: return L("保持当前速度")
        default: return "—"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 15) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle().fill(tint).frame(width: 8, height: 8)
                        Text(conclusion).font(.system(size: compact ? 14 : 16, weight: .semibold)).foregroundStyle(tint)
                    }
                    Text(detail).font(.system(size: 12)).foregroundStyle(ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)

                metric(L("目标时预计剩余"), projectedRemaining.map { String(format: "%.0f%%", $0) } ?? "—")
                metric(L("速度调整"), speedAdjustment)
            }

            HStack(spacing: compact ? 22 : 30) {
                rate(L("近期实测速率"), visibleMeasuredRate)
                rate(L("目标所需速度"), visibleRequiredRate)
                if let horizon = pace?.horizonHours, visibleMeasuredRate != nil {
                    Text(L("最近 {{0}}h · 百分点 / 小时", String(describing: Int(horizon))))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                } else {
                    Text(L("速度单位：百分点 / 小时"))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 12)).foregroundStyle(ink.secondary)
            Text(value).font(.system(size: compact ? 14 : 17, weight: .medium, design: .rounded))
                .monospacedDigit().foregroundStyle(.white).lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }.frame(minWidth: compact ? 88 : 112, alignment: .leading)
    }

    private func rate(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(ink.secondary)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.system(size: 14, weight: .medium, design: .rounded)).monospacedDigit()
        }
    }
}
