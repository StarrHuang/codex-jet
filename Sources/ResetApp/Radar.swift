import Foundation

struct RadarForecast: Decodable, Sendable {
    struct Probabilities: Decodable, Sendable {
        let rounded_24h: Double?
        let rounded_48h: Double?
    }
    struct ResetWindow: Decodable, Sendable {
        let label: String?
        let start_at: String?
        let target_kind: String?
        let end_at: String?
        let target_at: String?
    }
    struct Signal: Decodable, Sendable {
        let tweet_id: String?
        let signal_type: String?
        let at: String?
        let summary: String?
        let url: String?
        let kind: String?
        let corrected: Bool?
        let window: ResetWindow?
    }
    struct Alert: Decodable, Sendable {
        let id: String?
        let pending: String?
        let summary: String?
        let kind: String?
        let state: String?
        let source_at: String?
        let url: String?
        let corrected: Bool?
        let window: ResetWindow?
    }
    let mode: String?
    let updated_at: String
    let last_reset_at: String?
    let confidence: String?
    let probabilities: Probabilities
    let latest_alert: Alert?
    let official_signal: Signal?
}
struct RadarTimeline: Decodable, Sendable {
    struct Event: Decodable, Identifiable, Sendable {
        let id: String
        let date: String
        let summary: String?
        let announced_at: String?
        let scope: String?
        let corrected: Bool?
        let type: String
        let confidence: String?
        let reset_kind: String?
        let banked_state: String?
        let reset_verification_status: String?
        let url: String?
        var title: String {
            if reset_kind == "banked" { return L("储备重置 · ") + (banked_state == "available" ? L("站点监测账号已到账") : L("发放公告")) }
            if reset_kind == "hard" { return L("全局重置 · 站点已收录") }
            if type == "boost" { return L("额度调整信号") }
            if reset_verification_status == "pending" { return L("重置信号 · 尚待站点核验") }
            return type == "boost" ? L("额度调整信号") : L("重置相关公告")
        }
    }
    let updated_at: String
    let events: [Event]
}
struct RadarData: Sendable {
    let forecast: RadarForecast
    let timeline: RadarTimeline
    let fetchedAt: Date
    let observation: RadarObservation?
    let observationError: String?
    init(forecast: RadarForecast, timeline: RadarTimeline, fetchedAt: Date,
         observation: RadarObservation? = nil, observationError: String? = nil) {
        self.forecast = forecast; self.timeline = timeline; self.fetchedAt = fetchedAt
        self.observation = observation; self.observationError = observationError
    }
    static func fetch() async throws -> RadarData {
        // Public requests contain no account or quota data.
        async let forecast: RadarForecast = load("https://codex-reset.com/api/forecast?tz=Asia%2FShanghai")
        async let timeline: RadarTimeline = load("https://codex-reset.com/api/timeline")
        let (forecastValue, timelineValue) = try await (forecast, timeline)
        var observation: RadarObservation?
        var observationError: String?
        if let signal = forecastValue.official_signal, signal.window == nil,
           signal.signal_type == "promise", signal.corrected != true, let id = signal.tweet_id {
            do { observation = try await RadarObservation.fetch(eventID: id) }
            catch { observationError = L("观察窗口读取失败：{{0}}", String(describing: error.localizedDescription)) }
        }
        return RadarData(forecast: forecastValue, timeline: timelineValue, fetchedAt: Date(),
                         observation: observation, observationError: observationError)
    }
    private static func load<T: Decodable & Sendable>(_ address: String) async throws -> T {
        var request = URLRequest(url: URL(string: address)!)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("CodexResetLocal/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "codex-reset.com" else {
            throw NSError(domain: "Radar", code: 1, userInfo: [NSLocalizedDescriptionKey: L("全局雷达来源暂时不可用")])
        }
        guard data.count <= 2_000_000 else {
            throw NSError(domain: "Radar", code: 2, userInfo: [NSLocalizedDescriptionKey: L("全局雷达响应过大")])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

func parseDate(_ value: String) -> Date? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
