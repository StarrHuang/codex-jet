import Foundation
import Combine
import Security
import ResetCore

/// 个人提醒绑定仅保存在本机钥匙串；切换 Codex 账户后立即暂停并撤销旧绑定。
@MainActor
final class PocketSyncController: ObservableObject {
    @Published var serverAddress = ""
    @Published var pairingCode = ""
    @Published private(set) var isPaired = false
    @Published private(set) var busy = false
    @Published private(set) var status = "尚未配对手机"
    @Published private(set) var errorMessage: String?
    private var credentials: Credentials?
    private var loaded = false
    private var currentAccountKey: String?
    private var lastAttemptSample: Date?
    private let keychainService = "local.codexreset.pocket-relay.v1"

    private struct Credentials: Codable {
        let server: URL
        let macToken: String
        let bindingID: String
        let accountKey: String
        let accountRef: String
        var suspended: Bool
    }

    /// 仅在启动真实监测或打开配对设置后访问钥匙串，合成截图不触碰真实绑定。
    func restore() {
        guard !loaded else { return }
        loaded = true
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService, kSecAttrAccount as String: "mac",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let result = SecItemCopyMatching(query as CFDictionary, &item)
        if result == errSecItemNotFound { return }
        guard result == errSecSuccess, let data = item as? Data else {
            errorMessage = "Keychain OSStatus \(result)"; return
        }
        do {
            let stored = try JSONDecoder().decode(Credentials.self, from: data)
            credentials = stored; serverAddress = stored.server.absoluteString
            isPaired = !stored.suspended
            status = stored.suspended ? "账户已变化，正在等待撤销旧配对" : "已配对，等待新鲜额度采样"
        } catch { errorMessage = error.localizedDescription }
    }

    /// 账户身份改变时先停用本地发送，再尝试撤销服务器旧权限；网络失败保留撤销待办。
    func observeAccount(_ key: String) async {
        restore()
        currentAccountKey = key
        guard var stored = credentials, stored.accountKey != key || stored.suspended else { return }
        stored.suspended = true; credentials = stored; isPaired = false
        status = "账户已变化，正在等待撤销旧配对"
        do {
            try save(stored)
            try await client(stored.server).unpair(token: stored.macToken)
            try clearCredentials()
            status = "旧配对已撤销，请为当前账户重新配对"
        } catch PocketRelayError.http(401) {
            do { try clearCredentials(); status = "旧配对已撤销，请为当前账户重新配对" }
            catch { errorMessage = error.localizedDescription }
        } catch { errorMessage = error.localizedDescription }
    }

    /// 手机给出一次性配对码后绑定当前已成功读取的本机账户，绝不上传 Codex 凭据。
    func pair(snapshot: QuotaSnapshot?) async {
        restore()
        guard !busy else { return }
        guard credentials == nil else { status = "请先解除现有配对"; return }
        let now = Date()
        guard let snapshot, snapshot.sampledAt <= now, now.timeIntervalSince(snapshot.sampledAt) <= 600 else {
            status = "请先刷新当前账户的额度"; return
        }
        guard let url = URL(string: serverAddress.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            errorMessage = PocketRelayError.invalidServer.localizedDescription; return
        }
        busy = true; errorMessage = nil
        defer { busy = false; pairingCode = "" }
        let accountRef = UUID().uuidString
        currentAccountKey = snapshot.accountKey
        do {
            let api = try client(url)
            let paired = try await api.pair(code: pairingCode.trimmingCharacters(in: .whitespacesAndNewlines), accountRef: accountRef)
            guard currentAccountKey == snapshot.accountKey else {
                try await api.unpair(token: paired.macToken)
                status = "账户已变化，请重新配对"; return
            }
            let stored = Credentials(server: url, macToken: paired.macToken, bindingID: paired.bindingID,
                                     accountKey: snapshot.accountKey, accountRef: accountRef, suspended: false)
            do { try save(stored) }
            catch {
                let persistenceError = error
                do { try await api.unpair(token: paired.macToken) }
                catch { errorMessage = "\(persistenceError.localizedDescription) · revoke: \(error.localizedDescription)"; return }
                throw persistenceError
            }
            credentials = stored; isPaired = true; lastAttemptSample = nil
            status = "已配对，等待新鲜额度采样"
        } catch { errorMessage = error.localizedDescription }
    }

    /// 按本机周期默认一次的服务器去重提交，服务端可因确认或暂停拒绝；不将接受回执称作送达。
    func reconcile(snapshot: QuotaSnapshot?, history: [QuotaSnapshot], banked: BankedResetSnapshot?, now: Date) async {
        guard !busy, let snapshot, let stored = credentials, !stored.suspended,
              stored.accountKey == snapshot.accountKey, currentAccountKey == snapshot.accountKey,
              lastAttemptSample != snapshot.sampledAt else { return }
        guard let intent = PocketPersonalReminder.make(snapshot: snapshot, history: history, banked: banked,
            accountRef: stored.accountRef, bindingID: stored.bindingID, now: now) else {
            status = "未满足个人提醒条件：需在 24 小时内且预计有余量"; return
        }
        busy = true; errorMessage = nil
        defer { busy = false }
        do {
            let receipt = try await client(stored.server).submit(intent, token: stored.macToken)
            guard credentials?.bindingID == stored.bindingID, credentials?.suspended == false else { return }
            lastAttemptSample = snapshot.sampledAt
            status = receipt.accepted ? "提醒已进入服务器收件箱，尚未启用真机推送" : "该周期已处理或已暂停，等待下一次新鲜采样"
        } catch PocketRelayError.http(401) {
            do { try clearCredentials(); status = "手机配对已失效，请重新配对" }
            catch { errorMessage = error.localizedDescription }
        } catch { errorMessage = error.localizedDescription }
    }

    /// 先撤销远端绑定，再移除本机令牌；失败时保留暂停状态以便重试。
    func unpair() async {
        guard !busy, var stored = credentials else { return }
        busy = true; errorMessage = nil; stored.suspended = true
        credentials = stored; isPaired = false
        defer { busy = false }
        do {
            try save(stored)
            do { try await client(stored.server).unpair(token: stored.macToken) }
            catch PocketRelayError.http(401) { /* 手机已撤销权限，仍可清理本机。 */ }
            try clearCredentials(); status = "已解除手机配对"
        } catch { status = "正在等待撤销旧配对"; errorMessage = error.localizedDescription }
    }

    var hasCredentials: Bool { credentials != nil }

    private func client(_ url: URL) throws -> PocketRelayClient {
        #if DEBUG
        return try PocketRelayClient(server: url, allowLocalHTTP: true)
        #else
        return try PocketRelayClient(server: url)
        #endif
    }

    private func save(_ stored: Credentials) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService, kSecAttrAccount as String: "mac"]
        let value = try JSONEncoder().encode(stored)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: value] as CFDictionary)
        if update == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = value
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let result = SecItemAdd(item as CFDictionary, nil)
            guard result == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        } else if update != errSecSuccess { throw NSError(domain: NSOSStatusErrorDomain, code: Int(update)) }
    }

    private func clearCredentials() throws {
        let result = SecItemDelete([kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService, kSecAttrAccount as String: "mac"] as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(result))
        }
        credentials = nil; isPaired = false; lastAttemptSample = nil
    }
}
