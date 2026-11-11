import SwiftUI

struct DirectPasteMenu: View {
    let service: PasteService

    var body: some View {
        if service.isEnabled {
            Label("Direct Paste Enabled", systemImage: "checkmark")
        } else {
            Button("Enable Direct Paste…") { showHelp() }
        }
    }

    private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Allow direct paste"
        alert.informativeText = "Enable ^V in System Settings → Privacy & Security → Device Control and Data Access (Accessibility on older macOS versions). If it is already enabled, remove the old entry with the minus button, then add this copy of ^V and enable it again.\n\nRunning app: \(Bundle.main.bundleURL.path)\n\nAn older app build can remain listed even when macOS no longer grants it access."
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { service.openSettings() }
    }
}
