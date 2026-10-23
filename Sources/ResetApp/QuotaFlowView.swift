import SwiftUI
import ResetCore

/// A direct quota meter: fill is the observed balance and the optional tick shows measured pace.
struct QuotaFlowView: View {
    let remainingPercent: Double?
    let ratePerHour: Double?
    var stale = false
    var announced = false
    var animated = true
    var runwayLight: DeadlinePace.RunwayLight = .unknown

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var outlineStart: Date?
    @State private var announcementConsumed = false
    @State private var flowDistance = 0.0
    @State private var flowOrigin = Date()

    private var flow: QuotaFlowState {
        QuotaFlowState(remainingPercent: remainingPercent, stale: stale, ratePerHour: ratePerHour)
    }
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }
    private var motionAllowed: Bool { animated && !reduceMotion && scenePhase == .active }
    private var announcementColor: Color { Color(red: 0.95, green: 0.58, blue: 0.22) }
    private var flowActive: Bool {
        motionAllowed && (flow.remainingPercent ?? 0) > 0 && flow.flowSpeed > 0
    }
    private var statusText: String? {
        if stale { return L("读数过期") }
        guard flow.remainingPercent != nil else { return L("等待读数") }
        return announced ? L("公告待确认") : nil
    }
    private var accessibilityLabel: String {
        if stale { return L("额度读数已过期；剩余值暂不可用") }
        guard let remaining = flow.remainingPercent else { return L("等待有效额度读数") }
        if let ratePerHour, ratePerHour.isFinite, ratePerHour >= 0 {
            return String(format: L("剩余额度 %.0f%%；近期实测消耗 %.1f 点/h"), remaining, ratePerHour)
        }
        return String(format: L("剩余额度 %.0f%%"), remaining)
    }

    var body: some View {
        GeometryReader { outer in
            let isCompact = outer.size.width < 140
            VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(flow.remainingPercent.map { String(format: L("%.0f%%"), $0) } ?? "—")
                        .font(.system(size: isCompact ? 22 : 32, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(flow.remainingPercent == nil ? Color.secondary
                            : flow.remainingPercent == 0 ? runwayLight.color : Color.primary)
                        .contentTransition(.numericText())
                    Spacer(minLength: 2)
                    if !isCompact, let statusText {
                        Text(statusText)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(flow.remainingPercent == nil ? Color.secondary
                                : announced ? announcementColor : runwayLight.color)
                            .lineLimit(1).minimumScaleFactor(0.72)
                    }
                }

                quotaBar(isCompact: isCompact)

                if flow.remainingPercent != nil, let ratePerHour, ratePerHour.isFinite, ratePerHour >= 0 {
                    Text(String(format: L("%.1f 点/h"), ratePerHour))
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .monospacedDigit().foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .help(L("填充长度表示当前剩余额度；流动刻度表示近期实测消耗。公告轮廓只作提示，不代表额度已经恢复。"))
        .onAppear { startAnnouncementIfNeeded() }
        .onChange(of: announced) { _, isAnnounced in
            if isAnnounced { startAnnouncementIfNeeded() }
            else {
                announcementConsumed = false
                outlineStart = nil
            }
        }
        .onChange(of: flow.flowSpeed) { oldSpeed, _ in
            let now = Date()
            if motionAllowed { flowDistance += now.timeIntervalSince(flowOrigin) * oldSpeed }
            flowOrigin = now
        }
        .onChange(of: motionAllowed) { wasAllowed, isAllowed in
            let now = Date()
            if wasAllowed { flowDistance += now.timeIntervalSince(flowOrigin) * flow.flowSpeed }
            flowOrigin = now
            if isAllowed { startAnnouncementIfNeeded() }
            else { outlineStart = nil }
        }
        .task(id: outlineStart) {
            guard let start = outlineStart else { return }
            do { try await Task.sleep(for: .milliseconds(820)) } catch { return }
            guard outlineStart == start else { return }
            outlineStart = nil
        }
    }

    @ViewBuilder private func quotaBar(isCompact: Bool) -> some View {
        let height: CGFloat = isCompact ? 10 : 15
        let radius: CGFloat = isCompact ? 5 : 6
        GeometryReader { geometry in
            let barWidth = geometry.size.width
            let fillWidth = barWidth * CGFloat(flow.fillFraction ?? 0)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: radius).fill(Color.secondary.opacity(0.20))
                if flow.fillFraction != nil {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(runwayLight.color)
                        .frame(width: fillWidth)
                        .animation(motionAllowed ? .easeInOut(duration: 0.5) : nil,
                                   value: flow.fillFraction)
                }
                if flowActive {
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !flowActive)) { timeline in
                        let turns = (flowDistance + timeline.date.timeIntervalSince(flowOrigin) * flow.flowSpeed) * 0.20
                        let phase = turns.truncatingRemainder(dividingBy: 1)
                        let edgeFade = min(1, min(phase / 0.08, (1 - phase) / 0.08))
                        let x = fillWidth * CGFloat(phase)
                        Capsule()
                            .fill(Color.white.opacity(0.68 * edgeFade))
                            .frame(width: 2, height: max(6, height - 4))
                            .position(x: x, y: height / 2)
                    }
                }
                if announced {
                    if let outlineStart {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !motionAllowed)) { timeline in
                            let progress = min(1, max(0, timeline.date.timeIntervalSince(outlineStart) / 0.8))
                            RoundedRectangle(cornerRadius: radius)
                                .trim(from: 0, to: progress)
                                .stroke(announcementColor, lineWidth: 1.2)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: radius).stroke(announcementColor, lineWidth: 1.2)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius))
        }
        .frame(height: height)
    }

    private func startAnnouncementIfNeeded() {
        guard announced, motionAllowed, !announcementConsumed else { return }
        announcementConsumed = true
        outlineStart = Date()
    }
}
