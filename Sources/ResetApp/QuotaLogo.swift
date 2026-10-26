import SwiftUI
import AppKit
import ResetCore

/// Compact native companion to the app icon: an open quota ring and clock hands.
struct QuotaLogo: View {
    var tint: Color = ink.accent
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().trim(from: 0.12, to: 1)
                    .stroke(tint, style: StrokeStyle(lineWidth: side * 0.11, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(side * 0.09)
                Path { path in
                    path.move(to: CGPoint(x: side * 0.32, y: side * 0.36))
                    path.addLine(to: CGPoint(x: side * 0.5, y: side * 0.5))
                    path.addLine(to: CGPoint(x: side * 0.70, y: side * 0.30))
                }
                .stroke(tint, style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round, lineJoin: .round))
                Circle().fill(tint).frame(width: side * 0.105, height: side * 0.105)
            }.frame(width: side, height: side)
        }.accessibilityHidden(true)
    }

    /// MenuBarExtra receives an actual image, so the same outline works in the native menu host.
    @MainActor static func statusImage(light: DeadlinePace.RunwayLight) -> NSImage {
        let renderer = ImageRenderer(content: QuotaLogo(tint: light == .unknown ? .black.opacity(0.55) : light.color)
            .frame(width: 15, height: 15))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage!
        image.isTemplate = light == .unknown
        image.accessibilityDescription = "Codex Jet"
        return image
    }
}

struct QuotaMenuLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Label {
            Text(model.menuBarTitle).font(.system(size: 11)).monospacedDigit()
        } icon: {
            Image(nsImage: QuotaLogo.statusImage(light: model.menuRunwayLight))
                .renderingMode(model.menuRunwayLight == .unknown ? .template : .original)
        }
        .labelStyle(.titleAndIcon)
        .help("Codex Jet\n" + model.menuBarHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex Jet, " + model.menuBarHelp)
    }
}
