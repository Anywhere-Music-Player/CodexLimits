import AppKit
import Foundation

/// Interactive smoke test. Uses a separate sandbox container and never prints credentials.
@main
struct BrowserLoginProbe {
    @MainActor
    static func main() async {
        _ = NSApplication.shared
        let service = CodexAppServer()
        do {
            print("Opening official Codex sign-in in your browser. Complete sign-in there.")
            fflush(stdout)
            try await service.signIn { NSWorkspace.shared.open($0) }
            print("Browser sign-in completed.")
            let snapshot = try await service.fetch()
            print("Usage read succeeded. Available windows: \([snapshot.primaryWindow, snapshot.secondaryWindow].compactMap { $0 }.count).")
            service.stop()
            let restored = CodexAppServer()
            defer { restored.stop() }
            let afterRestart = try await restored.fetch()
            print("Session survived service restart. Available windows: \([afterRestart.primaryWindow, afterRestart.secondaryWindow].compactMap { $0 }.count).")
            print("Browser authentication smoke test passed.")
        } catch {
            service.stop()
            print("Browser authentication smoke test failed: \(error.localizedDescription)")
            exit(1)
        }
    }
}
