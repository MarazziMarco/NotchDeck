import Foundation

/// Kind of clipboard payload NotchDeck tracks.
enum ClipboardItemKind: String, Codable, Equatable {
    case text
    case richText
    case image
    case url
    case fileURL
}

/// One entry in the clipboard history. Persisted locally as JSON. Image bytes
/// are stored inline but capped; large images are downscaled before storage.
struct ClipboardItem: Identifiable, Codable, Equatable {
    let id: UUID
    var kind: ClipboardItemKind
    var createdAt: Date
    /// Human-readable preview (text content, URL string, or file name list).
    var preview: String
    /// Raw string content for text/url/fileURL kinds, used to restore.
    var stringContent: String?
    /// PNG bytes for image kind (already downscaled for storage).
    var imageData: Data?
    var sourceAppName: String?
    var sourceBundleID: String?
    var pinned: Bool

    init(id: UUID = UUID(),
         kind: ClipboardItemKind,
         createdAt: Date = Date(),
         preview: String,
         stringContent: String? = nil,
         imageData: Data? = nil,
         sourceAppName: String? = nil,
         sourceBundleID: String? = nil,
         pinned: Bool = false) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.preview = preview
        self.stringContent = stringContent
        self.imageData = imageData
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.pinned = pinned
    }

    /// Two entries are "the same copy" if kind + payload match, ignoring id/date.
    func isSameContent(as other: ClipboardItem) -> Bool {
        guard kind == other.kind else { return false }
        switch kind {
        case .image:
            return imageData == other.imageData
        default:
            return stringContent == other.stringContent
        }
    }
}
