import Foundation
import ResetCore

private enum Failure: Error { case assertion(String) }
private func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw Failure.assertion(message) }
}

private func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)!
}

private func run() throws {
    let clock = date("2026-10-22T06:00:00Z")
    try expect(ResetTimeDisplay.remaining(until: clock.addingTimeInterval(90061), now: clock) == "1天1小时1分", "human day hour minute countdown")
    try expect(ResetTimeDisplay.remaining(until: clock.addingTimeInterval(0.5), now: clock) == "不到1分钟", "positive subsecond deadline is still future")
    try expect(ResetTimeDisplay.remaining(until: clock, now: clock) == "目标已到，等待确认", "elapsed is not a future countdown")
    let announcement = date("2026-10-22T06:55:54Z")
    let live = "Lands tomorrow before 10am PST."
    guard let parsed = ResetTimeConversion.parse(live, announcedAt: announcement) else {
        throw Failure.assertion("live announcement phrase parses")
    }
    try expect(parsed.deadline == date("2026-10-22T18:00:00Z"), "PST is fixed UTC-8 and tomorrow uses PST calendar date")
    try expect(parsed.alternateDeadline == date("2026-10-22T17:00:00Z"), "Pacific daylight-saving interpretation is exposed")
    try expect(parsed.originalText == live && parsed.sourceZone == "PST", "source phrase and zone are retained")

    let nearMidnight = date("2026-10-22T07:30:00Z")
    let pstVsPacific = ResetTimeConversion.parse("Lands tomorrow before 10am PST", announcedAt: nearMidnight)
    try expect(pstVsPacific?.deadline == date("2026-10-22T18:00:00Z"), "PST tomorrow uses the PST calendar date")
    try expect(pstVsPacific?.alternateDeadline == date("2026-10-23T17:00:00Z"),
               "Pacific alternative tomorrow is recomputed from the announcement date in Los Angeles")
    let today = ResetTimeConversion.parse("Reset today by 1am PDT", announcedAt: nearMidnight)
    try expect(today?.deadline == date("2026-10-22T08:00:00Z"), "today follows the stated PDT local calendar")
    let tomorrow = ResetTimeConversion.parse("Reset tomorrow by 1:15pm PDT", announcedAt: nearMidnight)
    try expect(tomorrow?.deadline == date("2026-10-23T20:15:00Z"), "PDT minute precision converts across the date boundary")

    let inTwoHours = ResetTimeConversion.parse("Reset in 2 hours", announcedAt: announcement)
    try expect(inTwoHours?.deadline == announcement.addingTimeInterval(7200), "relative deadline is anchored to announcement instant")
    let withinTwoHours = ResetTimeConversion.parse("Reset within the next 2 hours", announcedAt: announcement)
    try expect(withinTwoHours?.deadline == announcement.addingTimeInterval(7200), "bounded within-the-next wording is supported")
    let landingInThirty = ResetTimeConversion.parse("Lands in 30 minutes", announcedAt: announcement)
    try expect(landingInThirty?.deadline == announcement.addingTimeInterval(1800), "landing countdown is supported")
    try expect(ResetTimeConversion.parse("Reset 2 hours", announcedAt: announcement) == nil,
               "bare duration without in or within is not treated as a deadline")
    try expect(ResetTimeConversion.parse("It only takes 15 mins to finish", announcedAt: announcement) == nil,
               "incidental duration is not mistaken for reset timing")

    try expect(ResetTimeConversion.parse("Reset today by 10am PST", announcedAt: announcement) == nil,
               "deadline earlier than announcement is rejected")
    try expect(ResetTimeConversion.parse("Reset tomorrow by 13pm PST", announcedAt: announcement) == nil,
               "invalid 12-hour time is rejected")
    try expect(ResetTimeConversion.parse("Reset tomorrow by 10am EST", announcedAt: announcement) == nil,
               "unsupported time zone is rejected")
    try expect(ResetTimeConversion.parse("Reset tomorrow by 10am", announcedAt: announcement) == nil,
               "zone-less time is rejected")
    try expect(ResetTimeConversion.parse("Reset in 49 hours", announcedAt: announcement) == nil,
               "relative windows beyond 48 hours are rejected")

    let winter = date("2026-01-10T12:00:00Z")
    let winterPST = ResetTimeConversion.parse("Lands tomorrow by 10am PST", announcedAt: winter)
    try expect(winterPST?.alternateDeadline == nil, "PST has no alternate when Pacific standard time agrees")
    let winterPDT = ResetTimeConversion.parse("Lands tomorrow by 10am PDT", announcedAt: winter)
    try expect(winterPDT?.alternateDeadline != nil, "incorrect seasonal PDT remains explicit with its Pacific alternative")

    print("Reset time conversion fixtures passed")
}

@main
private struct ResetTimeHarness {
    static func main() {
        do { try run() } catch {
            fputs("Reset time conversion fixture failure: \(error)\n", stderr)
            exit(1)
        }
    }
}
