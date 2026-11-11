import AppKit
import SwiftUI

struct ClipboardView: View {
    @Bindable var store: ClipboardStore
    let choose: (Clip) -> Void
    let dismiss: () -> Void
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clipboard")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                SearchField(text: $store.query, focusRequest: store.focusRequest)
                    .frame(height: 32)
                Menu {
                    Toggle("Pause Capture", isOn: $store.isPaused)
                    LoginItemMenu(service: store.loginItem)
                    DirectPasteMenu(service: store.pasteService)
                    Divider()
                    Button("Clear Unpinned History…", role: .destructive) { confirmClear = true }
                        .disabled(!store.clips.contains { !$0.isPinned })
                    Divider()
                    Button(CtrlVApp.quitTitle) { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 22, height: 18)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Clipboard options")
                .help("Clipboard options")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            Divider().padding(.horizontal, 20)


            HStack {
                Text(store.query.isEmpty ? "CLIPBOARD" : "RESULTS")
                    .font(.system(size: 10, weight: .semibold)).tracking(1.1)
                Text("\(store.filtered.count)").font(.system(size: 10, weight: .medium, design: .rounded))
                Spacer()
                if store.isPaused { Text("Paused").font(.system(size: 10)) }

            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 7)

            if store.filtered.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(selection: $store.selection) {
                        ForEach(Array(store.filtered.enumerated()), id: \.element.id) { index, clip in
                            ClipRow(clip: clip, shortcut: index < 9 ? index + 1 : nil)
                                .tag(clip.id)
                                .onTapGesture { choose(clip) }
                                .contextMenu {
                                    Button(store.pasteService.isEnabled ? "Paste" : "Copy") { choose(clip) }
                                    Button(clip.isPinned ? "Unpin" : "Pin") { store.togglePin(clip) }
                                    Divider()
                                    Button("Delete", role: .destructive) { store.remove(clip) }
                                }
                                .accessibilityAction(named: "Use clipboard item") { choose(clip) }
                                .accessibilityAction(named: clip.isPinned ? "Unpin" : "Pin") { store.togglePin(clip) }
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .background(ScrollBarAutoHider())
                    .onChange(of: store.selection) { _, id in
                        if let id { proxy.scrollTo(id) }
                    }
                }
            }

            Divider().padding(.horizontal, 16)
            HStack(spacing: 12) {
                Text("↑↓ Browse")
                Text(store.pasteService.isEnabled ? "↩ Paste" : "↩ Copy")
                Spacer()
                Text("⌃ V").fontWeight(.medium)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            if let status = store.status {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .onChange(of: store.query) { store.resetSelection() }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear Unpinned History", role: .destructive) { store.clearUnpinned() }
        } message: { Text("Pinned items will be kept. Your current clipboard won’t change.") }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.query.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32, weight: .light)).foregroundStyle(.tertiary)
            Text(store.query.isEmpty ? "Ready when you copy" : "No matching clips")
                .font(.system(size: 15, weight: .medium))
            Text(store.query.isEmpty ? "Copy text, links, images, or files.\nThey’ll be waiting here." : "Try another word or app name.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(3)
        }
        .padding(24)
    }
}

struct ScrollBarAutoHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollBarObserverView { ScrollBarObserverView() }
    func updateNSView(_ nsView: ScrollBarObserverView, context: Context) { nsView.attachIfNeeded() }
}

@MainActor
final class ScrollBarObserverView: NSView {
    private(set) weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []
    private var kvoTokens: [NSKeyValueObservation] = []
    private var hideTask: Task<Void, Never>?
    private var lastOriginY: CGFloat?
    private var isApplying = false
    private(set) var isScrolling = false
    var hideDelay: Duration = .milliseconds(600)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachIfNeeded()
        DispatchQueue.main.async { [weak self] in self?.attachIfNeeded() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        attachIfNeeded()
    }

    override func layout() {
        super.layout()
        attachIfNeeded()
        applyVisibility()
    }

    func attachIfNeeded() {
        if let scrollView, scrollView.window != nil {
            applyVisibility()
            return
        }
        guard let found = Self.findScrollView(from: self) else { return }
        attach(to: found)
    }

    func attach(to target: NSScrollView) {
        guard scrollView !== target else {
            applyVisibility()
            return
        }
        removeObservers()
        scrollView = target
        target.scrollerStyle = .overlay
        target.autohidesScrollers = true
        target.hasHorizontalScroller = false
        target.postsFrameChangedNotifications = true
        target.contentView.postsBoundsChangedNotifications = true
        lastOriginY = target.contentView.bounds.origin.y
        isScrolling = false
        observeScroller(of: target)
        applyVisibility()

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: target, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleScrollActivity() }
            },
            center.addObserver(forName: NSScrollView.didLiveScrollNotification, object: target, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleScrollActivity() }
            },
            center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: target, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleHide() }
            },
            center.addObserver(forName: NSView.boundsDidChangeNotification, object: target.contentView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleBoundsChange() }
            },
            center.addObserver(forName: NSView.frameDidChangeNotification, object: target, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyVisibility() }
            },
            center.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.applyVisibility() }
            }
        ]
    }

    private func observeScroller(of target: NSScrollView) {
        kvoTokens.removeAll()
        kvoTokens.append(target.observe(\.scrollerStyle, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.applyVisibility() }
        })
        kvoTokens.append(target.observe(\.verticalScroller, options: [.new]) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                self?.observeScroller(of: scrollView)
                self?.applyVisibility()
            }
        })
        if let scroller = target.verticalScroller {
            kvoTokens.append(scroller.observe(\.isHidden, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.applyVisibility() }
            })
            kvoTokens.append(scroller.observe(\.alphaValue, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.applyVisibility() }
            })
        }
    }

    func handleScrollActivity() {
        isScrolling = true
        applyVisibility()
        scrollView?.flashScrollers()
        scheduleHide()
    }

    private func handleBoundsChange() {
        guard let scrollView else { return }
        let currentY = scrollView.contentView.bounds.origin.y
        defer { lastOriginY = currentY }
        guard let lastOriginY, abs(currentY - lastOriginY) > 0.5 else {
            applyVisibility()
            return
        }
        handleScrollActivity()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let delay = hideDelay
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.isScrolling = false
            self.applyVisibility()
        }
    }

    func applyVisibility() {
        guard !isApplying, let scrollView else { return }
        isApplying = true
        defer { isApplying = false }
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        guard let scroller = scrollView.verticalScroller else { return }
        let targetAlpha: CGFloat = isScrolling ? 1 : 0
        if scroller.alphaValue != targetAlpha {
            scroller.alphaValue = targetAlpha
        }
        if scroller.isHidden == isScrolling {
            scroller.isHidden = !isScrolling
        }
    }

    private func removeObservers() {
        let center = NotificationCenter.default
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        kvoTokens.removeAll()
        hideTask?.cancel()
        hideTask = nil
    }

    static func findScrollView(from view: NSView) -> NSScrollView? {
        if let enclosing = view.enclosingScrollView { return enclosing }
        var current: NSView? = view.superview
        while let ancestor = current {
            if let found = firstScrollView(in: ancestor) { return found }
            current = ancestor.superview
        }
        return nil
    }

    private static func firstScrollView(in root: NSView) -> NSScrollView? {
        if let scroll = root as? NSScrollView { return scroll }
        for subview in root.subviews {
            if let found = firstScrollView(in: subview) { return found }
        }
        return nil
    }
}
