import Foundation
import AppKit
import SwiftUI
import ResetCore
@testable import ResetApp

@main struct MenuChecks {
    @MainActor static func main() throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let model = AppModel()
        model.now = now
        func set(_ rate: Double, age: Double = 0, used: Double = 60, hours: Double = 4) {
            let window = QuotaWindow(id: "codex:primary", bucketID: "codex", label: "Codex",
                                     usedPercent: used, durationMinutes: 10080, resetsAt: now.addingTimeInterval(hours * 3600))
            model.snapshot = QuotaSnapshot(sampledAt: now.addingTimeInterval(-age), accountKey: "menu-fixture", plan: nil, windows: [window])
            model.history = [-1800.0, -900, 0].map { offset in
                QuotaSnapshot(sampledAt: now.addingTimeInterval(offset), accountKey: "menu-fixture", plan: nil,
                    windows: [QuotaWindow(id: window.id, bucketID: window.bucketID, label: window.label,
                        usedPercent: used + offset / 3600 * rate, durationMinutes: window.durationMinutes, resetsAt: window.resetsAt)])
            }
        }
        check(model.menuBarTitle == "—%", "no account does not invent quota")
        set(2)
        check(model.menuBarTitle == "40% 4.0h" && model.menuRunwayLight == .green, "native logo carries state; text contains only quota and nearest countdown")
        set(20)
        check(model.menuBarTitle == "40% 4.0h" && model.menuRunwayLight == .red, "fast consumption uses a red native logo")
        set(10)
        check(model.menuBarTitle == "40% 4.0h" && model.menuRunwayLight == .yellow, "on-track native logo is yellow")
        set(0)
        check(model.menuBarTitle == "40% 4.0h", "zero speed does not fabricate finite multiplier")
        set(2, age: 601)
        check(model.menuBarTitle == "—%" && model.menuRunwayLight == .unknown, "stale current balance and native logo are unknown")
        check(!model.menuBarHelp.contains("* 表示过期") && model.menuBarHelp.contains("状态栏暂不显示当前额度"), "stale tooltip matches the unknown current-quota label")
        set(2)
        model.history = [model.snapshot!]
        check(model.menuBarTitle == "40% 4.0h", "insufficient samples are not zero usage")
        set(9.9)
        check(model.menuBarTitle == "40% 4.0h", "near target use is yellow even if a small remainder is projected")
        set(0.02)
        check(model.menuBarTitle == "40% 4.0h", "large multiplier is bounded without scientific notation")
        set(60, used: 98)
        check(model.menuBarTitle == "2% 4.0h", "tiny multiplier stays explicit")
        set(20, hours: 2)
        let iso = ISO8601DateFormatter()
        let forecast = try JSONDecoder().decode(RadarForecast.self, from: JSONSerialization.data(withJSONObject:[
            "updated_at":iso.string(from:now), "probabilities":[:],
            "official_signal":["at":iso.string(from:now.addingTimeInterval(-60)),"summary":"reset in four hours",
                "url":"https://x.com/thsottiaux/status/fixture",
                "window":["label":"in four hours","end_at":iso.string(from:now.addingTimeInterval(14400))]]]))
        let timeline = try JSONDecoder().decode(RadarTimeline.self, from: Data(#"{"updated_at":"now","events":[]}"#.utf8))
        model.radar = RadarData(forecast:forecast,timeline:timeline,fetchedAt:now)
        check(model.menuBarTitle == "40% 2.0h", "earlier normal reset wins even during temporary announcement")
        check(model.menuBarHelp.contains("正常订阅重置") && model.menuBarHelp.contains("实测 20.00 → 目标 20.00"), "tooltip explains target and actual rate units")
        model.radar = nil
        model.bankedResets = BankedResetSnapshot(sampledAt: now, accountKey: "menu-fixture", cards: [
            BankedResetCard(id: "soon", grantedAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(5.5 * 3600)),
            BankedResetCard(id: "later", grantedAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(8 * 3600))
        ])
        set(2, hours: 8)
        check(model.menuDeadline == now.addingTimeInterval(5.5 * 3600), "earliest unexpired same-account banked card is a countdown target")
        check(model.menuBarTitle == "40% 5.5h", "card expiry countdown matches the projection and suggested multiplier deadline")
        check(model.menuBarHelp.contains("储备卡到期") && model.menuBarHelp.contains("需手动兑换") && model.menuBarHelp.contains("不会自动回补"), "card countdown explains manual redemption and no automatic refill")
        model.now = now.addingTimeInterval(340)
        check(model.menuBarTitle.hasSuffix(" 5.4h"), "countdown advances using the injected app clock")
        model.now = now
        model.radar = RadarData(forecast:forecast,timeline:timeline,fetchedAt:now)
        model.bankedResets = BankedResetSnapshot(sampledAt: now, accountKey: "menu-fixture", cards: [
            BankedResetCard(id: "card", grantedAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(2 * 3600))
        ])
        set(2, hours: 3)
        check(model.menuDeadline == now.addingTimeInterval(2 * 3600), "banked card wins when earlier than temporary and weekly resets")
        check(model.menuBarHelp.contains("储备卡到期"), "selected card source is explained")
        model.bankedResets = BankedResetSnapshot(sampledAt: now, accountKey: "another-account", cards: [
            BankedResetCard(id: "card", grantedAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(1 * 3600))
        ])
        set(2, hours: 6)
        check(model.menuDeadline == now.addingTimeInterval(14400), "mismatched-account card is excluded and temporary reset wins")
        check(model.menuBarHelp.contains("官方窗口目标"), "temporary reset source is explained")
        model.bankedResets = BankedResetSnapshot(sampledAt: now.addingTimeInterval(-601), accountKey: "menu-fixture", cards: [
            BankedResetCard(id: "card", grantedAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(1 * 3600))
        ])
        check(model.menuDeadline == now.addingTimeInterval(14400), "stale card snapshot is excluded")
        model.bankedResets = BankedResetSnapshot(sampledAt: now, accountKey: "menu-fixture", cards: [
            BankedResetCard(id: "card", grantedAt: now.addingTimeInterval(-3600), expiresAt: now.addingTimeInterval(1 * 3600))
        ])
        model.bankedError = "fixture read failure"
        check(model.menuDeadline == now.addingTimeInterval(14400), "card read error excludes otherwise matching cards")
        model.bankedError = nil
        model.radar = nil
        model.snapshot = QuotaSnapshot(sampledAt: now, accountKey: "menu-fixture", plan: nil, windows: [
            QuotaWindow(id: "codex:primary", bucketID: "codex", label: "Codex", usedPercent: 60,
                        durationMinutes: 10080, resetsAt: now.addingTimeInterval(-1))
        ])
        model.bankedResets = BankedResetSnapshot(sampledAt: now, accountKey: "menu-fixture", cards: [
            BankedResetCard(id: "expired", grantedAt: now.addingTimeInterval(-7200), expiresAt: now.addingTimeInterval(-1))
        ])
        check(model.menuDeadline == nil && !model.menuBarTitle.contains("h"), "past, expired, and absent targets do not fabricate a future countdown")
        set(2, hours: 0.04)
        check(model.menuBarTitle.hasSuffix(" <0.1h"), "a positive countdown below three minutes is not rounded down to 0.0h")
        set(0, used: 100)
        check(model.menuRunwayLight == .red && model.menuBarTitle == "0% 4.0h", "exhaustion is red even at zero measured rate")
        set(8.9)
        check(model.menuRunwayLight == .green, "buffer beyond the 10-percent boundary is green")
        set(9.1)
        check(model.menuRunwayLight == .yellow, "near depletion boundary is yellow")
        set(10.9)
        check(model.menuRunwayLight == .yellow, "small uncertainty around target stays yellow")
        set(11.1)
        check(model.menuRunwayLight == .red, "rate above target plus 10-percent is red")
        set(0.1, hours: 48)
        check(model.menuBarTitle.hasSuffix(" 48.0h"), "48 hours exactly remains hours")
        set(0.1, hours: 48.001)
        check(model.menuBarTitle.hasSuffix(" 2.0天"), "strictly more than 48 hours switches to days")
        set(0.1, hours: 60)
        check(model.menuBarTitle == "40% 2.5天", "60 hours is 2.5 days")
        check(!model.menuBarTitle.contains("→") && !model.menuBarTitle.contains("×"), "no forecast arrow or multiplier in status bar")
        let promise = try JSONDecoder().decode(RadarForecast.self, from: JSONSerialization.data(withJSONObject: [
            "updated_at":iso.string(from:now), "probabilities":[:],
            "official_signal":["at":iso.string(from:now.addingTimeInterval(-60)), "tweet_id":"promise",
                "signal_type":"promise", "summary":"reset soon", "url":"https://x.com/thsottiaux/status/promise"]]))
        model.radar = RadarData(forecast:promise, timeline:timeline, fetchedAt:now,
            observation: RadarObservation(eventID:"promise", deadline:now.addingTimeInterval(3600),
                sourceURL:URL(string:"https://codex-reset.com/zh/")!))
        check(model.extraResetAdvice.state == .observation, "fixture has a site observation rather than a timed official announcement")
        check(model.menuDeadline == now.addingTimeInterval(60 * 3600), "site observation window is not an official reset countdown")
        model.radar = nil
        set(0.001, hours: 168)
        let font = NSFont.monospacedDigitSystemFont(ofSize:11, weight:.regular)
        let textWidth = (model.menuBarTitle as NSString).size(withAttributes:[.font:font]).width
        let width = NSHostingView(rootView: QuotaMenuLabel(model: model).fixedSize()).fittingSize.width
        check(width > textWidth + 10, "native status label includes a visible logo beside its text")
        check(width < 110, "normal status label remains compact")
        check(model.menuBarTitle == "40% 7.0天", "long countdown uses days and omits projection/multiplier")
        check(width <= 110, "long-deadline high-multiplier status label fits the width target")
        for light in [DeadlinePace.RunwayLight.green, .yellow, .red, .unknown] {
            let image = QuotaLogo.statusImage(light: light)
            check(image.size.width == 15 && image.size.height == 15, "status logo retains its compact logical size")
            check(image.isTemplate == (light == .unknown), "unknown logo adapts to native menu appearance")
            let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
            var visible = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    if bitmap.colorAt(x: x, y: y)!.alphaComponent > 0.4 { visible += 1 }
                }
            }
            check(visible > 30, "native logo contains rendered artwork, not a blank image")
        }
        print("PASS: native logo, compact quota/day countdown, source ordering and freshness; full label ‘\(model.menuBarTitle)’ is \(Int(width))pt")
    }
}
