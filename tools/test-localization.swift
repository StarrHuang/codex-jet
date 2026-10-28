import Foundation
import ResetCore
@testable import ResetApp

@main struct LocalizationChecks {
    @MainActor static func main() throws {
        let language = CommandLine.arguments[1]
        let chinese = language == "zh-Hans"
        let english = language == "en"
        precondition(AppLanguage.identifier == language, "identifier: \(AppLanguage.identifier), expected \(language)")
        precondition(AppLanguage.isEnglish == english)
        precondition(AppLanguage.locale.identifier == ["en": "en_US", "zh-Hans": "zh_CN", "ja": "ja_JP", "ko": "ko_KR"][language])
        precondition(L("语言") == ["en": "Language", "zh-Hans": "语言", "ja": "言語", "ko": "언어"][language])
        precondition(L("当前账户") == ["en": "Current account", "zh-Hans": "当前账户", "ja": "現在のアカウント", "ko": "현재 계정"][language])
        precondition(L("跟随系统") == ["en": "Follow System", "zh-Hans": "跟随系统", "ja": "システムに従う", "ko": "시스템 설정 따르기"][language])
        precondition(L("模型消耗") == ["en": "Model usage", "zh-Hans": "模型消耗", "ja": "モデル別使用量", "ko": "모델별 사용량"][language])
        precondition(String(format: L("%.1f天"), 2.5) == ["en": "2.5d", "zh-Hans": "2.5天", "ja": "2.5日", "ko": "2.5일"][language])
        let temporary = try PresentationProof.model(state: "temporary")
        let banner = TemporaryResetBanner(advice: temporary.extraResetAdvice,
            pace: temporary.temporaryResetPace, window: temporary.mainWindow, now: temporary.now)
        let rawCountdown = ResetTimeDisplay.remaining(until: temporary.extraResetAdvice.deadline!, now: temporary.now)
        let visibleCountdown = banner.deadlineValue(at: temporary.now)
        precondition(visibleCountdown == L(rawCountdown), "Live announcement countdown bypassed localization")
        if !chinese { precondition(!visibleCountdown.contains("小时"), visibleCountdown) }
        if language == "ja" { precondition(L("5h 59m") == "5時間 59分") }
        if language == "ko" { precondition(L("5h 59m") == "5시간 59분") }
        if language == "en" { precondition(L("5h 59m") == "5h 59m") }
        if language == "zh-Hans" { precondition(L("5h 59m") == "5h 59m") }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let model = AppModel(monitoringEnabled: false)
        model.now = now
        model.snapshot = QuotaSnapshot(sampledAt: now, accountKey: "localization-fixture", plan: nil, windows: [
            QuotaWindow(id: "codex:primary", bucketID: "codex", label: "Codex", usedPercent: 60,
                        durationMinutes: 10080, resetsAt: now.addingTimeInterval(60 * 60 * 60))
        ])
        precondition(model.menuBarTitle.contains("40%"))
        let title = model.menuBarTitle
        if english { precondition(title.contains("2.5d"), title) }
        else if chinese { precondition(title.contains("2.5天"), title) }
        else if language == "ja" { precondition(title.contains("2.5日"), title) }
        else { precondition(title.contains("2.5일"), title) }

        let duration = L(ResetTimeDisplay.remaining(until: now.addingTimeInterval(5500), now: now))
        let longDuration = L(ResetTimeDisplay.remaining(until: now.addingTimeInterval(60 * 60 * 60), now: now))
        let date = L(ResetTimeDisplay.shanghai(now))
        let warning = L("14 个近期日志只有累计计数，没有逐次增量记录，未换算为小时用量。")
        if english {
            precondition(duration == "1h 31m", duration)
            precondition(longDuration.contains("2d") && longDuration.contains("12h"), longDuration)
            precondition(warning.hasPrefix("14 recent logs"), warning)
            for text in [duration, longDuration, date, model.menuBarHelp, warning] {
                precondition(!text.contains("{{"), text)
                precondition(text.range(of: "[㐀-鿿]", options: .regularExpression) == nil, text)
            }
        } else if chinese {
            precondition(duration.contains("小时"), duration)
            precondition(longDuration.contains("天"), longDuration)
            precondition(date.contains("月"), date)
        } else if language == "ja" {
            precondition(duration.contains("時間") && duration.contains("分"), duration)
            precondition(longDuration.contains("日") && longDuration.contains("時間"), longDuration)
            precondition(date.contains("月") && date.contains("日"), date)
            precondition(warning != "14 个近期日志只有累计计数，没有逐次增量记录，未换算为小时用量。")
        } else {
            precondition(duration.contains("시간") && duration.contains("분"), duration)
            precondition(longDuration.contains("일") && longDuration.contains("시간"), longDuration)
            precondition(date.contains("월") && date.contains("일"), date)
            precondition(warning != "14 个近期日志只有累计计数，没有逐次增量记录，未换算为小时用量。")
        }
        print("PASS: \(language) catalog, dynamic core time, menu units, locale and tooltip")
    }
}
