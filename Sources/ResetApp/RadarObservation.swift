import Foundation

/// Site-authored observation targets, kept separate from an official reset window.
struct RadarObservation: Sendable {
    let eventID: String
    let deadline: Date
    let sourceURL: URL

    static func decode(script: String, eventID: String, sourceURL: URL) throws -> RadarObservation? {
        let pattern = #"OBSERVATION_DEADLINES\s*=\s*Object\.freeze\((\{[^;]*?\})\)"#
        let regex = try NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: script, range: NSRange(script.startIndex..., in: script)),
              let range = Range(match.range(at: 1), in: script) else {
            throw NSError(domain: "RadarObservation", code: 1, userInfo: [NSLocalizedDescriptionKey: L("站点观察窗口格式已变化")])
        }
        let deadlines = try JSONDecoder().decode([String: String].self, from: Data(script[range].utf8))
        guard let value = deadlines[eventID] else { return nil }
        guard let deadline = parseDate(value) else {
            throw NSError(domain: "RadarObservation", code: 2, userInfo: [NSLocalizedDescriptionKey: L("站点观察截止时间无效")])
        }
        return RadarObservation(eventID: eventID, deadline: deadline, sourceURL: sourceURL)
    }

    static func fetch(eventID: String) async throws -> RadarObservation? {
        let html = try await text(URL(string: "https://codex-reset.com/zh/")!)
        let regex = try NSRegularExpression(pattern: #"src="(/assets/[^"<>]+/app\.js)""#)
        guard let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html),
              let entry = URL(string: String(html[range]), relativeTo: URL(string: "https://codex-reset.com")!)?.absoluteURL else {
            throw NSError(domain: "RadarObservation", code: 3, userInfo: [NSLocalizedDescriptionKey: L("无法定位站点观察窗口来源")])
        }
        let source = entry.deletingLastPathComponent().appendingPathComponent("home-countdown.js")
        return try decode(script: await text(source), eventID: eventID, sourceURL: source)
    }

    private static func text(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "codex-reset.com", data.count <= 2_000_000,
              let text = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "RadarObservation", code: 4, userInfo: [NSLocalizedDescriptionKey: L("观察窗口来源暂时不可用")])
        }
        return text
    }
}
