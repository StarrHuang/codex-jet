import AppKit
import SwiftUI
import ResetCore
@testable import ResetApp

@MainActor private final class FlightInput: ObservableObject {
    @Published var balance = 20.0
    @Published var rate = 0.0
    @Published var announced = false
    @Published var runway: DeadlinePace.RunwayLight = .green
}
private struct FlightProof: View {
    @ObservedObject var input: FlightInput
    var body: some View {
        PaperPlaneFlightView(remainingPercent: input.balance, ratePerHour: input.rate, announced: input.announced, runwayLight: input.runway)
            .frame(width: 520, height: 360).padding(20).background(ink.background)
            .environment(\.scenePhase, .active)
    }
}
@main struct FlightMotionProof {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "/tmp/roadster-motion-proof")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let input = FlightInput()
        let host = NSHostingView(rootView: FlightProof(input: input))
        host.frame = NSRect(x: 0, y: 0, width: 560, height: 400)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func capture(_ name: String, scanPlane: Bool = true) throws -> (Data, Int) {
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "FlightProof", code: 1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "FlightProof", code: 2) }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            if !scanPlane { return (png, 0) }
            var top = rep.pixelsHigh
            // Restrict to the vehicle area; the stationary bottle and labels remain outside.
            // The paper mesh is neutral and bright against the dark teal hangar.
            for y in stride(from: Int(Double(rep.pixelsHigh) * 0.16), to: rep.pixelsHigh * 4 / 5, by: 2) {
                for x in stride(from: rep.pixelsWide / 8, to: rep.pixelsWide * 2 / 3, by: 2) {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.45 && abs(color.redComponent - color.greenComponent) < 0.12
                        && abs(color.greenComponent - color.blueComponent) < 0.12 {
                        top = min(top, y)
                    }
                }
                if top < rep.pixelsHigh { break }
            }
            precondition(top < rep.pixelsHigh, "the 3D paper mesh must appear in the live view")
            return (png, top)
        }
        try await Task.sleep(for: .milliseconds(180))
        if CommandLine.arguments.contains("--reduce-motion") {
            input.rate = 20
            try await Task.sleep(for: .milliseconds(250))
            let first = try capture("reduced-first")
            try await Task.sleep(for: .milliseconds(450))
            let second = try capture("reduced-second")
            precondition(first.0 == second.0, "reduced motion must remain pixel-identical at positive measured rate")
            input.balance = 90
            try await Task.sleep(for: .milliseconds(150))
            let refill = try capture("reduced-refill")
            try await Task.sleep(for: .milliseconds(450))
            let still = try capture("reduced-still")
            precondition(refill.1 < first.1 && refill.0 == still.0, "reduced motion must jump to observed altitude without a maneuver")
            print("PASS: reduced motion remains static at positive rate and updates quota without flipping")
            return
        }
        let before = try capture("01-before-20")
        input.balance = 90
        try await Task.sleep(for: .milliseconds(450))
        let early = try capture("02-rising")
        try await Task.sleep(for: .milliseconds(700))
        let middle = try capture("03-mid-rise")
        try await Task.sleep(for: .milliseconds(1950))
        let settled = try capture("04-settled-90")
        try await Task.sleep(for: .milliseconds(450))
        let resting = try capture("05-resting-90")
        precondition(early.1 != before.1 && early.1 != settled.1, "takeoff must have an intermediate height")
        precondition(middle.1 != early.1, "takeoff must progress between frames")
        precondition(settled.1 < before.1, "more quota must raise the plane")
        precondition(settled.0 == resting.0, "zero-rate refill motion must settle instead of looping")
        input.balance = 25
        try await Task.sleep(for: .milliseconds(350))
        let descending = try capture("06-descending")
        try await Task.sleep(for: .milliseconds(650))
        let lower = try capture("07-lowered-25")
        precondition(descending.1 != settled.1 && descending.1 != lower.1, "consumption must descend through an intermediate height")
        precondition(lower.1 > settled.1, "less quota must lower the plane")
        print("PASS: live-view finite refill takeoff, interpolated descent, static zero-rate rest; paper plane Y=\(before.1),\(early.1),\(middle.1),\(settled.1),\(lower.1)")
        for light in [DeadlinePace.RunwayLight.green, .yellow, .red] {
            input.runway = light
            try await Task.sleep(for: .milliseconds(180))
            let frame = try capture("bottle-" + light.rawValue, scanPlane: false).0
            let pixels = NSBitmapImageRep(data: frame)!
            var colored = 0
            for y in (pixels.pixelsHigh * 47 / 100)..<(pixels.pixelsHigh * 79 / 100) {
                for x in (pixels.pixelsWide * 78 / 100)..<(pixels.pixelsWide * 90 / 100) {
                    let c = pixels.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
                    let matches: Bool
                    switch light {
                    case .red: matches = r > 0.55 && r > g * 1.4 && r > b * 1.4
                    case .green: matches = g > 0.55 && g > r * 1.15 && g > b * 1.1
                    case .yellow: matches = r > 0.65 && g > 0.50 && b < g * 0.80
                    case .unknown: matches = false
                    }
                    if matches { colored += 1 }
                }
            }
            precondition(colored > 5, "bottle gauge and lit segments must visibly display the selected runway light")
        }
        print("PASS: live bottle gauge and segments render all three runway colors")
        if ProcessInfo.processInfo.environment["CODEXRESET_FLIGHT_PREVIEW"] == "1" {
            input.balance = 0
            input.runway = .red
            input.rate = 12
            try await Task.sleep(for: .milliseconds(180))
            var frames: [(String, Date)] = []
            for index in 0..<195 {
                if index == 8 { input.announced = true }
                if index == 20 { input.balance = 100; input.announced = false; input.runway = .green }
                if index == 65 { input.rate = 2 }
                if index == 100 { input.rate = 20; input.runway = .yellow }
                if index == 140 { input.balance = 5; input.runway = .red }
                if index == 175 { input.balance = 0 }
                let name = String(format: "preview-%03d", index)
                _ = try capture(name, scanPlane: false)
                frames.append((name, Date()))
                try await Task.sleep(for: .milliseconds(45))
            }
            var manifest = "ffconcat version 1.0\n"
            for index in frames.indices {
                let duration = index + 1 < frames.count ? frames[index + 1].1.timeIntervalSince(frames[index].1) : 0.06
                manifest += "file '\(frames[index].0).png'\nduration \(duration)\n"
            }
            try manifest.write(to: directory.appendingPathComponent("preview.ffconcat"), atomically: true, encoding: .utf8)
        }
        print(directory.path)
    }
}
