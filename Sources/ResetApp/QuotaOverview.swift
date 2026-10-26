import SwiftUI
import ResetCore

/// The shared account overview used by the main window and menu popover.
struct QuotaOverview: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    var compact = false
    var selectionAction: (() -> Void)? = nil

    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }

    private var stale: Bool {
        model.snapshot != nil && model.mainWindow != nil && model.liveRemainingPercent == nil
    }

    private var remainingReason: String {
        guard let snapshot = model.snapshot else { return L("等待账户额度读数") }
        guard model.mainWindow != nil else { return L("服务器未返回可显示的额度窗口") }
        if snapshot.sampledAt > model.now { return L("额度采样时间晚于当前时间，暂不显示") }
        if model.now.timeIntervalSince(snapshot.sampledAt) > 600 { return L("额度读数已过期，刷新后再判断") }
        return L("当前额度暂不可用")
    }

    private var deadlineSource: String {
        model.menuDeadlineExplanation ?? L("暂无有效未来截止")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("额度概览")).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if let window = model.mainWindow {
                    Text(windowDisplayName(window)).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink.secondary).lineLimit(1)
                }
            }

            HStack(alignment: .center, spacing: compact ? 12 : 18) {
                QuotaFlowView(remainingPercent: model.liveRemainingPercent,
                              ratePerHour: stale ? nil : model.menuPace?.recentRatePerHour,
                              stale: stale, announced: model.hasTemporaryTarget,
                              showsReadout: false, runwayLight: model.menuRunwayLight)
                    .frame(width: compact ? 88 : 120, height: compact ? 88 : 120)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L("当前剩余")).font(.system(size: 12)).foregroundStyle(ink.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(model.liveRemainingPercent.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: compact ? 48 : 68, weight: .medium, design: .rounded))
                            .monospacedDigit().foregroundStyle(model.liveRemainingPercent == nil ? ink.secondary : .white)
                            .contentTransition(reduceMotion ? .identity : .numericText()).lineLimit(1).minimumScaleFactor(0.72)
                        Text("%").font(.system(size: compact ? 19 : 24, weight: .light)).foregroundStyle(ink.secondary)
                    }
                    if model.liveRemainingPercent == nil {
                        Text(remainingReason).font(.system(size: 12)).foregroundStyle(ink.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(minWidth: compact ? 118 : 156, alignment: .leading)

                Spacer(minLength: compact ? 0 : 8)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(L("最近截止")).font(.system(size: 12)).foregroundStyle(ink.secondary)
                    Text(model.menuDeadlineHours ?? "—")
                        .font(.system(size: compact ? 19 : 23, weight: .medium, design: .monospaced))
                        .monospacedDigit().foregroundStyle(model.menuDeadline == nil ? ink.secondary : .white)
                    Text(deadlineSource).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ink.secondary).multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                    if model.menuDeadline == nil {
                        Text(L("没有可用的未来截止时间"))
                            .font(.system(size: 12)).foregroundStyle(ink.secondary)
                    }
                }.frame(minWidth: compact ? 160 : 205, maxWidth: compact ? 190 : 270, alignment: .trailing)
            }

            if let deadline = model.menuDeadline {
                HStack {
                    Spacer(minLength: 0)
                    Text(L("截止 {{0}} · 北京时间", String(describing: stamp(deadline))))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
            }

            PaceRideView(pace: model.menuPace,
                         targetLabel: deadlineSource,
                         compact: compact,
                         bankedCount: model.usableBankedCount,
                         quotaRemaining: model.liveRemainingPercent,
                         quotaStale: stale,
                         runwayLight: model.menuRunwayLight)
                .padding(.top, 2)

            if let window = model.mainWindow, let reset = window.resetsAt,
               model.liveRemainingPercent != nil, reset > model.now, model.menuDeadline != reset {
                Divider().overlay(.white.opacity(0.06))
                HStack(spacing: 8) {
                    Text(L("正常订阅重置")).font(.system(size: 12, weight: .medium)).foregroundStyle(ink.secondary)
                    Spacer()
                    Text(countdown(reset, now: model.now)).font(.system(size: 12, design: .monospaced))
                    Text(L("{{0}} · 北京时间", String(describing: stamp(reset))))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.secondary)
                }
            }

            if let selectionAction {
                HStack {
                    Spacer()
                    Button(L("分析此额度窗口"), action: selectionAction)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(ink.blue)
                }
            }
        }
        .padding(compact ? 18 : 22)
        .background(ink.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.07), lineWidth: 1))
    }
}
