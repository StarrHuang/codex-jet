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
    private var showsCompactTemporarySummary: Bool {
        [.upcoming, .observation, .announced].contains(model.extraResetAdvice.state)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                QuotaBrandBadge().frame(width: 26, height: 26)
                Text("Codex Jet").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(L("额度驾驶舱")).font(.system(size: 12)).foregroundStyle(muted)
                Button(action: openDashboard) { Image(systemName: "arrow.up.right.square").frame(width: 28, height: 28).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help(L("打开完整驾驶舱")).accessibilityLabel(L("打开完整驾驶舱"))
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider().overlay(.white.opacity(0.06))
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let window = model.mainWindow {
                        if showsCompactTemporarySummary {
                            compactQuotaOverview(window)
                            if let error = model.error { Text(L(error)).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                            compactTemporarySummary
                        } else {
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
                }.padding(14)
            }
            Divider().overlay(.white.opacity(0.06))
            HStack(spacing: 15) {
                Button { Task { await model.refresh() } } label: { Label(model.refreshing ? L("读取中…") : L("刷新"), systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing)
                Button(L("驾驶舱"), action: openDashboard)
                Button(L("重置通知")) { model.page = "notifications"; openDashboard() }
                Spacer()
                Text(model.snapshot.map { L("更新 {{0}}", String(describing: clock($0.sampledAt))) } ?? L("尚无读数")).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                Button(L("退出")) { NSApp.terminate(nil) }
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 10)
        }
        .frame(width: 650, height: min(830, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
        .foregroundStyle(.white).background(.ultraThinMaterial)
        .background(Color(red: 0.09, green: 0.115, blue: 0.15).opacity(0.8))
        .preferredColorScheme(.dark)
        .task { model.startMonitoring() }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .environment(\.locale, AppLanguage.locale)
    }
    private func compactQuotaOverview(_ window: QuotaWindow) -> some View {
        let deadlineSource = model.menuDeadlineExplanation ?? L("暂无有效未来截止")
        let stale = model.snapshot != nil && model.liveRemainingPercent == nil
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 10) {
                QuotaFlowView(remainingPercent: model.liveRemainingPercent,
                              ratePerHour: stale ? nil : model.menuPace?.recentRatePerHour,
                              stale: stale, announced: true, showsReadout: false,
                              runwayLight: model.menuRunwayLight)
                    .frame(width: 62, height: 62).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("当前剩余")).font(.system(size: 10)).foregroundStyle(muted)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(model.liveRemainingPercent.map { String(format: "%.1f", $0) } ?? "—")
                            .font(.system(size: 36, weight: .medium, design: .rounded)).monospacedDigit()
                            .foregroundStyle(model.liveRemainingPercent == nil ? muted : .white).lineLimit(1).minimumScaleFactor(0.7)
                        Text("%").font(.system(size: 16, weight: .light)).foregroundStyle(muted)
                    }
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(L("最近截止")).font(.system(size: 10)).foregroundStyle(muted)
                    Text(model.menuDeadlineHours ?? "—").font(.system(size: 17, weight: .medium, design: .monospaced))
                        .monospacedDigit().foregroundStyle(model.menuDeadline == nil ? muted : .white)
                    Text(deadlineSource).font(.system(size: 10, weight: .medium)).foregroundStyle(muted)
                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: 180, alignment: .trailing)
                }
            }
            if let deadline = model.menuDeadline {
                HStack {
                    Spacer(minLength: 0)
                    Text(L("截止 {{0}} · 北京时间", String(describing: stamp(deadline))))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).lineLimit(1)
                }
            }
            PaceRideView(pace: model.menuPace, targetLabel: deadlineSource, compact: true,
                         bankedCount: model.usableBankedCount, quotaRemaining: model.liveRemainingPercent,
                         quotaStale: stale, runwayLight: model.menuRunwayLight)
            DisclosureGroup(L("额度概览")) {
                QuotaOverview(model: model, compact: true).padding(.top, 6)
            }.font(.system(size: 11, weight: .medium)).tint(muted)
        }
        .padding(12)
        .background(ink.panel, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.07), lineWidth: 1))
    }
    private var compactTemporarySummary: some View {
        let advice = model.extraResetAdvice
        let heading: String = switch advice.state {
        case .upcoming: L("临时重置承诺")
        case .observation: L("临时重置目标正在观察中")
        case .announced: L("临时重置已有公告，时间未知")
        case .elapsed: L("公告目标时间已过，等账户读数确认")
        case .recent: L("站点刚确认临时重置")
        case .stale: L("临时重置公告数据过期")
        case .waiting, .unknown: L("临时重置状态未知")
        }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(Color(red: 1.0, green: 0.62, blue: 0.25)).frame(width: 7, height: 7)
                Text(heading).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                Spacer(minLength: 4)
                if let deadline = advice.deadline {
                    Text(L(ResetTimeDisplay.remaining(until: deadline, now: model.now)))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit().foregroundStyle(Color(red: 1.0, green: 0.68, blue: 0.34)).lineLimit(1)
                } else {
                    Text(L("时间未明确")).font(.system(size: 12, weight: .medium)).foregroundStyle(muted)
                }
            }
            HStack(spacing: 8) {
                if let deadline = advice.deadline {
                    Text(L("目标 {{0}} · 北京时间", String(describing: stamp(deadline))))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).lineLimit(1)
                } else if let announcedAt = advice.announcementAt {
                    Text(L("公告 {{0}}", String(describing: stamp(announcedAt))))
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                if let sourceURL = advice.sourceURL {
                    Link(L("查看来源 ↗"), destination: sourceURL).font(.system(size: 10, weight: .medium)).foregroundStyle(blue).fixedSize()
                }
            }
            if let summary = advice.summary, !summary.isEmpty {
                Text(summary).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1).truncationMode(.tail)
            }
            Text(advice.state == .recent
                 ? L("“已确认”仅指站点确认；个人账户是否到账，以本机 Codex 额度读数为准。")
                 : L("此目标不保证个人账户在该时间到账；正常订阅重置也可能更早。"))
                .font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup(L("公告详情与来源依据")) {
                TemporaryResetBanner(advice: advice, pace: model.temporaryResetPace,
                                     window: model.mainWindow, now: model.now,
                                     observationError: model.radar?.observationError, compact: true,
                                     bankedCount: model.usableBankedCount, runwayLight: model.menuRunwayLight)
                    .padding(.top, 6)
            }.font(.system(size: 11, weight: .medium)).tint(muted)
        }
        .padding(12)
        .background(Color(red: 0.15, green: 0.115, blue: 0.075), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.orange.opacity(0.26), lineWidth: 1))
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
                }.labelsHidden().pickerStyle(.segmented).tint(ink.accent).frame(width: 310)
            }
            VStack(alignment: .leading, spacing: 10) {
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
                let axisDates = (0...3).map { model.now.addingTimeInterval(-rangeHours * 3600 * Double(3 - $0) / 3) }
                Chart {
                    ForEach(points, id: \.id) { point in
                        LineMark(x: .value(L("时间"), point.sampledAt), y: .value(L("剩余"), point.remainingPercent), series: .value(L("观测段"), point.segmentID))
                            .interpolationMethod(.stepEnd).foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value(L("时间"), point.sampledAt), y: .value(L("剩余"), point.remainingPercent)).foregroundStyle(blue).symbolSize(8)
                    }
                }.chartYScale(domain: 0...100)
                    .chartXScale(domain: model.now.addingTimeInterval(-rangeHours * 3600)...model.now,
                                 range: .plotDimension(startPadding: 12, endPadding: 28))
                    .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(.white.opacity(0.10)); AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted) } } } }
                    .chartXAxis { AxisMarks(values: axisDates) { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.055))
                        if let date = value.as(Date.self) {
                            let anchor: UnitPoint = abs(date.timeIntervalSince(model.now)) < 1 ? .topTrailing
                                : abs(date.timeIntervalSince(axisDates[0])) < 1 ? .topLeading : .top
                            AxisValueLabel(anchor: anchor) {
                                Text(date, format: rangeHours > 24 ? .dateTime.month().day() : .dateTime.hour().minute())
                                    .font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                            }
                        }
                    } }
                    .frame(height: 150)
                if let first = points.first, let last = points.last {
                    Text(L("当前范围内观测 {{0}} {{1}} – {{2}} {{3}} · 不补造更早历史", String(describing: shortDate(first.sampledAt)), String(describing: clock(first.sampledAt)), String(describing: shortDate(last.sampledAt)), String(describing: clock(last.sampledAt))))
                        .font(.system(size: 9)).foregroundStyle(muted)
                } else {
                    Text(L("所选范围内暂无采样。历史从本机首次记录开始，不回填过去数据。"))
                        .font(.system(size: 9)).foregroundStyle(muted)
                }
            }.padding(12).popoverCard(blue)
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
        background(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(accent.opacity(0.22), lineWidth: 1))
    }
}
