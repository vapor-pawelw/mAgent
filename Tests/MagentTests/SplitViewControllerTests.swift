import AppKit
import MagentCore
import Testing

private final class RecordingTitlebarWindow: NSWindow {
    private(set) var didPerformDrag = false
    private(set) var didPerformZoom = false

    override func performDrag(with event: NSEvent) {
        didPerformDrag = true
    }

    override func performZoom(_ sender: Any?) {
        didPerformZoom = true
    }
}

@Suite("Split view sidebar sizing")
struct SplitViewControllerTests {
    @Test("Retention store restores the same controller while chat work is active")
    func retentionStoreRestoresActiveChatController() {
        final class DetailController {}
        let threadID = UUID()
        let controller = DetailController()
        var store = ChatNavigationRetentionStore<DetailController>()

        store.update(controller, for: threadID, hasActiveWork: true)
        let restored = store.take(for: threadID)

        #expect(restored === controller)
    }

    @Test("Retention store releases a controller after background chat work completes")
    func retentionStoreReleasesCompletedChatController() {
        final class DetailController {}
        let threadID = UUID()
        let controller = DetailController()
        var store = ChatNavigationRetentionStore<DetailController>()

        store.update(controller, for: threadID, hasActiveWork: true)
        store.update(controller, for: threadID, hasActiveWork: false)

        #expect(store.take(for: threadID) == nil)
    }

    @Test("Retention store can retain a controller again when queued chat work starts")
    func retentionStoreRetainsControllerAgainForQueuedWork() {
        final class DetailController {}
        let threadID = UUID()
        var store = ChatNavigationRetentionStore<DetailController>()

        let controller = DetailController()
        store.update(controller, for: threadID, hasActiveWork: true)
        store.update(controller, for: threadID, hasActiveWork: false)
        store.update(controller, for: threadID, hasActiveWork: true)

        #expect(store.take(for: threadID) === controller)
    }

    @Test("Sidebar split view lays out sidebar beside content")
    func sidebarUsesVerticalDivider() {
        #expect(SidebarTrackingSplitView().isVertical)
    }

