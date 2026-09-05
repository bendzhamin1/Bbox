import Foundation
import AppKit
import Combine

/// Owns the clipboard history: in-memory list + JSON persistence on disk.
/// Images are stored as PNG files next to the JSON index.
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    /// Maximum number of *unpinned* items kept. Pinned items are never trimmed.
    var maxItems: Int = 200

    private let baseURL: URL
    private let imagesURL: URL
    private let indexURL: URL

    /// `ephemeral` uses a throwaway temp directory (used for offscreen previews),
    /// so it never touches the real clipboard history on disk.
    init(ephemeral: Bool = false) {
        let fm = FileManager.default
        if ephemeral {
            baseURL = fm.temporaryDirectory
                .appendingPathComponent("Bbox-preview-\(UUID().uuidString)", isDirectory: true)
        } else {
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            baseURL = appSupport.appendingPathComponent("Bbox", isDirectory: true)
        }
        imagesURL = baseURL.appendingPathComponent("images", isDirectory: true)
        indexURL = baseURL.appendingPathComponent("history.json")

        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        load()
    }

    /// Fills the store with sample entries for offscreen preview rendering.
    func seedPreview() {
        items = [
            ClipItem(kind: .text, payload: "https://github.com", createdAt: Date().addingTimeInterval(-30)),
            ClipItem(kind: .text, payload: "func toggle() { isVisible ? hide() : show() }", createdAt: Date().addingTimeInterval(-120)),
            ClipItem(kind: .text, payload: "Список покупок: кофе, молоко, хлеб, яйца", createdAt: Date().addingTimeInterval(-600), pinned: true),
            ClipItem(kind: .text, payload: "Привет! Это пример записи буфера обмена, которая занимает несколько строк, чтобы показать перенос текста в карточке.", createdAt: Date().addingTimeInterval(-1800)),
            ClipItem(kind: .text, payload: "192.168.1.42", createdAt: Date().addingTimeInterval(-3600))
        ]
    }

    // MARK: - Reads

    /// Items filtered by a search query and sorted: pinned first, then recency.
    func filtered(_ query: String) -> [ClipItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty
            ? items
            : items.filter { $0.kind == .text && $0.payload.lowercased().contains(q) }
        return base.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func imageURL(for item: ClipItem) -> URL {
        imagesURL.appendingPathComponent(item.payload)
    }

    func image(for item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        return NSImage(contentsOf: imageURL(for: item))
    }

    // MARK: - Mutations

    /// Add a new text entry, de-duplicating against the most recent identical one.
    func addText(_ text: String, sourceApp: String?) {
        if let idx = items.firstIndex(where: { $0.kind == .text && $0.payload == text }) {
            // Move existing to the top instead of duplicating.
            var existing = items.remove(at: idx)
            existing.createdAt = Date()
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(kind: .text, payload: text, sourceApp: sourceApp), at: 0)
        }
        trimAndSave()
    }

    /// Add a new image entry, writing the PNG to disk.
    func addImage(_ image: NSImage, sourceApp: String?) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }

        let fileName = UUID().uuidString + ".png"
        let url = imagesURL.appendingPathComponent(fileName)
        do {
            try png.write(to: url)
        } catch {
            NSLog("Bbox: failed to write image: \(error)")
            return
        }
        items.insert(ClipItem(kind: .image, payload: fileName, sourceApp: sourceApp), at: 0)
        trimAndSave()
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].pinned.toggle()
        save()
    }

    func delete(_ item: ClipItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let removed = items.remove(at: idx)
        if removed.kind == .image {
            try? FileManager.default.removeItem(at: imageURL(for: removed))
        }
        save()
    }

    func clearAll() {
        // Keep pinned items; wipe everything else.
        let pinned = items.filter { $0.pinned }
        for item in items where !item.pinned && item.kind == .image {
            try? FileManager.default.removeItem(at: imageURL(for: item))
        }
        items = pinned
        save()
    }

    // MARK: - Persistence

    private func trimAndSave() {
        let pinned = items.filter { $0.pinned }
        var unpinned = items.filter { !$0.pinned }
        if unpinned.count > maxItems {
            let overflow = unpinned[maxItems...]
            for item in overflow where item.kind == .image {
                try? FileManager.default.removeItem(at: imageURL(for: item))
            }
            unpinned = Array(unpinned.prefix(maxItems))
        }
        // Preserve original ordering (recent first) after trimming.
        items = (pinned + unpinned).sorted { $0.createdAt > $1.createdAt }
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Bbox: failed to save history: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        if let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) {
            items = decoded.sorted { $0.createdAt > $1.createdAt }
        }
    }
}
