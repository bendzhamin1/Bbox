import Foundation
import AppKit

/// A single entry in the clipboard history.
enum ClipKind: String, Codable {
    case text
    case image
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipKind
    /// For `.text` this holds the string. For `.image` this holds the
    /// relative file name of the PNG stored on disk.
    var payload: String
    var createdAt: Date
    var pinned: Bool
    /// Best-effort name of the app the content was copied from.
    var sourceApp: String?

    init(id: UUID = UUID(),
         kind: ClipKind,
         payload: String,
         createdAt: Date = Date(),
         pinned: Bool = false,
         sourceApp: String? = nil) {
        self.id = id
        self.kind = kind
        self.payload = payload
        self.createdAt = createdAt
        self.pinned = pinned
        self.sourceApp = sourceApp
    }

    /// A short one-line preview used in the list.
    var preview: String {
        switch kind {
        case .text:
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
            return singleLine.isEmpty ? "(пустой текст)" : singleLine
        case .image:
            return "Изображение"
        }
    }

    /// Rough character/byte count shown as metadata.
    var detail: String {
        switch kind {
        case .text:
            let count = payload.count
            return "\(count) симв."
        case .image:
            return "PNG"
        }
    }
}
