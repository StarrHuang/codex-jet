import AppKit
import SwiftUI
import ResetCore
@testable import ResetApp

@MainActor private final class FlightInput: ObservableObject {
    @Published var balance = 20.0
    @Published var rate = 0.0
    @Published var announced = false
}
private struct FlightProof: View {
    @ObservedObject var input: FlightInput
    var body: some View {
        RoadsterFlightView(remainingPercent: input.balance, ratePerHour: input.rate, announced: input.announced)
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
        func capture(_ name: String, scanCar: Bool = true) throws -> (Data, Int) {
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "FlightProof", code: 1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw NSError(domain: "FlightProof", code: 2) }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            if !scanCar { return (png, 0) }
            var top = rep.pixelsHigh
            for y in 0..<rep.pixelsHigh {
                for x in 0..<rep.pixelsWide {
                    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.redComponent > 0.25 && color.redComponent > color.greenComponent * 1.6
                        && color.redComponent > color.blueComponent * 1.4 {
                        top = min(top, y)
                    }
                }
            }
            precondition(top < rep.pixelsHigh, "car asset must render from the packaged resource")
            return (png, top)
        }
        try await Task.sleep(for: .milliseconds(180))
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
        precondition(settled.1 < before.1, "more quota must raise the car")
        precondition(settled.0 == resting.0, "zero-rate refill motion must settle instead of looping")
        input.balance = 25
        try await Task.sleep(for: .milliseconds(350))
        let descending = try capture("06-descending")
        try await Task.sleep(for: .milliseconds(650))
        let lower = try capture("07-lowered-25")
        precondition(descending.1 != settled.1 && descending.1 != lower.1, "consumption must descend through an intermediate height")
        precondition(lower.1 > settled.1, "less quota must lower the car")
        print("PASS: live-view finite refill takeoff, interpolated descent, static zero-rate rest; red car Y=\(before.1),\(early.1),\(middle.1),\(settled.1),\(lower.1)")
        if ProcessInfo.processInfo.environment["CODEXRESET_FLIGHT_PREVIEW"] == "1" {
            input.balance = 0
            input.rate = 12
            try await Task.sleep(for: .milliseconds(180))
            var frames: [(String, Date)] = []
            for index in 0..<195 {
                if index == 8 { input.announced = true }
                if index == 20 { input.balance = 100; input.announced = false }
                if index == 65 { input.rate = 2 }
                if index == 100 { input.rate = 20 }
                if index == 140 { input.balance = 5 }
                if index == 175 { input.balance = 0 }
                let name = String(format: "preview-%03d", index)
                _ = try capture(name, scanCar: false)
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
