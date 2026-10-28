import AppKit
import SwiftUI
import ResetCore
// Older macOS SDKs omit Sendable annotations on immutable notification snapshots.
@preconcurrency import UserNotifications

@MainActor
final class ResetNotificationController: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "resetRemindersEnabled")
            if !enabled { dismissCurrent() }
        }
    }
    @Published private(set) var permission = L("尚未检查系统通知权限")
    @Published private(set) var delivery = L("等待即将到来的重置")
    @Published private(set) var error: String?
    @Published private(set) var active: ResetReminder?
    var openDashboard: (() -> Void)?
    private let defaults: UserDefaults
    private var ledger: ResetReminderLedger
    private var panel: NSPanel?
    private var reminderHostingView: NSHostingView<ResetReminderCard>?
    private var attentionRequest: Int?
    private var started = false
    private var runwayLight: DeadlinePace.RunwayLight = .unknown
    private var center: UNUserNotificationCenter { .current() }
    private static let category = "CODEX_RESET_REMINDER"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.object(forKey: "resetRemindersEnabled") as? Bool ?? true
        if let data = defaults.data(forKey: "resetReminderLedger") {
            do { ledger = try JSONDecoder().decode(ResetReminderLedger.self, from: data) }
            catch { ledger = ResetReminderLedger(); super.init(); self.error = L("提醒记录读取失败：{{0}}", String(describing: error.localizedDescription)); return }
        } else { ledger = ResetReminderLedger() }
        super.init()
    }

    func start() async {
        guard !started else { return }
        started = true
        center.delegate = self
        registerCategories()
        if enabled { await enableSystemNotifications() }
        else { await updatePermission() }
    }

    private func registerCategories() {
        let actions = [
            UNNotificationAction(identifier: "OPEN", title: L("查看额度"), options: .foreground),
            UNNotificationAction(identifier: "SNOOZE", title: L("15 分钟后提醒")),
            UNNotificationAction(identifier: "ACK", title: L("我知道了"))
        ]
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.category,
                                      actions: actions, intentIdentifiers: [], options: .customDismissAction)])
    }
    func updateLanguage() async {
        registerCategories()
        await updatePermission()
        if active == nil { delivery = L("等待即将到来的重置") }
    }

    func enableSystemNotifications() async {
        do {
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            await updatePermission()
        } catch { self.error = L("系统通知权限请求失败：{{0}}", String(describing: error.localizedDescription)) }
    }

    func updatePermission() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            permission = settings.alertSetting == .enabled
                ? (settings.alertStyle == .alert ? L("系统通知已允许 · 持续提醒") : L("系统通知已允许 · 临时横幅"))
                : L("系统通知已授权，但横幅未启用")
        case .denied: permission = L("系统通知未允许；常驻提醒窗仍有效")
        case .notDetermined: permission = L("系统通知尚未授权；常驻提醒窗仍有效")
        @unknown default: permission = L("系统通知权限状态未知")
        }
    }

    func reconcile(_ reminder: ResetReminder?, now: Date, runwayLight: DeadlinePace.RunwayLight = .unknown) async {
        self.runwayLight = runwayLight
        guard enabled else { return }
        if let active, active.isTest, active.expiresAt > now { return }
        let delivered = await center.deliveredNotifications()
        let obsolete = delivered.filter { $0.request.identifier != reminder?.id }.map { $0.request.identifier }
        center.removeDeliveredNotifications(withIdentifiers: obsolete)
        if active?.id != reminder?.id || active.map({ $0.expiresAt <= now }) == true {
            dismissCurrent()
        }
        guard let reminder else { return }
        if active?.id == reminder.id {
            active = reminder
            updatePanel(reminder)
            return
        }
        guard ledger.shouldPresent(reminder, now: now) else { return }
        ledger.record(reminder)
        saveLedger()
        await present(reminder)
    }

    func sendTest() async {
        guard started else { return }
        if let active, !active.isTest {
            delivery = L("已有真实重置提醒，请先确认后再测试")
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        await present(.test(now: Date()))
        // An explicit preview may take keyboard focus; automatic reminders do not.
        panel?.makeKeyAndOrderFront(nil)
    }

    private func present(_ reminder: ResetReminder) async {
        guard enabled else { return }
        dismissCurrent()
        active = reminder
        showPanel(reminder)
        attentionRequest = NSApp.requestUserAttention(.informationalRequest)
        NSApp.dockTile.badgeLabel = "1"
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.detail
        content.sound = .default
        content.interruptionLevel = .active
        content.categoryIdentifier = Self.category
        content.threadIdentifier = "codex-reset"
        let settings = await center.notificationSettings()
        guard active?.id == reminder.id, enabled else { return }
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            NSSound(named: "Glass")?.play()
            delivery = L("已弹出常驻提醒窗；系统通知未获授权")
            return
        }
        do {
            try await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: nil))
            guard active?.id == reminder.id, enabled else {
                center.removeDeliveredNotifications(withIdentifiers: [reminder.id])
                return
            }
            let delivered = await center.deliveredNotifications()
            delivery = delivered.contains(where: { $0.request.identifier == reminder.id })
                ? L("已送达通知中心，并弹出常驻提醒窗") : L("已提交系统通知，并弹出常驻提醒窗")
            error = nil
        } catch { self.error = L("系统通知发送失败：{{0}}；常驻提醒窗仍有效", String(describing: error.localizedDescription)) }
    }

    func acknowledge() {
        guard let active else { return }
        if !active.isTest { ledger.acknowledge(active); saveLedger() }
        delivery = active.isTest ? L("测试提醒已确认") : L("已确认本阶段提醒；临近截止时仍会分级提醒")
        dismissCurrent()
    }

    func snooze() {
        guard let active else { return }
        if !active.isTest { ledger.snooze(active, now: Date()); saveLedger() }
        delivery = active.isTest ? L("测试提醒已关闭") : L("15 分钟后重新检查；事件失效则不再提醒")
        dismissCurrent()
    }

    func viewDashboard() {
        openDashboard?()
    }

    private func dismissCurrent() {
        if let id = active?.id {
            center.removeDeliveredNotifications(withIdentifiers: [id])
            center.removePendingNotificationRequests(withIdentifiers: [id])
        }
        panel?.orderOut(nil)
        active = nil
        if let attentionRequest { NSApp.cancelUserAttentionRequest(attentionRequest) }
        attentionRequest = nil
        NSApp.dockTile.badgeLabel = nil
    }

    private func saveLedger() {
        do { defaults.set(try JSONEncoder().encode(ledger), forKey: "resetReminderLedger") }
        catch { self.error = L("提醒记录保存失败：{{0}}", String(describing: error.localizedDescription)) }
    }

    private func showPanel(_ reminder: ResetReminder) {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 360),
                                styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.title = "Codex Jet · " + L("重置通知")
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.isMovableByWindowBackground = true
            self.panel = panel
        }
        updatePanel(reminder)
        if let screen = NSScreen.main, let panel {
            let frame = screen.visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.maxY - 32))
        }
        panel?.orderFrontRegardless()
    }

    private func updatePanel(_ reminder: ResetReminder) {
        let rootView = ResetReminderCard(reminder: reminder, runwayLight: runwayLight,
            acknowledge: { [weak self] in self?.acknowledge() },
            snooze: { [weak self] in self?.snooze() },
            open: { [weak self] in self?.viewDashboard() })
        let view: NSHostingView<ResetReminderCard>
        if let existing = reminderHostingView {
            existing.rootView = rootView
            view = existing
        } else {
            view = NSHostingView(rootView: rootView)
            reminderHostingView = view
            panel?.contentView = view
        }
        panel?.setContentSize(NSSize(width: 510, height: max(330, view.fittingSize.height)))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                           didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let identifier = response.notification.request.identifier
        await MainActor.run {
            guard self.enabled else { return }
            if action == "ACK", self.active?.id == identifier { self.acknowledge() }
            else if action == "SNOOZE", self.active?.id == identifier { self.snooze() }
            else if action == "OPEN" || action == UNNotificationDefaultActionIdentifier {
                self.viewDashboard()
                if let active = self.active { self.showPanel(active) }
            }
        }
    }
}

