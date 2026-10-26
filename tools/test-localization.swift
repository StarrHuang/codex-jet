import Foundation
import ResetCore
@testable import ResetApp

@main struct LocalizationChecks {
    @MainActor static func main() throws {
        let english = CommandLine.arguments.contains("en")
        precondition(AppLanguage.isEnglish == english)
        precondition(L("语言") == (english ? "Language" : "语言"))
        precondition(String(format: L("%.1f天"), 2.5) == (english ? "2.5d" : "2.5天"))
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let model = AppModel()
        model.now = now
        model.snapshot = QuotaSnapshot(sampledAt: now, accountKey: "language-fixture", plan: nil, windows: [
            QuotaWindow(id: "codex:primary", bucketID: "codex", label: "Codex", usedPercent: 60,
                        durationMinutes: 10080, resetsAt: now.addingTimeInterval(60 * 3600))
        ])
        precondition(model.menuBarTitle == (english ? "40% 2.5d" : "40% 2.5天"))
        let duration = L(ResetTimeDisplay.remaining(until: now.addingTimeInterval(5500), now: now))
        let date = L(ResetTimeDisplay.shanghai(now))
        let warning = L("14 个近期日志只有累计计数，没有逐次增量记录，未换算为小时用量。")
        if english {
            precondition(duration == "1h 31m")
            precondition(warning.hasPrefix("14 recent logs"))
            for text in [duration, date, model.menuBarHelp, warning] {
                if let range = text.range(of: "[㐀-鿿]", options: .regularExpression) { fatalError("Untranslated: " + String(text[range]) + " in " + text) }
                precondition(!text.contains("{{"), text)
            }
        } else {
            precondition(duration.contains("小时"))
            precondition(date.contains("月"))
        }
        print("PASS: \(english ? "English" : "Chinese") catalog, dynamic core time, menu units and tooltip")
    }
}
