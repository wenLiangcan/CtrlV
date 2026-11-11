import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

@MainActor @Observable
final class PasteService {
    private(set) var isEnabled = false
    @ObservationIgnored private let accessCheck: () -> Bool
    @ObservationIgnored private var permissionTimer: Timer?
    private let logger = Logger(subsystem: "app.ctrlv.clipboard", category: "DirectPaste")

    init(accessCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.accessCheck = accessCheck
        refresh()
    }

    func refresh() { isEnabled = accessCheck() }

    func startMonitoring() {
        guard permissionTimer == nil else { return }
        refresh()
        // A nonactivating panel does not receive app-activation notifications.
        // Common modes also keep the permission label fresh inside an open menu.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    func stopMonitoring() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func paste(into target: NSRunningApplication) async -> String? {
        guard !Task.isCancelled else { return "Copied. Direct paste was cancelled. Press Command+V." }
        refresh()
        guard isEnabled else {
            return "Copied. Allow ^V in Accessibility settings to paste automatically, or press Command+V."
        }
        guard !target.isTerminated else { return "Copied. The previous app is no longer running." }
        target.activate()

        // Allow the nonactivating panel to release keyboard focus, even when the
        // target has remained the frontmost application throughout.
        do {
            try await Task.sleep(for: .milliseconds(100))
            for _ in 0..<80 {
                try Task.checkCancellation()
                guard !target.isTerminated else { return "Copied. The previous app is no longer running." }
                let modifiers = CGEventSource.flagsState(.hidSystemState)
                    .intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift])
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                   modifiers.isEmpty {
                    refresh()
                    guard isEnabled else { return "Copied. Direct paste permission was removed. Press Command+V." }
                    guard let source = CGEventSource(stateID: .privateState),
                          let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                          let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                        logger.error("Could not create paste keyboard events")
                        return "Copied. Couldn’t send the paste shortcut. Press Command+V."
                    }
                    down.flags = .maskCommand
                    up.flags = .maskCommand
                    // Address the intended app so a focus change cannot paste
                    // clipboard content into an unrelated application.
                    down.postToPid(target.processIdentifier)
                    up.postToPid(target.processIdentifier)
                    logger.info("Posted paste shortcut")
                    return nil
                }
                try await Task.sleep(for: .milliseconds(25))
            }
        } catch {
            return "Copied. Direct paste was cancelled. Press Command+V."
        }
        logger.error("Timed out waiting for target focus or modifier release")
        return "Copied. Release the shortcut keys and try again, or press Command+V."
    }
}
