import AppKit

struct SidebarWidthRange {
    static let minimum: CGFloat = 200
    static let maximum: CGFloat = 420

    static func configure(_ item: NSSplitViewItem) {
        item.minimumThickness = minimum
        item.maximumThickness = maximum
    }

    static func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, minimum), maximum)
    }
}

final class SidebarTrackingSplitView: NSSplitView {
    var onDividerDragStateChanged: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        performTrackedDividerDrag {
            super.mouseDown(with: event)
        }
    }

    func performTrackedDividerDrag(_ drag: () -> Void) {
        onDividerDragStateChanged?(true)
        defer { onDividerDragStateChanged?(false) }
        drag()
    }
}

struct SidebarSplitPositionPolicy {
    static func position(
        proposed: CGFloat,
        preferred: CGFloat,
        enforced: CGFloat?,
        allowsMovement: Bool
    ) -> CGFloat {
        if let enforced {
            return enforced
        }
        return allowsMovement ? proposed : preferred
    }
}
