import AppKit

struct MainWindowChromeLayout {
    static func configure(_ window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
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
            .sidebarTrackingSeparator,
            currentThread,
            .flexibleSpace,
            addRepository,
            recentlyArchived,
            settings,
        ]
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
