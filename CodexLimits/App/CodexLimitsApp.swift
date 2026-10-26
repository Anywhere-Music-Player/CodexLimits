import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchAtLogin.shared.enableByDefaultIfNeeded()
        menuBarController = MenuBarController(state: .shared)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.shutDown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let appURLs = urls.filter { $0.scheme == AppConfiguration.urlScheme }
        if appURLs.contains(where: { $0.host == "about" }) {
            AboutWindowController.shared.show()
        } else if !appURLs.isEmpty {
            SettingsWindowController.shared.show()
        }
    }
}

@main
struct CodexLimitsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commandsRemoved()
    }
}
