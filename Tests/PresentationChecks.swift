import AppKit
import SwiftUI
import WidgetKit

@main
struct PresentationChecks {
    @MainActor
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let session = try CodexUsageSession(object: [
            "accessToken": "test-token", "account": ["id": "test-account"]
        ])
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        session.authorize(&request)
        check(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token",
              "Usage requests must retain session authentication")
        check(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "test-account",
              "Usage requests must target the authenticated account")
        let switchedSession = try CodexUsageSession(object: [
            "access_token": "new-token", "account": ["id": "new-account"]
        ])
        switchedSession.authorize(&request)
        check(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "new-account"
              && request.value(forHTTPHeaderField: "Authorization") == "Bearer new-token",
              "Switching sessions must replace both account and token")
        for account: [String: Any] in [[:], ["id": ""], ["id": "  "], ["id": 123]] {
            do {
                _ = try CodexUsageSession(object: ["accessToken": "test-token", "account": account])
                check(false, "Missing account identity must not allow an unscoped usage request")
            } catch CodexUsageFetcherError.invalidResponse {
                check(true, "Invalid account identity rejected")
            }
        }
        do {
            _ = try CodexUsageSession(object: ["account": ["id": "test-account"]])
            check(false, "Missing token must require sign in")
        } catch CodexUsageFetcherError.signedOut {
            check(true, "Missing authentication rejected")
        }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let weekly = UsageWindow(kind: .secondary, usedPercent: 90,
                                 resetAt: now.addingTimeInterval(3 * 86400 + 20 * 3600),
                                 limitWindowSeconds: 604800)
        let short = UsageWindow(kind: .primary, usedPercent: 28,
                                resetAt: now.addingTimeInterval(7200), limitWindowSeconds: 18000)
        let zero = UsageWindow(kind: .secondary, usedPercent: 100, resetAt: now, limitWindowSeconds: 604800)
        let proResponse = #"{"rate_limit":{"primary_window":{"used_percent":90,"limit_window_seconds":604800,"reset_at":1800331200},"secondary_window":null}}"#
        let pro = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(proResponse.utf8)).makeSnapshot(fetchedAt: now)
        check(pro.primaryWindow == nil, "A weekly primary API window must not become a 5-hour limit")
        check(pro.secondaryWindow?.remainingPercent == 10, "Weekly usage must survive classification")
        let absentResponse = #"{"rate_limit":{"primary_window":null,"secondary_window":null}}"#
        let absent = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(absentResponse.utf8)).makeSnapshot(fetchedAt: now)
        check(absent.primaryWindow == nil && absent.secondaryWindow == nil, "Missing data must remain missing")
        check(absent.resetCredits == nil, "Missing reset information must not become zero available resets")
        let summaryResponse = #"{"rate_limit_reset_credits":{"available_count":3}}"#
        let summary = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(summaryResponse.utf8))
            .makeSnapshot(fetchedAt: now)
        check(summary.resetCredits?.availableCount == 3 && summary.resetCredits?.credits == nil,
              "A usage summary must preserve the count when reset details fail")
        let malformedSummaryResponse = #"{"rate_limit":{"primary_window":{"used_percent":90,"limit_window_seconds":604800}},"rate_limit_reset_credits":{"available_count":"unknown"}}"#
        let malformedSummary = try JSONDecoder().decode(CodexUsageResponse.self, from: Data(malformedSummaryResponse.utf8))
            .makeSnapshot(fetchedAt: now)
        check(malformedSummary.secondaryWindow?.remainingPercent == 10 && malformedSummary.resetCredits == nil,
              "Malformed optional reset metadata must not break usage or fabricate an available count")
        let resetResponse = #"{"available_count":5,"credits":[{"id":"later","status":"available","expires_at":"2026-10-29T18:56:58Z"},{"id":"first","status":"available","expires_at":"2026-10-05T04:19:06.429749Z"},{"id":"no-date","status":"available","expires_at":null},{"id":"used","status":"redeemed","expires_at":"2026-10-01T00:00:00Z"}]}"#
        let resets = try JSONDecoder().decode(CodexResetCreditsResponse.self, from: Data(resetResponse.utf8))
            .makeResetCredits()
        let beforeExpiration = Date(timeIntervalSince1970: 1_791_100_000)
        check(resets.availableCount(at: beforeExpiration) == 5,
              "The server count must remain authoritative when the detail list is capped")
        check(resets.availableCredits(at: beforeExpiration).map(\.id) == ["first", "later", "no-date"],
              "Only available resets should appear, ordered by nearest expiration with undated resets last")
        let firstExpiration = resets.credits!.first { $0.id == "first" }!.expiresAt!
        check(abs(firstExpiration.timeIntervalSince1970 - 1_791_173_946.429749) < 0.001,
              "The API's UTC timestamp must preserve its exact expiration instant")
        check(resets.availableCount(at: firstExpiration) == 4
              && !resets.availableCredits(at: firstExpiration).contains { $0.id == "first" },
              "A cached reset must stop being available at its expiration without waiting for a fetch")
        let invalidResetResponse = #"{"available_count":1,"credits":[{"id":"invalid","status":"available","expires_at":"not-a-date"}]}"#
        do {
            _ = try JSONDecoder().decode(CodexResetCreditsResponse.self, from: Data(invalidResetResponse.utf8))
                .makeResetCredits()
            check(false, "A malformed timestamp must not be presented as a reset without an expiration")
        } catch CodexUsageFetcherError.invalidResponse {
            check(true, "Malformed reset expiration rejected")
        }
        let noResets = try JSONDecoder().decode(CodexResetCreditsResponse.self,
            from: Data(#"{"available_count":0,"credits":[]}"#.utf8)).makeResetCredits()
        check(noResets.availableCount(at: now) == 0 && noResets.credits == [],
              "A confirmed empty response must be distinguishable from unavailable details")
        let oldSnapshot = try JSONDecoder().decode(UsageSnapshot.self,
            from: Data(#"{"fetchedAt":0,"primaryWindow":null,"secondaryWindow":null}"#.utf8))
        check(oldSnapshot.resetCredits == nil, "Snapshots written before reset support must remain readable")
        var resetSnapshot = pro
        resetSnapshot.resetCredits = resets
        let savedResetSnapshot = try JSONDecoder().decode(UsageSnapshot.self,
            from: JSONEncoder().encode(resetSnapshot))
        check(savedResetSnapshot == resetSnapshot, "Reset details must survive snapshot persistence")
        let kyiv = TimeZone(identifier: "Europe/Kyiv")!
        let ukrainian = Locale(identifier: "uk_UA")
        let localExpiration = ResetExpiration.text(for: firstExpiration, locale: ukrainian, timeZone: kyiv)
        check(localExpiration.contains("07:19:06") && localExpiration.contains("2026")
              && localExpiration.contains("жовтня") && localExpiration.contains("понеділок"),
              "Expiration must include a localized weekday, full date, year, and exact local time")
        let winterExpiration = resets.credits!.first { $0.id == "later" }!.expiresAt!
        check(ResetExpiration.text(for: winterExpiration, locale: ukrainian, timeZone: kyiv).contains("20:56:58"),
              "Kyiv expiration times must use the UTC offset on the expiration date, including DST changes")
        check(ResetExpiration.text(for: firstExpiration, locale: Locale(identifier: "en_US"), timeZone: kyiv)
                .contains("AM"), "Expiration formatting must respect a 12-hour locale")
        check(ResetExpiration.text(for: firstExpiration, locale: ukrainian, timeZone: TimeZone(secondsFromGMT: 0)!)
                .contains("04:19:06"), "Expiration formatting must use the selected time zone")
        let shortExpiration = ResetExpiration.shortText(for: firstExpiration, locale: ukrainian, timeZone: kyiv)
        _ = NSApplication.shared
        let resetsMenu = NSMenu()
        func updateResetsMenu(_ credits: UsageResetCredits?, _ status: UsageStatus = .ready,
                              at date: Date = beforeExpiration) {
            resetsMenu.removeAllItems()
            MenuBarPresentation.resetCreditsSection(resetCredits: credits,
                usageStatus: status, date: date, locale: ukrainian, timeZone: kyiv)
                .forEach { resetsMenu.addItem($0) }
            resetsMenu.update()
        }
        updateResetsMenu(resets)
        check(resetsMenu.items.first?.title.hasSuffix("5") == true
              && resetsMenu.items.last?.isSeparatorItem == true
              && resetsMenu.items.allSatisfy { $0.submenu == nil },
              "Resets must form a top-level section with the count first and a divider before existing actions")
        check(resetsMenu.items.contains {
            $0.title == shortExpiration && $0.title.contains("07:19") && $0.title.count < 30
                && $0.toolTip == localExpiration
        } && !resetsMenu.items.contains { $0.title == String(localized: "Expiration dates in your local time") },
              "The menu must show compact local dates, retain full precision in tooltips, and omit the explanatory row")
        updateResetsMenu(resets, at: firstExpiration)
        check(resetsMenu.items.first?.title.hasSuffix("4") == true
              && !resetsMenu.items.contains { $0.title == shortExpiration },
              "Reopening the menu after expiration must remove the expired reset and reduce the count")
        updateResetsMenu(resets, .signedOut)
        check(resetsMenu.items.filter { !$0.isSeparatorItem }.map(\.title)
              == [String(localized: "Usage limit resets"), String(localized: "Sign in to fetch usage")],
              "A signed-out menu must hide the cached count and dates")
        updateResetsMenu(nil)
        check(resetsMenu.items.first?.title.hasSuffix("0") == false
              && resetsMenu.items.contains { $0.title == String(localized: "Reset information is unavailable. Try refreshing.") },
              "Unknown reset data must not appear as zero available resets in the menu")
        updateResetsMenu(resets, .failed)
        check(resetsMenu.items.contains { $0.title == String(localized: "Refresh failed") },
              "Cached reset details must show the refresh failure")
        updateResetsMenu(noResets)
        check(resetsMenu.items.first?.title.hasSuffix("0") == true && resetsMenu.items.count == 2,
              "Zero resets must show only the count and section divider")
        updateResetsMenu(resets)
        check(resetsMenu.items.contains { $0.title == shortExpiration },
              "Reset details must reappear after an empty response")
        func title(_ windows: [UsageWindow], _ percentages: Bool, _ progress: Bool) -> NSAttributedString {
            MenuBarPresentation.title(windows: windows, showsPercentages: percentages,
                                      showsProgress: progress, textSize: .large)
        }
        func attachments(_ text: NSAttributedString) -> Int {
            var result = 0
            text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
                if value != nil { result += 1 }
            }
            return result
        }
        check(title([weekly], true, false).string == "10%", "Progress off must be text only without missing placeholders")
        check(attachments(title([weekly], true, false)) == 0, "Progress off must remove the meter")
        check(attachments(title([weekly], true, true)) == 1, "Weekly only must have one meter")
        check(!title([weekly], true, true).string.contains("/"), "Weekly only must not have a separator")
        check(attachments(title([short, weekly], true, true)) == 2, "Two limits must have two meters")
        check(title([short, weekly], true, false).string == "72% / 10%", "Both percentages must preserve their order")
        check(attachments(title([weekly], false, true)) == 1, "Progress-only mode must work")
        check(!title([weekly], false, true).string.contains("%"), "Progress-only mode must hide percentages")
        check(title([short, weekly], false, false).length == 0, "Icon mode must have no title")
        check(title([], true, true).length == 0, "No data must have no fabricated usage")
        check(title([zero], true, false).string == "0%", "An exhausted limit must remain visible")
        check(ResetCountdown.text(resetAt: now, relativeTo: now) == String(localized: "Reset due"), "Reset boundary")
        check(ResetCountdown.text(resetAt: now.addingTimeInterval(-1), relativeTo: now) == String(localized: "Reset due"), "Past reset")
        check(!ResetCountdown.text(resetAt: now.addingTimeInterval(1), relativeTo: now).contains("-"), "Sub-minute duration must not go negative")
        check(ResetCountdown.text(resetAt: weekly.resetAt!, relativeTo: now) != ResetCountdown.text(resetAt: weekly.resetAt!, relativeTo: now.addingTimeInterval(3600)), "Countdown must advance with entry date")
        check(WidgetLayoutStyle(rawValue: "themeOne") == .themeOne && WidgetLayoutStyle(rawValue: "themeTwo") == .themeTwo, "Existing theme preferences must survive")
        let suiteName = "CodexLimits.StatusChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        check(UsageStatusStore.load(hasSnapshot: false, defaults: defaults) == .signedOut,
              "A fresh widget must request sign in")
        check(UsageStatusStore.load(hasSnapshot: true, defaults: defaults) == .ready,
              "Existing snapshots must migrate without a fabricated error")
        UsageStatusStore.save(.signedOut, defaults: defaults)
        check(UsageStatusStore.load(hasSnapshot: true, defaults: defaults) == .signedOut,
              "Cached usage must not hide expired authentication")
        UsageStatusStore.save(.failed, defaults: defaults)
        check(UsageStatusStore.load(hasSnapshot: true, defaults: defaults) == .failed,
              "Refresh failure must survive a widget reload")
        UsageStatusStore.save(.ready, defaults: defaults)
        check(UsageStatusStore.load(hasSnapshot: true, defaults: defaults).message == nil,
              "Successful refresh must clear the warning")
        check(UsageStatus.signedOut.message != UsageStatus.failed.message,
              "Authentication and refresh failure must be distinguishable")
        print("Passed \(checks) presentation checks")

        guard let output = ProcessInfo.processInfo.environment["CODEX_LIMITS_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        let snapshots: [(String, UsageSnapshot?)] = [
            ("weekly", UsageSnapshot(fetchedAt: now, primaryWindow: nil, secondaryWindow: weekly)),
            ("both", UsageSnapshot(fetchedAt: now, primaryWindow: short, secondaryWindow: weekly)),
            ("zero", UsageSnapshot(fetchedAt: now, primaryWindow: nil, secondaryWindow: zero)),
            ("empty", nil)
        ]
        for dark in [false, true] {
            for (name, snapshot) in snapshots {
                let board = VStack(alignment: .leading, spacing: 16) {
                    ForEach(WidgetLayoutStyle.allCases) { style in
                        HStack(spacing: 16) {
                            Text(style.title).frame(width: 80, alignment: .leading)
                            CodexWidgetContentView(snapshot: snapshot, family: .medium, style: style, date: now)
                                .frame(width: 344, height: 170).clipShape(RoundedRectangle(cornerRadius: 24))
                            CodexWidgetContentView(snapshot: snapshot, family: .small, style: style, date: now)
                                .frame(width: 170, height: 170).clipShape(RoundedRectangle(cornerRadius: 24))
                        }
                    }
                }
                .padding(20)
                .background(dark ? Color.gray.opacity(0.5) : Color.gray.opacity(0.15))
                .environment(\.colorScheme, dark ? .dark : .light)
                .environment(\.widgetRenderingMode, .fullColor)
                let renderer = ImageRenderer(content: board)
                renderer.scale = 2
                guard let image = renderer.cgImage else { fatalError("Widget render failed") }
                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: "\(output)/\(name)-\(dark ? "dark" : "light").png"))
            }
        }
        for status in [UsageStatus.signedOut, .failed] {
            let board = VStack(spacing: 16) {
                ForEach(WidgetLayoutStyle.allCases) { style in
                    HStack(spacing: 16) {
                        CodexWidgetContentView(snapshot: snapshots[1].1, family: .small,
                                               style: style, date: now, usageStatus: status)
                            .frame(width: 170, height: 170)
                        CodexWidgetContentView(snapshot: snapshots[1].1, family: .medium,
                                               style: style, date: now, usageStatus: status)
                            .frame(width: 344, height: 170)
                        CodexWidgetContentView(snapshot: nil, family: .small,
                                               style: style, date: now, usageStatus: status)
                            .frame(width: 170, height: 170)
                    }
                }
            }
            .padding(20)
            .environment(\.colorScheme, .dark)
            .environment(\.widgetRenderingMode, .fullColor)
            let renderer = ImageRenderer(content: board)
            renderer.scale = 2
            guard let image = renderer.cgImage else { fatalError("Status render failed") }
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "\(output)/status-\(status.rawValue).png"))
        }
        let state = AppState(startsServices: false)
        let previewResets = UsageResetCredits(availableCount: 3, credits: [
            UsageResetCredit(id: "first", expiresAt: firstExpiration),
            UsageResetCredit(id: "second", expiresAt: Date(timeIntervalSince1970: 1_792_701_403)),
            UsageResetCredit(id: "third", expiresAt: winterExpiration)
        ])
        for dark in [false, true] {
            NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            for localeID in ["en_US", "uk_UA", "de_DE"] {
                let panel = UsageResetCreditsPanel(resetCredits: previewResets, usageStatus: .ready, date: beforeExpiration)
                    .environment(\.locale, Locale(identifier: localeID))
                    .environment(\.timeZone, kyiv)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .padding(24)
                    .frame(width: 540)
                    .background(Color(nsColor: .windowBackgroundColor))
                let renderer = ImageRenderer(content: panel)
                renderer.scale = 2
                guard let image = renderer.cgImage else { fatalError("Reset panel render failed") }
                try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: "\(output)/resets-\(localeID)-\(dark ? "dark" : "light").png"))
            }
        }
        for section in [SettingsSection.themes, .menuBar, .general, .colors, .account] {
            let root = SettingsView(state: state, selectedSection: section)
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.setContentSize(NSSize(width: 980, height: 720))
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let view = controller.view
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Settings render failed") }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!
                .write(to: URL(fileURLWithPath: "\(output)/settings-\(section.rawValue).png"))
        }
        print("Rendered widget states and settings to \(output)")
    }
}
