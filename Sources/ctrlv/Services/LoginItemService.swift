import Observation
import ServiceManagement

@MainActor @Observable
final class LoginItemService {
    private(set) var status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    // A pending registration remains checked, with an explicit approval action.
    var isRegistered: Bool { status == .enabled || status == .requiresApproval }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() { status = SMAppService.mainApp.status }

    func setEnabled(_ enabled: Bool) {
        refresh()
        errorMessage = nil
        guard enabled != isRegistered else { return }
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            errorMessage = error.localizedDescription
        }
        // The OS is the source of truth, including denial and registration failure.
        refresh()
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
