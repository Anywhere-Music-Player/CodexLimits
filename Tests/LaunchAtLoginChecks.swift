import Foundation
import ServiceManagement

@main
struct LaunchAtLoginChecks {
    @MainActor static func main() {
        let suite = "CodexLimits.LoginChecks.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var status = SMAppService.Status.notRegistered
        var registrations = 0
        var fail = false
        let service = LaunchAtLogin(defaults: defaults, readStatus: { status }, register: {
            registrations += 1
            if fail { throw NSError(domain: "Test", code: 1) }
            status = .enabled
        }, unregister: { status = .notRegistered })
        var count = 0
        func check(_ condition: Bool) { precondition(condition); count += 1 }
        service.enableByDefaultIfNeeded()
        check(service.isEnabled && registrations == 1)
        service.enableByDefaultIfNeeded()
        check(registrations == 1)
        service.setEnabled(false)
        service.enableByDefaultIfNeeded()
        check(!service.isEnabled && registrations == 1)
        service.setEnabled(true)
        check(service.isEnabled && registrations == 2)
        status = .notRegistered // User disabled the item in System Settings.
        service.enableByDefaultIfNeeded()
        check(!service.isEnabled && registrations == 2)
        status = .requiresApproval
        service.refresh()
        check(service.isEnabled && service.status == .requiresApproval)
        service.setEnabled(false)
        check(!service.isEnabled)
        fail = true
        service.setEnabled(true)
        check(!service.isEnabled && service.errorMessage != nil)
        fail = false
        service.setEnabled(true)
        check(service.isEnabled && service.errorMessage == nil)
        print("Passed \(count) launch-at-login checks")
    }
}
