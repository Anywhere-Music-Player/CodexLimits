import Foundation

enum CodexBrowserLoginError: LocalizedError {
    case unavailable, disconnected, timedOut, failed, invalidResponse, browserUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: return String(localized: "Install ChatGPT or Codex CLI to sign in with your browser.")
        case .disconnected: return String(localized: "The sign-in service stopped. Please try again.")
        case .timedOut: return String(localized: "The request timed out. Please try again.")
        case .failed: return String(localized: "Could not complete the request. Please try again.")
        case .invalidResponse: return String(localized: "The sign-in service returned an unsupported response.")
        case .browserUnavailable: return String(localized: "Could not open your browser. Please try again.")
        }
    }
}

/// The app-server owns OAuth, token refresh, and account-scoped usage requests.
/// No credentials or raw RPC responses are logged or passed to the widget.
@MainActor
final class CodexAppServer {
    private let executable: URL?
    private let home: URL
    private let requestTimeout: TimeInterval
    private let loginTimeout: TimeInterval
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var generation = UUID()
    private var nextID = 0
    private var startup: Task<Void, Error>?
    private var pending: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var loginResults: [String: Bool] = [:]
    private var loginWaiter: (id: String, continuation: CheckedContinuation<Void, Error>)?
    private var loginDeadline: Task<Void, Never>?

    init(executable: URL? = CodexAppServer.findExecutable(), home: URL? = nil,
         requestTimeout: TimeInterval = 45, loginTimeout: TimeInterval = 600) {
        self.executable = executable
        self.requestTimeout = requestTimeout
        self.loginTimeout = loginTimeout
        self.home = home ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexLimits/BrowserAuth", isDirectory: true)
    }

    nonisolated static func findExecutable() -> URL? {
        let paths = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/codex").path,
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return paths.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private func connect() async throws {
        if let startup { return try await startup.value }
        let task = Task { @MainActor [self] in
            guard let executable else { throw CodexBrowserLoginError.unavailable }
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: home.path)
            let child = Process()
            child.executableURL = executable
            child.currentDirectoryURL = home
            // A dedicated home keeps login/logout independent from the user's Codex installation.
            child.environment = ["HOME": NSHomeDirectory(), "PATH": "/usr/bin:/bin", "CODEX_HOME": home.path]
            child.arguments = ["app-server", "--listen", "stdio://", "-c", "cli_auth_credentials_store=\"file\""]
            let stdin = Pipe(), stdout = Pipe()
            child.standardInput = stdin
            child.standardOutput = stdout
            child.standardError = FileHandle.nullDevice
            let connection = generation
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                DispatchQueue.main.async {
                    guard let self, self.generation == connection else { return }
                    if data.isEmpty { self.stop() } else { self.consume(data) }
                }
            }
            child.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self, self.generation == connection else { return }
                    self.stop()
                }
            }
            process = child
            input = stdin.fileHandleForWriting
            output = stdout.fileHandleForReading
            try child.run()
            _ = try await request("initialize", params: ["clientInfo": [
                "name": "codex_limits", "title": "CodexLimits", "version": "1.0"
            ]])
            try send(["method": "initialized", "params": [:]])
        }
        startup = task
        do { try await task.value } catch { stop(); throw error }
    }

    func fetch() async throws -> UsageSnapshot {
        try await connect()
        try Task.checkCancellation()
        let account = try await request("account/read")
        guard let details = account["account"] as? [String: Any], details["type"] as? String == "chatgpt" else {
            throw CodexUsageFetcherError.signedOut
        }
        let result = try await request("account/rateLimits/read")
        return try CodexAppServerUsage.decode(result, fetchedAt: Date())
    }

    func signIn(openBrowser: (URL) -> Bool) async throws {
        do {
            try await performSignIn(openBrowser: openBrowser)
        } catch {
            stop()
            throw error
        }
    }

    private func performSignIn(openBrowser: (URL) -> Bool) async throws {
        try await connect()
        try Task.checkCancellation()
        loginResults.removeAll()
        let result = try await request("account/login/start", params: ["type": "chatgpt"])
        guard let id = result["loginId"] as? String,
              let value = result["authUrl"] as? String,
              let url = Self.authenticationURL(value) else { throw CodexBrowserLoginError.invalidResponse }
        try Task.checkCancellation()
        guard openBrowser(url) else { stop(); throw CodexBrowserLoginError.browserUnavailable }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                if let success = loginResults.removeValue(forKey: id) {
                    if success { continuation.resume() } else { continuation.resume(throwing: CodexBrowserLoginError.failed) }
                    return
                }
                loginWaiter = (id, continuation)
                loginDeadline = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(self?.loginTimeout ?? 600)) } catch { return }
                    self?.stop(error: CodexBrowserLoginError.timedOut)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop(error: CancellationError()) }
        }
        // The app-server writes this file; keep the containing directory and credential file private.
        let auth = home.appendingPathComponent("auth.json")
        if FileManager.default.fileExists(atPath: auth.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: auth.path)
        }
    }

    nonisolated static func authenticationURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "auth.openai.com",
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        return url
    }

    func stop(error: Error = CodexBrowserLoginError.disconnected) {
        generation = UUID()
        output?.readabilityHandler = nil
        try? output?.close()
        try? input?.close()
        output = nil
        input = nil
        let child = process
        process = nil
        child?.terminationHandler = nil
        if child?.isRunning == true { child?.terminate() }
        startup = nil
        buffer.removeAll()
        for deadline in deadlines.values { deadline.cancel() }
        deadlines.removeAll()
        let requests = pending.values
        pending.removeAll()
        for continuation in requests { continuation.resume(throwing: error) }
        loginDeadline?.cancel()
        loginDeadline = nil
        let waiter = loginWaiter
        loginWaiter = nil
        waiter?.continuation.resume(throwing: error)
        loginResults.removeAll()
    }

    private func request(_ method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()); return }
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(self?.requestTimeout ?? 45)) } catch { return }
                    self?.stop(error: CodexBrowserLoginError.timedOut)
                }
                do { try send(["id": id, "method": method, "params": params]) }
                catch { finish(id, result: .failure(error)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(id, result: .failure(CancellationError())) }
        }
    }

    private func send(_ message: [String: Any]) throws {
        guard let input else { throw CodexBrowserLoginError.disconnected }
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.write(contentsOf: data)
    }

    private func finish(_ id: Int, result: Result<[String: Any], Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 4 * 1024 * 1024 else { stop(error: CodexBrowserLoginError.invalidResponse); return }
        while let end = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<end]
            buffer.removeSubrange(...end)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                stop(error: CodexBrowserLoginError.invalidResponse); return
            }
            // This client never starts agent turns or accepts server-initiated work.
            if message["method"] != nil, let id = message["id"] {
                try? send(["id": id, "error": ["code": -32601, "message": "Unsupported request"]])
            } else if let id = message["id"] as? Int {
                if let result = message["result"] as? [String: Any] {
                    finish(id, result: .success(result))
                } else {
                    let error = message["error"] as? [String: Any]
                    let message = (error?["message"] as? String ?? "").lowercased()
                    // Only an explicit authentication error requests a new login. Network and
                    // service failures must not be presented as a lost session.
                    let requiresLogin = message.contains("authentication required")
                        || message.contains("refresh token has expired")
                        || message.contains("refresh token has been revoked")
                    finish(id, result: .failure(requiresLogin
                        ? CodexUsageFetcherError.signedOut : CodexBrowserLoginError.failed))
                }
            } else if message["method"] as? String == "account/login/completed",
                      let params = message["params"] as? [String: Any],
                      let id = params["loginId"] as? String,
                      let success = params["success"] as? Bool {
                if let waiter = loginWaiter, waiter.id == id {
                    loginWaiter = nil
                    loginDeadline?.cancel()
                    loginDeadline = nil
                    if success { waiter.continuation.resume() }
                    else { waiter.continuation.resume(throwing: CodexBrowserLoginError.failed) }
                } else if loginResults.count < 8 {
                    loginResults[id] = success
                }
            }
        }
    }
}

