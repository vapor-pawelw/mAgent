import AppKit

enum SidebarDropFeedback: Equatable {
    case insertionY(CGFloat)
    case onRow(NSRect)
}

enum SidebarDropFeedbackStyle {
    static let systemFeedbackStyle = NSTableView.DraggingDestinationFeedbackStyle.none

    static func insertionRect(y: CGFloat, visibleRect: NSRect) -> NSRect {
        NSRect(
            x: visibleRect.minX + 8,
            y: y - 1.5,
            width: max(0, visibleRect.width - 16),
            height: 3
        )
    }

    static func draw(
        _ feedback: SidebarDropFeedback,
        in visibleRect: NSRect,
        color: NSColor,
        appearance: NSAppearance
    ) {
        appearance.performAsCurrentDrawingAppearance {
            switch feedback {
            case let .insertionY(y):
                color.setFill()
                NSBezierPath(
                    roundedRect: insertionRect(y: y, visibleRect: visibleRect),
                    xRadius: 1.5,
                    yRadius: 1.5
                ).fill()
            case let .onRow(rowRect):
                let targetRect = rowRect.insetBy(dx: 6, dy: 2)
                color.withAlphaComponent(0.14).setFill()
                NSBezierPath(roundedRect: targetRect, xRadius: 7, yRadius: 7).fill()
                color.setStroke()
                let border = NSBezierPath(
                    roundedRect: targetRect.insetBy(dx: 1, dy: 1),
                    xRadius: 6,
                    yRadius: 6
                )
                border.lineWidth = 2
                border.stroke()
            }
        }
    }
}
