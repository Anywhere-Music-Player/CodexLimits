import AppKit
import Foundation

@main
struct BrowserAuthChecks {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            count += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("codexlimits-browser-tests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        func client(_ scenario: String) throws -> (CodexAppServer, URL) {
            let home = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try scenario.write(to: home.appendingPathComponent("scenario"), atomically: true, encoding: .utf8)
            return (CodexAppServer(executable: executable, home: home, requestTimeout: 2, loginTimeout: 0.25), home)
        }
        func expectFailure(_ client: CodexAppServer, _ operation: () async throws -> Void) async {
            do { try await operation(); preconditionFailure("Expected failure") }
            catch { count += 1 }
            client.stop()
        }
        check(CodexAppServer.authenticationURL("https://auth.openai.com/oauth/authorize") != nil, "OpenAI URL accepted")
        for url in ["http://auth.openai.com/login", "https://auth.openai.com.evil.test/", "https://user@auth.openai.com/", "file:///tmp/login"] {
            check(CodexAppServer.authenticationURL(url) == nil, "Unsafe login URL rejected")
        }
        let (service, home) = try client("success")
        do { _ = try await service.fetch(); preconditionFailure("Fresh client must be signed out") }
        catch CodexUsageFetcherError.signedOut { count += 1 }
        var opened = false
        try await service.signIn { _ in opened = true; return true }
        check(opened, "Login opens the browser")
        let usage = try await service.fetch()
        check(usage.primaryWindow == nil && usage.secondaryWindow?.remainingPercent == 68,
              "Weekly-only usage from the codex bucket must map correctly")
        service.stop()
        let restarted = CodexAppServer(executable: executable, home: home)
        let restored = try await restarted.fetch()
        check(restored.secondaryWindow?.remainingPercent == 68, "Login survives process restart")
        restarted.stop()
        let attributes = try FileManager.default.attributesOfItem(atPath: home.path)
        check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700, "Auth directory is private")
        for scenario in ["timeout", "crash", "malformed"] {
            let (service, _) = try client(scenario)
            await expectFailure(service) { _ = try await service.fetch() }
        }
        for scenario in ["failed-login", "unsafe-url", "unrelated-login"] {
            let (service, _) = try client(scenario)
            await expectFailure(service) { try await service.signIn { _ in scenario != "unsafe-url" } }
        }
        let (noBrowser, _) = try client("pending")
        await expectFailure(noBrowser) { try await noBrowser.signIn { _ in false } }
        let (cancelled, _) = try client("pending")
        let task = Task { try await cancelled.signIn { _ in true } }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { try await task.value; preconditionFailure("Cancelled login must not succeed") }
        catch is CancellationError { count += 1 }
        cancelled.stop()
        let (serverError, errorHome) = try client("server-error")
        FileManager.default.createFile(atPath: errorHome.appendingPathComponent("signed-in").path, contents: Data())
        do { _ = try await serverError.fetch(); preconditionFailure("Expected server failure") }
        catch {
            check(!error.localizedDescription.contains("Sensitive"), "Raw RPC errors must not leak to UI")
        }
        serverError.stop()
        let now = Date()
        let data: [String: Any] = ["rateLimits": ["primary": ["usedPercent": 20, "windowDurationMins": 300]],
                                  "rateLimitResetCredits": ["availableCount": 2, "credits": [
                                    ["id": "a", "status": "available", "resetType": "codexRateLimits", "expiresAt": 1800000000],
                                    ["id": "b", "status": "redeemed", "resetType": "codexRateLimits"]]]]
        let decoded = try CodexAppServerUsage.decode(data, fetchedAt: now)
        check(decoded.primaryWindow?.remainingPercent == 80 && decoded.secondaryWindow == nil, "5-hour mapping")
        check(decoded.resetCredits?.availableCount == 2 && decoded.resetCredits?.credits?.count == 1, "Reset count and details")
        let malformedOptional = try CodexAppServerUsage.decode(["rateLimits": ["primary": ["usedPercent": 20, "windowDurationMins": 300]], "rateLimitResetCredits": "unsupported"], fetchedAt: now)
        check(malformedOptional.primaryWindow?.remainingPercent == 80 && malformedOptional.resetCredits == nil,
              "Invalid optional reset metadata must not break usage")
        let noDetails = try CodexAppServerUsage.decode(["rateLimits": [:], "rateLimitResetCredits": ["availableCount": 3]], fetchedAt: now)
        check(noDetails.resetCredits?.credits == nil, "Missing reset details remain unknown")
        do {
            _ = try CodexAppServerUsage.decode(["rateLimitsByLimitId": ["other": [:]], "rateLimits": [:]], fetchedAt: now)
            preconditionFailure("Must not show a different quota bucket")
        } catch { count += 1 }
        print("Passed \(count) browser authentication checks")
    }
}
