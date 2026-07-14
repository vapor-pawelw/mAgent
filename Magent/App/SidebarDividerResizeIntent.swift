import AppKit

struct SidebarDividerResizeIntent {
    private(set) var isDragging = false

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
            if !isDragging {
                isDragging = isPointerOverDivider(
                    pointerX: pointerX,
                    dividerX: dividerX,
                    dividerThickness: dividerThickness
                )
            }
            return isDragging
        case .leftMouseUp:
            let recognized = isDragging || isPointerOverDivider(
                pointerX: pointerX,
                dividerX: dividerX,
                dividerThickness: dividerThickness
            )
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
