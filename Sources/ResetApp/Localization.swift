import Foundation

enum AppLanguage {
    private static var selection: String {
        ProcessInfo.processInfo.environment["CODEXRESET_LANGUAGE"]
            ?? UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    }

    static var identifier: String {
        let selectedTag = selection.replacingOccurrences(of: "_", with: "-").lowercased()
        if selectedTag == "en" || selectedTag.hasPrefix("en-") { return "en" }
        if selectedTag == "ja" || selectedTag.hasPrefix("ja-") { return "ja" }
        if selectedTag == "ko" || selectedTag.hasPrefix("ko-") { return "ko" }
        if selectedTag == "zh-hans" || selectedTag.hasPrefix("zh-hans-") || selectedTag == "zh" || selectedTag.hasPrefix("zh-") { return "zh-Hans" }
        for preferred in Locale.preferredLanguages {
            let normalized = preferred.replacingOccurrences(of: "_", with: "-").lowercased()
            if normalized.hasPrefix("zh") { return "zh-Hans" }
            if normalized.hasPrefix("ja") { return "ja" }
            if normalized.hasPrefix("ko") { return "ko" }
            if normalized.hasPrefix("en") { return "en" }
        }
        return "en"
    }

    static var isEnglish: Bool { identifier == "en" }
    static var locale: Locale {
        switch identifier {
        case "zh-Hans": Locale(identifier: "zh_Hans_CN")
        case "ja": Locale(identifier: "ja_JP")
        case "ko": Locale(identifier: "ko_KR")
        default: Locale(identifier: "en_US")
        }
    }

    static let english: [String: String] = loadCatalog("en")
    private static let catalogs: [String: [String: String]] = [
        "en": english,
        "zh-Hans": [:],
        "ja": loadCatalog("ja"),
        "ko": loadCatalog("ko")
    ]

    private static func loadCatalog(_ language: String) -> [String: String] {
        let url = Bundle.main.url(forResource: language, withExtension: "json")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/ResetApp/Resources/\(language).json")
        do { return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url)) }
        catch { fatalError("Unable to load \(language) localization: \(error)") }
    }

    static func translation(for source: String) -> String? {
        guard identifier != "zh-Hans" else { return nil }
        return catalogs[identifier]?[source]
    }

    private struct Pattern: Sendable {
        let regex: NSRegularExpression
        let source: String
        let count: Int
    }

    // Dynamic strings returned by the core (durations/errors) share the same catalog.
    private static let patterns: [Pattern] = english.keys.filter { $0.contains("{{0}}") }
        .sorted { $0.count > $1.count }.map { key in
            var pattern = NSRegularExpression.escapedPattern(for: key)
            var count = 0
            while key.contains("{{\(count)}}") {
                pattern = pattern.replacingOccurrences(of: NSRegularExpression.escapedPattern(for: "{{\(count)}}"), with: "(.*?)")
                count += 1
            }
            return Pattern(regex: try! NSRegularExpression(pattern: "\\A" + pattern + "\\z", options: .dotMatchesLineSeparators),
                           source: key, count: count)
        }

    static func dynamic(_ source: String, depth: Int = 0) -> String {
        if identifier == "zh-Hans" { return source }
        if let exact = translation(for: source) { return exact }
        if identifier == "ja" || identifier == "ko" {
            let abbreviatedDuration = try! NSRegularExpression(pattern: "\\A(?:(\\d+(?:\\.\\d+)?)d)?(?: ?(\\d+(?:\\.\\d+)?)h)?(?: ?(\\d+(?:\\.\\d+)?)m)?\\z")
            if let match = abbreviatedDuration.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
               (1...3).contains(where: { match.range(at: $0).location != NSNotFound }) {
                let units = identifier == "ja" ? ["日", "時間", "分"] : ["일", "시간", "분"]
                let nsSource = source as NSString
                return (1...3).compactMap { index -> String? in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? nil : nsSource.substring(with: range) + units[index - 1]
                }.joined(separator: " ")
            }
        }
        guard source.range(of: "[㐀-鿿]", options: .regularExpression) != nil else { return source }
        guard depth < 4 else { return source }
        let text = source as NSString
        let duration = try! NSRegularExpression(pattern: "\\A(?:([0-9]+)天)?(?:([0-9]+)小时)?([0-9]+)分\\z")
        if let match = duration.firstMatch(in: source, range: NSRange(location: 0, length: text.length)) {
            let units: [String]
            switch identifier {
            case "ja": units = ["日", "時間", "分"]
            case "ko": units = ["일", "시간", "분"]
            default: units = ["d", "h", "m"]
            }
            return (1...3).compactMap { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : text.substring(with: range) + units[index - 1]
            }.joined(separator: " ")
        }
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: source, range: NSRange(location: 0, length: text.length)) else { continue }
            var result = translation(for: pattern.source) ?? english[pattern.source]!
            for i in 0..<pattern.count {
                let value = dynamic(text.substring(with: match.range(at: i + 1)), depth: depth + 1)
                result = result.replacingOccurrences(of: "{{\(i)}}", with: value)
            }
            return result
        }
        // Core timestamps use Chinese month/day labels; keep the instant and timezone intact.
        let date = try! NSRegularExpression(pattern: "([0-9]{1,2})月([0-9]{1,2})日")
        var result = source
        for match in date.matches(in: source, range: NSRange(location: 0, length: text.length)).reversed() {
            let month = Int(text.substring(with: match.range(at: 1)))!
            let day = text.substring(with: match.range(at: 2))
            let replacement: String
            switch identifier {
            case "ja": replacement = "\(month)月\(day)日"
            case "ko": replacement = "\(month)월 \(day)일"
            default:
                let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
                replacement = (1...12).contains(month) ? names[month - 1] + " " + day : text.substring(with: match.range)
            }
            if let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }
}

func L(_ key: String, _ arguments: String...) -> String {
    var result = AppLanguage.translation(for: key) ?? AppLanguage.dynamic(key)
    for (index, value) in arguments.enumerated() {
        result = result.replacingOccurrences(of: "{{\(index)}}", with: AppLanguage.dynamic(value))
    }
    return result
}
