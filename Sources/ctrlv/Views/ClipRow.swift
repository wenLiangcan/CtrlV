import SwiftUI
import ImageIO

struct ClipRow: View {
    let clip: Clip
    let shortcut: Int?
    @State private var thumbnail: NSImage?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().scaledToFit()
                } else {
                    Image(systemName: clip.symbol)
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(clip.kind == .link ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 34, height: 34)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(clip.title.replacingOccurrences(of: "\n", with: " "))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.tail)
                Text(clip.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 2)
            if clip.isPinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityLabel("Pinned")
            } else if let shortcut {
                Text("⌘\(shortcut)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .task(id: clip.id) {
            guard clip.kind == .image else { return }
            let data = clip.items.first?.first { $0.type == "public.png" || $0.type == "public.tiff" }?.data
            guard let data else { return }
            let cgImage = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return Optional<CGImage>.none }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 88,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary)
            }.value
            if let cgImage { thumbnail = NSImage(cgImage: cgImage, size: .zero) }
        }
    }
}
