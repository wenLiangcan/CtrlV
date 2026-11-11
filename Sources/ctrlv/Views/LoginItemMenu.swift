import SwiftUI

struct LoginItemMenu: View {
    let service: LoginItemService

    var body: some View {
        Toggle("Start at Login", isOn: Binding(
            get: { service.isRegistered },
            set: { service.setEnabled($0) }
        ))
        .onAppear { service.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            service.refresh()
        }

        if service.requiresApproval {
            Button("Approve in System Settings…") { service.openSettings() }
        }
        if let message = service.errorMessage {
            Button("Show Login Error…") {
                let alert = NSAlert()
                alert.messageText = "Couldn’t update Start at Login"
                alert.informativeText = message
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