enum CodexAppServerUsage {
    static func decode(_ object: [String: Any], fetchedAt: Date) throws -> UsageSnapshot {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = try JSONDecoder().decode(Response.self, from: data)
        let limits: Limits
        if let buckets = response.rateLimitsByLimitId, !buckets.isEmpty {
            guard let codex = buckets["codex"] else { throw CodexBrowserLoginError.invalidResponse }
            limits = codex
        } else {
            guard let legacy = response.rateLimits, legacy.limitId == nil || legacy.limitId == "codex" else {
                throw CodexBrowserLoginError.invalidResponse
            }
            limits = legacy
        }
        let windows = [limits.primary, limits.secondary].compactMap { $0 }
        func window(long: Bool) -> UsageWindow? {
            guard let source = windows.first(where: {
                guard let minutes = $0.windowDurationMins, minutes > 0 else { return false }
                return (minutes >= 24 * 60) == long
            }), let minutes = source.windowDurationMins else { return nil }
            return UsageWindow(kind: long ? .secondary : .primary, usedPercent: source.usedPercent,
                               resetAt: source.resetsAt.map(Date.init(timeIntervalSince1970:)),
                               limitWindowSeconds: minutes * 60)
        }
        return UsageSnapshot(fetchedAt: fetchedAt, primaryWindow: window(long: false), secondaryWindow: window(long: true),
                             resetCredits: response.rateLimitResetCredits.map {
            UsageResetCredits(availableCount: max(0, $0.availableCount), credits: $0.credits?.filter {
                $0.status == "available" && $0.resetType == "codexRateLimits"
            }.map { UsageResetCredit(id: $0.id, expiresAt: $0.expiresAt.map(Date.init(timeIntervalSince1970:))) })
        })
    }

    private struct Response: Decodable {
        let rateLimits: Limits?
        let rateLimitsByLimitId: [String: Limits]?
        let rateLimitResetCredits: ResetCredits?

        private enum CodingKeys: String, CodingKey {
            case rateLimits, rateLimitsByLimitId, rateLimitResetCredits
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rateLimits = try container.decodeIfPresent(Limits.self, forKey: .rateLimits)
            rateLimitsByLimitId = try container.decodeIfPresent([String: Limits].self, forKey: .rateLimitsByLimitId)
            // Optional reset metadata must not prevent the main usage windows from updating.
            rateLimitResetCredits = try? container.decodeIfPresent(ResetCredits.self, forKey: .rateLimitResetCredits)
        }
    }
    private struct Limits: Decodable {
        let limitId: String?
        let primary: Window?
        let secondary: Window?
    }
    private struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Double?
        let resetsAt: TimeInterval?
    }
    private struct ResetCredits: Decodable {
        let availableCount: Int
        let credits: [Credit]?
    }
    private struct Credit: Decodable {
        let id: String
        let status: String
        let resetType: String
        let expiresAt: TimeInterval?
    }
}
