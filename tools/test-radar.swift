import Foundation
import ResetCore

@main
struct RadarChecks {
    static func main() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let iso = ISO8601DateFormatter()
        let source = "https://x.com/thsottiaux/status/123456789"
        func check(_ condition: Bool, _ message: String) {
            if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        func radar(signal: [String: Any]? = nil, alert: [String: Any]? = nil, updated: Date? = nil) throws -> RadarData {
            var json: [String: Any] = ["updated_at": iso.string(from: updated ?? now), "probabilities": ["rounded_24h": 99, "rounded_48h": 100]]
            if let signal { json["official_signal"] = signal }
            if let alert { json["latest_alert"] = alert }
            let forecast = try JSONDecoder().decode(RadarForecast.self, from: JSONSerialization.data(withJSONObject: json))
            let timeline = try JSONDecoder().decode(RadarTimeline.self, from: Data("{\"updated_at\":\"now\",\"events\":[]}".utf8))
            return RadarData(forecast: forecast, timeline: timeline, fetchedAt: now)
        }
        let pendingWindow: [String: Any] = ["label": "within an hour", "end_at": iso.string(from: now.addingTimeInterval(3600))]
        let signal: [String: Any] = ["at": iso.string(from: now.addingTimeInterval(-60)), "summary": "Full reset within the hour", "url": source, "window": pendingWindow]
        check(ExtraResetAdvice.evaluate(nil, now: now).state == .unknown, "missing radar is unknown rather than absence of a signal")
        let upcoming = try radar(signal: signal)
        check(ExtraResetAdvice.evaluate(upcoming, now: now).state == .upcoming, "future official reset enables sprint hint")
        check(ExtraResetAdvice.evaluate(upcoming, now: now).deadline == now.addingTimeInterval(3600), "announcement deadline preserved")
        let historyOnly = try radar()
        check(ExtraResetAdvice.evaluate(historyOnly, now: now).state == .waiting, "even 99 percent history forecast is not an announcement")
        var banked = signal; banked["kind"] = "banked"
        let bankedData = try radar(signal: banked)
        check(ExtraResetAdvice.evaluate(bankedData, now: now).state == .waiting, "banked issuance does not auto-refill quota")
        var unspecified = signal; unspecified["window"] = ["label": "official hint — timing unspecified", "end_at": iso.string(from: now.addingTimeInterval(3600))]
        let unspecifiedData = try radar(signal: unspecified)
        check(ExtraResetAdvice.evaluate(unspecifiedData, now: now).state == .waiting, "unspecified timing cannot start countdown")
        var expired = signal; expired["window"] = ["label": "within an hour", "end_at": iso.string(from: now.addingTimeInterval(-1))]
        let expiredData = try radar(signal: expired)
        check(ExtraResetAdvice.evaluate(expiredData, now: now).state == .elapsed, "past announcement is retained without a sprint countdown")
        var corrected = signal; corrected["corrected"] = true
        let correctedData = try radar(signal: corrected)
        check(ExtraResetAdvice.evaluate(correctedData, now: now).state == .waiting, "corrected announcement is suppressed")
        let staleData = try radar(signal: signal, updated: now.addingTimeInterval(-1801))
        check(ExtraResetAdvice.evaluate(staleData, now: now).state == .stale, "stale radar stops sprint hints")
        var confirmed: [String: Any] = ["kind": "reset", "state": "confirmed", "source_at": iso.string(from: now.addingTimeInterval(-60)), "url": source]
        let confirmedData = try radar(alert: confirmed)
        check(ExtraResetAdvice.evaluate(confirmedData, now: now).state == .recent, "just confirmed reset invites account readback before pedaling")
        confirmed["source_at"] = iso.string(from: now.addingTimeInterval(-86400))
        let oldData = try radar(alert: confirmed)
        check(ExtraResetAdvice.evaluate(oldData, now: now).state == .waiting, "old reset is not an imminent one")
        confirmed["source_at"] = iso.string(from: now.addingTimeInterval(-60)); confirmed["state"] = "pending"
        let pendingData = try radar(alert: confirmed)
        check(ExtraResetAdvice.evaluate(pendingData, now: now).state == .waiting, "unconfirmed reset does not encourage sprinting")
        let watch: [String: Any] = ["kind": "watch", "state": "active", "source_at": iso.string(from: now.addingTimeInterval(-60)), "url": source, "window": pendingWindow]
        let watchData = try radar(alert: watch)
        check(ExtraResetAdvice.evaluate(watchData, now: now).state == .upcoming, "active announced watch window supported")
        // Promise with no official window: only the matching site observation target
        // supplies a scenario deadline. Historical common hours are not a deadline.
        var promise: [String: Any] = ["tweet_id": "observation-1", "signal_type": "promise", "kind": "signal",
            "at": iso.string(from: now.addingTimeInterval(-3600)), "summary": "Global reset by EOD PST", "url": source]
        let promised = try radar(signal: promise)
        check(ExtraResetAdvice.evaluate(promised, now: now).state == .announced, "untimed promise remains prominent without inventing a deadline")
        let script = #"export const OBSERVATION_DEADLINES = Object.freeze({"observation-1":"2033-05-18T04:33:20Z"});"#
        let sourcePage = URL(string: "https://codex-reset.com/assets/test/home-countdown.js")!
        let observation = try RadarObservation.decode(script: script, eventID: "observation-1", sourceURL: sourcePage)
        check(observation?.deadline == now.addingTimeInterval(3600), "site observation mapping parsed exactly")
        check(try RadarObservation.decode(script: script, eventID: "another-event", sourceURL: sourcePage) == nil, "observation ID must match")
        let watched = RadarData(forecast: promised.forecast, timeline: promised.timeline, fetchedAt: now, observation: observation)
        let watchedAdvice = ExtraResetAdvice.evaluate(watched, now: now)
        check(watchedAdvice.state == .observation && watchedAdvice.deadlineBasis == .observation, "observation target cannot become official reset timing")
        check(ExtraResetAdvice.evaluate(watched, now: now.addingTimeInterval(1801)).state == .stale, "stale source cannot keep active countdown")
        let expiredObservation = RadarObservation(eventID: "observation-1", deadline: now.addingTimeInterval(-1), sourceURL: sourcePage)
        let elapsedWatch = RadarData(forecast: promised.forecast, timeline: promised.timeline, fetchedAt: now, observation: expiredObservation)
        check(ExtraResetAdvice.evaluate(elapsedWatch, now: now).state == .elapsed, "elapsed observation requests confirmation")
        promise["corrected"] = true
        let correctedPromise = try radar(signal: promise)
        check(ExtraResetAdvice.evaluate(RadarData(forecast: correctedPromise.forecast, timeline: promised.timeline, fetchedAt: now, observation: observation), now: now).state == .waiting, "corrected promise suppresses mapped countdown")
        var completedJSON: [String: Any] = ["updated_at": iso.string(from: now), "last_reset_at": iso.string(from: now.addingTimeInterval(-1)), "probabilities": [:], "official_signal": promised.forecast.official_signal == nil ? [:] : ["tweet_id": "observation-1", "signal_type": "promise", "at": iso.string(from: now.addingTimeInterval(-3600)), "summary": "reset promise", "url": source]]
        completedJSON["mode"] = "announced"
        let completedForecast = try JSONDecoder().decode(RadarForecast.self, from: JSONSerialization.data(withJSONObject: completedJSON))
        check(ExtraResetAdvice.evaluate(RadarData(forecast: completedForecast, timeline: promised.timeline, fetchedAt: now, observation: observation), now: now).state == .waiting, "newly confirmed reset invalidates earlier promise")
        do {
            _ = try RadarObservation.decode(script: "changed format", eventID: "observation-1", sourceURL: sourcePage)
            check(false, "changed observation format must fail visibly")
        } catch { /* Expected source boundary failure, not a fabricated target. */ }
        // Synthetic feed records keep the conversion checks reproducible without
        // publishing snapshots of the third-party site's live event feed.
        let followUpID = "synthetic-follow-up"
        let followUpAt = now.addingTimeInterval(-3600)
        let followUpObject: [String: Any] = [
            "updated_at": iso.string(from: now),
            "events": [[
                "id": followUpID,
                "date": "2033-05-18",
                "summary": "Resetting in 2 hours",
                "announced_at": iso.string(from: followUpAt),
                "scope": "global",
                "type": "reset",
                "confidence": "high",
                "reset_kind": "hard",
                "reset_verification_status": "pending",
                "url": "https://x.com/thsottiaux/status/\(followUpID)"
            ]]
        ]
        let followUpData = try JSONSerialization.data(withJSONObject: followUpObject)
        let followUpTimeline = try JSONDecoder().decode(RadarTimeline.self, from: followUpData)
        func followUpAdvice(_ timeline: RadarTimeline) -> ExtraResetAdvice {
            ExtraResetAdvice.evaluate(RadarData(forecast: promised.forecast, timeline: timeline, fetchedAt: now), now: now)
        }
        let announcementOnly = followUpAdvice(promised.timeline)
        check(announcementOnly.state == .announced && announcementOnly.deadline == nil,
              "active untimed announcement stays visible without inventing a deadline")
        let converted = followUpAdvice(followUpTimeline)
        check(converted.state == .upcoming && converted.deadlineBasis == .converted,
              "pending follow-up supplies an announcement-derived target")
        check(converted.deadline == now.addingTimeInterval(3600)
              && converted.conversion?.sourceZone == "announcement-relative",
              "relative target remains anchored to the synthetic announcement time")
        check(converted.conversionNote?.contains("发帖时刻与相对时长") == true,
              "converted target explains its source timing")
        for mutation in ["corrected", "other-author", "banked", "confirmed", "old", "low-confidence"] {
            var changed = followUpObject
            var events = followUpObject["events"] as! [[String: Any]]
            for index in events.indices {
                switch mutation {
                case "corrected": events[index]["corrected"] = true
                case "other-author": events[index]["url"] = "https://x.com/other/status/\(followUpID)"
                case "banked": events[index]["reset_kind"] = "banked"
                case "confirmed": events[index]["reset_verification_status"] = "confirmed"
                case "old": events[index]["announced_at"] = iso.string(from: now.addingTimeInterval(-49 * 3600))
                default: events[index]["confidence"] = "low"
                }
            }
            changed["events"] = events
            let timeline = try JSONDecoder().decode(RadarTimeline.self, from: JSONSerialization.data(withJSONObject: changed))
            check(followUpAdvice(timeline).deadline == nil, "ineligible follow-up suppressed: " + mutation)
        }
        print("PASS: extra-reset source parsing, upcoming/confirmed states, history-only, banked, expired, corrected, unknown-time and stale gates")
    }
}
