import SwiftUI
import ResetCore

/// A quota clock: the arc is observed balance and the hand moves at measured quota pace.
struct QuotaFlowView: View {
    let remainingPercent: Double?
    let ratePerHour: Double?
    var stale = false
    var announced = false
    var animated = true
    var showsReadout = true
    var runwayLight: DeadlinePace.RunwayLight = .unknown

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var announcementStart: Date?
    @State private var announcementConsumed = false
    @State private var handTurns = 0.0
    @State private var handOrigin = Date()

    private var flow: QuotaFlowState {
        QuotaFlowState(remainingPercent: remainingPercent, stale: stale, ratePerHour: ratePerHour)
    }
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }
    private var motionAllowed: Bool { animated && !reduceMotion && scenePhase == .active }
    private var handSpeed: Double { min(0.06, flow.flowSpeed / 1.5 * 0.06) }
    private var handActive: Bool { motionAllowed && (flow.remainingPercent ?? 0) > 0 && handSpeed > 0 }
    private var readingColor: Color { flow.remainingPercent == nil ? Color.secondary : runwayLight.color }
    private var announcementColor: Color { Color(red: 0.95, green: 0.58, blue: 0.22) }

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
            let compact = outer.size.width < 140
            let diameter = showsReadout
                ? min(outer.size.height - (compact ? 2 : 8), outer.size.width * (compact ? 0.44 : 0.38))
                : min(outer.size.height - 8, outer.size.width - 8)
            Group {
                if !showsReadout {
                    quotaClock(diameter: max(0, diameter))
                        .frame(width: diameter, height: diameter)
                } else {
                    HStack(spacing: compact ? 4 : 8) {
                        quotaClock(diameter: max(0, diameter))
                            .frame(width: diameter, height: diameter)
                        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
                            Text(flow.remainingPercent.map { String(format: L("%.0f%%"), $0) } ?? "—")
                                .font(.system(size: compact ? 18 : 29, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(readingColor)
                                .contentTransition(.numericText())
                                .lineLimit(1).minimumScaleFactor(0.72)
                            if flow.remainingPercent != nil, let ratePerHour, ratePerHour.isFinite, ratePerHour >= 0 {
                                Text(String(format: L("%.1f 点/h"), ratePerHour))
                                    .font(.system(size: compact ? 9 : 10, weight: compact ? .medium : .regular, design: .rounded))
                                    .monospacedDigit().foregroundStyle(compact ? Color.primary.opacity(0.68) : Color.secondary)
                                    .lineLimit(1).minimumScaleFactor(0.7)
                            }
                            if let statusText {
                                Text(statusText)
                                    .font(.system(size: compact ? 7 : 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(flow.remainingPercent == nil ? Color.secondary
                                        : announced ? announcementColor : runwayLight.color)
                                    .lineLimit(1).minimumScaleFactor(0.65)
                            }
                    }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .help(L("时钟表示额度：彩色弧长代表当前剩余额度，指针速度代表近期实测消耗；它不表示实际时间。公告描边只作提示，不代表额度已经恢复。"))
        .onAppear { startAnnouncementIfNeeded() }
        .onChange(of: announced) { _, isAnnounced in
            if isAnnounced { startAnnouncementIfNeeded() }
            else {
                announcementConsumed = false
                announcementStart = nil
            }
        }
        .onChange(of: handSpeed) { oldSpeed, _ in
            let now = Date()
            if motionAllowed { handTurns += now.timeIntervalSince(handOrigin) * oldSpeed }
            handOrigin = now
        }
        .onChange(of: motionAllowed) { wasAllowed, isAllowed in
            let now = Date()
            if wasAllowed { handTurns += now.timeIntervalSince(handOrigin) * handSpeed }
            handOrigin = now
            if isAllowed { startAnnouncementIfNeeded() }
            else { announcementStart = nil }
        }
        .task(id: announcementStart) {
            guard let start = announcementStart else { return }
            do { try await Task.sleep(for: .milliseconds(820)) } catch { return }
            guard announcementStart == start else { return }
            announcementStart = nil
        }
    }

    private func quotaClock(diameter: CGFloat) -> some View {
        let lineWidth = max(2, diameter * 0.045)
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.20), lineWidth: lineWidth)
                .padding(diameter * 0.045)
            if let fraction = flow.fillFraction {
                Circle().trim(from: 0, to: fraction)
                    .stroke(runwayLight.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(motionAllowed ? .easeInOut(duration: 0.5) : nil, value: flow.fillFraction)
                    .padding(diameter * 0.045)
            }
            ClockTicks().stroke(Color.primary.opacity(0.58), style: StrokeStyle(lineWidth: max(1, diameter * 0.025), lineCap: .round))
                .padding(diameter * 0.08)
            if (flow.remainingPercent ?? 0) > 0 {
                if handActive {
                    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !handActive)) { timeline in
                        let turns = handTurns + timeline.date.timeIntervalSince(handOrigin) * handSpeed
                        ClockHand().stroke(Color.primary, style: StrokeStyle(lineWidth: max(1.2, diameter * 0.035), lineCap: .round))
                            .rotationEffect(.degrees(turns.truncatingRemainder(dividingBy: 1) * 360))
                    }
                } else {
                    ClockHand().stroke(Color.primary, style: StrokeStyle(lineWidth: max(1.2, diameter * 0.035), lineCap: .round))
                        .rotationEffect(.degrees(handTurns.truncatingRemainder(dividingBy: 1) * 360))
                }
            }
            if announced {
                if let announcementStart, motionAllowed {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !motionAllowed)) { timeline in
                        let progress = min(1, max(0, timeline.date.timeIntervalSince(announcementStart) / 0.8))
                        Circle().trim(from: 0, to: progress)
                            .stroke(announcementColor, style: StrokeStyle(lineWidth: max(1.5, diameter * 0.035), lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                } else {
                    Circle().stroke(announcementColor, lineWidth: max(1.5, diameter * 0.035))
                }
            }
        }
        .padding(lineWidth / 2)
    }

    private func startAnnouncementIfNeeded() {
        guard announced, motionAllowed, !announcementConsumed else { return }
        announcementConsumed = true
        announcementStart = Date()
    }
}

private struct ClockTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) * 0.48
        let inner = outer * 0.82
        var path = Path()
        for index in 0..<12 {
            let angle = Double(index) * .pi / 6 - .pi / 2
            path.move(to: CGPoint(x: center.x + CGFloat(cos(angle)) * inner, y: center.y + CGFloat(sin(angle)) * inner))
            path.addLine(to: CGPoint(x: center.x + CGFloat(cos(angle)) * outer, y: center.y + CGFloat(sin(angle)) * outer))
        }
        return path
    }
}

private struct ClockHand: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        path.addLine(to: CGPoint(x: center.x, y: rect.minY + min(rect.width, rect.height) * 0.18))
        return path
    }
}
