import Foundation
import WebKit

private struct CodexUsageResponse: Codable {
    struct RateLimit: Codable {
        struct Window: Codable {
            let used_percent: Double?
            let limit_window_seconds: Double?
            let reset_after_seconds: Double?
            let reset_at: TimeInterval?
        }

        let primary_window: Window?
        let secondary_window: Window?
    }

    let rate_limit: RateLimit?

    func makeSnapshot(fetchedAt: Date) -> UsageSnapshot {
        let primary = makeWindow(kind: .primary, source: rate_limit?.primary_window)
        let secondary = primary?.isLongerThanWeekly == true
            ? nil
            : makeWindow(kind: .secondary, source: rate_limit?.secondary_window)
        return UsageSnapshot(
            fetchedAt: fetchedAt,
            primaryWindow: primary,
            secondaryWindow: secondary
        )
    }

    private func makeWindow(kind: UsageWindowKind, source: RateLimit.Window?) -> UsageWindow? {
        guard let source,
              let usedPercent = source.used_percent,
              let limitSeconds = source.limit_window_seconds else {
            return nil
        }
        if usedPercent == 0,
           let resetAfterSeconds = source.reset_after_seconds,
           abs(limitSeconds - resetAfterSeconds) <= 0.001 {
            return nil
        }
        return UsageWindow(
            kind: kind,
            usedPercent: usedPercent,
            resetAt: source.reset_at.map { Date(timeIntervalSince1970: $0) },
            limitWindowSeconds: limitSeconds
        )
    }
}

enum CodexUsageFetcherError: LocalizedError {
    case invalidResponse
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "error.parseFailed")
        case .scriptFailed(let message):
            return String(
                format: String(localized: "error.fetchFailed"),
                message
            )
        }
    }
}

struct CodexUsageFetcher {
    @MainActor
    func fetch(using webView: WKWebView) async throws -> UsageSnapshot {
        let json = try await runJSONScript(Self.usageScript, webView: webView)
        guard let data = json.data(using: .utf8),
              let response = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else {
            throw CodexUsageFetcherError.invalidResponse
        }
        return response.makeSnapshot(fetchedAt: Date())
    }

    @MainActor
    func hasValidSession(using webView: WKWebView) async -> Bool {
        do {
            let value = try await evaluate(Self.loginCheckScript, webView: webView)
            return value as? Bool ?? false
        } catch {
            return false
        }
    }

    @MainActor
    private func runJSONScript(_ script: String, webView: WKWebView) async throws -> String {
        let value = try await evaluate(script, webView: webView)
        guard let json = value as? String else {
            throw CodexUsageFetcherError.invalidResponse
        }
        if let data = json.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let message = object["__error"] as? String {
            throw CodexUsageFetcherError.scriptFailed(message)
        }
        return json
    }

    @MainActor
    private func evaluate(_ script: String, webView: WKWebView) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: CodexUsageFetcherError.scriptFailed(error.localizedDescription))
                }
            }
        }
    }

    private static let sessionScript = """
        async function fetchSession() {
          let response = await fetch("/api/auth/session", { credentials: "include" });
          if (response.ok) return await response.json();
          response = await fetch("/backend-api/auth/session", { credentials: "include" });
          if (response.ok) return await response.json();
          return null;
        }
    """

    private static let usageScript = """
    return (async () => {
      try {
        \(sessionScript)
        const session = await fetchSession();
        const accessToken = session && (session.accessToken || session.access_token);
        if (!accessToken) throw new Error("Missing access token");
        const response = await fetch("https://chatgpt.com/backend-api/wham/usage", {
          method: "GET",
          credentials: "include",
          headers: {
            "Accept": "application/json",
            "Authorization": "Bearer " + accessToken
          }
        });
        if (!response.ok) throw new Error("HTTP " + response.status);
        return JSON.stringify(await response.json());
      } catch (error) {
        const message = error && error.message ? error.message : String(error);
        return JSON.stringify({ "__error": message });
      }
    })();
    """

    private static let loginCheckScript = """
    return (async () => {
      try {
        \(sessionScript)
        const session = await fetchSession();
        return !!(session && (session.accessToken || session.access_token));
      } catch (error) {
        return false;
      }
    })();
    """
}
