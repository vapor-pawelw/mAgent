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

struct SidebarDividerResizeIntent {
    private(set) var isDragging = false

    mutating func reconcilePrimaryButtonState(isPressed: Bool) {
        if !isPressed {
            isDragging = false
        }
    }

    mutating func recognizes(
        _ eventType: NSEvent.EventType,
        pointerX: CGFloat,
        dividerX: CGFloat,
        dividerThickness: CGFloat
    ) -> Bool {
        switch eventType {
        case .leftMouseDown:
            isDragging = isPointerOverDivider(
                pointerX: pointerX,
                dividerX: dividerX,
                dividerThickness: dividerThickness
            )
            return isDragging
        case .leftMouseDragged:
            return isDragging
        case .leftMouseUp:
            let recognized = isDragging
            isDragging = false
            return recognized
        default:
            return false
        }
    }

    mutating func cancel() {
        isDragging = false
    }

    private func isPointerOverDivider(
        pointerX: CGFloat,
        dividerX: CGFloat,
        dividerThickness: CGFloat
    ) -> Bool {
        let hitTolerance: CGFloat = 4
        let hitRange = (dividerX - hitTolerance)...(dividerX + max(dividerThickness, 0) + hitTolerance)
        return hitRange.contains(pointerX)
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
