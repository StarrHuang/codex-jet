import SwiftUI
import AppKit
import ResetCore

/// Compact native companion to the app icon: an open quota ring and clock hands.
struct QuotaLogo: View {
    var tint: Color = ink.accent
    var body: some View {
        QuotaBrandMark(tint: tint)
    }

    /// MenuBarExtra receives an actual image, so the same outline works in the native menu host.
    @MainActor static func statusImage(light: DeadlinePace.RunwayLight, colorScheme: ColorScheme = .dark) -> NSImage {
        // 浅色菜单使用较深的状态色，保持小图标的轮廓对比。
        let tint: Color = if light == .unknown { .black }
        else if colorScheme == .dark { light.color }
        else {
            switch light {
            case .green: Color(red: 0.10, green: 0.43, blue: 0.28)
            case .yellow: Color(red: 0.57, green: 0.34, blue: 0.02)
            case .red: Color(red: 0.77, green: 0.12, blue: 0.16)
            case .unknown: .black
            }
        }
        let renderer = ImageRenderer(content: QuotaLogo(tint: tint)
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
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Label {
            Text(model.menuBarTitle).font(.system(size: 11)).monospacedDigit()
        } icon: {
            Image(nsImage: QuotaLogo.statusImage(light: model.menuRunwayLight, colorScheme: colorScheme))
                .renderingMode(model.menuRunwayLight == .unknown ? .template : .original)
        }
        .labelStyle(.titleAndIcon)
        .help("Codex Jet\n" + model.menuBarHelp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex Jet, " + model.menuBarHelp)
    }
}
