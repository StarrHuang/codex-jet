import SwiftUI
import Charts
import ResetCore

struct Dashboard: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }
    @Namespace private var navigation
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let error = model.error { errorBanner(error) }
                    if ["dashboard", "radar"].contains(model.page) {
                        TemporaryResetBanner(advice: model.extraResetAdvice, pace: model.temporaryResetPace,
                                             window: model.mainWindow, now: model.now,
                                             observationError: model.radar?.observationError, bankedCount: model.usableBankedCount)
                    }
                    if model.page == "radar" { radar }
                    else if model.page == "method" { methodology }
                    else if model.page == "tokens" {
                        HourlyTokenPanel(report: model.tokenReport, loading: model.tokensLoading, error: model.tokenError)
                    }
                    else if model.page == "notifications" {
                        ResetNotificationSettings(controller: model.reminders)
                    }
                    else { dashboard }
                }.padding(28).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.foregroundStyle(.white).background(ink.background).preferredColorScheme(.dark)
            .frame(minWidth: 1000, minHeight: 760)
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise.circle.fill").font(.system(size: 30)).foregroundStyle(ink.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CODEX RESET").font(.system(size: 13, weight: .bold, design: .monospaced))
                    Text("额度 · 节奏 · 重置").font(.system(size: 9, design: .monospaced)).foregroundStyle(ink.secondary)
                }
            }.padding(.top, 15)
            VStack(spacing: 7) {
                nav("dashboard", "额度驾驶舱", "chart.xyaxis.line")
                nav("tokens", "模型消耗", "chart.bar.xaxis")
                nav("radar", "全局重置雷达", "dot.radiowaves.left.and.right")
                nav("notifications", "重置通知", "bell.badge")
                nav("method", "数据与预测方法", "slider.horizontal.3")
            }
            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    label("CURRENT ACCOUNT")
                    Text((snapshot.plan ?? "套餐未知").uppercased()).font(.system(size: 20, weight: .medium, design: .monospaced))
                    Text("账户 \(snapshot.accountKey.prefix(8))").font(.system(size: 11, design: .monospaced)).foregroundStyle(ink.secondary)
                    Text("本地 Codex CLI 登录账户").font(.system(size: 11)).foregroundStyle(ink.secondary)
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(ink.panel, in: RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                HStack { Circle().fill(model.snapshot == nil ? Color.orange : ink.accent).frame(width: 6, height: 6); Text("本机采样 · 每 5 分钟").font(.system(size: 11)) }
                Text("额度历史只保存在这台 Mac\n窗口采用服务器返回的时间").font(.system(size: 11)).foregroundStyle(ink.secondary).lineSpacing(5)
                Button("导出当前账户历史", action: model.exportHistory).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(ink.blue)
                if let message = model.exportMessage { Text(message).font(.system(size: 10)).foregroundStyle(ink.secondary) }
            }.padding(.bottom, 14)
        }.padding(18).frame(width: 200).background(Color.black.opacity(0.18))
    }
    func nav(_ key: String, _ title: String, _ symbol: String) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) { model.page = key }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 13)
            .background {
                if model.page == key {
                    RoundedRectangle(cornerRadius: 10).fill(ink.accent.opacity(0.1))
                        .matchedGeometryEffect(id: "selection", in: navigation)
                }
            }
            .foregroundStyle(model.page == key ? ink.accent : ink.secondary)
            .contentShape(Rectangle())
        }.buttonStyle(InstrumentButtonStyle())
    }
    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 9) {

                Text(model.page == "radar" ? "全局重置雷达" : model.page == "method" ? "知道数字从哪里来" : model.page == "tokens" ? "每个小时，都花在哪里？" : model.page == "notifications" ? "重置快到了，叫我使劲蹬" : "额度驾驶舱")
                    .font(.system(size: 25, weight: .semibold))
            }
            Spacer()
            Button { Task { if model.page == "tokens" { await model.refreshTokens() } else { await model.refresh() } } } label: {
                HStack(spacing: 7) { Image(systemName: "arrow.clockwise"); Text(model.page == "tokens" ? (model.tokensLoading ? "读取中…" : "刷新统计") : (model.refreshing ? "读取中…" : "刷新额度")) }
                    .font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(ink.panel, in: Capsule())
            }.buttonStyle(InstrumentButtonStyle()).disabled(model.page == "tokens" ? model.tokensLoading : model.refreshing)
        }
    }
    @ViewBuilder var dashboard: some View {
        if let snapshot = model.snapshot {
            if let window = model.mainWindow {
                mainQuotaCard(window)
                if !model.hasTemporaryTarget || model.weeklyPace?.expectedUsedPercent != nil {
                    subscriptionAdvice(window)
                }
            }
            BankedResetPanel(model: model)
            if !model.secondaryWindows.isEmpty { auxiliaryQuota }
            Button { model.page = "tokens" } label: {
                HStack {
                    Label("每小时 · 分模型 token 消耗", systemImage: "chart.bar.xaxis")
                    Spacer()
                    Text("查看明细 →")
                }.font(.system(size: 12)).foregroundStyle(ink.blue).padding(16).card()
            }.buttonStyle(.plain)
            if [.waiting, .unknown].contains(model.extraResetAdvice.state) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(ink.secondary)
                    Text("暂无有效临时重置公告").font(.system(size: 12)).foregroundStyle(ink.secondary)
                    Spacer()
                    Button("查看雷达 →") { model.page = "radar" }.buttonStyle(.plain).foregroundStyle(ink.blue).font(.system(size: 12))
                }.padding(.horizontal, 2)
            }
            ResetScheduleView(window: model.mainWindow, radar: model.radar, now: model.now,
                              history: model.history, accountKey: model.snapshot?.accountKey)
            if snapshot.windows.isEmpty { errorBanner("服务器未返回百分比额度窗口；不会据套餐名称推断窗口。") }
            if let window = model.selectedWindow {
                chartPanel(window)
                HStack(alignment: .top, spacing: 16) { pacePanel(window); scenarioPanel(window) }
            }
            HStack {
                Text("上次成功采样 \(stamp(snapshot.sampledAt)) · \(model.history.count) 个账户采样").font(.system(size: 11, design: .monospaced)).foregroundStyle(ink.secondary)
                Spacer()
                Text("只读接口 / account/rateLimits/read").font(.system(size: 10, design: .monospaced)).foregroundStyle(ink.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "waveform.path.ecg").font(.system(size: 48)).foregroundStyle(ink.accent)
                Text(model.refreshing ? "正在读取本机 Codex 账户…" : "等待真实额度读数").font(.title2)
                Text("使用已登录的 Codex CLI 获取账户额度。首次运行开始建立自己的消耗曲线，至少 3 个样本、跨 15 分钟后显示实测速率。")
                    .foregroundStyle(ink.secondary).lineSpacing(5)
                Text("若提示未登录，请在终端运行 codex login，再点击刷新。").font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.blue)
            }.padding(32).frame(maxWidth: .infinity, minHeight: 380, alignment: .leading).card()
        }
        if let data = model.radar { compactRadar(data) }
        if let error = model.radarError { errorBanner(error) }
    }
    func mainQuotaCard(_ window: QuotaWindow) -> some View {
        Button { model.selectedWindowID = window.id; model.scenarioMultiplier = 1 } label: {
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 9) {
                        Text("CODEX").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(ink.accent)
                        Text("整体订阅额度").font(.system(size: 13)).foregroundStyle(ink.secondary)
                        Spacer()
                        Text(window.durationMinutes == 10080 ? "周额度" : windowDisplayName(window))
                            .font(.system(size: 11)).foregroundStyle(ink.secondary)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(number(100 - window.usedPercent)).font(.system(size: 80, weight: .medium, design: .rounded)).monospacedDigit()
                            .contentTransition(reduceMotion ? .identity : .numericText())
                        Text("%").font(.system(size: 26, weight: .light)).foregroundStyle(ink.accent)
                        Text("剩余").font(.system(size: 14)).foregroundStyle(ink.secondary).padding(.leading, 6)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 7) {
                            Text(countdown(window.resetsAt, now: model.now)).font(.system(size: 24, weight: .medium, design: .monospaced))
                            Text("至正常重置").font(.system(size: 11)).foregroundStyle(ink.secondary)
                        }
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.07))
                            Capsule().fill(window.usedPercent > 85 ? Color.orange : ink.accent)
                                .frame(width: proxy.size.width * (100 - window.usedPercent) / 100)
                        }
                    }.frame(height: 6)
                    HStack {
                        Text("已用 \(number(window.usedPercent))%")
                        Spacer()
                        Text(window.resetsAt.map { "\(stamp($0)) · 上海" } ?? "重置时间未知")
                    }.font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.secondary)
                }
                QuotaInstrument(remaining: 100 - window.usedPercent, tint: window.usedPercent > 85 ? .orange : ink.accent)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.65), value: window.usedPercent)
            }.padding(24)
                .background(ink.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(ink.accent.opacity(0.22), lineWidth: 1))
        }.buttonStyle(InstrumentButtonStyle())
    }
    var auxiliaryQuota: some View {
        DisclosureGroup {
            ForEach(model.secondaryWindows) { window in
                Button { model.selectedWindowID = window.id; model.scenarioMultiplier = 1 } label: {
                    HStack {
                        Text(windowDisplayName(window)).font(.system(size: 11))
                        Spacer()
                        Text("\(number(100 - window.usedPercent))% 剩余").font(.system(size: 12, design: .monospaced))
                        Text(window.resetsAt.map { "重置 \(stamp($0))" } ?? "时间未知").font(.system(size: 10)).foregroundStyle(ink.secondary)
                        Image(systemName: model.selectedWindowID == window.id ? "checkmark.circle" : "chart.xyaxis.line")
                    }.padding(.vertical, 8)
                }.buttonStyle(.plain)
            }
        } label: {
            HStack {
                Text("辅助额度").font(.system(size: 10, weight: .medium)).foregroundStyle(ink.secondary)
                Spacer()
                Text(model.secondaryWindows.map { "\($0.label.components(separatedBy: " · ").first ?? $0.bucketID) \(number(100 - $0.usedPercent))%" }.joined(separator: " · "))
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(ink.secondary)
            }
        }.tint(ink.secondary).padding(.horizontal, 15).padding(.vertical, 8)
            .background(.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
    }
    var weeklyTint: Color {
        switch model.weeklyPace?.state {
        case .ahead, .exhausted: return .orange
        case .surplus: return ink.accent
        case .balanced: return ink.blue
        default: return ink.secondary
        }
    }
    func subscriptionAdvice(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if !model.hasTemporaryTarget { PaceRideView(pace: model.normalDeadlinePace, bankedCount: model.usableBankedCount, quotaRemaining: model.liveRemainingPercent) }
            if let pace = model.weeklyPace, pace.expectedUsedPercent != nil {
                Text("周期均速参考 · " + weeklyDetail(window))
                    .font(.system(size: 11)).foregroundStyle(ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(20)
            .background(ink.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
    }
    func weeklyDetail(_ window: QuotaWindow) -> String {
        guard let pace = model.weeklyPace else { return "等有效读数后，再判断当前节奏。" }
        switch pace.state {
        case .ahead:
            let timing = pace.exhaustionAt.map { "预计 \(stamp($0)) 用尽" } ?? "可能提前用尽"
            let early = pace.hoursEarly.map { "，比正常重置早约 \(String(format: "%.1f", $0 / 24)) 天" } ?? ""
            let safe = pace.safeSpeedMultiplier.map { "。想撑到重置，接下来放到约 \(String(format: "%.1f", $0))× 当前均速" } ?? ""
            return timing + early + safe + "。"
        case .surplus:
            return "按本周期平均速度，正常重置时约剩 \(number(pace.projectedRemainingAtReset))%。还有余力，把想做的任务蹬起来！"
        case .balanced:
            if let early = pace.hoursEarly, early > 0 {
                return "用量与时间基本同步；按均速仍可能提前约 \(String(format: "%.1f", early)) 小时用尽，稍微收点力。"
            }
            return "用量与时间基本同步，按本周期均速预计能撑到正常重置。"
        case .exhausted: return "先休息一下，等账户正常重置，或确认有额外重置到账。"
        case .stale: return "最新读数超过 10 分钟，刷新后再调整节奏。"
        case .waitingForReset: return "倒计时已到；等账户新读数确认，暂不假定额度已经补满。"
        case .unknown: return "窗口刚开始或时间信息不足，暂时不判断会不会提前用完。"
        }
    }
    var extraResetPanel: some View {
        let advice = ExtraResetAdvice.evaluate(model.radar, now: model.now)
        let active = advice.state == .upcoming || advice.state == .observation
            || advice.state == .announced || advice.state == .recent
        let title: String = switch advice.state {
        case .upcoming: "额外重置在路上，使劲蹬！"
        case .observation: "今天有临时重置承诺，观察中"
        case .announced: "临时重置已有公告，截止时间未明确"
        case .elapsed: "公告目标时间已过，等待账户读数"
        case .recent: "站点刚确认额外重置，准备使劲蹬！"
        case .stale: "额外重置雷达过期，等待更新"
        case .waiting: "等待新的额外重置信号"
        case .unknown: "正在读取额外重置信号"
        }
        let detail: String = switch advice.state {
        case .upcoming: "站点公告窗口截止 \(advice.deadline.map(stamp) ?? "未知")。这是额外重置提示；到账前留好正常额度。"
        case .observation: "站点提供观察目标 \(advice.deadline.map(stamp) ?? "未知")。这是观察窗口，不保证账户在此时到账。"
        case .announced: "公告已确认，但截止时间未明确；不计算倒计时或目标速度。"
        case .elapsed: "目标时间 \(advice.deadline.map(stamp) ?? "未知") 已过；以本机额度读数确认是否到账。"
        case .recent: "公告已被站点确认；先看账户读数是否到账，确认后就把任务蹬起来。"
        case .stale: "刷新雷达后再判断是否有新的补额信号。"
        case .waiting: "当前没有有效的新公告。历史概率不是补额时间，正常周额度照自己的节奏蹬。"
        case .unknown: "还未取得有效的雷达数据，暂不判断是否有新公告。"
        }
        return HStack(spacing: 16) {
            RoadsterFlightView(remainingPercent: model.liveRemainingPercent, ratePerHour: model.menuPace?.recentRatePerHour,
                               announced: active, animated: active)
                .frame(width: 128, height: 86)
            VStack(alignment: .leading, spacing: 9) {
                Text("额外重置 · CODEX RESET 雷达").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(active ? ink.accent : ink.secondary)
                Text(title).font(.system(size: active ? 20 : 15, weight: .medium)).foregroundStyle(active ? ink.accent : .white)
                Text(detail).font(.system(size: 11)).foregroundStyle(ink.secondary).lineSpacing(4)
                if let source = advice.sourceURL { Link("查看公告原文 ↗", destination: source).font(.system(size: 10)).foregroundStyle(ink.blue) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { model.page = "radar" } label: { Image(systemName: "arrow.up.right").foregroundStyle(ink.secondary) }.buttonStyle(.plain)
        }.padding(16).card()
    }
    func chartPanel(_ window: QuotaWindow) -> some View {
        let start = model.now.addingTimeInterval(-model.horizonHours * 3600)
        let points = model.recentPoints.filter { $0.0 >= start }
        let end = min(window.resetsAt ?? model.now, model.now.addingTimeInterval(model.horizonHours * 3600 / 2))
        return VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text("额度消耗曲线").font(.system(size: 15, weight: .semibold)); Text("\(windowDisplayName(window)) · 当前周期 · 已用百分比").font(.system(size: 11)).foregroundStyle(ink.secondary) }
                Spacer()
                Picker("显示范围", selection: $model.horizonHours) { Text("6 小时").tag(6.0); Text("24 小时").tag(24.0); Text("7 天").tag(168.0) }.pickerStyle(.segmented).labelsHidden().frame(width: 215)
            }
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("时间", point.0), y: .value("已用", point.1), series: .value("系列", "采样"))
                        .foregroundStyle(ink.accent).lineStyle(StrokeStyle(lineWidth: 2))
                    PointMark(x: .value("时间", point.0), y: .value("已用", point.1)).foregroundStyle(ink.accent).symbolSize(15)
                }
                if let rate = model.effectiveRate, model.usablePrediction, end > model.now {
                    LineMark(x: .value("时间", model.now), y: .value("预测", window.usedPercent), series: .value("系列", "预测"))
                        .foregroundStyle(ink.blue).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    LineMark(x: .value("时间", end), y: .value("预测", min(100, window.usedPercent + rate * end.timeIntervalSince(model.now) / 3600)), series: .value("系列", "预测"))
                        .foregroundStyle(ink.blue).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }
                RuleMark(y: .value("额度上限", 100)).foregroundStyle(.white.opacity(0.16)).lineStyle(StrokeStyle(dash: [3, 4]))
                RuleMark(x: .value("现在", model.now)).foregroundStyle(.white.opacity(0.15)).annotation(position: .top, alignment: .leading) { Text("现在").font(.system(size: 9)).foregroundStyle(ink.secondary) }
            }.chartYScale(domain: 0...100).chartXScale(domain: start...max(end, model.now.addingTimeInterval(60)))
                .chartYAxis { AxisMarks(values: [0, 25, 50, 75, 100]) { value in AxisGridLine().foregroundStyle(.white.opacity(0.04)); AxisValueLabel { if let n = value.as(Int.self) { Text("\(n)%").font(.system(size: 10, design: .monospaced)) } } } }
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { _ in AxisValueLabel(format: model.horizonHours > 24 ? .dateTime.month().day() : .dateTime.hour().minute()).font(.system(size: 10, design: .monospaced)) } }
                .frame(height: 185)
            HStack(spacing: 18) {
                legend("实际采样", color: ink.accent)
                legend(model.effectiveRate == nil ? "预测尚未建立" : model.usesBaseline ? "窗口平均估算" : "近期速度外推", color: ink.blue)
                Spacer()
                Text(points.count < 3 ? "采样积累中，未填充过去历史" : "重置或额度回落时自动分段").font(.system(size: 10)).foregroundStyle(ink.secondary)
            }
        }.padding(24).card()
    }
    func pacePanel(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("消耗速度").font(.system(size: 15, weight: .semibold))
            rateRow("近期实测速率", model.forecast?.recentRatePerHour, color: ink.accent)
            rateRow("窗口平均估算", model.forecast?.baselineRatePerHour, color: ink.blue)
            rateRow("重置前用尽所需", model.forecast?.requiredRatePerHour, color: .white)
            Text("单位：百分点 / 小时。\n近期速率取当前周期最近 24 小时，包含闲置；正常重置提示参考 CodexBar 的本周期均速；近期实测单独显示，可能与长期节奏不同。")
                .font(.system(size: 10)).foregroundStyle(ink.secondary).lineSpacing(4)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).card()
    }
    func scenarioPanel(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack { Text("假如接下来…").font(.system(size: 15, weight: .semibold)); Spacer(); Text("情景估算").font(.system(size: 10)).foregroundStyle(ink.secondary) }
            HStack { Text("当前估算速度的").font(.system(size: 12)).foregroundStyle(ink.secondary); Spacer(); Text(String(format: "%.1f×", model.scenarioMultiplier)).font(.system(size: 23, design: .monospaced)).foregroundStyle(ink.accent) }
            Slider(value: $model.scenarioMultiplier, in: 0...4, step: 0.1).tint(ink.accent).disabled(model.effectiveRate == nil || !model.usablePrediction)
            if let rate = model.effectiveRate, let reset = window.resetsAt, model.usablePrediction {
                let remaining = max(0, 100 - window.usedPercent - rate * model.scenarioMultiplier * max(0, reset.timeIntervalSince(model.now) / 3600))
                Text(remaining <= 0 ? "这个速度预计能在重置前用尽" : "重置时预计剩余 \(number(remaining))%")
                    .font(.system(size: 13)).foregroundStyle(ink.blue)
                if let required = model.forecast?.requiredRatePerHour, rate > 0 {
                    Text("恰好用尽需约 \(String(format: "%.1f", required / rate))× 当前速度").font(.system(size: 10)).foregroundStyle(ink.secondary)
                }
            } else { Text("有有效速率与重置时间后可比较情景").font(.system(size: 11)).foregroundStyle(ink.secondary) }
            Text("仅帮助安排实际工作，不会自动消耗额度。其他窗口可能先触及上限。")
                .font(.system(size: 10)).foregroundStyle(ink.secondary).lineSpacing(4)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).card()
    }
    func compactRadar(_ data: RadarData) -> some View {
        Button { model.page = "radar" } label: {
            HStack(spacing: 13) {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 22)).foregroundStyle(ink.blue)
                VStack(alignment: .leading, spacing: 5) { Text("全局重置展望").font(.system(size: 12)); Text("24h \(number(data.forecast.probabilities.rounded_24h))% · 48h \(number(data.forecast.probabilities.rounded_48h))% · 第三方 \(data.forecast.confidence ?? "未知") 预测").font(.system(size: 10)).foregroundStyle(ink.secondary) }
                Spacer(); Image(systemName: "arrow.up.right").foregroundStyle(ink.secondary)
            }.padding(18).card()
        }.buttonStyle(.plain)
    }
    @ViewBuilder var radar: some View {
        if let error = model.radarError { errorBanner(error) }
        if let data = model.radar {
            if [.waiting, .unknown].contains(model.extraResetAdvice.state) { extraResetPanel }
            HStack(spacing: 16) {
                radarMetric("上次站点收录的全局重置", text: data.forecast.last_reset_at.flatMap(parseDate).map(stamp) ?? "未知", detail: "不会据此修改你的个人额度")
                radarMetric("未来 24 小时", text: "\(number(data.forecast.probabilities.rounded_24h))%", detail: "站点置信度：\(data.forecast.confidence ?? "未知")")
                radarMetric("未来 48 小时", text: "\(number(data.forecast.probabilities.rounded_48h))%", detail: "历史模型估算，非官方时间表")
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack { Text("重置与储备额度时间线").font(.system(size: 16, weight: .medium)); Spacer(); Button("更新雷达") { Task { await model.refreshRadar() } }.buttonStyle(.plain).foregroundStyle(ink.blue).font(.system(size: 12)) }
                ForEach(Array(data.timeline.events.prefix(10))) { event in
                    HStack(alignment: .top, spacing: 16) {
                        Text(event.date).font(.system(size: 12, design: .monospaced)).foregroundStyle(ink.secondary).frame(width: 100, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) { Text(event.title).font(.system(size: 13)); Text("来源：codex-reset.com · 站点置信度 \(event.confidence ?? "未知")").font(.system(size: 10)).foregroundStyle(ink.secondary) }
                        Spacer()
                        if let address = event.url, let url = URL(string: address), url.scheme == "https", url.host == "x.com" { Link("原文 ↗", destination: url).font(.system(size: 11)).foregroundStyle(ink.blue) }
                    }
                    Divider().overlay(.white.opacity(0.03))
                }
                HStack { Text("来源更新 \(parseDate(data.forecast.updated_at).map(stamp) ?? data.forecast.updated_at)").font(.system(size: 10)).foregroundStyle(ink.secondary); Spacer(); Link("打开完整站点 ↗", destination: URL(string: "https://codex-reset.com/zh/")!).font(.system(size: 11)).foregroundStyle(ink.blue) }
            }.padding(24).card()
            Text("雷达数据来自第三方公开接口，保留其未核验和储备重置标记。全局公告不能证明你的账户已到账；以账户额度读数为准。预测模型处于实验阶段，不用于推算个人重置倒计时。")
                .font(.system(size: 12)).foregroundStyle(ink.secondary).lineSpacing(6)
        } else { Text("正在获取公开雷达…").foregroundStyle(ink.secondary).task { await model.refreshRadar() } }
    }
    var methodology: some View {
        VStack(alignment: .leading, spacing: 24) {
            method("01 / 真实额度", "由本机 Codex app-server 的只读账户接口返回。按 account 与 bucket 分区，不按套餐名称猜测 5 小时或每周限制。缺失的窗口、重置时间或时长保持未知。")
            method("02 / 自己的消耗曲线", "每 5 分钟采样一次，保存时间、账户哈希、套餐与窗口读数。相同账户、同一窗口、同一重置时间才连接成曲线。额度降低时开始新段。Tokei 旧历史缺乏可靠账户和周期标识，所以从首次运行开始记录。")
            method("03 / 两种速度", "近期实测速率 = 同周期最近 24 小时已用百分点增加量 ÷ 实际经过小时数。需要至少 3 个样本、跨度 15 分钟。窗口平均估算 = 当前已用百分比 ÷ 服务端窗口已过小时数，借鉴 CodexBar 的 pace 思路；它不是实测历史。正常重置按这个均速对比时间进度，提醒是否会提前用尽。")
            method("04 / 能否用尽", "所需速度 = 剩余百分比 ÷ 至重置的小时数。预测剩余 = 当前剩余 − 速度 × 至重置小时数。假定未来工作强度、模型组合与额度规则相近；额外重置只有有效公告窗口或刚确认的重置才提示「使劲蹬」，不拿历史概率代替到账事实。不输出未经校准的用尽概率。超过 10 分钟无新读数暂停预测，时间到也要服务端确认。")
            method("05 / 本机数据", "历史文件：~/Library/Application Support/CodexReset/history.json。只保存账户哈希，不保存邮箱、令牌或对话。通过 CLI 复用现有登录态。公开雷达请求不包含个人额度，第三方数据有独立更新时间。App 运行时采样；退出或 Mac 休眠时不会补造数据。")
            method("06 / 每小时模型消耗", "从本机 Codex 会话日志读取 token 用量记录，按事件时间归入上海时间整点；模型来自对应轮次的会话上下文，缺失时保留未知。输入包含缓存，输出包含推理，子项不重复相加。记录只在本机汇总，不保存或上传对话内容。统计不绑定当前订阅账户，也不把 token 换算成额度百分比；未记录的小时不等同于真实零消耗。")
            HStack { Link("codex-reset.com ↗", destination: URL(string: "https://codex-reset.com/zh/")!); Link("CodexBar 源码 ↗", destination: URL(string: "https://github.com/steipete/CodexBar")!) }.font(.system(size: 12)).foregroundStyle(ink.blue)
        }.padding(26).card()
    }
    func method(_ title: String, _ text: String) -> some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(ink.accent); Text(text).font(.system(size: 12)).foregroundStyle(ink.secondary).lineSpacing(6) } }
    func radarMetric(_ title: String, text: String, detail: String) -> some View { VStack(alignment: .leading, spacing: 15) { Text(title).font(.system(size: 11)).foregroundStyle(ink.secondary); Text(text).font(.system(size: 22, weight: .medium, design: .monospaced)).foregroundStyle(ink.accent); Text(detail).font(.system(size: 10)).foregroundStyle(ink.secondary) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).card() }
    func rateRow(_ title: String, _ rate: Double?, color: Color) -> some View { HStack { Text(title).font(.system(size: 12)).foregroundStyle(ink.secondary); Spacer(); Text(rate.map { String(format: "%.2f", $0) } ?? "—").font(.system(size: 18, design: .monospaced)).foregroundStyle(color) } }
    func legend(_ text: String, color: Color) -> some View { HStack(spacing: 6) { Capsule().fill(color).frame(width: 13, height: 3); Text(text).font(.system(size: 10)).foregroundStyle(ink.secondary) } }
    func errorBanner(_ text: String) -> some View { HStack(alignment: .top, spacing: 10) { Image(systemName: "exclamationmark.circle"); Text(text).textSelection(.enabled) }.font(.system(size: 12)).foregroundStyle(Color.orange).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)) }
    func label(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.5).foregroundStyle(ink.secondary) }
}
extension View { func card() -> some View { background(ink.panel, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.055), lineWidth: 1)) } }
func number(_ value: Double?) -> String { value.map { String(format: "%.0f", $0) } ?? "—" }
func stamp(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
    formatter.dateFormat = "M月d日 HH:mm"
    return formatter.string(from: date)
}
func countdown(_ date: Date?, now: Date) -> String {
    guard let date else { return "—" }
    return ResetTimeDisplay.remaining(until: date, now: now)
}

func windowDisplayName(_ window: QuotaWindow) -> String {
    let name = window.bucketID == "codex" ? "Codex" : window.label.components(separatedBy: " · ").first ?? window.bucketID
    let duration = window.durationMinutes.map { $0 == 10080 ? "每周额度" : $0 == 300 ? "5 小时额度" : "\($0 / 60) 小时窗口" } ?? "时长未知"
    return "\(name) · \(duration)"
}
