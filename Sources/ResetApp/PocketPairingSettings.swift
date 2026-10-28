import SwiftUI

/// 手机负责生成短时配对码，Mac 在用户确认当前账户后绑定。
struct PocketPairingSettings: View {
    @ObservedObject var controller: PocketSyncController
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(L("手机额度提醒"), systemImage: "iphone.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
            Text(L("在 iPhone 中连接同一服务器并生成配对码。此电脑在线时，若周重置或储备卡兑换截止进入 24 小时且预计仍有余量，会发送个人提醒。Tibo 公告由服务器独立广播。"))
                .font(.system(size: 12)).foregroundStyle(ink.secondary).lineSpacing(5)
            TextField(L("服务器地址，例如 https://notify.example.com"), text: $controller.serverAddress)
                .textFieldStyle(.roundedBorder).disabled(controller.hasCredentials || controller.busy)
            if !controller.hasCredentials {
                HStack {
                    SecureField(L("手机上的一次性配对码"), text: $controller.pairingCode).textFieldStyle(.roundedBorder)
                    Button(L("配对当前账户")) {
                        Task { await controller.pair(snapshot: model.error == nil ? model.snapshot : nil); await model.checkReminders() }
                    }.disabled(controller.busy || controller.pairingCode.isEmpty)
                }
            } else {
                Button(L("解除配对")) { Task { await controller.unpair() } }.disabled(controller.busy)
            }
            Text(L(controller.status)).font(.system(size: 12)).foregroundStyle(controller.isPaired ? ink.accent : ink.secondary)
            if let error = controller.errorMessage { Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled) }
            Text(L("仅同步提醒摘要，OpenAI 登录凭据留在电脑。当前使用服务器收件箱验证，尚未连接 APNs；手机需打开 App 刷新查看。"))
                .font(.system(size: 11)).foregroundStyle(ink.secondary).lineSpacing(4)
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading).card()
            .task { controller.restore() }
    }
}
