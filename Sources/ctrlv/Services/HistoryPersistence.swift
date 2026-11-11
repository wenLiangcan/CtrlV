import Foundation

/// A serial queue keeps disk work off the UI thread and preserves write order.
final class HistoryPersistence: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.ctrlv.persistence", qos: .utility)
    let url: URL

    init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ctrlv/history.json")
    }

    func load() async -> [Clip] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let clips = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Clip].self, from: $0) } ?? []
                continuation.resume(returning: clips.reversed().reduce([]) { HistoryPolicy.inserting($1, into: $0) })
            }
        }
    }

    func save(_ clips: [Clip], completion: @escaping @Sendable (Bool) -> Void) {
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let data = try JSONEncoder().encode(clips)
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                completion(true)
            } catch { completion(false) }
        }
    }
}
