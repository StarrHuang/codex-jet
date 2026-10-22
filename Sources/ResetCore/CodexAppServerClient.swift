import CryptoKit
import Darwin
import Foundation

public enum CodexAppServerError: Error, LocalizedError {
    case executableNotFound(URL)
    case processStart(String)
    case io(String)
    case timeout(String)
    case rpc(String)
    case malformedResponse(String)
    case noQuotaWindows
    case missingAccountIdentity
    case invalidUsageValue(String)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(url): "Codex executable not found at \(url.path)."
        case let .processStart(message): "Could not start Codex app-server: \(message)"
        case let .io(message): "Codex app-server I/O failed: \(message)"
        case let .timeout(method): "Timed out waiting for Codex app-server method \(method)."
        case let .rpc(message): "Codex app-server RPC failed: \(message)"
        case let .malformedResponse(message): "Codex app-server returned invalid data: \(message)"
        case .noQuotaWindows: "Codex app-server returned no quota windows."
        case .missingAccountIdentity: "Codex app-server did not provide a stable account identity; quota history was not saved."
        case let .invalidUsageValue(bucketID): "Codex app-server returned an invalid usage percentage for quota bucket \(bucketID)."
        }
    }
}

public struct CodexAppServerClient: Sendable {
    public let executableURL: URL
    public let timeout: TimeInterval

    public init(executableURL: URL? = nil, timeout: TimeInterval = 8) {
        self.executableURL = executableURL ?? Self.discoverExecutable()
        self.timeout = timeout
    }

    public static func discoverExecutable(environment: [String: String] = ProcessInfo.processInfo.environment,
                                         homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if let configured = environment["CODEX_EXECUTABLE"], !configured.isEmpty {
            return URL(fileURLWithPath: configured)
        }
        let pathCandidates = (environment["PATH"] ?? "").split(separator: ":")
            .filter { $0.hasPrefix("/") }.map { String($0) + "/codex" }
        let candidates = pathCandidates + [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            homeDirectory.appendingPathComponent(".local/bin/codex").path,
            homeDirectory.appendingPathComponent(".npm-global/bin/codex").path,
            homeDirectory.appendingPathComponent(".volta/bin/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
            homeDirectory.appendingPathComponent("Applications/Codex.app/Contents/Resources/codex").path,
        ]
        let path = candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? "/opt/homebrew/bin/codex"
        return URL(fileURLWithPath: path)
    }

    public func fetchSnapshot(sampledAt: Date = .now) throws -> QuotaSnapshot {
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw CodexAppServerError.executableNotFound(executableURL)
        }
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.arguments = ["-s", "read-only", "-a", "never", "app-server"]
        // Finder launches omit Homebrew from PATH. The npm Codex entrypoint
        // uses /usr/bin/env node, so include its installation directory.
        var environment = ProcessInfo.processInfo.environment
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = executableURL.deletingLastPathComponent().path
            + ":/opt/homebrew/bin:/usr/local/bin:" + inheritedPath
        process.environment = environment
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() }
        catch { throw CodexAppServerError.processStart(error.localizedDescription) }
        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
                let shutdownDeadline = Date().addingTimeInterval(0.5)
                while process.isRunning && Date() < shutdownDeadline { usleep(10_000) }
                if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
            }
        }

        var requestID = 0
        func request(_ method: String, params: [String: Any] = [:]) throws -> [String: Any] {
            requestID += 1
            let id = requestID
            let deadline = Date().addingTimeInterval(timeout)
            var payload = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": params])
            payload.append(0x0A)
            do { try input.fileHandleForWriting.write(contentsOf: payload) }
            catch { throw CodexAppServerError.io(error.localizedDescription) }
            while true {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0,
                      let message = try readMessage(from: output.fileHandleForReading, timeout: remaining)
                else {
                    throw CodexAppServerError.timeout(method)
                }
                if (message["id"] as? Int) != id { continue }
                if let rpcError = message["error"] as? [String: Any] {
                    throw CodexAppServerError.rpc(rpcError["message"] as? String ?? "unknown RPC error")
                }
                guard let result = message["result"] as? [String: Any] else {
                    throw CodexAppServerError.malformedResponse("missing result for \(method)")
                }
                return result
            }
        }

        _ = try request("initialize", params: ["clientInfo": ["name": "CodexReset", "version": "1.0"]])
        var initialized = try JSONSerialization.data(withJSONObject: ["method": "initialized", "params": [String: Any]()])
        initialized.append(0x0A)
        do { try input.fileHandleForWriting.write(contentsOf: initialized) }
        catch { throw CodexAppServerError.io(error.localizedDescription) }

        let account = try request("account/read")
        let identity = accountIdentity(account)
        guard let accountKey = identity.key else { throw CodexAppServerError.missingAccountIdentity }
        let rates = try request("account/rateLimits/read")
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: JSONSerialization.data(withJSONObject: rates))
        let windows = try response.makeWindows()
        guard !windows.isEmpty else { throw CodexAppServerError.noQuotaWindows }
        return QuotaSnapshot(sampledAt: sampledAt, accountKey: accountKey, plan: identity.plan, windows: windows)
    }
}

