import Foundation
import ResetCore

struct ExtraResetAdvice {
    enum State { case upcoming, observation, announced, elapsed, recent, waiting, stale, unknown }
    enum DeadlineBasis { case official, observation, converted }
    let state: State
    let deadline: Date?
    let sourceURL: URL?
    let summary: String?
    let announcementAt: Date?
    let deadlineBasis: DeadlineBasis?
    var conversion: ResetTimeConversion? = nil
    var targetName: String {
        switch deadlineBasis {
        case .official: L("官方窗口目标")
        case .observation: L("站点观察目标")
        case .converted: L("公告原文换算目标")
        case nil: L("公告时间未明确")
        }
    }
    var conversionNote: String? {
        guard let conversion else { return nil }
        let zoneLabel = conversion.sourceZone == "announcement-relative" ? L("发帖时刻与相对时长") : conversion.sourceZone
        var note = L("按原文 {{0}} 换算：{{1}} 前（北京时间 UTC+8）。", String(describing: zoneLabel), String(describing: L(ResetTimeDisplay.shanghai(conversion.deadline))))
        if let alternate = conversion.alternateDeadline {
            note += L("原文若泛指太平洋当地时间，则为 {{0}} 前；两种解释请留意。", String(describing: L(ResetTimeDisplay.shanghai(alternate))))
        }
        return note
    }

    static func evaluate(_ radar: RadarData?, now: Date) -> ExtraResetAdvice {
        func advice(_ state: State, deadline: Date? = nil, source: String? = nil,
                    summary: String? = nil, at: Date? = nil, basis: DeadlineBasis? = nil) -> ExtraResetAdvice {
            let url = source.flatMap(URL.init(string:))
            return ExtraResetAdvice(state: state, deadline: deadline,
                                    sourceURL: url?.scheme == "https" && url?.host == "x.com" ? url : nil,
                                    summary: summary, announcementAt: at, deadlineBasis: basis)
        }
        guard let radar else { return advice(.unknown) }
        guard let updated = parseDate(radar.forecast.updated_at),
              now >= updated, now.timeIntervalSince(updated) <= 30 * 60,
              now >= radar.fetchedAt, now.timeIntervalSince(radar.fetchedAt) <= 30 * 60 else {
            let signal = radar.forecast.official_signal
            return advice(.stale, source: signal?.url, summary: signal?.summary, at: signal?.at.flatMap(parseDate))
        }
        let resetAt = radar.forecast.last_reset_at.flatMap(parseDate)
        if let alert = radar.forecast.latest_alert, alert.corrected != true,
           let at = alert.source_at.flatMap(parseDate), at <= now,
           alert.kind == "reset", alert.state == "confirmed", now.timeIntervalSince(at) < 15 * 60 {
            return advice(.recent, source: alert.url, summary: alert.summary, at: at)
        }
        // The feed can publish a precise follow-up while forecast.window is still null.
        // Only recent, pending global reset posts from the source account are eligible.
        let timedPosts = radar.timeline.events.filter { event in
            guard event.type == "reset", event.scope == "global", event.reset_kind != "banked",
                  event.corrected != true, event.reset_verification_status == "pending",
                  ["medium", "high"].contains(event.confidence ?? ""),
                  let at = event.announced_at.flatMap(parseDate), at <= now, now.timeIntervalSince(at) <= 48 * 3600,
                  resetAt.map({ at > $0 }) ?? true,
                  let address = event.url, let url = URL(string: address), url.scheme == "https", url.host == "x.com",
                  url.path == "/thsottiaux/status/" + event.id,
                  let summary = event.summary, ResetTimeConversion.parse(summary, announcedAt: at) != nil
            else { return false }
            return true
        }.sorted { parseDate($0.announced_at!)! > parseDate($1.announced_at!)! }
        if let post = timedPosts.first, let at = post.announced_at.flatMap(parseDate), let summary = post.summary,
           let converted = ResetTimeConversion.parse(summary, announcedAt: at),
           radar.forecast.official_signal?.at.flatMap(parseDate).map({ at >= $0 }) ?? true {
            var result = advice(converted.deadline > now ? .upcoming : .elapsed, deadline: converted.deadline,
                                source: post.url, summary: summary, at: at, basis: .converted)
            result.conversion = converted
            return result
        }
        if let signal = radar.forecast.official_signal,
           signal.kind != "banked", signal.corrected != true,
           let at = signal.at.flatMap(parseDate), at <= now, now.timeIntervalSince(at) <= 86400,
           resetAt.map({ at > $0 }) ?? true, signal.summary?.isEmpty == false {
            if let window = signal.window,
               let text = window.label, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !text.lowercased().contains("timing unspecified"),
               let deadline = (window.end_at ?? window.target_at).flatMap(parseDate), deadline >= at {
                return advice(deadline > now ? .upcoming : .elapsed, deadline: deadline,
                              source: signal.url, summary: signal.summary, at: at, basis: .official)
            }
            if signal.window == nil, signal.signal_type == "promise" {
                if let observation = radar.observation, observation.eventID == signal.tweet_id,
                   observation.deadline > at, observation.deadline.timeIntervalSince(at) <= 86400 {
                    return advice(observation.deadline > now ? .observation : .elapsed,
                                  deadline: observation.deadline, source: signal.url, summary: signal.summary,
                                  at: at, basis: .observation)
                }
                return advice(.announced, source: signal.url, summary: signal.summary, at: at)
            }
        }
        if let alert = radar.forecast.latest_alert, alert.corrected != true,
           let at = alert.source_at.flatMap(parseDate), at <= now, now.timeIntervalSince(at) <= 86400,
           resetAt.map({ at > $0 }) ?? true, alert.kind == "watch", alert.state == "active" {
            if let window = alert.window, let text = window.label,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !text.lowercased().contains("timing unspecified"),
               let deadline = (window.end_at ?? window.target_at).flatMap(parseDate), deadline >= at {
                return advice(deadline > now ? .upcoming : .elapsed, deadline: deadline,
                              source: alert.url, summary: alert.summary, at: at, basis: .official)
            }
            if alert.window == nil, alert.pending == "on_its_way", alert.summary?.isEmpty == false {
                return advice(.announced, source: alert.url, summary: alert.summary, at: at)
            }
        }
        return advice(.waiting)
    }
}
