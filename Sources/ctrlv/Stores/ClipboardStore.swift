import AppKit
import Observation

@MainActor @Observable
final class ClipboardStore {
    private(set) var clips: [Clip] = []
    var query = ""
    var selection: UUID?
    var focusRequest = 0
    var isPaused = false { didSet { monitor.isPaused = isPaused } }
    var status: String?
    var isReady = false
    let loginItem = LoginItemService()
    let pasteService = PasteService()
    @ObservationIgnored let monitor = ClipboardMonitor()
    @ObservationIgnored private let persistence = HistoryPersistence()

    var filtered: [Clip] {
        clips.filter { $0.matches(query) }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.date > $1.date
        }
    }
    var selectedClip: Clip? { filtered.first { $0.id == selection } }

    func start() async {
        clips = await persistence.load()
        monitor.onCapture = { [weak self] clip in self?.insert(clip) }
        monitor.start()
        monitor.poll()
        isReady = true
        resetSelection()
    }

    func insert(_ clip: Clip) {
        clips = HistoryPolicy.inserting(clip, into: clips)
        if selection == nil { resetSelection() }
        save()
    }

    func resetSelection() { selection = filtered.first?.id }
    func moveSelection(_ delta: Int) {
        let rows = filtered
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == selection } ?? 0
        selection = rows[min(max(index + delta, 0), rows.count - 1)].id
    }
    func togglePin(_ clip: Clip) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        guard clip.isPinned || clips.filter(\.isPinned).count < HistoryPolicy.maximumPins else {
            status = "You can pin up to 30 items."
            return
        }
        clips[index].isPinned.toggle()
        save()
    }
    func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        resetSelection()
        save()
    }
    func clearUnpinned() {
        clips.removeAll { !$0.isPinned }
        resetSelection()
        save()
    }
    private func save() {
        persistence.save(clips) { [weak self] success in
            if !success { Task { @MainActor in self?.status = "History couldn’t be saved to disk." } }
        }
    }
}
