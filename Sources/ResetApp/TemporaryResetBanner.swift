import SwiftUI
import ResetCore

struct TemporaryResetBanner: View {
    let advice: ExtraResetAdvice
    let pace: DeadlinePace?
    let window: QuotaWindow?
    let now: Date
    var observationError: String? = nil
    var compact = false
    var bankedCount = 0
    var runwayLight: DeadlinePace.RunwayLight? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }

    private let green = Color(red: 0.28, green: 0.96, blue: 0.53)
    private let amber = Color(red: 1.00, green: 0.66, blue: 0.27)
    private let muted = Color.white.opacity(0.54)
    private var paceState: DeadlinePace.State { pace?.state ?? .unknown }

    @ViewBuilder
    var body: some View {
        if shouldShow {
            banner
        }
    }

    private var shouldShow: Bool {
        switch advice.state {
        case .upcoming, .observation, .announced, .elapsed, .recent: return true
        case .stale: return advice.summary != nil || advice.announcementAt != nil
        case .waiting, .unknown: return false
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 13) {
            HStack(alignment: .center, spacing: 9) {
                statusPill
                Text(headline).font(.system(size: compact ? 13 : 17, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 4)

            }

            if let summary = advice.summary, !summary.isEmpty {
                Text(summary).font(.system(size: compact ? 10 : 13)).foregroundStyle(muted)
                    .lineLimit(compact ? 2 : 3).fixedSize(horizontal: false, vertical: true)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    deadlineBlock(at: context.date)
                    Spacer()
                    Image(systemName: "scope").font(.system(size: compact ? 22 : 30)).foregroundStyle(amber)
                }
            }
            if let note = advice.conversionNote {
                Text(note).font(.system(size: compact ? 10 : 12)).foregroundStyle(amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            PaceRideView(pace: pace,
                         targetLabel: advice.targetName, compact: compact, bankedCount: bankedCount,
                         quotaRemaining: window.map { 100 - $0.usedPercent }, quotaStale: pace?.state == .stale,
                         resetAnnounced: [.upcoming, .observation, .announced].contains(advice.state),
                         runwayLight: runwayLight)

            if advice.state == .announced, let observationError, !observationError.isEmpty {
                Text(observationError).font(.system(size: compact ? 8 : 11)).foregroundStyle(muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 7) {
                Text(L("1h / 6h / 24h 实测速率"))
                    .font(.system(size: compact ? 9 : 11, weight: .medium)).foregroundStyle(muted)
                ForEach(pace?.measurements ?? [], id: \.horizonHours) { measurement in
                    measurementChip(measurement)
                }
                Spacer(minLength: 2)
                if let sourceURL = advice.sourceURL {
                    Link(L("查看来源 ↗"), destination: sourceURL)
                        .font(.system(size: compact ? 9 : 11, weight: .medium)).foregroundStyle(green)
                }
            }

            Text(qualification)
                .font(.system(size: compact ? 8 : 11)).foregroundStyle(muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(compact ? 13 : 17)
        .background(
            LinearGradient(colors: [green.opacity(0.085), amber.opacity(0.035), .white.opacity(0.012)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(accent.opacity(0.47), lineWidth: 1))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.9)).frame(width: 3)
                .padding(.vertical, 12).padding(.leading, 1)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: paceState)
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text(pillTitle).font(.system(size: compact ? 8 : 10, weight: .bold, design: .monospaced)).tracking(0.4)
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(accent.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(accent.opacity(0.27), lineWidth: 0.7))
        .fixedSize()
    }

    private func deadlineBlock(at currentTime: Date) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(deadlineLabel.uppercased())
                .font(.system(size: compact ? 8 : 10, weight: .bold, design: .monospaced)).tracking(1.0).foregroundStyle(muted)
            if advice.state == .stale {
                Text(L("来源数据过期")).font(.system(size: 18, weight: .semibold)).foregroundStyle(amber)
                if let deadline = advice.deadline {
                    Text(L("此前目标 {{0}}", String(describing: stamp(deadline))))
                        .font(.system(size: compact ? 9 : 11, design: .monospaced)).foregroundStyle(muted)
                }
            } else if let deadline = advice.deadline, deadline > currentTime {
                Text(countdown(to: deadline, now: currentTime))
                    .font(.system(size: compact ? 25 : 31, weight: .bold, design: .monospaced))
                    .foregroundStyle(amber)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                Text(L("还有 {{0}} · 北京时间 UTC+8", String(describing: L(ResetTimeDisplay.remaining(until: deadline, now: currentTime)))))
                    .font(.system(size: compact ? 9 : 11, design: .monospaced)).foregroundStyle(muted)
            } else if let deadline = advice.deadline {
                Text(L("窗口已过")).font(.system(size: 19, weight: .semibold)).foregroundStyle(amber)
                Text(L("目标时间 {{0}}", String(describing: stamp(deadline)))).font(.system(size: compact ? 9 : 11, design: .monospaced)).foregroundStyle(muted)
            } else if advice.state == .recent {
                Text(L("已确认")).font(.system(size: 19, weight: .semibold)).foregroundStyle(green)
                Text(L("站点近期确认 · 等账户读数验证")).font(.system(size: compact ? 9 : 12)).foregroundStyle(muted)
            } else {
                Text(L("时间未明确")).font(.system(size: 18, weight: .semibold)).foregroundStyle(amber)
                Text(advice.announcementAt.map { L("公告 {{0}}", String(describing: stamp($0))) } ?? L("暂无可用目标时间"))
                    .font(.system(size: compact ? 9 : 11, design: .monospaced)).foregroundStyle(muted)
            }
            if let basis = advice.deadlineBasis {
                Text(advice.targetName)
                    .font(.system(size: compact ? 8 : 10, weight: .medium)).foregroundStyle(basis == .official ? green : amber)
            }
        }
    }

    private func measurementChip(_ measurement: DeadlinePace.Measurement) -> some View {
        HStack(spacing: 3) {
            Text("\(Int(measurement.horizonHours))h")
                .foregroundStyle(.white.opacity(0.76))
            Text(measurement.ratePerHour.map { String(format: "%.1f", $0) } ?? "—")
                .foregroundStyle(measurement.ratePerHour == nil ? muted : green)
            if measurement.ratePerHour == nil, measurement.sampleCount > 0 {
                Text(L("{{0}}点", String(describing: measurement.sampleCount))).foregroundStyle(muted)
            }
        }
        .font(.system(size: compact ? 8 : 10, weight: .medium, design: .monospaced))
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
        .fixedSize()
    }

    private var accent: Color {
        switch advice.state {
        case .recent: return green
        case .upcoming, .observation, .announced: return amber
        case .elapsed, .stale: return .orange
        case .waiting, .unknown: return muted
        }
    }

    private var pillTitle: String {
        switch advice.state {
        case .upcoming: return L("临时重置承诺")
        case .observation: return L("临时重置观察")
        case .announced: return L("临时重置公告")
        case .elapsed: return L("公告窗口已结束")
        case .recent: return L("站点确认重置")
        case .stale: return L("公告数据过期")
        case .waiting, .unknown: return L("重置信息")
        }
    }

    private var headline: String {
        switch advice.state {
        case .upcoming:
            return advice.deadline.map(isShanghaiToday) == true ? L("今天有临时重置承诺") : L("临时重置提醒")
        case .observation:
            return advice.deadline.map(isShanghaiToday) == true ? L("今天有临时重置承诺") : L("临时重置观察窗口")
        case .announced: return advice.announcementAt.map(isShanghaiToday) == true ? L("今天有临时重置公告") : L("临时重置已有公告")
        case .elapsed: return L("公告目标时间已过")
        case .recent: return L("站点刚确认临时重置")
        case .stale: return L("临时重置公告数据过期")
        case .waiting, .unknown: return L("临时重置状态未知")
        }
    }

    private var deadlineLabel: String {
        switch advice.state {
        case .upcoming: return L("重置目标倒计时")
        case .observation: return L("观察窗口倒计时")
        case .announced: return L("公告时间")
        case .elapsed: return L("目标时间状态")
        case .recent: return L("站点确认状态")
        case .stale: return L("上次已知时间")
        case .waiting, .unknown: return L("重置时间")
        }
    }

    private var qualification: String {
        if advice.state == .recent {
            return L("“已确认”仅指站点确认；个人账户是否到账，以本机 Codex 额度读数为准。")
        }
        return L("速度单位为额度百分点 / 小时，基于本机账户采样；目标时间不保证额度到账，正常订阅重置可能更早。")
    }

    private func isShanghaiToday(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.isDate(date, inSameDayAs: now)
    }

    private func countdown(to date: Date, now currentTime: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(currentTime)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        return days > 0
            ? String(format: "%dd %02d:%02d:%02d", days, hours, minutes, remainder)
            : String(format: "%02d:%02d:%02d", hours, minutes, remainder)
    }
}
