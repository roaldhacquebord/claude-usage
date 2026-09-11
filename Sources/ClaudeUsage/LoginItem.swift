import Foundation
import Observation
import ServiceManagement

/// The "Open at login" setting, backed by the system login items list.
@MainActor
@Observable
final class LoginItem {
    private(set) var isEnabled = false
    private(set) var problem: String?

    init() {
        refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        problem = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            problem = error.localizedDescription
        }
        refreshStatus()
    }

    /// Turns the setting on the first time the app runs; afterwards the user's choice stands.
    func enableOnFirstLaunch(defaults: UserDefaults = .standard) {
        let key = "hasConfiguredLoginItem"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        setEnabled(true)
    }

    private func refreshStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        if status == .requiresApproval {
            problem = "Approve Claude Usage in System Settings → General → Login Items"
        }
    }
}
