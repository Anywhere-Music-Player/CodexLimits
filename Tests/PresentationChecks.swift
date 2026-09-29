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