struct ResetReminderCard: View {
    let reminder: ResetReminder
    var runwayLight: DeadlinePace.RunwayLight = .unknown
    let acknowledge: () -> Void
    let snooze: () -> Void
    let open: () -> Void
    @State private var kickoff = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || CommandLine.arguments.contains("--reduce-motion") }

    private var paceSummary: String? {
        guard reminder.recentRate != nil || reminder.requiredRate != nil
                || reminder.projectedRemaining != nil || reminder.multiplier != nil else { return nil }
        var parts: [String] = []
        if let rate = reminder.recentRate { parts.append(String(format: L("近期实测 %.2f 百分点/小时"), rate)) }
        if let rate = reminder.requiredRate { parts.append(String(format: L("目标需 %.2f 百分点/小时"), rate)) }
        if let remaining = reminder.projectedRemaining { parts.append(String(format: L("按当前速度届时约剩 %.0f%%"), remaining)) }
        if let multiplier = reminder.multiplier {
            parts.append(String(format: multiplier > 1.1 ? L("建议加速至 %.2f×") : multiplier < 0.9 ? L("建议放慢至 %.2f×") : L("目标约 %.2f×"), multiplier))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                QuotaBrandBadge().frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex Jet").font(.system(size: 13, weight: .semibold))
                    Text(reminder.isTest ? L("通知功能测试") : L("重置通知"))
                        .font(.system(size: 12)).foregroundStyle(ink.secondary)
                }
                Spacer()
                Image(systemName: "bell.badge").foregroundStyle(.orange).font(.system(size: 18))
            }
            Text(reminder.title).font(.system(size: 22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let deadline = reminder.deadline {
                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    HStack(spacing: 14) {
                        QuotaFlowView(remainingPercent: reminder.currentRemaining, ratePerHour: reminder.recentRate,
                                      announced: !reminder.isTest, animated: kickoff, runwayLight: runwayLight)
                            .frame(width: 108, height: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(countdown(until: deadline, now: timeline.date))
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit().foregroundStyle(.orange)
                            Text(L("目标 · {{0}} 上海时间", String(describing: ResetReminder.dateText(deadline))))
                                .font(.system(size: 12)).foregroundStyle(ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                QuotaFlowView(remainingPercent: reminder.currentRemaining, ratePerHour: reminder.recentRate,
                              announced: !reminder.isTest, animated: kickoff, runwayLight: runwayLight)
                    .frame(width: 108, height: 72)
            }
            if let paceSummary {
                Text(paceSummary).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(reminder.isTest ? ink.secondary : runwayLight.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(reminder.detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.78))
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(action: open) {
                    Text(L("查看额度")).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(ink.accent, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black)
                }.buttonStyle(.plain)
                Button(L("15 分钟后提醒"), action: snooze).buttonStyle(.bordered)
                Spacer()
                Button(L("我知道了"), action: acknowledge).buttonStyle(.bordered)
            }.font(.system(size: 12))
            Text(L("常驻显示，直到确认或稍后提醒；重置窗口失效后自动收起。"))
                .font(.system(size: 11)).foregroundStyle(ink.secondary)
        }.padding(22).frame(width: 510, alignment: .leading)
            .background(ink.background)
            .overlay(alignment: .top) { Rectangle().fill(.orange).frame(height: 3) }
            .foregroundStyle(.white).preferredColorScheme(.dark)
            .task(id: reminder.id) {
                guard !reduceMotion else { kickoff = false; return }
                kickoff = true
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                kickoff = false
            }
    }

    private func countdown(until deadline: Date, now: Date) -> String {
        let seconds = max(0, Int(deadline.timeIntervalSince(now)))
        if seconds == 0 { return L("目标时间已到") }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        return days > 0 ? L("剩余 {{0}}天 {{1}}小时", String(describing: days), String(describing: hours)) : L("剩余 {{0}}小时 {{1}}分", String(describing: hours), String(describing: minutes))
    }
}
