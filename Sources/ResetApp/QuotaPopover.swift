import SwiftUI
import Charts
import ResetCore

struct QuotaPopover: View {
    @ObservedObject var model: AppModel
    let openDashboard: () -> Void
    @State private var rangeHours = 24.0
    private let blue = ink.accent
    private let muted = ink.secondary
    private var analysis: QuotaHistoryAnalysis? {
        guard let window = model.mainWindow, let snapshot = model.snapshot else { return nil }
        return QuotaHistoryAnalysis.analyze(history: model.history, accountKey: snapshot.accountKey,
                                            windowID: window.id, bucketID: window.bucketID,
                                            now: model.now, horizonHours: rangeHours)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                QuotaLogo().frame(width: 21, height: 21)
                Text("Codex Jet").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(L("额度驾驶舱")).font(.system(size: 10)).foregroundStyle(muted)
                Button(action: openDashboard) { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help(L("打开完整驾驶舱"))
            }.padding(.horizontal, 20).padding(.vertical, 15)
            Divider().overlay(.white.opacity(0.06))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let window = model.mainWindow {
                        QuotaOverview(model: model, compact: true)
                        if let error = model.error { Text(L(error)).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                        TemporaryResetBanner(advice: model.extraResetAdvice, pace: model.temporaryResetPace,
                                             window: window, now: model.now,
                                             observationError: model.radar?.observationError, compact: true,
                                             bankedCount: model.usableBankedCount, runwayLight: model.menuRunwayLight)
                        if [.waiting, .unknown].contains(model.extraResetAdvice.state)
                            || (model.extraResetAdvice.state == .stale && model.extraResetAdvice.summary == nil && model.extraResetAdvice.announcementAt == nil) {
                            extraResetCard
                        }
                        historyChart(window)
                        changes
                        BankedResetPanel(model: model, compact: true)
                        ResetScheduleView(window: window, radar: model.radar, now: model.now,
                                          history: model.history, accountKey: model.snapshot?.accountKey,
                                          compact: true, quotaReadingFresh: model.liveRemainingPercent != nil)
                        historicalCycles
                        if !model.secondaryWindows.isEmpty {
                            DisclosureGroup {
                                ForEach(model.secondaryWindows) { auxiliary in
                                    HStack { Text(windowDisplayName(auxiliary)); Spacer(); Text(L("{{0}}% 剩余", String(describing: number(100 - auxiliary.usedPercent)))) }.font(.system(size: 11)).foregroundStyle(muted).padding(.vertical, 5)
                                }
                            } label: {
                                HStack { Text(L("辅助额度")); Spacer(); Text(model.secondaryWindows.map { "\($0.label.components(separatedBy: " · ").first ?? $0.bucketID) \(number(100 - $0.usedPercent))%" }.joined(separator: " · ")) }
                                    .font(.system(size: 10)).foregroundStyle(muted)
                            }.tint(muted)
                        }
                    } else {
                        if let error = model.error { Text(L(error)).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                        TemporaryResetBanner(advice: model.extraResetAdvice, pace: model.temporaryResetPace,
                                             window: nil, now: model.now,
                                             observationError: model.radar?.observationError, compact: true, bankedCount: model.usableBankedCount, runwayLight: model.menuRunwayLight)
                        VStack(alignment: .leading, spacing: 13) {
                            Text(model.refreshing ? L("正在读取 Codex 额度…") : L("等待 Codex 额度读数")).font(.system(size: 18, weight: .medium))
                            Text(L("从真实账户读数开始采样，不填充过去历史。")).font(.system(size: 12)).foregroundStyle(muted)
                        }.padding(20).popoverCard(blue)
                        ResetScheduleView(window: nil, radar: model.radar, now: model.now,
                                          history: model.history, accountKey: model.snapshot?.accountKey,
                                          compact: true, quotaReadingFresh: model.liveRemainingPercent != nil)
                    }
                    HourlyTokenPanel(report: model.tokenReport, loading: model.tokensLoading,
                                     error: model.tokenError, compact: true)
                    Button(L("打开每小时模型明细 →")) {
                        model.page = "tokens"
                        openDashboard()
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(blue)
                }.padding(18)
            }
            Divider().overlay(.white.opacity(0.06))
            HStack(spacing: 15) {
                Button { Task { await model.refresh() } } label: { Label(model.refreshing ? L("读取中…") : L("刷新"), systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing)
                Button(L("驾驶舱"), action: openDashboard)
                Button(L("重置通知")) { model.page = "notifications"; openDashboard() }
                Spacer()
                Text(model.snapshot.map { L("更新 {{0}}", String(describing: clock($0.sampledAt))) } ?? L("尚无读数")).font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                Button(L("退出")) { NSApp.terminate(nil) }
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 650, height: min(830, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
        .foregroundStyle(.white).background(.ultraThinMaterial)
        .background(Color(red: 0.09, green: 0.115, blue: 0.15).opacity(0.8))
        .preferredColorScheme(.dark)
        .task { model.startMonitoring() }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .environment(\.locale, AppLanguage.locale)
    }
    var historicalCycles: some View {
        DisclosureGroup(L("过去几个额度周期")) {
            let previous = Array((analysis?.cycles ?? []).filter { !$0.isCurrent && ($0.initialUsedPercent > 0 || $0.finalUsedPercent > 0) }.suffix(3).reversed())
            if previous.isEmpty {
                Text(L("还未观测到过去周期；已开始记录本周期，不补造历史。"))
                    .font(.system(size: 12)).foregroundStyle(muted)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(previous, id: \.id) { cycle in
                        HStack(spacing: 12) {
                            Text("\(shortDate(cycle.firstSeen)) → \(shortDate(cycle.lastSeen))")
                                .font(.system(size: 12, design: .monospaced))
                            Text(L("观测 {{0}}", String(describing: span(cycle.lastSeen.timeIntervalSince(cycle.firstSeen)))))
                                .font(.system(size: 12)).foregroundStyle(muted)
                            GeometryReader { proxy in
                                Capsule().fill(blue.opacity(0.6)).frame(width: proxy.size.width * cycle.observedConsumptionPercent / 100)
                            }.frame(height: 6)
                            Text(L("增用 {{0}}%", String(describing: number(cycle.observedConsumptionPercent))))
                                .font(.system(size: 12, weight: .medium)).fixedSize()
                        }
                    }
                    Text(L("记录为已观测区间；回补或重锚会分段，区间长度可能不同。"))
                        .font(.system(size: 12)).foregroundStyle(muted)
                }
            }
        }.font(.system(size: 12, weight: .medium)).tint(muted)
    }

    var extraResetCard: some View {
        let advice = ExtraResetAdvice.evaluate(model.radar, now: model.now)
        let title: String = switch advice.state {
        case .upcoming: L("额外重置窗口已公布")
        case .observation: L("临时重置目标正在观察中")
        case .announced: L("临时重置已有公告，时间未知")
        case .elapsed: L("公告目标时间已过，等账户读数确认")
        case .recent: L("站点刚确认额外重置，先看账户是否到账")
        case .waiting: L("额外重置：等待新的公告信号")
        case .stale: L("额外重置雷达已过期")
        case .unknown: L("额外重置状态未知")
        }
        let deadlineDetail: String? = switch advice.state {
        case .upcoming: advice.deadline.map { L("站点窗口截止 {{0}}；到账前留好正常额度。", String(describing: stamp($0))) }
        case .observation: advice.deadline.map { L("站点观察目标 {{0}}；不保证账户在此时到账。", String(describing: stamp($0))) }
        case .elapsed: advice.deadline.map { L("目标时间 {{0}} 已过；等待账户读数确认。", String(describing: stamp($0))) }
        case .announced: L("公告有了，截止时间未明确。")
        case .recent: L("站点刚确认；以账户读数验证到账。")
        case .waiting: L("当前没有有效的新公告。")
        case .stale: L("雷达数据过期，刷新后再判断。")
        case .unknown: L("尚无有效的雷达数据。")
        }
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let deadlineDetail { Text(deadlineDetail).font(.system(size: 12)).foregroundStyle(muted) }
            }
            Spacer()
        }.padding(.horizontal, 4)
    }
    func historyChart(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text(L("额度轨迹")).font(.system(size: 16, weight: .bold)); Text(L("按分钟聚合 · 剩余额度")).font(.system(size: 9)).foregroundStyle(muted) }
                Spacer()
                Picker(L("时间范围"), selection: $rangeHours) {
                    Text("1h").tag(1.0); Text("6h").tag(6.0); Text("24h").tag(24.0); Text(L("1周")).tag(168.0); Text(L("1月")).tag(720.0); Text(L("1年")).tag(8760.0)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 310)
            }
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    metric(L("周剩余"), String(format: "%.1f%%", 100 - window.usedPercent), color: blue)
                    metric(L("采样点"), "\(analysis?.points.count ?? 0)", color: .white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(L("最大区间下降")).font(.system(size: 10)).foregroundStyle(muted)
                        if let change = analysis?.maximumDrop {
                            Text("−\(String(format: "%.1f", change.dropPercent))% / \(String(format: "%.0f", change.intervalMinutes))min")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(blue)
                        } else { Text(L("尚无下降记录")).font(.system(size: 11)).foregroundStyle(muted) }
                    }
                }
                let points = analysis?.points ?? []
                Chart {
                    ForEach(points, id: \.id) { point in
                        LineMark(x: .value(L("时间"), point.sampledAt), y: .value(L("剩余"), point.remainingPercent), series: .value(L("观测段"), point.segmentID))
                            .interpolationMethod(.stepEnd).foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value(L("时间"), point.sampledAt), y: .value(L("剩余"), point.remainingPercent)).foregroundStyle(blue).symbolSize(8)
                    }
                }.chartYScale(domain: 0...100)
                    .chartXScale(domain: model.now.addingTimeInterval(-rangeHours * 3600)...model.now)
                    .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(.white.opacity(0.07)); AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%").font(.system(size: 9, design: .monospaced)) } } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.03)); AxisValueLabel(format: rangeHours > 24 ? .dateTime.month().day() : .dateTime.hour().minute()).font(.system(size: 9, design: .monospaced)) } }
                    .frame(height: 185)
                if let first = points.first, let last = points.last {
                    Text(L("当前范围内观测 {{0}} {{1}} – {{2}} {{3}} · 不补造更早历史", String(describing: shortDate(first.sampledAt)), String(describing: clock(first.sampledAt)), String(describing: shortDate(last.sampledAt)), String(describing: clock(last.sampledAt))))
                        .font(.system(size: 9)).foregroundStyle(muted)
                } else {
                    Text(L("所选范围内暂无采样。历史从本机首次记录开始，不回填过去数据。"))
                        .font(.system(size: 9)).foregroundStyle(muted)
                }
            }.padding(17).popoverCard(blue)
        }
    }
    var changes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("最近额度变化")).font(.system(size: 15, weight: .bold))
            let records = Array((analysis?.recentChanges ?? []).prefix(8))
            if records.isEmpty { Text(L("所选范围内尚未观测到额度变化。")).font(.system(size: 11)).foregroundStyle(muted) }
            ForEach(records, id: \.id) { change in
                HStack(spacing: 12) {
                    Text(clock(change.sampledAt)).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    Text(L("周")).font(.system(size: 10, weight: .medium)).foregroundStyle(blue)
                    Spacer()
                    if change.kind == .consumption {
                        Text("−\(String(format: "%.1f", change.dropPercent))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    } else { Text(L("回补 / 重锚")).font(.system(size: 11, weight: .medium)).foregroundStyle(blue) }
                    Text(L("{{0}} 分钟", String(describing: String(format: "%.0f", change.intervalMinutes)))).font(.system(size: 10)).foregroundStyle(muted).frame(width: 70, alignment: .trailing)
                }
            }
            Text(L("记录为相邻采样区间内变化，不推断具体消耗发生时刻或模型。")).font(.system(size: 9)).foregroundStyle(muted).lineSpacing(3)
        }.padding(.horizontal, 3)
    }
    func metric(_ title: String, _ value: String, color: Color) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 10)).foregroundStyle(muted); Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(color) } }
    func clock(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.locale = AppLanguage.locale; style.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return date.formatted(style)
    }
    func shortDate(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.twoDigits).day(.twoDigits)
        style.locale = AppLanguage.locale; style.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return date.formatted(style)
    }
    func span(_ interval: TimeInterval) -> String { interval >= 86400 ? String(format: L("%.1f天"), interval / 86400) : String(format: "%.1fh", interval / 3600) }
}
extension View {
    func popoverCard(_ accent: Color) -> some View {
        background(LinearGradient(colors: [.white.opacity(0.065), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(accent.opacity(0.28), lineWidth: 1))
    }
}
