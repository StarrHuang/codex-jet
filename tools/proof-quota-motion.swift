import AppKit
import SwiftUI
import ResetCore
@testable import ResetApp

@MainActor private final class MeterInput: ObservableObject {
    @Published var balance: Double? = 20
    @Published var rate: Double? = 0
    @Published var stale = false
    @Published var announced = false
    @Published var animated = true
    @Published var phase: ScenePhase = .active
    @Published var light: DeadlinePace.RunwayLight = .green
}
private struct MeterProof: View {
    @ObservedObject var input: MeterInput
    var body: some View {
        QuotaFlowView(remainingPercent: input.balance, ratePerHour: input.rate, stale: input.stale,
            announced: input.announced, animated: input.animated, runwayLight: input.light)
            .frame(width: 520, height: 120).padding(20).background(ink.background)
            .environment(\.scenePhase, input.phase).preferredColorScheme(.dark)
    }
}
@main struct QuotaMotionProof {
    @MainActor static func main() async throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/quota-flow-proof")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        NSApplication.shared.setActivationPolicy(.prohibited)
        let input = MeterInput()
        let host = NSHostingView(rootView: MeterProof(input: input))
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 160)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func capture(_ name: String, measure: Bool = true) throws -> (png: Data, width: Int) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent(name + ".png"))
            guard measure else { return (png, 0) }
            var maximum = 0
            // Read the bar band, excluding the large percent and its exhausted color.
            for y in (rep.pixelsHigh * 39 / 100)..<(rep.pixelsHigh / 2) {
                var first: Int?, last: Int?
                for x in (rep.pixelsWide / 30)..<(rep.pixelsWide * 29 / 30) {
                    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                    let matches: Bool
                    switch input.light {
                    case .green: matches = g > 0.55 && g > r * 1.15 && g > b * 1.10
                    case .red: matches = r > 0.55 && r > g * 1.4 && r > b * 1.4
                    case .yellow: matches = r > 0.65 && g > 0.5 && b < g * 0.8
                    case .unknown: matches = false
                    }
                    if matches { if first == nil { first = x }; last = x }
                }
                if let first, let last { maximum = max(maximum, last - first + 1) }
            }
            return (png, maximum)
        }
        try await Task.sleep(for: .milliseconds(200))
        let before = try capture("01-quota-20")
        if CommandLine.arguments.contains("--reduce-motion") {
            input.rate = 20
            input.balance = 90
            try await Task.sleep(for: .milliseconds(120))
            let first = try capture("reduced-first")
            try await Task.sleep(for: .milliseconds(300))
            let still = try capture("reduced-still")
            precondition(first.png == still.png && first.width > before.width * 3,
                         "Reduce Motion updates quota immediately and never loops at positive pace")
            input.announced = true
            try await Task.sleep(for: .milliseconds(100))
            let announcement = try capture("reduced-announcement", measure: false)
            try await Task.sleep(for: .milliseconds(250))
            let announcementStill = try capture("reduced-announcement-still", measure: false)
            precondition(announcement.png == announcementStill.png, "Reduce Motion keeps a static announcement outline")
            print("PASS: Reduce Motion displays quota and announcement immediately with no loops")
            return
        }
        input.balance = 90
        try await Task.sleep(for: .milliseconds(200))
        let growing = try capture("02-refilling")
        try await Task.sleep(for: .milliseconds(500))
        let full = try capture("03-quota-90")
        try await Task.sleep(for: .milliseconds(200))
        let resting = try capture("04-resting")
        precondition(growing.width > before.width && growing.width < full.width,
                     "a real refill must visibly interpolate the quota bar width")
        precondition(full.png == resting.png, "zero measured pace is static after refill")
        precondition(abs(Double(full.width) / Double(before.width) - 4.5) < 0.10,
                     "fill length must track 90 versus 20 percent")
        input.balance = 25
        try await Task.sleep(for: .milliseconds(160))
        let falling = try capture("05-consuming")
        try await Task.sleep(for: .milliseconds(500))
        let lower = try capture("06-quota-25")
        precondition(falling.width < full.width && falling.width > lower.width, "consumption interpolates only after new observations")
        input.rate = 20
        try await Task.sleep(for: .milliseconds(150))
        let flowing = try capture("07-flowing")
        try await Task.sleep(for: .milliseconds(250))
        let flowNext = try capture("08-flowing-next")
        precondition(flowing.png != flowNext.png && abs(flowing.width - flowNext.width) <= 3,
                     "a positive measured pace moves the tick without silently consuming displayed quota")
        input.phase = .inactive
        try await Task.sleep(for: .milliseconds(100))
        let inactive = try capture("inactive")
        try await Task.sleep(for: .milliseconds(200))
        let inactiveNext = try capture("inactive-next")
        precondition(inactive.png == inactiveNext.png, "inactive views stop motion")
        input.phase = .active
        input.balance = nil
        try await Task.sleep(for: .milliseconds(100))
        let unknown = try capture("unknown")
        try await Task.sleep(for: .milliseconds(200))
        let unknownNext = try capture("unknown-next")
        precondition(unknown.width == 0 && unknown.png == unknownNext.png, "unknown quota has no colored fill or flow")
        input.balance = 60
        input.stale = true
        try await Task.sleep(for: .milliseconds(100))
        let stale = try capture("stale")
        try await Task.sleep(for: .milliseconds(200))
        let staleNext = try capture("stale-next")
        precondition(stale.width == 0 && stale.png == staleNext.png, "stale readings cannot imply current quota or pace")
        input.stale = false
        input.balance = 0
        input.rate = 0
        input.light = .red
        try await Task.sleep(for: .milliseconds(600))
        let empty = try capture("empty")
        input.announced = true
        try await Task.sleep(for: .milliseconds(150))
        let entering = try capture("announcement-enter", measure: false)
        try await Task.sleep(for: .milliseconds(900))
        let announced = try capture("announcement-settled", measure: false)
        try await Task.sleep(for: .milliseconds(200))
        let announcedRest = try capture("announcement-rest", measure: false)
        precondition(entering.png != announced.png && announced.png == announcedRest.png,
                     "an announcement sweeps once at zero quota, then stays visible and static")
        precondition(empty.width <= 20, "an announcement never refills the quota bar")
        input.phase = .inactive
        try await Task.sleep(for: .milliseconds(60))
        input.phase = .active
        try await Task.sleep(for: .milliseconds(120))
        let resumed = try capture("announcement-resumed", measure: false)
        precondition(resumed.png == announced.png, "reactivating the app does not replay the same announcement")
        input.announced = false
        print("PASS: observed quota fill interpolation, rate tick at stable fill, unknown/stale/inactive pause, finite announcement without false refill or replay")
        if ProcessInfo.processInfo.environment["CODEXRESET_FLOW_PREVIEW"] == "1" {
            var frames: [(String, Date)] = []
            for index in 0..<150 {
                if index == 8 { input.announced = true }
                if index == 40 { input.balance = 100; input.announced = false; input.light = .green; input.rate = 2 }
                if index == 80 { input.rate = 20; input.light = .yellow }
                if index == 110 { input.balance = 20; input.light = .red }
                if index == 140 { input.balance = 0 }
                let name = String(format: "preview-%03d", index)
                _ = try capture(name, measure: false)
                frames.append((name, Date()))
                try await Task.sleep(for: .milliseconds(50))
            }
            var manifest = "ffconcat version 1.0\n"
            for i in frames.indices {
                let duration = i + 1 < frames.count ? frames[i + 1].1.timeIntervalSince(frames[i].1) : 0.06
                manifest += "file '\(frames[i].0).png'\nduration \(duration)\n"
            }
            try manifest.write(to: output.appendingPathComponent("preview.ffconcat"), atomically: true, encoding: .utf8)
        }
        print(output.path)
    }
}
