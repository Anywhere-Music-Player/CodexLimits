import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(state: .shared))
            let window = NSWindow(contentViewController: controller)
            window.title = String(localized: "window.settings.title")
            window.identifier = NSUserInterfaceItemIdentifier("settings")
            window.styleMask = [.titled, .closable, .resizable]
            window.setContentSize(NSSize(width: 680, height: 640))
            window.minSize = NSSize(width: 560, height: 520)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
