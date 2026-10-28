import SwiftUI
import AppKit

struct ResetNotificationSettings: View {
    @ObservedObject var controller: ResetNotificationController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Toggle(L("开启重置提醒"), isOn: $controller.enabled)
                .font(.system(size: 18, weight: .semibold)).tint(ink.accent)
                .onChange(of: controller.enabled) { _, enabled in
                    if enabled { Task { await controller.enableSystemNotifications() } }
                }
            HStack(alignment: .top, spacing: 20) {
                Image(systemName: "bell.badge.fill").font(.system(size: 36)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("系统通知 + 跨桌面常驻提醒窗")).font(.system(size: 20, weight: .semibold))
                    Text(L("新提醒有一次声音、Dock 提示和最多 2 秒的轻柔流动提示，随后静止常驻。提醒窗保留到你确认或选择稍后提醒；事件过期、已完成或来源失效后自动收起。"))
                        .font(.system(size: 13)).foregroundStyle(ink.secondary).lineSpacing(5)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                Label(controller.permission, systemImage: "checkmark.shield")
                Label(controller.delivery, systemImage: "bell")
                if let error = controller.error { Text(L(error)).foregroundStyle(.orange).textSelection(.enabled) }
            }.font(.system(size: 12)).foregroundStyle(ink.secondary)
            HStack(spacing: 12) {
                Button { Task { await controller.sendTest() } } label: {
                    Text(L("发送测试提醒")).padding(.horizontal, 14).padding(.vertical, 10)
                        .background(ink.accent, in: RoundedRectangle(cornerRadius: 7)).foregroundStyle(.black)
                }.buttonStyle(.plain).disabled(!controller.enabled)
                Button(L("检查通知权限")) { Task { await controller.enableSystemNotifications() } }.buttonStyle(.bordered)
                Button(L("打开系统通知设置")) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                }.buttonStyle(.bordered)
            }.font(.system(size: 12))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(L("什么时候叫我？")).font(.system(size: 15, weight: .semibold))
                Text(L("• 新的有效临时重置预告出现时立即提醒；未知时间和站点观察目标分别标注。\n• 正常订阅重置在最后 24 小时进入提醒范围。\n• 有明确目标时，首次、最后 2 小时、最后 30 分钟各提醒一次；确认记录跨重启保留。\n• 选择“15 分钟后提醒”后，只有事件仍有效才会再次弹出。\n• 近期实测速度偏慢时提示加速和所需倍速；已经接近用尽时提示稳住节奏。"))
                    .font(.system(size: 12)).foregroundStyle(ink.secondary).lineSpacing(7)
            }
            Text(L("想让系统通知也保留到手动关闭，可在 macOS 通知设置中将 Codex Jet 设为“持续”（部分系统称“提醒”），并开启声音。系统通知仍受专注模式与系统设置影响；常驻提醒窗独立显示。App 运行时每 5 分钟检查新公告，退出或休眠时不检查。"))
                .font(.system(size: 11)).foregroundStyle(ink.secondary).lineSpacing(5)
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).card()
            .task { await controller.updatePermission() }
    }
}
