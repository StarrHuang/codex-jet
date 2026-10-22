import Foundation
import CryptoKit
import ResetCore

@main struct BankedChecks {
    static func main() async throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        func card(_ id: String, _ hours: Double) -> BankedResetCard {
            BankedResetCard(id: id, grantedAt: now.addingTimeInterval(-86400), expiresAt: now.addingTimeInterval(hours * 3600))
        }
        func plan(_ cards: [BankedResetCard], remaining: Double = 20, rate: Double? = 10,
                  normal: Date? = nil, global: Date? = nil) -> BankedResetPlan {
            BankedResetPlan.evaluate(cards: cards, remaining: remaining, rate: rate, normalReset: normal,
                durationMinutes: 10080, globalReset: global, now: now)
        }
        let cards = [card("second", 15), card("first", 3)]
        let plain = plan(cards)
        check(plain.entries.map(\.id) == ["first", "second"], "oldest expiry first")
        check(plain.entries[0].estimatedRedeemAt == now.addingTimeInterval(7200), "current remaining consumed before redeeming")
        check(plain.entries[1].estimatedRedeemAt == now.addingTimeInterval(43200), "one reset restores 100, not additive bank balance")
        let arrival = plan(cards, global: now.addingTimeInterval(10800))
        check(arrival.entries[1].estimatedRedeemAt == now.addingTimeInterval(46800), "global refresh overwrites balance and is not banked")
        let normal = plan([card("first", 3)], normal: now.addingTimeInterval(3600))
        check(normal.entries[0].estimatedRedeemAt == nil && normal.entries[0].remainingAtExpiry == 80,
              "natural refresh before expiry can make depletion-first redemption too late")
        let reanchor = plan([card("first", 3),card("second",15)], normal: now.addingTimeInterval(10800))
        check(reanchor.entries[1].estimatedRedeemAt == now.addingTimeInterval(43200), "card use replaces previous weekly reset schedule")
        let same = plan([card("a",3),card("b",3)], rate: 0)
        check(same.entries.count == 2 && same.entries.allSatisfy { $0.remainingAtExpiry == 20 }, "equal expiries and zero speed keep all cards")
        check(plan(cards, rate: nil).entries.allSatisfy { $0.estimatedRedeemAt == nil && $0.remainingAtExpiry == nil }, "unknown speed is not treated as zero")
        check(plan([card("expired",-1)]).entries.isEmpty, "expired cards excluded")
        let iso = ISO8601DateFormatter()
        func item(_ id: String, status: String = "available", supported: Bool = true, expires: Double = 3600) -> [String: Any] {
            ["id": id, "status":status,"is_supported_by_plan":supported,"reset_type":"codex_rate_limits",
             "granted_at":iso.string(from: now.addingTimeInterval(-3600)),"expires_at":iso.string(from: now.addingTimeInterval(expires))]
        }
        let json = try JSONSerialization.data(withJSONObject: ["available_count":3,"credits":[item("private-id"),item("used",status:"redeemed"),item("other-plan",supported:false),item("expired",expires:-1)]])
        let decoded = try BankedResetSnapshot.decode(json, accountKey:"account-a", now:now)
        check(decoded.cards.count == 1 && decoded.cards[0].id != "private-id", "only supported unexpired available cards retained with hashed identifiers")
        var invalid = item("bad"); invalid["expires_at"] = "tomorrow"
        do { _ = try BankedResetSnapshot.decode(JSONSerialization.data(withJSONObject:["available_count":1,"credits":[invalid]]),accountKey:"a",now:now); check(false,"invalid expiry rejected") }
        catch { }
        let claim = try JSONSerialization.data(withJSONObject:["email":"fixture@example.invalid"]).base64EncodedString().replacingOccurrences(of:"=",with:"")
        let auth = try JSONSerialization.data(withJSONObject:["tokens":["access_token":"dummy","id_token":"header."+claim+".signature","account_id":"dummy-account"]])
        let key = SHA256.hash(data:Data("chatgpt:fixture@example.invalid".utf8)).map { String(format:"%02x",$0) }.joined()
        let headers = try BankedResetReader.credentialHeaders(authData:auth, expectedAccountKey:key)
        check(headers["Authorization"] == "Bearer dummy", "same account may use its existing credential")
        do { _ = try BankedResetReader.credentialHeaders(authData:auth,expectedAccountKey:"other-account");check(false,"cross-account credential use rejected") }
        catch BankedResetError.accountMismatch { }
        print("PASS: banked expiry parsing, account binding, chronological redemption, non-stacking global/natural reset scenarios and unknown speed")
    }
}
