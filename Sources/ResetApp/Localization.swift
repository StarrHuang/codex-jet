import Foundation

enum AppLanguage {
    static var isEnglish: Bool {
        let selected = ProcessInfo.processInfo.environment["CODEXRESET_LANGUAGE"]
            ?? UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        if selected == "en" { return true }
        if selected == "zh-Hans" { return false }
        return !(Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
    }
    static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "zh_Hans_CN") }
    static let english: [String: String] = {
        let url = Bundle.main.url(forResource: "en", withExtension: "json")
            ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Sources/ResetApp/Resources/en.json")
        do { return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url)) }
        catch { fatalError("Unable to load English localization: \(error)") }
    }()
    private struct Pattern: Sendable {
        let regex: NSRegularExpression
        let english: String
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
                           english: english[key]!, count: count)
        }
    static func dynamic(_ source: String, depth: Int = 0) -> String {
        guard isEnglish, source.range(of: "[㐀-鿿]", options: .regularExpression) != nil else { return source }
        if let exact = english[source] { return exact }
        guard depth < 4 else { return source }
        let text = source as NSString
        let duration = try! NSRegularExpression(pattern: "\\A(?:([0-9]+)天)?(?:([0-9]+)小时)?([0-9]+)分\\z")
        if let match = duration.firstMatch(in: source, range: NSRange(location: 0, length: text.length)) {
            return (1...3).compactMap { index -> String? in
                let range = match.range(at: index)
                return range.location == NSNotFound ? nil : text.substring(with: range) + ["d", "h", "m"][index - 1]
            }.joined(separator: " ")
        }
        for pattern in patterns {
            guard let match = pattern.regex.firstMatch(in: source, range: NSRange(location: 0, length: text.length)) else { continue }
            var result = pattern.english
            for i in 0..<pattern.count {
                let value = dynamic(text.substring(with: match.range(at: i + 1)), depth: depth + 1)
                result = result.replacingOccurrences(of: "{{\(i)}}", with: value)
            }
            return result
        }
        // The core deliberately formats account times in Shanghai; translate the month label
        // without changing the timestamp, timezone, or account deadline.
        let date = try! NSRegularExpression(pattern: "([0-9]{1,2})月([0-9]{1,2})日")
        var result = source
        for match in date.matches(in: source, range: NSRange(location: 0, length: text.length)).reversed() {
            let month = Int(text.substring(with: match.range(at: 1)))!
            let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
            if (1...12).contains(month), let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: names[month - 1] + " " + text.substring(with: match.range(at: 2)))
            }
        }
        return result
    }
}

func L(_ key: String, _ arguments: String...) -> String {
    var result = AppLanguage.isEnglish ? (AppLanguage.english[key] ?? AppLanguage.dynamic(key)) : key
    for (index, value) in arguments.enumerated() {
        result = result.replacingOccurrences(of: "{{\(index)}}", with: AppLanguage.dynamic(value))
    }
    return result
}
