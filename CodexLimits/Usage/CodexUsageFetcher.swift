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
        let windows = [
            rate_limit?.primary_window,
            rate_limit?.secondary_window
        ].compactMap { $0 }
        let primary = makeWindow(
            kind: .primary,
            source: windows.first { ($0.limit_window_seconds ?? 0) < Self.longWindowThreshold }
        )
        let secondary = makeWindow(
            kind: .secondary,
            source: windows.first { ($0.limit_window_seconds ?? 0) >= Self.longWindowThreshold }
        )
        return UsageSnapshot(
            fetchedAt: fetchedAt,
            primaryWindow: primary,
            secondaryWindow: secondary
        )
    }

    private static let longWindowThreshold: TimeInterval = 24 * 60 * 60

    private func makeWindow(kind: UsageWindowKind, source: RateLimit.Window?) -> UsageWindow? {
        guard let source,
              let usedPercent = source.used_percent,
              let limitSeconds = source.limit_window_seconds else {
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
    case signedOut
    case serviceUnavailable
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return String(localized: "error.parseFailed")
        case .signedOut:
            return String(localized: "content.notFetched")
        case .serviceUnavailable:
            return "ChatGPT is temporarily unavailable. Your saved usage data is unchanged."
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
    func fetch() async throws -> UsageSnapshot {
        let cookies = await websiteCookies()
        let accessToken = try await fetchAccessToken(using: cookies)

        guard var components = URLComponents(
            string: "https://chatgpt.com/backend-api/wham/usage"
        ) else {
            throw CodexUsageFetcherError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "_codex_limits", value: String(Date().timeIntervalSince1970))
        ]
        guard let url = components.url else {
            throw CodexUsageFetcherError.invalidResponse
        }

        var request = makeRequest(url: url, cookies: cookies)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await response(for: request)

        switch response.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw CodexUsageFetcherError.signedOut
        case 500...599:
            throw CodexUsageFetcherError.serviceUnavailable
        default:
            throw CodexUsageFetcherError.scriptFailed("HTTP \(response.statusCode)")
        }

        if Self.isUpstreamFailure(data) {
            throw CodexUsageFetcherError.serviceUnavailable
        }
        guard let usage = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else {
            throw CodexUsageFetcherError.invalidResponse
        }
        return usage.makeSnapshot(fetchedAt: Date())
    }

    @MainActor
    private func websiteCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func fetchAccessToken(using cookies: [HTTPCookie]) async throws -> String {
        let endpointStrings = [
            "https://chatgpt.com/api/auth/session",
            "https://chatgpt.com/backend-api/auth/session"
        ]
        var encounteredTemporaryFailure = false

        for endpointString in endpointStrings {
            guard let url = URL(string: endpointString) else { continue }
            let request = makeRequest(url: url, cookies: cookies)

            let data: Data
            let response: HTTPURLResponse
            do {
                (data, response) = try await self.response(for: request)
            } catch CodexUsageFetcherError.serviceUnavailable {
                encounteredTemporaryFailure = true
                continue
            }

            switch response.statusCode {
            case 200..<300:
                if Self.isUpstreamFailure(data) {
                    encounteredTemporaryFailure = true
                    continue
                }
                guard let object = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any] else {
                    encounteredTemporaryFailure = true
                    continue
                }
                if let token = (object["accessToken"] ?? object["access_token"]) as? String,
                   !token.isEmpty {
                    return token
                }
                throw CodexUsageFetcherError.signedOut
            case 401, 403:
                continue
            case 404:
                continue
            case 500...599:
                encounteredTemporaryFailure = true
            default:
                encounteredTemporaryFailure = true
            }
        }

        if encounteredTemporaryFailure {
            throw CodexUsageFetcherError.serviceUnavailable
        }
        throw CodexUsageFetcherError.signedOut
    }

    private func makeRequest(url: URL, cookies: [HTTPCookie]) -> URLRequest {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 30
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("https://chatgpt.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                + "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                + "Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        let applicableCookies = cookies.filter { cookie in
            guard let host = url.host?.lowercased() else { return false }
            let domain = cookie.domain
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            return host == domain || host.hasSuffix(".\(domain)")
        }
        HTTPCookie.requestHeaderFields(with: applicableCookies).forEach {
            request.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        return request
    }

    private func response(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw CodexUsageFetcherError.invalidResponse
            }
            return (data, httpResponse)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as CodexUsageFetcherError {
            throw error
        } catch {
            throw CodexUsageFetcherError.serviceUnavailable
        }
    }

    private static func isUpstreamFailure(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8)?.lowercased() else {
            return false
        }
        return text.contains("upstream connect error")
            || text.contains("connection timeout")
            || text.contains("remote connection failure")
    }
}
