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
    var width: CGFloat = 560
    var height: CGFloat = 160
    var body: some View {
        QuotaFlowView(remainingPercent: input.balance, ratePerHour: input.rate, stale: input.stale,
            announced: input.announced, animated: input.animated, runwayLight: input.light)
            .frame(width: width, height: height).background(ink.background)
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

        func isRunway(_ color: NSColor) -> Bool {
            let c = color.usingColorSpace(.deviceRGB)!
            let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
            switch input.light {
            case .green: return g > 0.60 && g > r * 1.18 && g > b * 1.10
            case .red: return r > 0.60 && r > g * 1.45 && r > b * 1.45
            case .yellow: return r > 0.70 && g > 0.48 && b < g * 0.72
            case .unknown: return false
            }
        }
        func isAnnouncement(_ color: NSColor) -> Bool {
            let c = color.usingColorSpace(.deviceRGB)!
            let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
            return r > 0.72 && g > 0.30 && g < 0.78 && b < 0.42 && r > g * 1.12
        }
        func capture(_ name: String) throws -> (png: Data, arcDegrees: Int, rimDegrees: Int) {
            host.layoutSubtreeIfNeeded()
            let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: rep)
            let png = rep.representation(using: .png, properties: [:])!
            try png.write(to: output.appendingPathComponent(name + ".png"))

            // The proof host is fixed at 560x160; the dial fills 152pt and sits at (76, 80).
            // Probe along the colored ring center, with a small radial tolerance for antialiasing.
            let centerX = rep.pixelsWide * 76 / 560
            let centerY = rep.pixelsHigh * 80 / 160
            let pixelScale = Double(min(rep.pixelsWide / 560, rep.pixelsHigh / 160))
            let quotaRadius = pixelScale * 65.2
            let announcementRadius = pixelScale * 72.0
            func coverage(_ matcher: (NSColor) -> Bool, radius: Double) -> Int {
                var count = 0
                for degree in 0..<360 {
                    let angle = Double(degree) * .pi / 180 - .pi / 2
                    var hit = false
                    for radialOffset in -2...2 {
                        let r = radius + Double(radialOffset)
                        let x = centerX + Int((cos(angle) * r).rounded())
                        let y = centerY + Int((sin(angle) * r).rounded())
                        if x >= 0, x < rep.pixelsWide, y >= 0, y < rep.pixelsHigh,
                           matcher(rep.colorAt(x: x, y: y)!) { hit = true; break }
                    }
                    if hit { count += 1 }
                }
                return count
            }
            return (png, coverage(isRunway, radius: quotaRadius), coverage(isAnnouncement, radius: announcementRadius))
        }

        try await Task.sleep(for: .milliseconds(150))
        let twenty = try capture("01-quota-20")
        if CommandLine.arguments.contains("--reduce-motion") {
            input.balance = 90
            try await Task.sleep(for: .milliseconds(120))
            let first = try capture("reduced-first")
            try await Task.sleep(for: .milliseconds(250))
            let still = try capture("reduced-still")
            precondition(first.png == still.png && first.arcDegrees > twenty.arcDegrees * 3,
                         "Reduce Motion applies observed balance immediately with no hand loop")
            input.announced = true
            try await Task.sleep(for: .milliseconds(100))
            let announcement = try capture("reduced-announcement")
            try await Task.sleep(for: .milliseconds(250))
            let announcementStill = try capture("reduced-announcement-still")
            precondition(announcement.png == announcementStill.png && announcement.rimDegrees > 0,
                         "Reduce Motion keeps the announcement rim static")
            print("PASS: Reduce Motion applies quota immediately and keeps the hand and announcement static")
            print(output.path)
            return
        }
        input.balance = 90
        try await Task.sleep(for: .milliseconds(150))
        let growing = try capture("02-refilling")
        try await Task.sleep(for: .milliseconds(500))
        let ninety = try capture("03-quota-90")
        try await Task.sleep(for: .milliseconds(180))
        let resting = try capture("04-resting")
        precondition(growing.arcDegrees > twenty.arcDegrees && growing.arcDegrees < ninety.arcDegrees,
                     "a real refill must smoothly interpolate the observed angular arc")
        precondition(abs(Double(ninety.arcDegrees) / Double(twenty.arcDegrees) - 4.5) < 0.3,
                     "colored angular coverage must track 90 versus 20 percent")
        precondition(ninety.png == resting.png, "zero measured pace rests at a static hand")

        input.announced = true
        try await Task.sleep(for: .milliseconds(900))
        let announcedNinety = try capture("quota-90-with-announcement")
        precondition(abs(announcedNinety.arcDegrees - ninety.arcDegrees) <= 2 && announcedNinety.rimDegrees > 330,
                     "the outer announcement rim stays distinct while the positive quota arc remains measurable")
        input.announced = false
        try await Task.sleep(for: .milliseconds(100))
        let unannouncedNinety = try capture("quota-90-after-announcement")
        precondition(unannouncedNinety.arcDegrees == announcedNinety.arcDegrees,
                     "removing the announcement rim does not change observed quota coverage")

        input.balance = 25
        try await Task.sleep(for: .milliseconds(160))
        let falling = try capture("05-consuming")
        try await Task.sleep(for: .milliseconds(500))
        let twentyFive = try capture("06-quota-25")
        precondition(falling.arcDegrees < ninety.arcDegrees && falling.arcDegrees > twentyFive.arcDegrees,
                     "consumption interpolates only after a new observed balance")

        input.rate = 60
        try await Task.sleep(for: .milliseconds(150))
        let handFirst = try capture("07-hand-moving")
        try await Task.sleep(for: .milliseconds(350))
        let handNext = try capture("08-hand-moving-next")
        precondition(handFirst.png != handNext.png && abs(handFirst.arcDegrees - handNext.arcDegrees) <= 2,
                     "positive measured pace moves the hand while the observed arc stays fixed")

        input.phase = .inactive
        try await Task.sleep(for: .milliseconds(80))
        let inactive = try capture("inactive")
        try await Task.sleep(for: .milliseconds(180))
        let inactiveNext = try capture("inactive-next")
        precondition(inactive.png == inactiveNext.png, "inactive views stop hand motion")
        input.phase = .active
        input.rate = 0
        input.balance = 0
        try await Task.sleep(for: .milliseconds(550))
        let empty = try capture("empty")
        precondition(empty.arcDegrees <= 3, "zero quota has no colored arc")
        input.balance = nil
        input.rate = 60
        try await Task.sleep(for: .milliseconds(100))
        let unknown = try capture("unknown")
        try await Task.sleep(for: .milliseconds(180))
        let unknownNext = try capture("unknown-next")
        precondition(unknown.arcDegrees == 0 && unknown.png == unknownNext.png,
                     "unknown quota is gray with no implied arc or hand movement")
        input.balance = 60
        input.stale = true
        try await Task.sleep(for: .milliseconds(100))
        let stale = try capture("stale")
        try await Task.sleep(for: .milliseconds(180))
        let staleNext = try capture("stale-next")
        precondition(stale.arcDegrees == 0 && stale.png == staleNext.png,
                     "stale quota is gray with no implied arc or hand movement")

        input.stale = false
        input.balance = 0
        input.rate = 0
        input.light = .red
        try await Task.sleep(for: .milliseconds(550))
        let zeroBeforeNotice = try capture("zero-before-notice")
        input.announced = true
        try await Task.sleep(for: .milliseconds(150))
        let rimSweep = try capture("announcement-sweep")
        try await Task.sleep(for: .milliseconds(850))
        let rimSettled = try capture("announcement-settled")
        try await Task.sleep(for: .milliseconds(180))
        let rimRest = try capture("announcement-rest")
        precondition(rimSweep.rimDegrees > 0 && rimSweep.rimDegrees < rimSettled.rimDegrees,
                     "announcement rim sweeps once over about 0.8 seconds")
        precondition(rimSettled.png == rimRest.png && rimSettled.arcDegrees == zeroBeforeNotice.arcDegrees,
                     "announcement settles to a static rim without refilling quota")
        input.phase = .inactive
        try await Task.sleep(for: .milliseconds(60))
        input.phase = .active
        try await Task.sleep(for: .milliseconds(120))
        let resumed = try capture("announcement-resumed")
        precondition(resumed.png == rimSettled.png, "reactivating the app does not replay the same announcement")
        input.announced = false
        input.balance = 60
        input.rate = 60
        input.animated = false
        try await Task.sleep(for: .milliseconds(180))
        let reducedFirst = try capture("reduced-first")
        try await Task.sleep(for: .milliseconds(200))
        let reducedStill = try capture("reduced-still")
        precondition(reducedFirst.png == reducedStill.png,
                     "disabled animation shows the observed balance immediately and stops the hand")
        host.rootView = MeterProof(input: input, width: 108, height: 82)
        host.frame = NSRect(x: 0, y: 0, width: 108, height: 82)
        window.setContentSize(host.frame.size)
        host.layoutSubtreeIfNeeded()
        let compactRep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: compactRep)
        try compactRep.representation(using: .png, properties: [:])!
            .write(to: output.appendingPathComponent("compact-108x82.png"))
        print("PASS: angular balance interpolation, measured-pace hand, paused/unknown/stale/zero states, and one-time announcement rim")
        print(output.path)
    }
}
