import CryptoKit
import Foundation

public struct BankedResetCard: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let grantedAt: Date
    public let expiresAt: Date
    public init(id: String, grantedAt: Date, expiresAt: Date) {
        self.id = id; self.grantedAt = grantedAt; self.expiresAt = expiresAt
    }
}

public struct BankedResetSnapshot: Equatable, Sendable {
    public let sampledAt: Date
    public let accountKey: String
    public let cards: [BankedResetCard]
    public init(sampledAt: Date, accountKey: String, cards: [BankedResetCard]) {
        self.sampledAt = sampledAt; self.accountKey = accountKey; self.cards = cards
    }
    public static func decode(_ data: Data, accountKey: String, now: Date) throws -> Self {
        struct Payload: Decodable {
            struct Card: Decodable {
                let id: String
                let reset_type: String
                let is_supported_by_plan: Bool
                let status: String
                let granted_at: String
                let expires_at: String
            }
            let credits: [Card]
            let available_count: Int
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard payload.available_count >= 0 else { throw BankedResetError.invalidResponse }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        let cards = try payload.credits.filter {
            $0.status == "available" && $0.is_supported_by_plan && $0.reset_type == "codex_rate_limits"
        }.map { card -> BankedResetCard in
            guard let expires = iso.date(from: card.expires_at) ?? plain.date(from: card.expires_at),
                  let granted = iso.date(from: card.granted_at) ?? plain.date(from: card.granted_at), expires > granted else {
                throw BankedResetError.invalidResponse
            }
            return BankedResetCard(id: SHA256.hash(data: Data(card.id.utf8)).map { String(format: "%02x", $0) }.joined(),
                                   grantedAt: granted, expiresAt: expires)
        }.filter { $0.expiresAt > now }.sorted { $0.expiresAt < $1.expiresAt }
        return Self(sampledAt: now, accountKey: accountKey, cards: cards)
    }
}

public enum BankedResetError: Error, LocalizedError {
    case missingLogin, accountMismatch, invalidResponse, http(Int)
    public var errorDescription: String? {
        switch self {
        case .missingLogin: "无法读取本机 Codex OAuth 登录，请先在 Codex 登录后刷新。"
        case .accountMismatch: "重置卡登录身份与当前额度账户不同，已停止合并计算。"
        case .invalidResponse: "重置卡接口返回的数据格式无效。"
        case let .http(code): "重置卡接口读取失败（HTTP \(code)），请检查 Codex 登录状态。"
        }
    }
}

public struct BankedResetReader: Sendable {
    public init() {}
    /// The ID token is used only to bind the local credential to the already-read account.
    /// The service validates the bearer token. Credentials never leave chatgpt.com or enter history.
    public static func credentialHeaders(authData: Data, expectedAccountKey: String) throws -> [String: String] {
        struct Auth: Decodable {
            struct Tokens: Decodable { let access_token: String; let id_token: String; let account_id: String }
            let tokens: Tokens?
        }
        guard let tokens = try JSONDecoder().decode(Auth.self, from: authData).tokens,
              !tokens.access_token.isEmpty, !tokens.account_id.isEmpty else { throw BankedResetError.missingLogin }
        let parts = tokens.id_token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw BankedResetError.missingLogin }
        var segment = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        segment += String(repeating: "=", count: (4 - segment.count % 4) % 4)
        guard let body = Data(base64Encoded: segment),
              let claims = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let email = claims["email"] as? String, !email.isEmpty else { throw BankedResetError.missingLogin }
        let key = SHA256.hash(data: Data(("chatgpt:" + email.lowercased()).utf8)).map { String(format: "%02x", $0) }.joined()
        guard key == expectedAccountKey else { throw BankedResetError.accountMismatch }
        return ["Authorization": "Bearer " + tokens.access_token, "ChatGPT-Account-ID": tokens.account_id,
                "originator": "Codex Desktop", "OpenAI-Beta": "codex-1"]
    }
    public func read(accountKey: String, now: Date = .now) async throws -> BankedResetSnapshot {
        let authURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/auth.json")
        let headers = try Self.credentialHeaders(authData: Data(contentsOf: authURL), expectedAccountKey: accountKey)
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let session = URLSession(configuration: .ephemeral, delegate: BankedResetNoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw BankedResetError.invalidResponse }
        guard response.statusCode == 200 else { throw BankedResetError.http(response.statusCode) }
        guard response.url == request.url, data.count <= 1_000_000 else { throw BankedResetError.invalidResponse }
        return try BankedResetSnapshot.decode(data, accountKey: accountKey, now: now)
    }
}

private final class BankedResetNoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Conditional planning for the main allowance only: maintain the measured rate, redeem
/// the oldest card at exhaustion, and refresh to 100 rather than adding 100 on top.
public struct BankedResetPlan: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let card: BankedResetCard
        public let estimatedRedeemAt: Date?
        public let remainingAtExpiry: Double?
        public var id: String { card.id }
    }
    public let entries: [Entry]
    public static func evaluate(cards: [BankedResetCard], remaining: Double, rate: Double?,
                                normalReset: Date?, durationMinutes: Int?, globalReset: Date?, now: Date) -> Self {
        let ordered = cards.filter { $0.expiresAt > now }.sorted { $0.expiresAt < $1.expiresAt }
        guard let rate, rate.isFinite, rate >= 0 else {
            return Self(entries: ordered.map { Entry(card: $0, estimatedRedeemAt: nil, remainingAtExpiry: nil) })
        }
        var time = now, balance = remaining
        let duration = durationMinutes.map { TimeInterval($0) * 60 }
        var nextNormal = normalReset.flatMap { $0 > now ? $0 : nil }
        var nextGlobal = globalReset.flatMap { $0 > now ? $0 : nil }
        var entries: [Entry] = []
        for card in ordered {
            if time >= card.expiresAt {
                entries.append(Entry(card: card, estimatedRedeemAt: nil, remainingAtExpiry: balance))
                continue
            }
            while time < card.expiresAt {
                let exhaust = balance <= 0 ? time : rate > 0 ? time.addingTimeInterval(balance / rate * 3600) : Date.distantFuture
                let refresh = [nextNormal, nextGlobal].compactMap { $0 }.min() ?? Date.distantFuture
                if refresh <= exhaust && refresh < card.expiresAt {
                    balance = 100; time = refresh
                    if nextGlobal == refresh { nextGlobal = nil }
                    nextNormal = duration.flatMap { $0 > 0 ? refresh.addingTimeInterval($0) : nil }
                } else if exhaust < card.expiresAt {
                    entries.append(Entry(card: card, estimatedRedeemAt: exhaust, remainingAtExpiry: nil))
                    time = exhaust; balance = 100
                    nextNormal = duration.flatMap { $0 > 0 ? exhaust.addingTimeInterval($0) : nil }
                    break
                } else {
                    balance = max(0, balance - rate * card.expiresAt.timeIntervalSince(time) / 3600)
                    time = card.expiresAt
                    entries.append(Entry(card: card, estimatedRedeemAt: nil, remainingAtExpiry: balance))
                }
            }
        }
        return Self(entries: entries)
    }
}
