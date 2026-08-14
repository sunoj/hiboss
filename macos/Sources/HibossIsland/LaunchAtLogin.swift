// Login-item control backed by SMAppService, so the menu-bar app can restart
// itself at login. Registration is per-user and needs no helper bundle.
// Exports: LaunchAtLoginController.
// Dependencies: ServiceManagement, Combine, os.

import Combine
import ServiceManagement
import os

@MainActor
final class LaunchAtLoginController: ObservableObject {
    /// The app is registered as a login item, including the state where macOS
    /// still wants the user to approve it in System Settings.
    @Published private(set) var isEnabled = false
    /// Set when register/unregister failed, so Settings can show why.
    @Published private(set) var failure: String?
    @Published private(set) var status: SMAppService.Status = .notRegistered

    private let service: SMAppService
    private static let log = Logger(subsystem: "ai.hiboss.island", category: "login-item")

    init(service: SMAppService = .mainApp) {
        self.service = service
        refresh()
        Self.log.notice("Login item initial status: \(String(describing: self.status), privacy: .public)")
    }

    var explanation: String { Self.explanation(for: status, failure: failure) }

    static func explanation(for status: SMAppService.Status, failure: String?) -> String {
        if let failure { return failure }
        switch status {
        case .enabled:
            return L("HiBoss Island starts automatically when you log in.")
        case .requiresApproval:
            return L("Approve HiBoss Island under System Settings › General › Login Items to finish enabling this.")
        case .notFound:
            // Seen on a freshly replaced bundle before Launch Services catches
            // up. Registering usually still works, so this only explains.
            return L("macOS does not recognise this copy of the app yet. Turning this on should still work — if it does not, relaunch from /Applications and try again.")
        default:
            return L("HiBoss Island stays closed until you open it.")
        }
    }

    static func isRegistered(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            failure = nil
        } catch {
            failure = error.localizedDescription
            Self.log.error("Login item \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    /// macOS can flip the status behind our back (System Settings › Login Items).
    func refresh() {
        status = service.status
        isEnabled = Self.isRegistered(status)
    }
}
