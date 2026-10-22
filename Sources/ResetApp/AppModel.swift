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
    func startMonitoring() {
        guard monitor == nil else { return }
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
            case .bankedCard: "储备卡到期（需手动兑换，不会自动回补）"
            case .temporaryReset: "临时重置目标"
            case .weeklyReset: "正常订阅重置"
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
        if [.upcoming, .observation].contains(advice.state), let deadline = advice.deadline, deadline > now {
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
    private var menuDeadlineExplanation: String? {
        guard let candidate = menuDeadlineCandidate else { return nil }
        if case .temporaryReset = candidate.source { return extraResetAdvice.targetName }
        return candidate.source.explanation
    }
    private var menuDeadlineHours: String? {
        guard let deadline = menuDeadline else { return nil }
        let hours = deadline.timeIntervalSince(now) / 3600
        return hours < 0.05 ? "<0.1h" : String(format: "%.1fh", hours)
    }
    private var menuDeadlineSuffix: String { menuDeadlineHours.map { " " + $0 } ?? "" }
    var menuPace: DeadlinePace? {
        guard let window = mainWindow, let snapshot else { return nil }
        return DeadlinePace.evaluate(window: window, observedAt: snapshot.sampledAt, history: history,
            accountKey: snapshot.accountKey, deadline: menuDeadline, now: now)
    }
    var menuBarTitle: String {
        guard let window = mainWindow, let snapshot else { return "—%→— —×" }
        let fresh = snapshot.sampledAt <= now && now.timeIntervalSince(snapshot.sampledAt) <= 600
        let current = number(100 - window.usedPercent) + "%" + (fresh ? "" : "*")
        let signal = hasTemporaryTarget ? "⚡" : ""
        guard let pace = menuPace, [.tooSlow, .onTrack, .tooFast, .exhausted].contains(pace.state) else {
            return signal + current + "→— —×" + menuDeadlineSuffix
        }
        if pace.state == .exhausted { return signal + current + "→0% ⏸" + menuDeadlineSuffix }
        guard let remaining = pace.projectedRemainingAtDeadline else { return signal + current + "→— —×" + menuDeadlineSuffix }
        let projected = remaining > 0 && remaining < 1 ? "<1" : number(remaining)
        let change: String
        if pace.state == .onTrack { change = "≈1×" }
        else if let multiplier = pace.speedMultiplier {
            var amount = multiplier > 99 ? ">99" : multiplier < 0.01 ? "<0.01"
                : String(format: multiplier < 1 ? "%.2f" : multiplier < 10 ? "%.1f" : "%.0f", multiplier)
            if amount.contains("."), !amount.hasPrefix("<") {
                while amount.hasSuffix("0") { amount.removeLast() }
                if amount.hasSuffix(".") { amount.removeLast() }
            }
            change = (multiplier > 1 ? "↑" : "↓") + amount + "×"
        } else { change = "↑启动" }
        return signal + current + "→" + projected + "% " + change + menuDeadlineSuffix
    }
    var menuBarHelp: String {
        guard let window = mainWindow, let snapshot else { return "尚无账户额度读数；点击打开额度面板。" }
        let fresh = snapshot.sampledAt <= now && now.timeIntervalSince(snapshot.sampledAt) <= 600
        var lines = ["当前本轮剩余：" + number(100 - window.usedPercent) + "%" + (fresh ? "" : "（上次读数，* 表示过期）")]
        if let target = menuDeadline {
            lines.append("预测目标：" + (menuDeadlineExplanation ?? "") + " · " + ResetTimeDisplay.shanghai(target) + " 北京时间")
            lines.append("距目标：" + ResetTimeDisplay.remaining(until: target, now: now))
        }
        if let pace = menuPace, [.tooSlow, .onTrack, .tooFast].contains(pace.state),
           let remaining = pace.projectedRemainingAtDeadline {
            lines.append(String(format: "按现速到目标时，本轮预计剩余：%.1f%%", remaining))
            if let rate = pace.recentRatePerHour, let required = pace.requiredRatePerHour {
                lines.append(String(format: "实测 %.2f → 目标 %.2f 百分点/小时", rate, required))
            }
            if let multiplier = pace.speedMultiplier {
                lines.append(String(format: "↑/↓ 表示建议调整到当前速度的 %.2f 倍，以本轮恰好用尽为目标。", multiplier))
            } else { lines.append("近期实测为零：需启动任务，不能计算有限的加速倍数。") }
        } else { lines.append("— 表示缺少有效速度样本、读数过期或目标已到；不估算倍速。") }
        if hasTemporaryTarget { lines.append("⚡ 有临时重置公告；到账时间以账户实际回补为准。") }
        if usableBankedCount > 0 { lines.append("另有 \(usableBankedCount) 张储备卡，需手动兑换；不计入本轮预计余量。下拉查看到期与衔接安排。") }
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
        case .ahead: return "蹬太快啦，额度可能撑不到重置"
        case .surplus: return "额度很宽裕，可以使劲蹬"
        case .balanced: return "节奏刚刚好，稳稳蹬到重置"
        case .exhausted: return "额度已用完，等账户重置"
        case .stale: return "读数过期啦，先看看仪表盘"
        case .waitingForReset: return "到重置时间啦，等服务端确认"
        default: return "等待有效的节奏读数"
        }
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false; now = Date() }
        async let tokenRefresh: Void = refreshTokens()
        async let radarRefresh: Void = refreshRadarIfNeeded()
        var failureStage = "额度读取失败"
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
            failureStage = "额度已读取，但历史保存失败"
            let store = try QuotaHistoryStore()
            try store.append(live)
            history = try store.load(accountKey: live.accountKey)
            error = nil
            do { bankedResets = try await BankedResetReader().read(accountKey: live.accountKey); bankedError = nil }
            catch { bankedError = "储备重置卡读取失败：\(error.localizedDescription)" }
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
        await reminders.reconcile(reminder, now: currentTime)
    }
    func refreshTokens() async {
        guard !tokensLoading else { return }
        tokensLoading = true
        defer { tokensLoading = false }
        do {
            tokenReport = try await tokenReader.read(now: Date())
            tokenError = nil
        } catch {
            tokenError = "本机 token 统计读取失败：\(error.localizedDescription)"
        }
    }
    private func refreshRadarIfNeeded() async {
        if radar == nil || Date().timeIntervalSince(radar!.fetchedAt) > 5 * 60 {
            await refreshRadar()
        }
    }
    func refreshRadar() async {
        do { radar = try await RadarData.fetch(); radarError = nil }
        catch { radarError = "全局雷达更新失败：\(error.localizedDescription)" }
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
            exportMessage = "已导出当前账户的 \(history.count) 个采样"
        } catch { exportMessage = "导出失败：\(error.localizedDescription)" }
    }
}

let ink = ColorTokens()
struct ColorTokens {
    let background = SwiftUI.Color(red: 0.055, green: 0.068, blue: 0.078)
    let panel = SwiftUI.Color(red: 0.092, green: 0.109, blue: 0.119)
    let secondary = SwiftUI.Color(red: 0.64, green: 0.69, blue: 0.70)
    let accent = SwiftUI.Color(red: 0.53, green: 0.91, blue: 0.72)
    let blue = SwiftUI.Color(red: 0.44, green: 0.72, blue: 0.98)
}
import SwiftUI
