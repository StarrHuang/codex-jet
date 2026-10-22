import Foundation

/// A deadline parsed conservatively from a reset announcement.
public struct ResetTimeConversion: Equatable, Sendable {
    public let deadline: Date
    public let originalText: String
    public let sourceZone: String
    /// A daylight-saving interpretation, when it differs from the stated fixed offset.
    public let alternateDeadline: Date?
    public let explanation: String

    private init(deadline: Date, originalText: String, sourceZone: String,
                alternateDeadline: Date?, explanation: String) {
        self.deadline = deadline
        self.originalText = originalText
        self.sourceZone = sourceZone
        self.alternateDeadline = alternateDeadline
        self.explanation = explanation
    }

    /// Parses only explicit, bounded deadline phrases. Relative windows are anchored to
    /// `announcedAt`, so a later display time cannot move the deadline.
    public static func parse(_ text: String, announcedAt: Date) -> ResetTimeConversion? {
        let phrase = #"(?i)\b(?:lands?|landing|resets?|resetting)\s+(today|tomorrow)\s+(?:before|by)\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s+(PST|PDT|UTC|GMT)\b"#
        if let match = firstMatch(phrase, in: text),
           let dayWord = group(1, match, text),
           let hourText = group(2, match, text),
           let hourValue = Int(hourText),
           let meridiem = group(4, match, text)?.uppercased(),
           let zone = group(5, match, text)?.uppercased(),
           (1...12).contains(hourValue),
           let fixedZone = fixedTimeZone(zone)
        {
            let minuteValue = group(3, match, text).flatMap(Int.init) ?? 0
            guard (0...59).contains(minuteValue) else { return nil }
            let hour = (hourValue % 12) + (meridiem == "PM" ? 12 : 0)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = fixedZone
            let dayOffset = dayWord.lowercased() == "tomorrow" ? 1 : 0
            guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: announcedAt) else { return nil }
            let parts = calendar.dateComponents([.year, .month, .day], from: targetDay)
            var target = DateComponents()
            target.calendar = calendar
            target.timeZone = fixedZone
            target.year = parts.year
            target.month = parts.month
            target.day = parts.day
            target.hour = hour
            target.minute = minuteValue
            target.second = 0
            guard let deadline = calendar.date(from: target),
                  deadline > announcedAt,
                  deadline.timeIntervalSince(announcedAt) <= 48 * 3600
            else { return nil }

            let alternate = daylightAlternative(zone: zone, dayWord: dayWord,
                                                hour: hour, minute: minuteValue,
                                                announcedAt: announcedAt)
            let explanation: String
            if let alternate {
                explanation = "\(zone) is treated as a fixed offset (PST UTC-8, PDT UTC-7). The Pacific daylight-saving interpretation differs; the alternate is shown explicitly."
                return ResetTimeConversion(deadline: deadline, originalText: text, sourceZone: zone,
                                           alternateDeadline: alternate, explanation: explanation)
            }
            explanation = "\(zone) is interpreted as an explicit time-zone abbreviation."
            return ResetTimeConversion(deadline: deadline, originalText: text, sourceZone: zone,
                                       alternateDeadline: nil, explanation: explanation)
        }

        let relative = #"(?i)\b(?:lands?|landing|resets?|resetting)\s+(?:in\s+|within\s+(?:the\s+next\s+)?)(\d{1,2})\s+(hours?|hrs?|minutes?|mins?)\b"#
        guard let match = firstMatch(relative, in: text),
              let amountText = group(1, match, text), let amount = Int(amountText),
              let unit = group(2, match, text)?.lowercased(), amount > 0
        else { return nil }
        let isMinute = unit.hasPrefix("m")
        let maximum = isMinute ? 48 * 60 : 48
        guard amount <= maximum else { return nil }
        let interval = TimeInterval(amount) * (isMinute ? 60 : 3600)
        return ResetTimeConversion(deadline: announcedAt.addingTimeInterval(interval),
                                   originalText: text, sourceZone: "announcement-relative",
                                   alternateDeadline: nil,
                                   explanation: "The stated \(amount) \(unit) window is anchored to the announcement time.")
    }

    private static func fixedTimeZone(_ abbreviation: String) -> TimeZone? {
        switch abbreviation {
        case "PST": return TimeZone(secondsFromGMT: -8 * 3600)
        case "PDT": return TimeZone(secondsFromGMT: -7 * 3600)
        case "UTC", "GMT": return TimeZone(secondsFromGMT: 0)
        default: return nil
        }
    }

    private static func daylightAlternative(zone: String, dayWord: String, hour: Int,
                                             minute: Int, announcedAt: Date) -> Date? {
        guard zone == "PST" || zone == "PDT" else { return nil }
        let pacific = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let dayOffset = dayWord.lowercased() == "tomorrow" ? 1 : 0
        guard let targetDay = calendar.date(byAdding: .day, value: dayOffset, to: announcedAt) else { return nil }
        let parts = calendar.dateComponents([.year, .month, .day], from: targetDay)
        var local = DateComponents()
        local.calendar = calendar
        local.timeZone = pacific
        local.year = parts.year
        local.month = parts.month
        local.day = parts.day
        local.hour = hour
        local.minute = minute
        local.second = 0
        guard let date = calendar.date(from: local) else { return nil }
        // Only surface an alternative when the named abbreviation differs from the
        // actual Pacific offset for that wall-clock date.
        let explicitOffset = zone == "PST" ? -8 * 3600 : -7 * 3600
        return calendar.timeZone.secondsFromGMT(for: date) == explicitOffset ? nil : date
    }

    private static func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
        try! NSRegularExpression(pattern: pattern).firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func group(_ index: Int, _ match: NSTextCheckingResult, _ text: String) -> String? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