private func readMessage(from handle: FileHandle, timeout: TimeInterval) throws -> [String: Any]? {
    let descriptor = handle.fileDescriptor
    let deadline = Date().addingTimeInterval(timeout)
    var line = Data()
    while true {
        let remaining = deadline.timeIntervalSinceNow
        if remaining <= 0 { return nil }
        var descriptorState = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        let milliseconds = Int32(max(1, min(Double(Int32.max), remaining * 1000)))
        let ready = poll(&descriptorState, 1, milliseconds)
        if ready == 0 { return nil }
        if ready < 0 {
            if errno == EINTR { continue }
            throw CodexAppServerError.io(String(cString: strerror(errno)))
        }
        var byte: UInt8 = 0
        let count = Darwin.read(descriptor, &byte, 1)
        if count == 0 { throw CodexAppServerError.io("app-server closed stdout") }
        if count < 0 {
            if errno == EINTR { continue }
            throw CodexAppServerError.io(String(cString: strerror(errno)))
        }
        if byte == 0x0A {
            if line.isEmpty { continue }
            guard let message = try JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                throw CodexAppServerError.malformedResponse("JSON line was not an object")
            }
            return message
        }
        line.append(byte)
        guard line.count <= 1_048_576 else { throw CodexAppServerError.malformedResponse("JSON line exceeded 1 MiB") }
    }
}

private func accountIdentity(_ payload: [String: Any]) -> (key: String?, plan: String?) {
    let account = payload["account"] as? [String: Any] ?? [:]
    let type = (account["type"] as? String ?? "unknown").lowercased()
    let identity = (account["accountId"] as? String ?? account["account_id"] as? String ?? account["email"] as? String)?.lowercased()
    guard let identity, !identity.isEmpty, identity != "unknown" else {
        return (nil, account["planType"] as? String ?? account["plan_type"] as? String)
    }
    let source = "\(type):\(identity)"
    let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
    let plan = account["planType"] as? String ?? account["plan_type"] as? String
    return (digest, plan)
}

private struct RateLimitsResponse: Decodable {
    let rateLimits: RateLimitBucket
    let rateLimitsByLimitId: [String: RateLimitBucket]?

    enum CodingKeys: String, CodingKey {
        case rateLimits
        case rateLimitsByLimitId
        case snake = "rate_limits_by_limit_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rateLimits = try container.decode(RateLimitBucket.self, forKey: .rateLimits)
        rateLimitsByLimitId = try container.decodeIfPresent([String: RateLimitBucket].self, forKey: .rateLimitsByLimitId)
            ?? container.decodeIfPresent([String: RateLimitBucket].self, forKey: .snake)
    }

    func makeWindows() throws -> [QuotaWindow] {
        let mapped = (rateLimitsByLimitId ?? [:]).sorted(by: { $0.key < $1.key })
        let buckets = mapped.isEmpty ? [(rateLimits.limitId ?? "default", rateLimits)] : mapped
        var result: [QuotaWindow] = []
        for (bucketID, bucket) in buckets {
            for (kind, value) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let value, let used = value.usedPercent else { continue }
                guard used.isFinite, (0 ... 100).contains(used) else {
                    throw CodexAppServerError.invalidUsageValue(bucketID)
                }
                let label = "\(bucket.limitName ?? bucket.limitId ?? bucketID) · \(kind.capitalized)"
                result.append(QuotaWindow(
                    id: "\(bucketID):\(kind)", bucketID: bucketID, label: label,
                    usedPercent: used, durationMinutes: value.windowDurationMins,
                    resetsAt: value.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }))
            }
        }
        return result
    }
}

private struct RateLimitBucket: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateWindowPayload?
    let secondary: RateWindowPayload?

    enum CodingKeys: String, CodingKey {
        case limitId, limitName, primary, secondary
        case limitIdSnake = "limit_id"
        case limitNameSnake = "limit_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        limitId = try container.decodeIfPresent(String.self, forKey: .limitId)
            ?? container.decodeIfPresent(String.self, forKey: .limitIdSnake)
        limitName = try container.decodeIfPresent(String.self, forKey: .limitName)
            ?? container.decodeIfPresent(String.self, forKey: .limitNameSnake)
        primary = try container.decodeIfPresent(RateWindowPayload.self, forKey: .primary)
        secondary = try container.decodeIfPresent(RateWindowPayload.self, forKey: .secondary)
    }
}

private struct RateWindowPayload: Decodable {
    let usedPercent: Double?
    let windowDurationMins: Int?
    let resetsAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent, windowDurationMins, resetsAt
        case usedPercentSnake = "used_percent"
        case durationSnake = "window_duration_mins"
        case resetsAtSnake = "resets_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = try container.decodeIfPresent(Double.self, forKey: .usedPercent)
            ?? container.decodeIfPresent(Double.self, forKey: .usedPercentSnake)
        windowDurationMins = try container.decodeIfPresent(Int.self, forKey: .windowDurationMins)
            ?? container.decodeIfPresent(Int.self, forKey: .durationSnake)
        resetsAt = try container.decodeIfPresent(Int.self, forKey: .resetsAt)
            ?? container.decodeIfPresent(Int.self, forKey: .resetsAtSnake)
    }
}
