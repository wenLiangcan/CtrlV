import Foundation
import CryptoKit

struct Clip: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case text, link, image, file }
    struct Representation: Codable, Equatable, Sendable {
        let type: String
        let data: Data
    }
    var id: UUID = UUID()
    let fingerprint: String
    var date: Date = Date()
    let kind: Kind
    let title: String
    let source: String
    let items: [[Representation]]
    var isPinned = false

    var byteCount: Int { items.flatMap { $0 }.reduce(0) { $0 + $1.data.count } }
    var symbol: String {
        switch kind {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        }
    }
    var subtitle: String {
        switch kind {
        case .text: "Text · \(source)"
        case .link: "Link · \(source)"
        case .image: "Image · \(source)"
        case .file: "\(items.count == 1 ? "File" : "\(items.count) files") · \(source)"
        }
    }
    func matches(_ query: String) -> Bool {
        query.split(whereSeparator: \.isWhitespace).allSatisfy {
            (title + " " + source + " " + kind.rawValue).localizedStandardContains(String($0))
        }
    }
    static func fingerprint(for items: [[Representation]]) -> String {
        var hash = SHA256()
        for item in items {
            hash.update(data: Data([0xff]))
            for entry in item.sorted(by: { $0.type < $1.type }) {
                hash.update(data: Data(entry.type.utf8))
                hash.update(data: Data(String(entry.data.count).utf8))
                hash.update(data: entry.data)
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

enum HistoryPolicy {
    static let maximumCount = 200
    static let maximumBytes = 32 * 1_024 * 1_024
    static let maximumItemBytes = 4 * 1_024 * 1_024
    static let maximumPins = 30

    static func inserting(_ clip: Clip, into history: [Clip]) -> [Clip] {
        guard clip.byteCount <= maximumItemBytes else { return history }
        var result = history
        var incoming = clip
        if let index = result.firstIndex(where: { $0.fingerprint == clip.fingerprint }) {
            incoming.id = result[index].id
            incoming.isPinned = result[index].isPinned
            result.remove(at: index)
        }
        result.insert(incoming, at: 0)
        while result.count > maximumCount || result.reduce(0, { $0 + $1.byteCount }) > maximumBytes {
            guard let index = result.lastIndex(where: { !$0.isPinned }) else { break }
            result.remove(at: index)
        }
        return result
    }
}