    @Test("Sidebar extends through the window titlebar")
    func sidebarUsesFullHeightLayout() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSViewController())

        MainWindowChromeLayout.configure(sidebarItem)

        #expect(sidebarItem.allowsFullHeightLayout)
    }

    @Test("Current thread strip starts on the content side of the sidebar")
    func toolbarTracksSidebarBeforeCurrentThread() throws {
        let currentThread = NSToolbarItem.Identifier("currentThread")
        let identifiers = MainWindowChromeLayout.defaultToolbarItemIdentifiers(
            currentThread: currentThread,
            addRepository: NSToolbarItem.Identifier("addRepository"),
            recentlyArchived: NSToolbarItem.Identifier("recentlyArchived"),
            settings: NSToolbarItem.Identifier("settings")
        )
        let separatorIndex = try #require(
            identifiers.firstIndex(of: NSToolbarItem.Identifier.sidebarTrackingSeparator)
        )
        let currentThreadIndex = try #require(
            identifiers.firstIndex(of: currentThread)
        )

        #expect(currentThreadIndex == separatorIndex + 1)
    }

    @Test("Add repository sits at the trailing edge of the sidebar toolbar")
    func addRepositoryPrecedesSidebarDividerAfterFlexibleSpace() throws {
        let addRepository = NSToolbarItem.Identifier("addRepository")
        let identifiers = MainWindowChromeLayout.defaultToolbarItemIdentifiers(
            currentThread: NSToolbarItem.Identifier("currentThread"),
            addRepository: addRepository,
            recentlyArchived: NSToolbarItem.Identifier("recentlyArchived"),
            settings: NSToolbarItem.Identifier("settings")
        )
        let addRepositoryIndex = try #require(identifiers.firstIndex(of: addRepository))
        let separatorIndex = try #require(
            identifiers.firstIndex(of: NSToolbarItem.Identifier.sidebarTrackingSeparator)
        )

        #expect(addRepositoryIndex == separatorIndex - 1)
        #expect(identifiers[addRepositoryIndex - 1] == .flexibleSpace)
    }

    @Test("Sidebar toolbar separator tracks the split-view divider")
    func toolbarSeparatorTracksSidebarDivider() {
        let splitView = NSSplitView()
        let separator = MainWindowChromeLayout.sidebarTrackingSeparator(for: splitView)

        #expect(separator.splitView === splitView)
        #expect(separator.dividerIndex == 0)
    }

    @Test("Main window keeps its existing vertical toolbar layout")
    func mainWindowPreservesVerticalToolbarLayout() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .expanded

        MainWindowChromeLayout.configure(window)

        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.toolbarStyle == .expanded)
    }

    @Test("Sidebar content starts below the window-control safe area")
    func sidebarContentUsesSafeAreaTop() {
        let container = NSView()
        let content = NSView()
        let constraint = SidebarContentLayout.topConstraint(for: content, in: container)

        #expect(constraint.firstItem === content)
        #expect(constraint.firstAttribute == .top)
        #expect(constraint.secondItem === container.safeAreaLayoutGuide)
        #expect(constraint.secondAttribute == .top)
    }

    @Test("Main detail content keeps the tab bar below the window toolbar")
    func mainDetailContentUsesSafeAreaTop() {
        let container = NSView()
        let content = NSView()
        let constraint = MainDetailContentLayout.topConstraint(for: content, in: container)

        #expect(constraint.firstItem === content)
        #expect(constraint.firstAttribute == .top)
        #expect(constraint.secondItem === container.safeAreaLayoutGuide)
        #expect(constraint.secondAttribute == .top)
    }

    @Test("Sidebar titlebar blur stays visually consistent and non-interactive")
    func sidebarTitlebarBlurUsesStickyHeaderStyleWithoutCapturingClicks() {
        let blurView = SidebarChromeBlurView(frame: NSRect(x: 0, y: 0, width: 280, height: 48))

        #expect(blurView.blendingMode == .withinWindow)
        #expect(blurView.material == .popover)
        #expect(blurView.state == .active)
        #expect(blurView.hitTest(NSPoint(x: 20, y: 20)) == nil)
    }

    @Test("Empty sidebar titlebar area explicitly starts native window dragging")
    func sidebarTitlebarStartsNativeWindowDrag() throws {
        let window = RecordingTitlebarWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let interactionView = SidebarTitlebarInteractionView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 48)
        )
        window.contentView = interactionView
        let event = try #require(titlebarMouseDownEvent(clickCount: 1))

        interactionView.mouseDown(with: event)

        #expect(window.didPerformDrag)
        #expect(!window.didPerformZoom)
    }

    @Test("Double-clicking the empty sidebar titlebar toggles window zoom")
    func sidebarTitlebarDoubleClickPerformsZoom() throws {
        let window = RecordingTitlebarWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        let interactionView = SidebarTitlebarInteractionView(
            frame: NSRect(x: 0, y: 0, width: 280, height: 48)
        )
        window.contentView = interactionView
        let event = try #require(titlebarMouseDownEvent(clickCount: 2))

        interactionView.mouseDown(with: event)

        #expect(window.didPerformZoom)
        #expect(!window.didPerformDrag)
    }

    @Test("Sidebar scroll content rests below chrome but can move underneath it")
    func sidebarScrollViewportAccountsForChromeInsets() {
        let insets = SidebarScrollUnderlayLayout.contentInsets(
            safeAreaInsets: NSEdgeInsets(top: 48, left: 3, bottom: 2, right: 3)
        )
        let visibleRect = SidebarScrollUnderlayLayout.unobscuredRect(
            clipBounds: NSRect(x: 0, y: 120, width: 280, height: 600),
            contentInsets: insets
        )

        #expect(insets.top == 48)
        #expect(insets.left == 0)
        #expect(insets.bottom == 4)
        #expect(insets.right == 0)
        #expect(visibleRect == NSRect(x: 0, y: 168, width: 280, height: 548))
        #expect(
            SidebarScrollUnderlayLayout.clipOriginY(
                documentYAtUnobscuredTop: 200,
                topInset: insets.top
            ) == 152
        )
    }

    private func titlebarMouseDownEvent(clickCount: Int) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: 140, y: 24),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        )
    }

    @Test("Sidebar width range supports a compact minimum on small screens")
    func sidebarSupportsCompactWidth() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSViewController())
        SidebarWidthRange.configure(sidebarItem)

        #expect(sidebarItem.minimumThickness == 200)
        #expect(sidebarItem.maximumThickness == 420)
        #expect(SidebarWidthRange.clamp(100) == 200)
        #expect(SidebarWidthRange.clamp(220) == 220)
        #expect(SidebarWidthRange.clamp(500) == 420)
    }

    @Test("Split view owns divider drag state for the full AppKit tracking loop")
    func splitViewOwnsDividerDragLifecycle() {
        let splitView = SidebarTrackingSplitView()
        var states: [Bool] = []
        splitView.onDividerDragStateChanged = { states.append($0) }

        splitView.performTrackedDividerDrag {
            #expect(states == [true])
        }

        #expect(states == [true, false])
    }

    @Test("AppKit divider tracking moves the sidebar and ends drag state")
    func appKitDividerDragMovesSidebar() throws {
        let splitView = SidebarTrackingSplitView(frame: NSRect(x: 0, y: 0, width: 800, height: 400))
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.addArrangedSubview(NSView())
        splitView.addArrangedSubview(NSView())

        let window = NSWindow(
            contentRect: splitView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = splitView
        window.alphaValue = 0
        window.orderFront(nil)
        defer { window.close() }

        splitView.adjustSubviews()
        splitView.setPosition(280, ofDividerAt: 0)
        splitView.layoutSubtreeIfNeeded()
        let initialWidth = splitView.arrangedSubviews[0].frame.width
        #expect(splitView.hitTest(NSPoint(x: 100, y: 200)) !== splitView)
        #expect(splitView.hitTest(NSPoint(x: initialWidth, y: 200)) === splitView)
        var states: [Bool] = []
        splitView.onDividerDragStateChanged = { states.append($0) }

        let targetX = initialWidth + 60
        let timestamp = ProcessInfo.processInfo.systemUptime
        let windowNumber = window.windowNumber
        let mouseUp = try #require(NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: NSPoint(x: targetX, y: 200),
            modifierFlags: [],
            timestamp: timestamp + 0.02,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 3,
            clickCount: 1,
            pressure: 0
        ))
        let mouseDragged = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged,
            location: NSPoint(x: targetX, y: 200),
            modifierFlags: [],
            timestamp: timestamp + 0.01,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 2,
            clickCount: 1,
            pressure: 1
        ))
        let mouseDown = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: NSPoint(x: initialWidth, y: 200),
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1
        ))

        NSApp.postEvent(mouseUp, atStart: true)
        NSApp.postEvent(mouseDragged, atStart: true)
        splitView.mouseDown(with: mouseDown)

        #expect(splitView.arrangedSubviews[0].frame.width > initialWidth + 40)
        #expect(states == [true, false])
    }

    @Test("Automatic layout keeps the preferred sidebar position")
    func automaticLayoutKeepsPreferredPosition() {
        let position = SidebarSplitPositionPolicy.position(
            proposed: 320,
            preferred: 280,
            enforced: nil,
            allowsMovement: false
        )

        #expect(position == 280)
    }

    @Test("A real divider drag or collapse can move the divider")
    func explicitSidebarInteractionAllowsMovement() {
        let position = SidebarSplitPositionPolicy.position(
            proposed: 320,
            preferred: 280,
            enforced: nil,
            allowsMovement: true
        )

        #expect(position == 320)
    }

    @Test("Content-swap enforcement takes precedence over active interaction")
    func contentSwapEnforcementTakesPrecedence() {
        let position = SidebarSplitPositionPolicy.position(
            proposed: 320,
            preferred: 280,
            enforced: 260,
            allowsMovement: true
        )

        #expect(position == 260)
    }

    @Test("Selecting the Diff tab keeps the changes panel fitting width stable")
    func diffSelectionKeepsChangesPanelWidthStable() {
        let stack = DiffPanelHeaderActionStack()
        stack.refreshButton.title = "Refresh"
        stack.infoButton.title = "Info"
        stack.showsInfoButton = false
        let commitsWidth = stack.fittingSize.width

        stack.showsInfoButton = true
        let changesWidth = stack.fittingSize.width

        #expect(abs(changesWidth - commitsWidth) < 0.5)
    }
}
