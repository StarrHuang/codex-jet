import Foundation

public struct QuotaHistoryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) throws {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true)
            self.fileURL = support.appendingPathComponent("CodexReset", isDirectory: true)
                .appendingPathComponent("history.json")
        }
    }

    public func load(accountKey: String? = nil) throws -> [QuotaSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let snapshots = try JSONDecoder.quotaDecoder.decode([QuotaSnapshot].self, from: data)
        guard let accountKey else { return snapshots }
        return snapshots.filter { $0.accountKey == accountKey }
    }

    @discardableResult
    public func append(_ snapshot: QuotaSnapshot) throws -> [QuotaSnapshot] {
        let existing = try load()
        // Keep the return value aligned with the date precision in the persisted JSON.
        let snapshotData = try JSONEncoder.quotaEncoder.encode(snapshot)
        let persistedSnapshot = try JSONDecoder.quotaDecoder.decode(QuotaSnapshot.self, from: snapshotData)
        let snapshots = existing + [persistedSnapshot]
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder.quotaEncoder.encode(snapshots)
        try data.write(to: fileURL, options: .atomic)
        return snapshots
    }
}

extension JSONEncoder {
    fileprivate static var quotaEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var quotaDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
