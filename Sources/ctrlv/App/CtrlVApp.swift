import SwiftUI

@main
struct CtrlVApp: App {
    static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    static var quitTitle: String { "Quit ^V (\(version))" }

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("^V", systemImage: "clipboard") {
            Button("Open Clipboard     ⌃V") { delegate.panelController?.show() }
            Divider()
            Toggle("Pause Capture", isOn: Binding(get: { delegate.store.isPaused }, set: { delegate.store.isPaused = $0 }))
            LoginItemMenu(service: delegate.store.loginItem)
            DirectPasteMenu(service: delegate.store.pasteService)
            Divider()
            Button(Self.quitTitle) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipboardStore()
    var panelController: PanelController?
    private let hotKey = GlobalHotKey()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Deliberately a menu-bar-only utility, with no Dock icon or ordinary main window.
        NSApp.setActivationPolicy(.accessory)
        store.pasteService.startMonitoring()
        panelController = PanelController(store: store)
        hotKey.onPress = { [weak self] in self?.panelController?.toggle() }
        if !hotKey.register() { store.status = "Control+V is unavailable. Open ^V from the menu bar." }
        let shouldShowOnLaunch = Self.shouldShowOnLaunch(notification)
        Task {
            await store.start()
            if shouldShowOnLaunch {
                panelController?.show()
            }
        }
    }

    static func shouldShowOnLaunch(
        _ notification: Notification,
        appleEvent: NSAppleEventDescriptor? = NSAppleEventManager.shared().currentAppleEvent
    ) -> Bool {
        if let appleEvent,
           appleEvent.eventID == AEEventID(kAEOpenApplication),
           let propData = appleEvent.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)),
           propData.enumCodeValue == DescType(keyAELaunchedAsLogInItem)
            || propData.enumCodeValue == DescType(keyAELaunchedAsServiceItem) {
            return false
        }
        if let isDefault = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool, !isDefault {
            return false
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { store.pasteService.stopMonitoring() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }
}
