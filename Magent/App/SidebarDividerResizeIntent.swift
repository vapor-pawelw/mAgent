import AppKit

enum SidebarChromeBlurStyle {
    static func apply(to view: NSVisualEffectView) {
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
    }
}

final class SidebarChromeBlurView: NSVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        SidebarChromeBlurStyle.apply(to: self)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        SidebarChromeBlurStyle.apply(to: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Keep traffic-light controls and titlebar dragging available above this visual-only layer.
        nil
    }
}

struct MainWindowChromeLayout {
    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
    }

    static func configure(_ sidebarItem: NSSplitViewItem) {
        sidebarItem.allowsFullHeightLayout = true
    }

    static func sidebarTrackingSeparator(for splitView: NSSplitView) -> NSTrackingSeparatorToolbarItem {
        NSTrackingSeparatorToolbarItem(
            identifier: .sidebarTrackingSeparator,
            splitView: splitView,
            dividerIndex: 0
        )
    }

    static func defaultToolbarItemIdentifiers(
        currentThread: NSToolbarItem.Identifier,
        addRepository: NSToolbarItem.Identifier,
        recentlyArchived: NSToolbarItem.Identifier,
        settings: NSToolbarItem.Identifier
    ) -> [NSToolbarItem.Identifier] {
        [
            .flexibleSpace,
            addRepository,
            .sidebarTrackingSeparator,
            currentThread,
            .flexibleSpace,
            recentlyArchived,
            settings,
        ]
    }
}

struct SidebarContentLayout {
    static func topConstraint(for content: NSView, in container: NSView) -> NSLayoutConstraint {
        content.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor)
    }
}

enum SidebarScrollUnderlayLayout {
    static let bottomInset: CGFloat = 4

    static func contentInsets(safeAreaInsets: NSEdgeInsets) -> NSEdgeInsets {
        NSEdgeInsets(
            top: safeAreaInsets.top,
            left: 0,
            bottom: bottomInset,
            right: 0
        )
    }

    static func unobscuredRect(
        clipBounds: NSRect,
        contentInsets: NSEdgeInsets
    ) -> NSRect {
        let obscuredHeight = contentInsets.top + contentInsets.bottom
        return NSRect(
            x: clipBounds.origin.x,
            y: clipBounds.origin.y + contentInsets.top,
            width: clipBounds.width,
            height: max(0, clipBounds.height - obscuredHeight)
        )
    }

    static func clipOriginY(
        documentYAtUnobscuredTop: CGFloat,
        topInset: CGFloat
    ) -> CGFloat {
        documentYAtUnobscuredTop - topInset
    }
}

struct MainDetailContentLayout {
    static func topConstraint(for content: NSView, in container: NSView) -> NSLayoutConstraint {
        content.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor)
    }
}

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

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isVertical = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isVertical = true
    }

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
