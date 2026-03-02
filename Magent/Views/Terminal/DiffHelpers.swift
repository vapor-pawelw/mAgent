import Cocoa

// MARK: - Image Helpers

let imageExtensions: Set<String> = [
    "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "bmp", "tiff", "tif",
]

func isImageFile(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return imageExtensions.contains(ext)
}

enum ImageDiffMode {
    case added, deleted, modified
}

func detectImageDiffState(from chunk: String) -> ImageDiffMode {
    if chunk.contains("new file") || chunk.contains("--- /dev/null") {
        return .added
    }
    if chunk.contains("deleted file") || chunk.contains("+++ /dev/null") {
        return .deleted
    }
    return .modified
}

/// Extracts the old path from a `rename from <path>` line in a diff chunk.
func extractRenameFrom(_ chunk: String) -> String? {
    for line in chunk.components(separatedBy: "\n") {
        if line.hasPrefix("rename from ") {
            return String(line.dropFirst("rename from ".count))
        }
    }
    return nil
}

// MARK: - Shared Diff Styling

let diffDefaultFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
let diffHeaderFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
let diffAddColor = NSColor(red: 0.35, green: 0.75, blue: 0.35, alpha: 1.0)
let diffDelColor = NSColor(red: 0.9, green: 0.35, blue: 0.35, alpha: 1.0)
let diffHunkColor = NSColor(red: 0.45, green: 0.65, blue: 0.85, alpha: 1.0)
let diffHeaderColor = NSColor(red: 0.8, green: 0.8, blue: 0.6, alpha: 1.0)
let diffContextColor = NSColor(resource: .textSecondary)

let statsAddColor = NSColor(red: 0.35, green: 0.65, blue: 0.35, alpha: 1.0)
let statsDelColor = NSColor(red: 0.78, green: 0.3, blue: 0.3, alpha: 1.0)

/// Parses an array of diff lines into a colored attributed string.
func parseDiffLines(_ lines: [String]) -> NSAttributedString {
    let result = NSMutableAttributedString()
    for line in lines {
        let attrs: [NSAttributedString.Key: Any]
        if line.hasPrefix("diff --git") {
            continue
        } else if line.hasPrefix("+++") || line.hasPrefix("---") {
            attrs = [.font: diffHeaderFont, .foregroundColor: diffHeaderColor]
        } else if line.hasPrefix("@@") {
            attrs = [.font: diffDefaultFont, .foregroundColor: diffHunkColor]
        } else if line.hasPrefix("+") {
            attrs = [
                .font: diffDefaultFont,
                .foregroundColor: diffAddColor,
                .backgroundColor: diffAddColor.withAlphaComponent(0.08),
            ]
        } else if line.hasPrefix("-") {
            attrs = [
                .font: diffDefaultFont,
                .foregroundColor: diffDelColor,
                .backgroundColor: diffDelColor.withAlphaComponent(0.08),
            ]
        } else if line.hasPrefix("new file") || line.hasPrefix("deleted file") ||
                    line.hasPrefix("index ") || line.hasPrefix("Binary") ||
                    line.hasPrefix("rename") || line.hasPrefix("similarity") {
            attrs = [.font: diffDefaultFont, .foregroundColor: diffContextColor.withAlphaComponent(0.6)]
        } else {
            attrs = [.font: diffDefaultFont, .foregroundColor: diffContextColor]
        }
        result.append(NSAttributedString(string: line + "\n", attributes: attrs))
    }
    return result
}

/// Measures the height needed to render an attributed string at a given width.
func calculateDiffTextHeight(for attrStr: NSAttributedString, width: CGFloat = 300) -> CGFloat {
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(size: NSSize(width: max(width, 300), height: .greatestFiniteMagnitude))
    textContainer.lineFragmentPadding = 5
    let textStorage = NSTextStorage(attributedString: attrStr)
    textStorage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    layoutManager.ensureLayout(for: textContainer)
    let height = layoutManager.usedRect(for: textContainer).height + 8
    return max(height, 20)
}

/// Populates a horizontal stats stack with colored +N / -N labels.
func populateStatsStack(_ stack: NSStackView, additions: Int, deletions: Int, isImage: Bool) {
    stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    if isImage {
        let label = NSTextField(labelWithString: "image")
        label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = NSColor(resource: .textSecondary)
        label.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(label)
    } else {
        if additions > 0 {
            let label = NSTextField(labelWithString: "+\(additions)")
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = statsAddColor
            label.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(label)
        }
        if deletions > 0 {
            let label = NSTextField(labelWithString: "-\(deletions)")
            label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            label.textColor = statsDelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(label)
        }
    }
}
