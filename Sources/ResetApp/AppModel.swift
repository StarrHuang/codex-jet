import Foundation
import Combine
import ResetCore
import AppKit

@MainActor
final class AppModel: ObservableObject {
    @Published var snapshot: QuotaSnapshot?
    @Published var history: [QuotaSnapshot] = []
    @Published var selectedWindowID: String?
    @Published var refreshing = false
    @Published var error: String?
    @Published var bankedResets: BankedResetSnapshot?
    @Published var bankedError: String?
    @Published var radar: RadarData?
    @Published var radarError: String?
    @Published var now = Date()
    @Published var page = "dashboard"
    @Published var horizonHours: Double = 24
    @Published var scenarioMultiplier = 1.0
    @Published var exportMessage: String?
    @Published var tokenReport: LocalTokenReport?
    @Published var tokensLoading = false
    @Published var tokenError: String?
    private let tokenReader = LocalTokenUsageReader()
    let reminders = ResetNotificationController()
    private var monitor: Task<Void, Never>?
    private let monitoringEnabled: Bool
    init(monitoringEnabled: Bool = true) { self.monitoringEnabled = monitoringEnabled }
    func startMonitoring() {
        guard monitoringEnabled, monitor == nil else { return }
        monitor = Task {
            await reminders.start()
            await refresh()
            var lastRefresh = Date()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                now = Date()
                await checkReminders()
                if Date().timeIntervalSince(lastRefresh) >= 300 {
                    await refresh()
                    lastRefresh = Date()
                }
            }
        }
    }
    var liveRemainingPercent: Double? {
        guard let snapshot, let window = mainWindow, snapshot.sampledAt <= now,
              now.timeIntervalSince(snapshot.sampledAt) <= 600 else { return nil }
        return 100 - window.usedPercent
    }
    var usableBankedCount: Int {
        guard bankedError == nil, let bankedResets, bankedResets.accountKey == snapshot?.accountKey,
              bankedResets.sampledAt <= now, now.timeIntervalSince(bankedResets.sampledAt) <= 600 else { return 0 }
        return bankedResets.cards.filter { $0.expiresAt > now }.count
    }
    var extraResetAdvice: ExtraResetAdvice { ExtraResetAdvice.evaluate(radar, now: now) }
    var temporaryResetPace: DeadlinePace? {
        guard let window = mainWindow, let snapshot else { return nil }
        let advice = extraResetAdvice
        let deadline = [.upcoming, .observation, .elapsed].contains(advice.state) ? advice.deadline : nil
        return DeadlinePace.evaluate(window: window, observedAt: snapshot.sampledAt, history: history,
                                     accountKey: snapshot.accountKey, deadline: deadline, now: now)
    }
    var hasTemporaryTarget: Bool { [.upcoming, .observation, .announced].contains(extraResetAdvice.state) }
    var normalDeadlinePace: DeadlinePace? {
        guard let window = mainWindow, let snapshot else { return nil }
        return DeadlinePace.evaluate(window: window, observedAt: snapshot.sampledAt, history: history,
            accountKey: snapshot.accountKey, deadline: window.resetsAt, now: now)
    }
    private enum MenuDeadlineSource {
        case bankedCard
        case temporaryReset
        case weeklyReset

        var explanation: String {
            switch self {
            case .bankedCard: L("储备卡到期（需手动兑换，不会自动回补）")
            case .temporaryReset: L("临时重置目标")
            case .weeklyReset: L("正常订阅重置")
            }
        }
    }
    private var menuDeadlineCandidate: (date: Date, source: MenuDeadlineSource)? {
        var candidates: [(date: Date, source: MenuDeadlineSource)] = []
        if let snapshot, snapshot.sampledAt <= now, now.timeIntervalSince(snapshot.sampledAt) <= 600,
           let reset = mainWindow?.resetsAt, reset > now {
            candidates.append((reset, .weeklyReset))
        }
        let advice = extraResetAdvice
        if advice.state == .upcoming, let deadline = advice.deadline, deadline > now {
            candidates.append((deadline, .temporaryReset))
        }
        if bankedError == nil, let bankedResets, bankedResets.accountKey == snapshot?.accountKey,
           bankedResets.sampledAt <= now, now.timeIntervalSince(bankedResets.sampledAt) <= 600 {
            candidates += bankedResets.cards.filter { $0.expiresAt > now }
                .map { ($0.expiresAt, .bankedCard) }
        }
        return candidates.min { $0.date < $1.date }
    }
    var menuDeadline: Date? { menuDeadlineCandidate?.date }
    var menuDeadlineExplanation: String? {
        guard let candidate = menuDeadlineCandidate else { return nil }
        if case .temporaryReset = candidate.source { return extraResetAdvice.targetName }
        return candidate.source.explanation
    }
    var menuDeadlineHours: String? {
        guard let deadline = menuDeadline else { return nil }
        let hours = deadline.timeIntervalSince(now) / 3600
        if hours > 48 { return String(format: L("%.1f天"), hours / 24) }
        return hours < 0.05 ? "<0.1h" : String(format: "%.1fh", hours)
    }
    private var menuDeadlineSuffix: String { menuDeadlineHours.map { " " + $0 } ?? "" }
    var menuPace: DeadlinePace? {
        guard let window = mainWindow, let snapshot else { return nil }
        return DeadlinePace.evaluate(window: window, observedAt: snapshot.sampledAt, history: history,
            accountKey: snapshot.accountKey, deadline: menuDeadline, now: now)
    }
    var menuRunwayLight: DeadlinePace.RunwayLight { menuPace?.runwayLight ?? .unknown }
    var menuBarTitle: String {
        let current = liveRemainingPercent.map { number($0) + "%" } ?? "—%"
        return current + menuDeadlineSuffix
    }
    var menuBarHelp: String {
        guard let window = mainWindow, let snapshot else { return L("尚无账户额度读数；点击打开额度面板。") }
        let fresh = snapshot.sampledAt <= now && now.timeIntervalSince(snapshot.sampledAt) <= 600
        var lines = [L("当前本轮剩余：") + number(100 - window.usedPercent) + "%" + (fresh ? "" : L("（上次读数已过期；状态栏暂不显示当前额度）"))]
        lines.append(menuRunwayLight.explanation)
        if let target = menuDeadline {
            lines.append(L("预测目标：") + (menuDeadlineExplanation ?? "") + " · " + L(ResetTimeDisplay.shanghai(target)) + L(" 北京时间"))
            lines.append(L("距目标：") + L(ResetTimeDisplay.remaining(until: target, now: now)))
        }
        if let pace = menuPace, [.tooSlow, .onTrack, .tooFast].contains(pace.state),
           let remaining = pace.projectedRemainingAtDeadline {
            lines.append(String(format: L("按现速到目标时，本轮预计剩余：%.1f%%"), remaining))
            if let rate = pace.recentRatePerHour, let required = pace.requiredRatePerHour {
                lines.append(String(format: L("实测 %.2f → 目标 %.2f 百分点/小时"), rate, required))
            }
            if let multiplier = pace.speedMultiplier {
                lines.append(String(format: L("建议调整到当前速度的 %.2f 倍，以本轮恰好用尽为目标。"), multiplier))
            } else { lines.append(L("近期实测为零：需启动任务，不能计算有限的加速倍数。")) }
        } else { lines.append(L("— 表示缺少有效速度样本、读数过期或目标已到；不估算倍速。")) }
        if hasTemporaryTarget { lines.append(L("有临时重置公告；到账时间以账户实际回补为准。")) }
        if usableBankedCount > 0 { lines.append(L("另有 {{0}} 张储备卡，需手动兑换；不计入本轮预计余量。下拉查看到期与衔接安排。", String(describing: usableBankedCount))) }
        return lines.joined(separator: "\n")
    }
    var mainWindow: QuotaWindow? {
        snapshot?.windows.first(where: { $0.bucketID == "codex" && $0.durationMinutes == 10080 })
            ?? snapshot?.windows.first(where: { $0.bucketID == "codex" })
    }
    var secondaryWindows: [QuotaWindow] { snapshot?.windows.filter { $0.id != mainWindow?.id } ?? [] }
    var selectedWindow: QuotaWindow? {
        snapshot?.windows.first(where: { $0.id == selectedWindowID }) ?? mainWindow ?? snapshot?.windows.first
    }
    var weeklyPace: WeeklyPace? {
        guard let mainWindow, let snapshot else { return nil }
        return WeeklyPace.evaluate(window: mainWindow, observedAt: snapshot.sampledAt, now: now)
    }
    var forecast: WindowForecast? {
        guard let selectedWindow, let snapshot else { return nil }
        return ForecastEngine.forecast(window: selectedWindow, history: history, accountKey: snapshot.accountKey, now: now)
    }
    var recentPoints: [(Date, Double)] {
        guard let selectedWindow, let snapshot else { return [] }
        return ForecastEngine.cycleSamples(window: selectedWindow, history: history, accountKey: snapshot.accountKey)
            .map { ($0.sampledAt, $0.windows.first(where: { $0.id == selectedWindow.id })!.usedPercent) }
    }
    var effectiveRate: Double? { forecast?.recentRatePerHour ?? forecast?.baselineRatePerHour }
    var usesBaseline: Bool { forecast?.recentRatePerHour == nil && forecast?.baselineRatePerHour != nil }
    var usablePrediction: Bool {
        guard let forecast else { return false }
        return forecast.state == .ready || forecast.state == .insufficientHistory
    }
    var projectedRemaining: Double? {
        guard usablePrediction, let window = selectedWindow, let reset = window.resetsAt,
              let rate = effectiveRate else { return nil }
        return max(0, 100 - window.usedPercent - rate * max(0, reset.timeIntervalSince(now) / 3600))
    }
    var predictionTitle: String {
        switch weeklyPace?.state {
        case .ahead: return L("蹬太快啦，额度可能撑不到重置")
        case .surplus: return L("额度很宽裕，可以使劲蹬")
        case .balanced: return L("节奏刚刚好，稳稳蹬到重置")
        case .exhausted: return L("额度已用完，等账户重置")
        case .stale: return L("读数过期啦，先看看仪表盘")
        case .waitingForReset: return L("到重置时间啦，等服务端确认")
        default: return L("等待有效的节奏读数")
        }
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false; now = Date() }
        async let tokenRefresh: Void = refreshTokens()
        async let radarRefresh: Void = refreshRadarIfNeeded()
        var failureStage = L("额度读取失败")
        do {
            let live = try await Task.detached { try CodexAppServerClient().fetchSnapshot() }.value
            // Publish only a successfully fetched account. Old account history never mixes in.
            if snapshot?.accountKey != live.accountKey { bankedResets = nil; bankedError = nil }
            snapshot = live
            if !live.windows.contains(where: { $0.id == selectedWindowID }) {
                selectedWindowID = live.windows.first(where: { $0.bucketID == "codex" && $0.durationMinutes == 10080 })?.id
                    ?? live.windows.first(where: { $0.bucketID == "codex" })?.id
                    ?? live.windows.first?.id
            }
            failureStage = L("额度已读取，但历史保存失败")
            let store = try QuotaHistoryStore()
            try store.append(live)
            history = try store.load(accountKey: live.accountKey)
            error = nil
            do { bankedResets = try await BankedResetReader().read(accountKey: live.accountKey); bankedError = nil }
            catch { bankedError = L("储备重置卡读取失败：{{0}}", String(describing: error.localizedDescription)) }
        } catch {
            self.error = "\(failureStage)：\(error.localizedDescription)"
        }
        await radarRefresh
        await tokenRefresh
        await checkReminders()
    }
    func checkReminders() async {
        guard monitor != nil else { return }
        let currentTime = Date()
        let normalPace: DeadlinePace?
        if let window = mainWindow, let snapshot {
            normalPace = DeadlinePace.evaluate(window: window, observedAt: snapshot.sampledAt,
                history: history, accountKey: snapshot.accountKey, deadline: window.resetsAt, now: currentTime)
        } else { normalPace = nil }
        let reminder = ResetReminder.evaluate(advice: ExtraResetAdvice.evaluate(radar, now: currentTime),
            window: mainWindow, observedAt: snapshot?.sampledAt, accountKey: snapshot?.accountKey,
            temporaryPace: temporaryResetPace, normalPace: normalPace, now: currentTime,
            bankedResets: bankedError == nil ? bankedResets : nil)
            ?? ResetReminder.banked(bankedError == nil ? bankedResets : nil, accountKey: snapshot?.accountKey, now: currentTime)
        await reminders.reconcile(reminder, now: currentTime, runwayLight: menuRunwayLight)
    }
    func refreshTokens() async {
        guard !tokensLoading else { return }
        tokensLoading = true
        defer { tokensLoading = false }
        do {
            tokenReport = try await tokenReader.read(now: Date())
            tokenError = nil
        } catch {
            tokenError = L("本机 token 统计读取失败：{{0}}", String(describing: error.localizedDescription))
        }
    }
    private func refreshRadarIfNeeded() async {
        if radar == nil || Date().timeIntervalSince(radar!.fetchedAt) > 5 * 60 {
            await refreshRadar()
        }
    }
    func refreshRadar() async {
        do { radar = try await RadarData.fetch(); radarError = nil }
        catch { radarError = L("全局雷达更新失败：{{0}}", String(describing: error.localizedDescription)) }
        now = Date()
        await checkReminders()
    }
    func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "codex-quota-history.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(history).write(to: url, options: .atomic)
            exportMessage = L("已导出当前账户的 {{0}} 个采样", String(describing: history.count))
        } catch { exportMessage = L("导出失败：{{0}}", String(describing: error.localizedDescription)) }
    }
}

let ink = ColorTokens()
struct ColorTokens {
    let background = SwiftUI.Color(red: 0.065, green: 0.077, blue: 0.086)
    let panel = SwiftUI.Color(red: 0.105, green: 0.123, blue: 0.133)
    let secondary = SwiftUI.Color(red: 0.70, green: 0.75, blue: 0.76)
    let accent = SwiftUI.Color(red: 0.55, green: 0.91, blue: 0.74)
    let blue = SwiftUI.Color(red: 0.50, green: 0.76, blue: 0.99)
}
import SwiftUI
