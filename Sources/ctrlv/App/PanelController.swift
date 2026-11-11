import AppKit
import SwiftUI

@MainActor
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let store: ClipboardStore
    private(set) var panel: ClipboardPanel!
    private var previousApp: NSRunningApplication?
    private var pasteTask: Task<Void, Never>?
    private var keyMonitor: Any?
    private var accessibilityObserver: NSObjectProtocol?
    private var surface: NSView!

    init(store: ClipboardStore) {
        self.store = store
        super.init()
        panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 510),
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.title = "^V"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 340, height: 350)
        panel.maxSize = NSSize(width: 580, height: 850)
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.delegate = self
        panel.setFrameAutosaveName("ClipboardPanel")

        let content = ClipboardView(store: store, choose: { [weak self] in self?.choose($0) }, dismiss: { [weak self] in self?.hide() })
        let hosting = NSHostingView(rootView: content.ignoresSafeArea(.container, edges: .top))
        surface = NSView()
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 16
            glass.contentView = surface
            panel.contentView = glass
        } else {
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .hudWindow
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 16
            visualEffect.layer?.masksToBounds = true
            visualEffect.addSubview(surface)
            surface.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                surface.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
                surface.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
                surface.topAnchor.constraint(equalTo: visualEffect.topAnchor),
                surface.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor)
            ])
            panel.contentView = visualEffect
        }
        surface.addSubview(hosting)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: surface.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: surface.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: surface.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: surface.bottomAnchor)
        ])
        updateAccessibility()
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.updateAccessibility() } }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) == nil }
            return consumed ? nil : event
        }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        pasteTask?.cancel()
        store.pasteService.refresh()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
        store.monitor.poll()
        store.query = ""
        store.resetSelection()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2,
                                         y: visible.midY - panel.frame.height / 2 + visible.height * 0.1))
        }
        panel.makeKeyAndOrderFront(nil)
        store.focusRequest += 1
    }

    func hide() { panel.orderOut(nil) }
    func windowDidResignKey(_ notification: Notification) { hide() }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }

    func choose(_ clip: Clip) {
        pasteTask?.cancel()
        guard store.monitor.restore(clip) else {
            store.status = "Couldn’t copy this item. Please try again."
            return
        }
        hide()
        guard let previousApp, !previousApp.isTerminated else {
            store.status = "Copied. Switch to an app and press Command+V to paste."
            return
        }
        store.pasteService.refresh()
        previousApp.activate()
        guard store.pasteService.isEnabled else {
            store.status = "Copied. Enable Direct Paste in the options menu, or press Command+V."
            return
        }
        store.status = nil
        pasteTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let message = await store.pasteService.paste(into: previousApp)
            guard !Task.isCancelled else { return }
            store.status = message
        }
    }

    private func updateAccessibility() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        surface.wantsLayer = true
        surface.layer?.backgroundColor = reduced ? NSColor.windowBackgroundColor.cgColor : nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow, event.window === panel else { return event }
        // Let marked text / input methods own their navigation and Return keys.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) {
            if let text = event.charactersIgnoringModifiers, let number = Int(text), (1...9).contains(number),
               number <= store.filtered.count {
                choose(store.filtered[number - 1]); return nil
            }
            if event.keyCode == 3 { store.focusRequest += 1; return nil } // Command+F
            if event.keyCode == 35, let clip = store.selectedClip { store.togglePin(clip); return nil }
            if event.keyCode == 51, let clip = store.selectedClip { store.remove(clip); return nil }
            if event.keyCode == 13 { hide(); return nil }
        }
        guard modifiers.intersection([.command, .control, .option, .shift]).isEmpty else { return event }
        switch event.keyCode {
        case 125: store.moveSelection(1); return nil
        case 126: store.moveSelection(-1); return nil
        case 36, 76:
            if let clip = store.selectedClip { choose(clip) }
            return nil
        case 53: hide(); return nil
        default: return event
        }
    }
}
