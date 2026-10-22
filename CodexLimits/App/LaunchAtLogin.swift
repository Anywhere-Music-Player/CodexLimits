import Combine
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()
    @Published private(set) var status: SMAppService.Status = .notRegistered
    @Published private(set) var errorMessage: String?

    private let defaults: UserDefaults
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let initializedKey = "CodexLimits.launchAtLoginInitialized"

    init(
        defaults: UserDefaults = .standard,
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() }
    ) {
        self.defaults = defaults
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        refresh()
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }

    func enableByDefaultIfNeeded() {
        guard !defaults.bool(forKey: initializedKey) else { refresh(); return }
        // Apply the default once, preserving subsequent changes in System Settings.
        defaults.set(true, forKey: initializedKey)
        refresh()
        if status == .notRegistered { setEnabled(true) }
    }

    func refresh() { status = readStatus() }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: initializedKey)
        errorMessage = nil
        refresh()
        do {
            if enabled && !isEnabled { try register() }
            if !enabled && isEnabled { try unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}
