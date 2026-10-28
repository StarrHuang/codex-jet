import Foundation
import CryptoKit

/// 手机中继的个人提醒合同；不含登录凭据、原始账户标识或会话历史。
public struct PocketPersonalReminder: Encodable, Sendable {
    public struct Observation: Codable, Sendable {
        public let remainingPercent: Double
        public let ratePercentPerHour: Double
        public let sampledAt: Date
        public let sampleCount: Int
        public let sampleSpanSeconds: TimeInterval
        public let accountScope: String
    }
    public struct Event: Codable, Sendable {
        public let identifier: String
        public let accountScope: String
        public let kind: String
        public let observedAt: Date
        public let deadline: Date
        public let earlierResetAt: Date?
    }
    public let schemaVersion = 2
    public let id: String
    public let kind = "personalReminder"
    public let createdAt: Date
    public let expiresAt: Date
    public let title: String
    public let body: String
    public let observation: Observation
    public let event: Event
    public let isSynthetic = false
    public let dedupeKey: String
    public let bindingID: String

    /// 只从新鲜、当前周期且采样充分的实测速度构造意图，优先最近可行动截止。
    public static func make(snapshot: QuotaSnapshot, history: [QuotaSnapshot], banked: BankedResetSnapshot?,
                            accountRef: String, bindingID: String, now: Date) -> Self? {
        guard !accountRef.isEmpty, !bindingID.isEmpty,
              snapshot.sampledAt <= now, now.timeIntervalSince(snapshot.sampledAt) < 600,
              let window = snapshot.windows.first(where: { $0.bucketID == "codex" && $0.durationMinutes == 10080 }),
              window.usedPercent.isFinite, (0..<100).contains(window.usedPercent) else { return nil }
        var targets: [(date: Date, kind: String, identifier: String)] = []
        if let reset = window.resetsAt, reset > now {
            targets.append((reset, "weekly", window.id))
        }
        if let banked, banked.accountKey == snapshot.accountKey,
           banked.sampledAt <= now, now.timeIntervalSince(banked.sampledAt) <= 600 {
            targets += banked.cards.filter { $0.expiresAt > now }.map { ($0.expiresAt, "bankedExpiry", $0.id) }
        }
        guard let target = targets.min(by: { $0.date < $1.date }),
              target.date.timeIntervalSince(now) <= 24 * 3600 else { return nil }
        let pace = DeadlinePace.evaluate(window: window, observedAt: snapshot.sampledAt,
            history: history, accountKey: snapshot.accountKey, deadline: target.date, now: now)
        guard [.tooSlow, .onTrack].contains(pace.state),
              let rate = pace.recentRatePerHour, rate.isFinite, rate >= 0,
              let remaining = pace.projectedRemainingAtDeadline, remaining > 0,
              let measurement = pace.measurements.first(where: { $0.ratePerHour != nil }),
              measurement.sampleCount >= 3, measurement.spanHours >= 0.25 else { return nil }
        let balance = 100 - window.usedPercent
        let earlier = target.kind == "bankedExpiry" ? window.resetsAt.flatMap { $0 > now && $0 < target.date ? $0 : nil } : nil
        // 账户作用域使用本机生成的随机配对 ID，不上传 history 的邮箱散列。
        let observation = Observation(remainingPercent: balance, ratePercentPerHour: rate,
            sampledAt: snapshot.sampledAt, sampleCount: measurement.sampleCount,
            sampleSpanSeconds: measurement.spanHours * 3600, accountScope: accountRef)
        let event = Event(identifier: target.identifier, accountScope: accountRef, kind: target.kind,
                          observedAt: snapshot.sampledAt, deadline: target.date, earlierResetAt: earlier)
        let material = [accountRef, target.kind, target.identifier, String(Int(target.date.timeIntervalSince1970))].joined(separator: "|")
        let key = SHA256.hash(data: Data(material.utf8)).map { String(format: "%02x", $0) }.joined()
        return Self(id: UUID().uuidString, createdAt: now,
                    expiresAt: min(snapshot.sampledAt.addingTimeInterval(600), target.date),
                    title: target.kind == "bankedExpiry" ? "Card redemption deadline" : "Weekly reset",
                    body: String(format: "%.1f%% remaining; projected unused %.1f%%. %.2f percentage points/hour needed.",
                                 balance, remaining, balance / (target.date.timeIntervalSince(now) / 3600)),
                    observation: observation, event: event, dedupeKey: key, bindingID: bindingID)
    }
}

public struct PocketPairing: Decodable, Sendable {
    public let macID: String
    public let macToken: String
    public let bindingID: String
}
public struct PocketRelayAcceptance: Decodable, Sendable {
    public let accepted: Bool
    public let id: String?
}

public enum PocketRelayError: Error, LocalizedError, Sendable {
    case invalidServer, invalidResponse, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidServer: "Use an HTTPS server origin; local HTTP is allowed only in a development build."
        case .invalidResponse: "The reminder relay returned an invalid response."
        case let .http(code): "Reminder relay HTTP \(code)."
        }
    }
}

/// 中继 HTTP 客户端：禁止重定向，避免令牌被第三方地址接收。
public final class PocketRelayClient: Sendable {
    private final class RedirectBlocker: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }
    public let server: URL
    private let session: URLSession

    public init(server: URL, allowLocalHTTP: Bool = false) throws {
        guard let parts = URLComponents(url: server, resolvingAgainstBaseURL: false),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
              parts.scheme == "https" || (allowLocalHTTP && parts.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw PocketRelayError.invalidServer
        }
        self.server = server
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 15
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: RedirectBlocker(), delegateQueue: nil)
    }

    /// 一次性配对码仅用于兑换该产品的 Mac 令牌。
    public func pair(code: String, accountRef: String) async throws -> PocketPairing {
        struct Claim: Encodable { let code: String; let accountRef: String }
        let data = try await request(path: "v1/pairings/claim", body: JSONEncoder().encode(Claim(code: code, accountRef: accountRef)))
        let pair = try JSONDecoder().decode(PocketPairing.self, from: data)
        guard !pair.macID.isEmpty, !pair.bindingID.isEmpty, pair.macToken.count >= 32 else { throw PocketRelayError.invalidResponse }
        return pair
    }

    /// 每次提交只包含这一条当前有效的提醒；中继再次验证新鲜度和绑定。
    public func submit(_ reminder: PocketPersonalReminder, token: String) async throws -> PocketRelayAcceptance {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try await request(path: "v1/personal-reminders", token: token, body: encoder.encode(reminder))
        return try JSONDecoder().decode(PocketRelayAcceptance.self, from: data)
    }

    /// 撤销服务器绑定后，旧 Mac 令牌不再能提交消息。
    public func unpair(token: String) async throws {
        _ = try await request(path: "v1/unpair", token: token, body: Data("{}".utf8))
    }

    private func request(path: String, token: String? = nil, body: Data) async throws -> Data {
        var request = URLRequest(url: server.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, data.count <= 256_000 else { throw PocketRelayError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw PocketRelayError.http(http.statusCode) }
        return data
    }
}
