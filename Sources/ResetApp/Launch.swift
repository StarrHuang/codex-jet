import SwiftUI
import AppKit
import ResetCore

struct ResetDesktopApp: App {
    @StateObject private var model = AppModel()
    @AppStorage("appLanguage") private var language = "system"
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup("Codex Jet", id: "dashboard") {
            Dashboard(model: model).id(language)
                .task {
                    let appModel = model
                    let showWindow = openWindow
                    model.reminders.openDashboard = { [weak appModel] in
                        appModel?.page = "dashboard"
                        showWindow(id: "dashboard")
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    model.startMonitoring()
                }
                .onChange(of: language) { _, _ in
                    Task { await model.reminders.updateLanguage(); await model.checkReminders() }
                }
                .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
                .environment(\.locale, AppLanguage.locale)
        }.defaultSize(width: 1240, height: 1000)
        MenuBarExtra {
            QuotaPopover(model: model) {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            }.id(language)
                .environment(\.locale, AppLanguage.locale)
                .environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
        } label: {
            QuotaMenuLabel(model: model).id(language)
        }.menuBarExtraStyle(.window)
    }
}

private struct QuotaMenuLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        Text(model.menuBarTitle).font(.system(size: 11)).monospacedDigit().help(model.menuBarHelp)
    }
}

@main
enum Launch {
    @MainActor static func main() async {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--ride-proof"), index + 1 < args.count {
            do {
                let stateIndex = args.firstIndex(of: "--ride-state")
                let state = stateIndex.flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "slow"
                try renderView(RideProofScene(state: state), destination: args[index + 1],
                               size: NSSize(width: args.contains("--narrow") ? 650 : 900, height: state == "reminder" ? 620 : 540))
                print("Rendered synthetic ride proof (no account/history/notification I/O): " + state)
                exit(0)
            } catch { fputs("Ride proof failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if args.contains("--menu-probe") {
            do {
                let model = AppModel()
                let snapshot = try await Task.detached { try CodexAppServerClient().fetchSnapshot() }.value
                model.snapshot = snapshot
                model.history = try QuotaHistoryStore().load(accountKey: snapshot.accountKey)
                model.radar = try await RadarData.fetch()
                model.bankedResets = try await BankedResetReader().read(accountKey: snapshot.accountKey)
                model.now = Date()
                let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
                let width = (model.menuBarTitle as NSString).size(withAttributes: [.font: font]).width
                print(String(decoding: try JSONSerialization.data(withJSONObject:
                    ["title": model.menuBarTitle, "textWidthPoints": width, "help": model.menuBarHelp],
                    options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
                exit(0)
            } catch { fputs("Menu probe failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if args.contains("--banked-probe") {
            do {
                let quota = try await Task.detached { try CodexAppServerClient().fetchSnapshot() }.value
                let stored = try await BankedResetReader().read(accountKey: quota.accountKey)
                let payload: [String: Any] = ["availableCount": stored.cards.count,
                    "expiresAtShanghai": stored.cards.map { L(ResetTimeDisplay.shanghai($0.expiresAt)) }]
                print(String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
                exit(0)
            } catch { fputs("Banked reset probe failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if args.contains("--radar-probe") {
            do {
                let radar = try await RadarData.fetch()
                let now = Date()
                let advice = ExtraResetAdvice.evaluate(radar, now: now)
                let payload: [String: Any] = [
                    "state": String(describing: advice.state), "basis": advice.targetName,
                    "deadline": advice.deadline.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown",
                    "remaining": advice.deadline.map { L(ResetTimeDisplay.remaining(until: $0, now: now)) } ?? L("时间未明确"),
                    "conversion": advice.conversionNote ?? L("无文字换算"),
                    "source": advice.sourceURL?.absoluteString ?? "unknown"
                ]
                print(String(decoding: try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
                exit(0)
            } catch { fputs("Radar probe failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if args.contains("--tokens-probe") {
            do {
                let report = try await LocalTokenUsageReader().read(now: Date())
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .custom { date, encoder in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    var container = encoder.singleValueContainer()
                    try container.encode(formatter.string(from: date))
                }
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
                exit(0)
            } catch { fputs("Token probe failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if args.contains("--probe") {
            do {
                let snapshot = try await Task.detached { try CodexAppServerClient().fetchSnapshot() }.value
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
                exit(0)
            } catch { fputs("Quota probe failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let index = args.firstIndex(of: "--render-proof"), index + 1 < args.count {
            do {
                let model = AppModel()
                if args.contains("--tokens") {
                    await model.refreshTokens()
                    model.page = "tokens"
                } else { await model.refresh() }
                if args.contains("--radar") { model.page = "radar" }
                try render(model: model, destination: args[index + 1], popover: args.contains("--popover"), narrow: args.contains("--narrow"))
                print("Rendered native view: \(args[index + 1])")
                if let error = model.error { fputs("\(error)\n", stderr); exit(1) }
                if args.contains("--tokens"), let error = model.tokenError { fputs("\(error)\n", stderr); exit(1) }
                exit(0)
            } catch { fputs("Render failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        ResetDesktopApp.main()
    }
    @MainActor static func render(model: AppModel, destination: String, popover: Bool = false, narrow: Bool = false) throws {
        let size = popover ? NSSize(width: 650, height: min(830, (NSScreen.main?.visibleFrame.height ?? 900) - 80)) : NSSize(width: narrow ? 1000 : 1260, height: model.page == "radar" ? 1000 : 1170)
        try renderView(Group {
            if popover { QuotaPopover(model: model, openDashboard: {}) }
            else { Dashboard(model: model) }
        }, destination: destination, size: size)
    }
    @MainActor static func renderView<V: View>(_ root: V, destination: String, size: NSSize) throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let view = NSHostingView(rootView: root.environment(\.timeZone, TimeZone(identifier: "Asia/Shanghai")!)
            .environment(\.locale, AppLanguage.locale))
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw NSError(domain: "Render", code: 1, userInfo: [NSLocalizedDescriptionKey: L("无法创建原生截图")])
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "Render", code: 2)
        }
        try data.write(to: URL(fileURLWithPath: destination), options: .atomic)
    }
}
