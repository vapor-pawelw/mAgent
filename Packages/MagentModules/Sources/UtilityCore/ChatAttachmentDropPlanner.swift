import Foundation

public struct ChatAttachmentDropPlan: Equatable, Sendable {
    public var fileURLs: [URL]
    public var shouldImportPasteboardImages: Bool

    public init(fileURLs: [URL], shouldImportPasteboardImages: Bool) {
        self.fileURLs = fileURLs
        self.shouldImportPasteboardImages = shouldImportPasteboardImages
    }
}

public enum ChatAttachmentDropPlanner {
    /// Builds an attachment import plan for an AppKit pasteboard/drop payload.
    ///
    /// Some drags, notably screenshot files dragged from Finder, advertise both a
    /// file URL and image data. Treat the file URL as authoritative so one user
    /// gesture creates one attachment instead of a duplicate temporary
    /// `paste-*.png` beside the original `Screenshot*.png` file.
    public static func plan(fileURLs: [URL], hasPasteboardImages: Bool) -> ChatAttachmentDropPlan {
        ChatAttachmentDropPlan(
            fileURLs: fileURLs,
            shouldImportPasteboardImages: fileURLs.isEmpty && hasPasteboardImages
        )
    }
}
