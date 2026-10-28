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
    private let muted = Color.white.opacity(0.62)

    @ViewBuilder
    var body: some View {
        if shouldShow { banner }
    }

    private var shouldShow: Bool {
        switch advice.state {
        case .upcoming, .observation, .announced, .elapsed, .recent: true
        case .stale: advice.summary != nil || advice.announcementAt != nil
        case .waiting, .unknown: false
        }
    }

    private var statusTint: Color {
        switch advice.state {
        case .upcoming, .observation, .announced: Color(red: 0.95, green: 0.58, blue: 0.22)
        case .elapsed, .recent, .stale, .waiting, .unknown: ink.secondary
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 9) {
                statusPill
                Text(headline).font(.system(size: compact ? 13 : 15, weight: .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
            }

            HStack(alignment: .center, spacing: 12) {
                deadlineSummary
                Spacer(minLength: 6)
                if let sourceURL = advice.sourceURL {
                    Link(L("查看来源 ↗"), destination: sourceURL)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.blue)
                        .fixedSize()
                }
            }

            if let summary = advice.summary, !summary.isEmpty {
                Text(summary).font(.system(size: 12)).foregroundStyle(muted)
                    .lineLimit(compact ? 2 : 3).fixedSize(horizontal: false, vertical: true)
            }

            Text(qualification).font(.system(size: 12)).foregroundStyle(muted)
                .lineLimit(1).minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)

            DisclosureGroup(L("公告详情与来源依据")) {
                VStack(alignment: .leading, spacing: 8) {
                    if let summary = advice.summary, !summary.isEmpty {
                        detailRow(L("公告原文摘要"), value: summary)
                    }
                    detailRow(L("目标依据"), value: advice.targetName)
                    if let announcementAt = advice.announcementAt {
                        detailRow(L("公告发布时间 · 北京时间"), value: stamp(announcementAt))
                    } else {
                        detailRow(L("公告发布时间"), value: L("来源未提供时刻"))
                    }
                    if let deadline = advice.deadline {
                        detailRow(L("目标时间 · 北京时间"), value: stamp(deadline))
                    } else {
                        detailRow(L("目标时间"), value: L("时间未明确"))
                    }
                    if let note = advice.conversionNote {
                        Text(note).font(.system(size: 12)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                    }
                    if let observationError, !observationError.isEmpty {
                        detailRow(L("观察窗口读取情况"), value: observationError)
                    }
                    if let sourceURL = advice.sourceURL {
                        Link(L("打开来源原文 ↗"), destination: sourceURL)
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.blue)
                    }
                }
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 12, weight: .medium))
            .tint(ink.secondary)
        }
        .padding(compact ? 14 : 17)
        .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.075), lineWidth: 1))
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle().fill(statusTint).frame(width: 6, height: 6)
            Text(pillTitle).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(statusTint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(statusTint.opacity(0.11), in: Capsule())
        .fixedSize()
    }

    private var deadlineSummary: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(deadlineLabel).font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                Text(deadlineValue(at: context.date))
                    .font(.system(size: compact ? 16 : 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                if let deadline = advice.deadline {
                    Text(L("目标 {{0}} · 北京时间", String(describing: stamp(deadline))))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(muted)
                } else if let announcedAt = advice.announcementAt {
                    Text(L("公告 {{0}}", String(describing: stamp(announcedAt))))
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(muted)
                }
            }
        }
    }

    func deadlineValue(at currentTime: Date) -> String {
        if advice.state == .stale { return L("来源数据过期") }
        if let deadline = advice.deadline, deadline > currentTime {
            return L(ResetTimeDisplay.remaining(until: deadline, now: currentTime))
        }
        if advice.deadline != nil { return advice.state == .recent ? L("已确认") : L("窗口已过") }
        if advice.state == .recent { return L("已确认") }
        return L("时间未明确")
    }

    private func detailRow(_ title: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(ink.secondary)
            Text(value).font(.system(size: 12)).foregroundStyle(tint ?? muted).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pillTitle: String {
        switch advice.state {
        case .upcoming: L("临时重置承诺")
        case .observation: L("临时重置观察")
        case .announced: L("临时重置公告")
        case .elapsed: L("公告窗口已结束")
        case .recent: L("站点确认重置")
        case .stale: L("公告数据过期")
        case .waiting, .unknown: L("重置信息")
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
        case .upcoming: L("临时目标倒计时")
        case .observation: L("观察窗口倒计时")
        case .announced: L("公告时间")
        case .elapsed: L("目标时间状态")
        case .recent: L("站点确认状态")
        case .stale: L("上次已知时间")
        case .waiting, .unknown: L("重置时间")
        }
    }

    private var qualification: String {
        if advice.state == .recent {
            return L("“已确认”仅指站点确认；个人账户是否到账，以本机 Codex 额度读数为准。")
        }
        return L("此目标不保证个人账户在该时间到账；正常订阅重置也可能更早。")
    }

    private func isShanghaiToday(_ date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.isDate(date, inSameDayAs: now)
    }
}
