import SwiftUI
import Charts
import ResetCore

struct QuotaPopover: View {
    @ObservedObject var model: AppModel
    let openDashboard: () -> Void
    @State private var rangeHours = 24.0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }
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
                Image(systemName: "waveform.path").font(.system(size: 17)).foregroundStyle(blue)
                Text("Codex Jet").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("额度驾驶舱").font(.system(size: 10)).foregroundStyle(muted)
                Button(action: openDashboard) { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain).help("打开完整驾驶舱")
            }.padding(.horizontal, 20).padding(.vertical, 15)
            Divider().overlay(.white.opacity(0.06))
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
                    if let window = model.mainWindow {
                        TemporaryResetBanner(advice: model.extraResetAdvice, pace: model.temporaryResetPace,
                                             window: window, now: model.now,
                                             observationError: model.radar?.observationError, compact: true, bankedCount: model.usableBankedCount)
                        quotaCard(window)
                        BankedResetPanel(model: model, compact: true)
                        ResetScheduleView(window: window, radar: model.radar, now: model.now,
                                          history: model.history, accountKey: model.snapshot?.accountKey, compact: true)
                        extraResetCard
                        if !model.secondaryWindows.isEmpty {
                            DisclosureGroup {
                                ForEach(model.secondaryWindows) { auxiliary in
                                    HStack { Text(windowDisplayName(auxiliary)); Spacer(); Text("\(number(100 - auxiliary.usedPercent))% 剩余") }.font(.system(size: 11)).foregroundStyle(muted).padding(.vertical, 5)
                                }
                            } label: {
                                HStack { Text("辅助额度"); Spacer(); Text(model.secondaryWindows.map { "\($0.label.components(separatedBy: " · ").first ?? $0.bucketID) \(number(100 - $0.usedPercent))%" }.joined(separator: " · ")) }
                                    .font(.system(size: 10)).foregroundStyle(muted)
                            }.tint(muted)
                        }
                        historyChart(window)
                        changes
                    } else {
                        TemporaryResetBanner(advice: model.extraResetAdvice, pace: model.temporaryResetPace,
                                             window: nil, now: model.now,
                                             observationError: model.radar?.observationError, compact: true, bankedCount: model.usableBankedCount)
                        VStack(alignment: .leading, spacing: 13) {
                            Text(model.refreshing ? "正在读取 Codex 额度…" : "等待 Codex 额度读数").font(.system(size: 18, weight: .medium))
                            Text("从真实账户读数开始采样，不填充过去历史。").font(.system(size: 12)).foregroundStyle(muted)
                        }.padding(20).popoverCard(blue)
                        ResetScheduleView(window: nil, radar: model.radar, now: model.now,
                                          history: model.history, accountKey: model.snapshot?.accountKey, compact: true)
                    }
                    HourlyTokenPanel(report: model.tokenReport, loading: model.tokensLoading,
                                     error: model.tokenError, compact: true)
                    Button("打开每小时模型明细 →") {
                        model.page = "tokens"
                        openDashboard()
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(blue)
                }.padding(18)
            }
            Divider().overlay(.white.opacity(0.06))
            HStack(spacing: 15) {
                Button { Task { await model.refresh() } } label: { Label(model.refreshing ? "读取中…" : "刷新", systemImage: "arrow.clockwise") }
                    .disabled(model.refreshing)
                Button("驾驶舱", action: openDashboard)
                Button("重置通知") { model.page = "notifications"; openDashboard() }
                Spacer()
                Text(model.snapshot.map { "更新 \(clock($0.sampledAt))" } ?? "尚无读数").font(.system(size: 9, design: .monospaced)).foregroundStyle(muted)
                Button("退出") { NSApp.terminate(nil) }
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(width: 650, height: min(830, (NSScreen.main?.visibleFrame.height ?? 900) - 80))
        .foregroundStyle(.white).background(.ultraThinMaterial)
        .background(Color(red: 0.09, green: 0.115, blue: 0.15).opacity(0.8))
        .preferredColorScheme(.dark)
        .task { model.startMonitoring() }
        .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        .environment(\.locale, Locale(identifier: "zh_CN"))
    }
    func quotaCard(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(window.durationMinutes == 10080 ? "Codex 周额度" : "Codex 整体额度").font(.system(size: 18, weight: .bold)).foregroundStyle(blue)
                Spacer()
                Text(countdown(window.resetsAt, now: model.now) + " 后重置").font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
            }
            HStack(spacing: 14) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) { Capsule().fill(.white.opacity(0.1)); Capsule().fill(blue).frame(width: proxy.size.width * (100 - window.usedPercent) / 100) }
                }.frame(height: 7)
                Text("剩余 \(number(100 - window.usedPercent))%").font(.system(size: 12, weight: .semibold)).fixedSize()
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("当前剩余").font(.system(size: 11)).foregroundStyle(muted)
                    HStack(alignment: .firstTextBaseline, spacing: 3) { Text(String(format: "%.1f", 100 - window.usedPercent)).font(.system(size: 46, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(reduceMotion ? .identity : .numericText()); Text("%").font(.system(size: 19)).foregroundStyle(muted) }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text("正常重置 · 上海时间").font(.system(size: 10)).foregroundStyle(muted)
                    Text(window.resetsAt.map(stamp) ?? "未知").font(.system(size: 13, weight: .semibold, design: .monospaced))
                    if let pace = model.weeklyPace, let expected = pace.expectedUsedPercent {
                        Text("窗口已过 \(number(expected))% · 用量 \(number(window.usedPercent))%").font(.system(size: 10)).foregroundStyle(muted)
                    }
                }
            }
            if !model.hasTemporaryTarget {
                PaceRideView(pace: model.normalDeadlinePace, compact: true, bankedCount: model.usableBankedCount, quotaRemaining: model.liveRemainingPercent)
            }

            Divider().overlay(.white.opacity(0.08))
            Text("过去几个周期").font(.system(size: 12, weight: .semibold))
            let previous = Array((analysis?.cycles ?? []).filter { !$0.isCurrent && ($0.initialUsedPercent > 0 || $0.finalUsedPercent > 0) }.suffix(3).reversed())
            if previous.isEmpty {
                Text("还未观测到过去周期；已开始记录本周期，不补造历史。").font(.system(size: 10)).foregroundStyle(muted)
            } else {
                ForEach(previous, id: \.id) { cycle in
                    HStack(spacing: 12) {
                        Text("\(shortDate(cycle.firstSeen)) → \(shortDate(cycle.lastSeen))").font(.system(size: 10, design: .monospaced))
                        Text("观测 \(span(cycle.lastSeen.timeIntervalSince(cycle.firstSeen)))").font(.system(size: 9)).foregroundStyle(muted)
                        GeometryReader { proxy in
                            Capsule().fill(blue.opacity(0.6)).frame(width: proxy.size.width * cycle.observedConsumptionPercent / 100)
                        }.frame(height: 6)
                        Text("增用 \(number(cycle.observedConsumptionPercent))%").font(.system(size: 10, weight: .medium)).fixedSize()
                    }
                }
                Text("记录为已观测区间；回补或重锚会分段，区间长度可能不同。").font(.system(size: 9)).foregroundStyle(muted)
            }
        }.padding(18).popoverCard(blue)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: window.usedPercent)
    }
    var paceDetail: String {
        guard let pace = model.weeklyPace else { return "等待有效的窗口读数。" }
        switch pace.state {
        case .ahead:
            return "按本周期均速，预计提前 \(String(format: "%.1f", (pace.hoursEarly ?? 0) / 24)) 天用尽。放到约 \(String(format: "%.1f", pace.safeSpeedMultiplier ?? 0))× 均速可撑到重置。"
        case .surplus: return "按本周期均速，重置时约剩 \(number(pace.projectedRemainingAtReset))%。把想做的任务蹬起来！"
        case .balanced: return "用量与窗口时间基本同步；这是本周期均速估算。"
        case .exhausted: return "等正常重置，或先核对额外重置是否到账。"
        case .stale: return "最新额度读数过期，刷新后再判断节奏。"
        case .waitingForReset: return "倒计时已到，等待新读数确认额度恢复。"
        case .unknown: return "窗口刚开始或时间信息不足，暂不推断节奏。"
        }
    }
    var extraResetCard: some View {
        let advice = ExtraResetAdvice.evaluate(model.radar, now: model.now)
        let title: String = switch advice.state {
        case .upcoming: "额外重置在路上，使劲蹬！"
        case .observation: "临时重置目标正在观察中"
        case .announced: "临时重置已有公告，时间未知"
        case .elapsed: "公告目标时间已过，等账户读数确认"
        case .recent: "站点刚确认额外重置，先看账户是否到账"
        case .waiting: "额外重置：等待新的公告信号"
        case .stale: "额外重置：雷达过期，先刷新"
        case .unknown: "额外重置：等有效的雷达数据"
        }
        let deadlineDetail: String? = switch advice.state {
        case .upcoming: advice.deadline.map { "站点窗口截止 \(stamp($0))；到账前留好正常额度。" }
        case .observation: advice.deadline.map { "站点观察目标 \(stamp($0))；不保证账户在此时到账。" }
        case .elapsed: advice.deadline.map { "目标时间 \(stamp($0)) 已过；等待账户读数确认。" }
        case .announced: "公告有了，截止时间未明确。"
        case .recent: "站点刚确认；以账户读数验证到账。"
        case .waiting: "当前没有有效的新公告。"
        case .stale: "雷达数据过期，刷新后再判断。"
        case .unknown: "尚无有效的雷达数据。"
        }
        return HStack(alignment: .top, spacing: 9) {
            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(blue)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 11, weight: .medium))
                if let deadlineDetail { Text(deadlineDetail).font(.system(size: 9)).foregroundStyle(muted) }
            }
            Spacer()
        }.padding(.horizontal, 4)
    }
    func historyChart(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) { Text("额度轨迹").font(.system(size: 16, weight: .bold)); Text("按分钟聚合 · 剩余额度").font(.system(size: 9)).foregroundStyle(muted) }
                Spacer()
                Picker("时间范围", selection: $rangeHours) {
                    Text("1h").tag(1.0); Text("6h").tag(6.0); Text("24h").tag(24.0); Text("1周").tag(168.0); Text("1月").tag(720.0); Text("1年").tag(8760.0)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 310)
            }
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    metric("周剩余", String(format: "%.1f%%", 100 - window.usedPercent), color: blue)
                    metric("采样点", "\(analysis?.points.count ?? 0)", color: .white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("最大区间下降").font(.system(size: 10)).foregroundStyle(muted)
                        if let change = analysis?.maximumDrop {
                            Text("−\(String(format: "%.1f", change.dropPercent))% / \(String(format: "%.0f", change.intervalMinutes))min")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundStyle(blue)
                        } else { Text("尚无下降记录").font(.system(size: 11)).foregroundStyle(muted) }
                    }
                }
                let points = analysis?.points ?? []
                Chart {
                    ForEach(points, id: \.id) { point in
                        LineMark(x: .value("时间", point.sampledAt), y: .value("剩余", point.remainingPercent), series: .value("观测段", point.segmentID))
                            .interpolationMethod(.stepEnd).foregroundStyle(blue).lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("时间", point.sampledAt), y: .value("剩余", point.remainingPercent)).foregroundStyle(blue).symbolSize(8)
                    }
                }.chartYScale(domain: 0...100)
                    .chartXScale(domain: model.now.addingTimeInterval(-rangeHours * 3600)...model.now)
                    .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(.white.opacity(0.07)); AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%").font(.system(size: 9, design: .monospaced)) } } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisGridLine().foregroundStyle(.white.opacity(0.03)); AxisValueLabel(format: rangeHours > 24 ? .dateTime.month().day() : .dateTime.hour().minute()).font(.system(size: 9, design: .monospaced)) } }
                    .frame(height: 185)
                if let first = points.first, let last = points.last {
                    Text("当前范围内观测 \(shortDate(first.sampledAt)) \(clock(first.sampledAt)) – \(shortDate(last.sampledAt)) \(clock(last.sampledAt)) · 不补造更早历史")
                        .font(.system(size: 9)).foregroundStyle(muted)
                } else {
                    Text("所选范围内暂无采样。历史从本机首次记录开始，不回填过去数据。")
                        .font(.system(size: 9)).foregroundStyle(muted)
                }
            }.padding(17).popoverCard(blue)
        }
    }
    var changes: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近额度变化").font(.system(size: 15, weight: .bold))
            let records = Array((analysis?.recentChanges ?? []).prefix(8))
            if records.isEmpty { Text("所选范围内尚未观测到额度变化。").font(.system(size: 11)).foregroundStyle(muted) }
            ForEach(records, id: \.id) { change in
                HStack(spacing: 12) {
                    Text(clock(change.sampledAt)).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    Text("周").font(.system(size: 10, weight: .medium)).foregroundStyle(blue)
                    Spacer()
                    if change.kind == .consumption {
                        Text("−\(String(format: "%.1f", change.dropPercent))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    } else { Text("回补 / 重锚").font(.system(size: 11, weight: .medium)).foregroundStyle(blue) }
                    Text("\(String(format: "%.0f", change.intervalMinutes)) 分钟").font(.system(size: 10)).foregroundStyle(muted).frame(width: 70, alignment: .trailing)
                }
            }
            Text("记录为相邻采样区间内变化，不推断具体消耗发生时刻或模型。").font(.system(size: 9)).foregroundStyle(muted).lineSpacing(3)
        }.padding(.horizontal, 3)
    }
    func metric(_ title: String, _ value: String, color: Color) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 10)).foregroundStyle(muted); Text(value).font(.system(size: 21, weight: .bold, design: .rounded)).foregroundStyle(color) } }
    func clock(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.locale = Locale(identifier: "zh_CN"); style.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return date.formatted(style)
    }
    func shortDate(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.month(.twoDigits).day(.twoDigits)
        style.locale = Locale(identifier: "zh_CN"); style.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return date.formatted(style)
    }
    func span(_ interval: TimeInterval) -> String { interval >= 86400 ? String(format: "%.1f天", interval / 86400) : String(format: "%.1fh", interval / 3600) }
}
extension View {
    func popoverCard(_ accent: Color) -> some View {
        background(LinearGradient(colors: [.white.opacity(0.065), .white.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(accent.opacity(0.28), lineWidth: 1))
    }
}
