import Cocoa
import MagentCore

private final class SplitContentContainerViewController: NSViewController {
    fileprivate var currentChild: NSViewController?
    private var currentChildConstraints: [NSLayoutConstraint] = []

    override func loadView() {
        view = NSView()
    }

    func setContent(_ child: NSViewController) {
        if currentChild === child { return }

        if let currentChild {
            // Clean up views that live outside the VC's own hierarchy (e.g.
            // DiffImageOverlayView on window.contentView) before removing.
            (currentChild as? ThreadDetailViewController)?.cleanUpBeforeRemoval()
            NSLayoutConstraint.deactivate(currentChildConstraints)
            currentChildConstraints.removeAll()
            currentChild.view.removeFromSuperview()
            currentChild.removeFromParent()
        }

        addChild(child)
        let childView = child.view
        childView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(childView)
        currentChildConstraints = [
            MainDetailContentLayout.topConstraint(for: childView, in: view),
            childView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            childView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            childView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(currentChildConstraints)

        currentChild = child
    }
}

private final class ThreadToolbarCapsuleView: NSStackView {
    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let borderColor = isDark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.08)
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
            layer?.borderColor = borderColor.cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
    }
}

final class SplitViewController: NSSplitViewController {

    private static let sidebarWidthDefaultsKey = "MagentSidebarWidth"
    private static let sidebarHiddenDefaultsKey = "MagentSidebarHidden"
    private static let pendingPromptRecoveryToolbarHintShownDefaultsKey = "MagentPendingPromptRecoveryToolbarHintShown"
    private static let defaultSidebarWidth: CGFloat = 280

    private let threadListVC = ThreadListViewController()
    private let emptyStateVC = EmptyStateViewController()
    private let contentContainerVC = SplitContentContainerViewController()
    private var currentDetailVC: ThreadDetailViewController?
    private var settingsWindowController: NSWindowController?
    private var sidebarItem: NSSplitViewItem?
    private var didApplyInitialSidebarWidth = false
    private var preferredSidebarWidth: CGFloat = defaultSidebarWidth
    private var enforcedSidebarWidth: CGFloat?
    private var isRestoringSidebarWidth = false
    private var isTogglingSidebarCollapse = false
    private var isSidebarDividerDragActive = false
    private var keyEventMonitor: Any?
    private var cachedKeyBindings: KeyBindingSettings = KeyBindingSettings()
    private weak var observedWindowForFocusNotifications: NSWindow?
    private let currentThreadToolbarStrip = CurrentThreadStripView()
    private let currentThreadToolbarStack = ThreadToolbarCapsuleView()
    private var didConfigureCurrentThreadToolbarStack = false
    private var didInstallCurrentThreadToolbarSizingConstraints = false
    private weak var pendingPromptRecoveryToolbarButton: NSButton?
    private var pendingPromptRecoveryToolbarHintPopover: NSPopover?

    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        configureSplitViewHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        configureSplitViewHierarchy()
    }

    private func configureSplitViewHierarchy() {

        let trackingSplitView = SidebarTrackingSplitView()
        trackingSplitView.onDividerDragStateChanged = { [weak self] isActive in
            self?.isSidebarDividerDragActive = isActive
        }
        splitView = trackingSplitView

        threadListVC.delegate = self
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: threadListVC)
        MainWindowChromeLayout.configure(sidebarItem)
        SidebarWidthRange.configure(sidebarItem)
        // `sidebarWithViewController:` already configures `canCollapse = true`
        // as part of the sidebar behavior — no explicit assignment needed.
        // Seed the collapsed state from persistence before adding to the split view.
        // Setting `isCollapsed` directly (instead of via the animator) avoids any
        // launch-time animation while still being respected by NSSplitViewController.
        if UserDefaults.standard.bool(forKey: Self.sidebarHiddenDefaultsKey) {
            sidebarItem.isCollapsed = true
        }
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        contentContainerVC.setContent(emptyStateVC)
        let contentItem = NSSplitViewItem(contentListWithViewController: contentContainerVC)
        addSplitViewItem(contentItem)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        preferredSidebarWidth = resolvedSavedSidebarWidth()
        splitView.dividerStyle = .thin
        splitView.delegate = self
    }

    // MARK: - Keyboard Shortcuts

    override func viewWillAppear() {
        super.viewWillAppear()
        applyInitialSidebarWidthIfNeeded()
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        applyInitialSidebarWidthIfNeeded()
        setupWindowToolbar()
        installWindowFocusObserversIfNeeded()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openSettingsFromNotification),
            name: .magentOpenSettings,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigateToThread),
            name: .magentNavigateToThread,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenExternalLinkInApp(_:)),
            name: .magentOpenExternalLinkInApp,
            object: nil
        )

        reloadKeyBindings()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyBindingsDidChange),
            name: .magentKeyBindingsDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThreadReturnedToMain(_:)),
            name: .magentThreadReturnedToMain,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThreadPoppedOut(_:)),
            name: .magentThreadPoppedOut,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePopOutThreadRequested(_:)),
            name: .magentPopOutThreadRequested,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleVisibleThreadCompletionDetected(_:)),
            name: .magentAgentCompletionDetected,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleProjectVisibilityChanged(_:)),
            name: .magentProjectVisibilityDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrentThreadToolbarRefreshNeeded),
            name: .magentThreadsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrentThreadToolbarRefreshNeeded),
            name: .magentSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleCurrentThreadToolbarRefreshNeeded),
            name: .magentSectionsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePendingPromptRecoveryReminderChanged),
            name: .magentPendingPromptRecoveryReminderChanged,
            object: nil
        )
        refreshPendingPromptRecoveryToolbarItem()
    }

    /// Forwarded from the main menu's "New Thread" item (⌘N).
    @objc func requestNewThread() {
        requestNewThread(contextThread: nil, presentingWindow: nil)
    }

    func requestNewThread(contextThread: MagentThread?, presentingWindow: NSWindow?) {
        threadListVC.requestNewThread(contextThread: contextThread, presentingWindow: presentingWindow)
    }

    /// Forwarded from the main menu's "New Thread from Branch" item (⌘⇧N).
    @objc func requestNewThreadFromBranch() {
        requestNewThreadFromBranch(contextThread: nil, presentingWindow: nil)
    }

    func requestNewThreadFromBranch(contextThread: MagentThread?, presentingWindow: NSWindow?) {
        threadListVC.requestNewThreadFromBranch(contextThread: contextThread, presentingWindow: presentingWindow)
    }

    /// Forwarded from the main menu's "AI Rename" item (⌘⇧R).
    @objc func requestAIRename() {
        requestAIRename(contextThread: nil, presentingWindow: nil)
    }

    func requestAIRename(contextThread: MagentThread?, presentingWindow: NSWindow?) {
        guard let thread = contextThread ?? threadListVC.selectedThreadFromState(),
              !thread.isMain else {
            NSSound.beep()
            return
        }
        threadListVC.presentAIRenameSheet(for: thread, presentingWindow: presentingWindow)
    }

    // MARK: - Key Bindings

    @objc private func keyBindingsDidChange() {
        reloadKeyBindings()
    }

    @objc private func handleCurrentThreadToolbarRefreshNeeded() {
        refreshCurrentThreadToolbarStrip()
        refreshPendingPromptRecoveryToolbarItem()
    }

    private func reloadKeyBindings() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }

        cachedKeyBindings = PersistenceService.shared.loadSettings().keyBindings

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyEvent(event)
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        // Skip if event targets a pop-out window — let the pop-out handle its own shortcuts
        if let eventWindow = event.window,
           PopoutWindowManager.shared.isPopoutWindow(eventWindow) {
            return event
        }

        if event.magentIsBareEscapeKeyDown, dismissTopUserDismissibleBannerFromKeyboard(in: event.window) {
            return nil
        }

        let eventModifiers = KeyModifiers.from(event.modifierFlags.intersection(.deviceIndependentFlagsMask))

        if matchesBinding(.newTab, keyCode: event.keyCode, modifiers: eventModifiers) {
            newTabShortcut()
            return nil
        }
        if matchesBinding(.closeTab, keyCode: event.keyCode, modifiers: eventModifiers) {
            closeTabShortcut()
            return nil
        }
        if matchesBinding(.reopenLastClosedTab, keyCode: event.keyCode, modifiers: eventModifiers) {
            reopenLastClosedTabShortcut()
            return nil
        }
        if matchesBinding(.newThreadFromBranch, keyCode: event.keyCode, modifiers: eventModifiers) {
            requestNewThreadFromBranch()
            return nil
        }
        if matchesBinding(.newThread, keyCode: event.keyCode, modifiers: eventModifiers) {
            requestNewThread()
            return nil
        }
        if matchesBinding(.popOutThread, keyCode: event.keyCode, modifiers: eventModifiers) {
            popOutCurrentThread()
            return nil
        }
        if matchesBinding(.detachTab, keyCode: event.keyCode, modifiers: eventModifiers) {
            let settings = PersistenceService.shared.loadSettings()
            guard settings.isTabDetachFeatureEnabled else { return nil }
            _ = performDetachTabShortcut(contextThreadId: nil)
            return nil
        }
        if matchesBinding(.toggleSidebar, keyCode: event.keyCode, modifiers: eventModifiers) {
            // Key-repeat would otherwise flicker the sidebar — swallow repeats.
            guard !event.isARepeat else { return nil }
            toggleSidebar(nil)
            return nil
        }
        if matchesBinding(.recenterCurrentThread, keyCode: event.keyCode, modifiers: eventModifiers) {
            performRecenterCurrentThreadShortcut(contextThreadId: nil)
            return nil
        }

        return event
    }

    private func dismissTopUserDismissibleBannerFromKeyboard(in window: NSWindow?) -> Bool {
        if BannerManager.shared.dismissCurrentIfUserDismissible(in: window) {
            return true
        }
        return currentDetailVC?.dismissTopUserDismissibleBannerFromKeyboard() ?? false
    }

    private func matchesBinding(_ action: KeyBindingAction, keyCode: UInt16, modifiers: KeyModifiers) -> Bool {
        let binding = cachedKeyBindings.binding(for: action)
        return binding.keyCode == keyCode && binding.modifiers == modifiers
    }

    // MARK: - Sidebar Visibility

    /// Toggle the sidebar with animation and persist the new state.
    /// Routed through `toggleSidebar(_:)` so that menu items using the standard
    /// `toggleSidebar:` first-responder action get AppKit's automatic
    /// "Hide Sidebar" / "Show Sidebar" title swap for free.
    override func toggleSidebar(_ sender: Any?) {
        beginSidebarCollapseAnimationGuard()
        super.toggleSidebar(sender)
        persistSidebarHiddenState()
    }

    /// Reveal the sidebar if hidden, used by user actions that focus a
    /// thread (status bar popovers, top info strip click, navigate-to-thread
    /// notifications, restore archived). No-op if already visible.
    func revealSidebarIfHidden() {
        guard let sidebarItem, sidebarItem.isCollapsed else { return }
        beginSidebarCollapseAnimationGuard()
        sidebarItem.animator().isCollapsed = false
        persistSidebarHiddenState()
    }

    private func persistSidebarHiddenState() {
        guard let sidebarItem else { return }
        UserDefaults.standard.set(sidebarItem.isCollapsed, forKey: Self.sidebarHiddenDefaultsKey)
    }

    /// Suppress the preferred-width snap-back path in
    /// `splitViewDidResizeSubviews` while NSSplitViewController's collapse /
    /// expand animation is running. Intermediate frames have width values
    /// between 0 and `preferredSidebarWidth`; without this guard, the
    /// restore branch would call `setPosition(preferredSidebarWidth, 0)`
    /// every frame and fight the animator.
    private func beginSidebarCollapseAnimationGuard() {
        isTogglingSidebarCollapse = true
        // NSSplitViewController's collapse animation settles in ~0.25s.
        // A short margin covers settle frames and any layout side effects.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            self?.isTogglingSidebarCollapse = false
        }
    }

    private func applyInitialSidebarWidthIfNeeded() {
        guard !didApplyInitialSidebarWidth else { return }
        guard let sidebarItem else { return }
        guard splitViewItems.count >= 2 else { return }

        didApplyInitialSidebarWidth = true

        let clampedWidth = resolvedSavedSidebarWidth()
        preferredSidebarWidth = clampedWidth
        // Skip setPosition while collapsed — it would fight the persisted hidden
        // state by snapping the divider to a non-zero position and effectively
        // re-expanding the sidebar at launch.
        if !sidebarItem.isCollapsed {
            splitView.setPosition(clampedWidth, ofDividerAt: 0)
        }
        threadListVC.refreshSidebarLayout(forceColumnRefit: true)
    }

    override func splitViewDidResizeSubviews(_ notification: Notification) {
        super.splitViewDidResizeSubviews(notification)
        threadListVC.refreshSidebarLayout(forceColumnRefit: true)
        guard !isRestoringSidebarWidth else { return }
        // During the collapse/expand animation, intermediate frames carry
        // widths between 0 and `preferredSidebarWidth`. Skip the preferred-
        // width restoration path so we don't snap-back every frame.
        guard !isTogglingSidebarCollapse else { return }
        guard let sidebarItem else { return }
        let width = sidebarItem.viewController.view.frame.width
        guard width.isFinite, width > 0 else { return }
        let clampedWidth = SidebarWidthRange.clamp(width)
        let deltaFromPreferred = abs(clampedWidth - preferredSidebarWidth)

        if let enforcedSidebarWidth {
            if abs(clampedWidth - enforcedSidebarWidth) > 0.5 {
                restoreSidebarWidth(enforcedSidebarWidth)
            }
            return
        }
        if isSidebarDividerDragActive {
            preferredSidebarWidth = clampedWidth
            UserDefaults.standard.set(Double(clampedWidth), forKey: Self.sidebarWidthDefaultsKey)
            return
        }

        // Ignore spontaneous width shifts caused by internal layout changes
        // (for example when sidebar content updates after thread selection).
        // Sidebar width should only change via user divider drags.
        if deltaFromPreferred > 0.1 {
            restoreSidebarWidth(preferredSidebarWidth)
        }
    }

    private func newTabShortcut() {
        _ = performNewTabShortcut(contextThreadId: nil)
    }

    private func closeTabShortcut() {
        _ = performCloseTabShortcut(contextThreadId: nil)
    }

    private func reopenLastClosedTabShortcut() {
        _ = performReopenLastClosedTabShortcut(contextThreadId: nil)
    }

    func selectedThreadForContextRouting() -> MagentThread? {
        currentDetailVC?.thread ?? threadListVC.selectedThreadFromState()
    }

    @discardableResult
    func performNewTabShortcut(contextThreadId: UUID?) -> Bool {
        if let threadId = contextThreadId {
            if let controller = PopoutWindowManager.shared.threadWindows[threadId] {
                controller.detailVC.addTabFromKeyboard()
                return true
            }
            if let currentDetailVC, currentDetailVC.thread.id == threadId {
                currentDetailVC.addTabFromKeyboard()
                return true
            }
            if !PopoutWindowManager.shared.isThreadPoppedOut(threadId),
               ThreadManager.shared.threads.contains(where: { $0.id == threadId }) {
                threadListVC.selectThread(byId: threadId)
                if let currentDetailVC, currentDetailVC.thread.id == threadId {
                    currentDetailVC.addTabFromKeyboard()
                    return true
                }
            }
            return false
        }

        guard let currentDetailVC else { return false }
        currentDetailVC.addTabFromKeyboard()
        return true
    }

    @discardableResult
    func performCloseTabShortcut(contextThreadId: UUID?) -> Bool {
        if let threadId = contextThreadId {
            if let controller = PopoutWindowManager.shared.threadWindows[threadId] {
                controller.detailVC.closeCurrentTab()
                return true
            }
            if let currentDetailVC, currentDetailVC.thread.id == threadId {
                currentDetailVC.closeCurrentTab()
                return true
            }
            return false
        }

        guard let currentDetailVC else { return false }
        currentDetailVC.closeCurrentTab()
        return true
    }

    @discardableResult
    func performReopenLastClosedTabShortcut(contextThreadId: UUID?) -> Bool {
        if let threadId = contextThreadId {
            if let controller = PopoutWindowManager.shared.threadWindows[threadId] {
                controller.detailVC.reopenLastClosedTab()
                return true
            }
            if let currentDetailVC, currentDetailVC.thread.id == threadId {
                currentDetailVC.reopenLastClosedTab()
                return true
            }
            if !PopoutWindowManager.shared.isThreadPoppedOut(threadId),
               ThreadManager.shared.threads.contains(where: { $0.id == threadId }) {
                threadListVC.selectThread(byId: threadId)
                if let currentDetailVC, currentDetailVC.thread.id == threadId {
                    currentDetailVC.reopenLastClosedTab()
                    return true
                }
            }
            return false
        }

        guard let currentDetailVC else { return false }
        currentDetailVC.reopenLastClosedTab()
        return true
    }

    @discardableResult
    func performDetachTabShortcut(contextThreadId: UUID?) -> Bool {
        let settings = PersistenceService.shared.loadSettings()
        guard settings.isTabDetachFeatureEnabled else { return false }

        if let threadId = contextThreadId {
            if let controller = PopoutWindowManager.shared.threadWindows[threadId] {
                controller.detailVC.detachCurrentTabFromKeyboard()
                return true
            }
            if let currentDetailVC, currentDetailVC.thread.id == threadId {
                currentDetailVC.detachCurrentTabFromKeyboard()
                return true
            }
            return false
        }

        guard let currentDetailVC else { return false }
        currentDetailVC.detachCurrentTabFromKeyboard()
        return true
    }

    @discardableResult
    func performRecenterCurrentThreadShortcut(contextThreadId: UUID?) -> Bool {
        guard let threadId = contextThreadId ?? selectedThreadForContextRouting()?.id else {
            NSSound.beep()
            return false
        }

        revealSidebarIfHidden()
        threadListVC.centerAndPulseThreadRow(byId: threadId)
        return true
    }

    private func showThread(_ thread: MagentThread) {
        DevSessionLog.log(.navigation, "show-thread requested", fields: [
            "currentThreadId": currentDetailVC?.thread.id,
            "threadId": thread.id,
            "thread": thread.name,
        ])

        Task {
            // Keep thread switching from immediately killing sessions that only look
            // stale because metadata or UI state is still catching up.
            _ = await ThreadManager.shared.cleanupStaleMagentSessions(minimumStaleAge: 30)
        }

        // Sidebar items can be stale snapshots; always resolve the latest thread model.
        let resolvedThread = ThreadManager.shared.threads.first(where: { $0.id == thread.id }) ?? thread

        // Refresh statuses for the thread being deselected (so its row updates while we view another)
        if let previousId = currentDetailVC?.thread.id, previousId != resolvedThread.id,
           let previousThread = ThreadManager.shared.threads.first(where: { $0.id == previousId }) {
            ThreadManager.shared.refreshJiraTicketForSelectedThread(previousThread)
            ThreadManager.shared.refreshPRForSelectedThread(previousThread)
        }

        // Refresh Jira ticket title/status and PR status in the background
        ThreadManager.shared.refreshJiraTicketForSelectedThread(resolvedThread)
        ThreadManager.shared.refreshPRForSelectedThread(resolvedThread)

        // Skip if already showing this thread (preserves terminal scrollback)
        if currentDetailVC?.thread.id == resolvedThread.id {
            DevSessionLog.log(.navigation, "show-thread skipped already showing", fields: [
                "threadId": resolvedThread.id,
                "thread": resolvedThread.name,
            ])
            refreshCurrentThreadToolbarStrip(with: resolvedThread)
            return
        }

        // Pending threads have no worktree yet — show directly so the detail view
        // can display the creation progress overlay while setup completes in background.
        if ThreadManager.shared.pendingThreadIds.contains(resolvedThread.id) {
            presentThread(resolvedThread)
            return
        }

        // Check if worktree exists on disk
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolvedThread.worktreePath, isDirectory: &isDir) && isDir.boolValue

        if exists {
            presentThread(resolvedThread)
        } else {
            DevSessionLog.log(.navigation, "show-thread recovering missing worktree", fields: [
                "threadId": resolvedThread.id,
                "worktreePath": resolvedThread.worktreePath,
            ])
            recoverAndShowThread(resolvedThread)
        }
    }

    private func installWindowFocusObserversIfNeeded() {
        guard let window = view.window, observedWindowForFocusNotifications !== window else { return }
        if let previousWindow = observedWindowForFocusNotifications {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didBecomeKeyNotification,
                object: previousWindow
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMainWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        observedWindowForFocusNotifications = window
    }

    private func focusedThreadIdForCompletionRead() -> UUID? {
        if let detailVC = currentDetailVC {
            return detailVC.thread.id
        }
        if contentContainerVC.currentChild is DetachedThreadPlaceholderView {
            return ThreadManager.shared.activeThreadId
        }
        return nil
    }

    private func markFocusedThreadCompletionSeenIfNeeded() {
        guard view.window?.isKeyWindow == true,
              let threadId = focusedThreadIdForCompletionRead() else { return }
        ThreadManager.shared.markThreadCompletionSeen(threadId: threadId)
    }

    private func presentThread(_ thread: MagentThread) {
        DevSessionLog.log(.navigation, "present-thread", fields: [
            "threadId": thread.id,
            "thread": thread.name,
        ])
        currentDetailVC?.cacheTerminalViewsForReuse()
        let detailVC = ThreadDetailViewController(thread: thread)
        detailVC.loadViewIfNeeded()
        currentDetailVC = detailVC
        refreshCurrentThreadToolbarStrip(with: thread)
        refreshCurrentThreadToolbarActions()

        preserveSidebarWidthDuringContentChange {
            contentContainerVC.setContent(detailVC)
        }

        if AppFeatures.jiraSyncEnabled, thread.jiraUnassigned {
            BannerManager.shared.show(
                message: "This ticket is no longer assigned to you",
                style: .info,
                duration: 5.0
            )
        }
    }

    private func currentThreadSectionColor(for thread: MagentThread) -> NSColor? {
        let settings = PersistenceService.shared.loadSettings()
        guard settings.shouldUseThreadSections(for: thread.projectId) else { return nil }
        let sections = settings.sections(for: thread.projectId)
        let effectiveSectionId = ThreadManager.shared.effectiveSectionId(for: thread, settings: settings)
        return sections.first(where: { $0.id == effectiveSectionId })?.color
    }

    private func refreshCurrentThreadToolbarStrip(with selectedThread: MagentThread? = nil) {
        guard isViewLoaded else { return }

        let resolvedThread = selectedThread
            ?? currentDetailVC?.thread
            ?? threadListVC.selectedThreadFromState()

        guard let thread = resolvedThread.flatMap({ candidate in
            ThreadManager.shared.threads.first(where: { $0.id == candidate.id }) ?? candidate
        }) else {
            currentThreadToolbarStrip.isHidden = true
            return
        }

        currentThreadToolbarStrip.isHidden = false
        currentThreadToolbarStrip.configure(with: thread, sectionColor: currentThreadSectionColor(for: thread))
    }

    private func clearCurrentThreadToolbarStrip() {
        currentThreadToolbarStrip.isHidden = true
        refreshCurrentThreadToolbarActions()
    }

    private func configureCurrentThreadToolbarStackIfNeeded() {
        guard !didConfigureCurrentThreadToolbarStack else { return }
        didConfigureCurrentThreadToolbarStack = true

        currentThreadToolbarStack.orientation = .horizontal
        currentThreadToolbarStack.alignment = .centerY
        currentThreadToolbarStack.spacing = 4
        currentThreadToolbarStack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        currentThreadToolbarStack.detachesHiddenViews = true
        currentThreadToolbarStack.translatesAutoresizingMaskIntoConstraints = false
        currentThreadToolbarStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        currentThreadToolbarStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        currentThreadToolbarStack.onClick = { [weak self] in
            self?.navigateToCurrentThreadFromToolbar()
        }
        currentThreadToolbarStack.addArrangedSubview(currentThreadToolbarStrip)
        currentThreadToolbarStack.setCustomSpacing(16, after: currentThreadToolbarStrip)
    }

    private func navigateToCurrentThreadFromToolbar() {
        guard let threadId = currentDetailVC?.thread.id
            ?? threadListVC.selectedThreadFromState()?.id
        else { return }

        NotificationCenter.default.post(
            name: .magentNavigateToThread,
            object: self,
            userInfo: [
                "threadId": threadId,
                "centerInSidebar": true,
                "revealSidebarIfHidden": true,
            ]
        )
    }

    private func refreshCurrentThreadToolbarActions() {
        configureCurrentThreadToolbarStackIfNeeded()

        for view in currentThreadToolbarStack.arrangedSubviews where view !== currentThreadToolbarStrip {
            currentThreadToolbarStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard let detailVC = currentDetailVC else { return }
        let actions = detailVC.mainWindowThreadBarToolbarActions()
        guard !actions.isEmpty else { return }

        for action in actions {
            if let previousStack = action.superview as? NSStackView {
                previousStack.removeArrangedSubview(action)
            }
            action.removeFromSuperview()
            action.translatesAutoresizingMaskIntoConstraints = false
            currentThreadToolbarStack.addArrangedSubview(action)
        }
    }

    private func recoverAndShowThread(_ thread: MagentThread) {
        if thread.isMain {
            BannerManager.shared.show(
                message: "Repository not found at \(thread.worktreePath)",
                style: .error,
                duration: nil,
                isDismissible: true
            )
            return
        }

        BannerManager.shared.show(
            message: "Recreating worktree for '\(thread.name)'...",
            style: .info,
            duration: nil,
            isDismissible: false
        )

        Task {
            let result = await ThreadManager.shared.recoverWorktree(for: thread)
            await MainActor.run {
                switch result {
                case .recovered:
                    BannerManager.shared.show(
                        message: "Worktree '\(thread.name)' recovered successfully",
                        style: .info,
                        duration: 3.0
                    )
                    // Fetch updated thread from manager
                    if let updated = ThreadManager.shared.threads.first(where: { $0.id == thread.id }) {
                        presentThread(updated)
                    } else {
                        presentThread(thread)
                    }
                case .mainThreadMissing:
                    BannerManager.shared.show(
                        message: "Repository not found — cannot recover worktree",
                        style: .error,
                        duration: 5.0
                    )
                case .projectNotFound:
                    BannerManager.shared.show(
                        message: "Project no longer exists — cannot recover worktree",
                        style: .error,
                        duration: 5.0
                    )
                case .failed(let error):
                    BannerManager.shared.show(
                        message: "Failed to recover worktree: \(error.localizedDescription)",
                        style: .error,
                        duration: 5.0
                    )
                }
            }
        }
    }

    private static let settingsToolbarItemId = NSToolbarItem.Identifier("settings")
    private static let addRepositoryToolbarItemId = NSToolbarItem.Identifier("addRepository")
    private static let recentlyArchivedToolbarItemId = NSToolbarItem.Identifier("recentlyArchived")
    private static let pendingPromptRecoveryToolbarItemId = NSToolbarItem.Identifier("pendingPromptRecovery")
    private static let currentThreadToolbarItemId = NSToolbarItem.Identifier("currentThread")

    private var recentlyArchivedPopover: NSPopover?

    private func setupWindowToolbar() {
        guard let window = view.window, window.toolbar == nil else { return }
        let toolbar = NSToolbar(identifier: "MagentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        refreshCurrentThreadToolbarStrip()
        refreshPendingPromptRecoveryToolbarItem()
    }

    @objc private func handlePendingPromptRecoveryReminderChanged() {
        refreshPendingPromptRecoveryToolbarItem(animateWhenShowing: true)
    }

    private func shouldShowPendingPromptRecoveryToolbarItem() -> Bool {
        threadListVC.showsPendingPromptRecoveryReminder ||
            (currentDetailVC?.showsPendingPromptRecoveryReminder ?? false)
    }

    private func refreshPendingPromptRecoveryToolbarItem(animateWhenShowing: Bool = false) {
        guard let toolbar = view.window?.toolbar else { return }

        let shouldShow = shouldShowPendingPromptRecoveryToolbarItem()
        let existingIndex = toolbar.items.firstIndex {
            $0.itemIdentifier == Self.pendingPromptRecoveryToolbarItemId
        }

        if shouldShow {
            guard existingIndex == nil else { return }
            toolbar.insertItem(
                withItemIdentifier: Self.pendingPromptRecoveryToolbarItemId,
                at: pendingPromptRecoveryToolbarInsertionIndex(in: toolbar)
            )
            if animateWhenShowing {
                flashPendingPromptRecoveryToolbarButton()
            }
            presentPendingPromptRecoveryToolbarHintIfNeeded()
        } else if let existingIndex {
            toolbar.removeItem(at: existingIndex)
            pendingPromptRecoveryToolbarButton = nil
        }
    }

    private func pendingPromptRecoveryToolbarInsertionIndex(in toolbar: NSToolbar) -> Int {
        if let archiveIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == Self.recentlyArchivedToolbarItemId }) {
            return archiveIndex
        }
        if let settingsIndex = toolbar.items.firstIndex(where: { $0.itemIdentifier == Self.settingsToolbarItemId }) {
            return settingsIndex
        }
        return toolbar.items.count
    }

    private func flashPendingPromptRecoveryToolbarButton() {
        guard let button = pendingPromptRecoveryToolbarButton else { return }
        button.wantsLayer = true

        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [1.0, 0.45, 1.0]
        animation.keyTimes = [0.0, 0.5, 1.0]
        animation.duration = 0.9
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        button.layer?.add(animation, forKey: "magentPendingPromptRecoveryFlash")
    }

    private func presentPendingPromptRecoveryToolbarHintIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.pendingPromptRecoveryToolbarHintShownDefaultsKey) else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            self?.showPendingPromptRecoveryToolbarHint()
        }
    }

    private func showPendingPromptRecoveryToolbarHint() {
        guard let button = pendingPromptRecoveryToolbarButton,
              button.window != nil else { return }

        var hintState = PendingPromptRecoveryToolbarHintState(
            hasShownHint: UserDefaults.standard.bool(
                forKey: Self.pendingPromptRecoveryToolbarHintShownDefaultsKey
            )
        )
        guard hintState.consumeHintIfNeeded(isReminderVisible: shouldShowPendingPromptRecoveryToolbarItem()) else {
            return
        }
        UserDefaults.standard.set(
            hintState.hasShownHint,
            forKey: Self.pendingPromptRecoveryToolbarHintShownDefaultsKey
        )

        pendingPromptRecoveryToolbarHintPopover?.close()

        let label = NSTextField(wrappingLabelWithString: String(localized: .ThreadStrings.threadRecoveredPromptsToolbarHint))
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .labelColor
        label.maximumNumberOfLines = 3
        label.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView()
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            label.widthAnchor.constraint(equalToConstant: 220),
        ])

        let viewController = NSViewController()
        viewController.view = contentView

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = viewController
        pendingPromptRecoveryToolbarHintPopover = popover

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self, weak popover] in
            guard self?.pendingPromptRecoveryToolbarHintPopover === popover else { return }
            popover?.close()
            self?.pendingPromptRecoveryToolbarHintPopover = nil
        }
    }

    @objc private func pendingPromptRecoveryTapped(_ sender: Any?) {
        pendingPromptRecoveryToolbarHintPopover?.close()
        pendingPromptRecoveryToolbarHintPopover = nil
        threadListVC.showDismissedPendingPromptRecoveryBanners()
        currentDetailVC?.redisplayDismissedRecoveryBanner()
        refreshPendingPromptRecoveryToolbarItem()
    }

    @objc private func openSettingsFromNotification(_ notification: Notification) {
        settingsTapped()
    }

    @objc private func handleNavigateToThread(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID else { return }
        let tabIdentifier = notification.userInfo?["sessionName"] as? String
        let centerInSidebar = notification.userInfo?["centerInSidebar"] as? Bool ?? false

        // Pre-seed UserDefaults so a newly-created ThreadDetailViewController
        // opens on the correct tab during its async setup.
        if let tabIdentifier {
            UserDefaults.standard.set(threadId.uuidString, forKey: "MagentLastOpenedThreadID")
            UserDefaults.standard.set(tabIdentifier, forKey: "MagentLastOpenedSessionName")
        }

        // User-driven navigation should reveal the sidebar so the focused row
        // is visible. This is opt-in: posters must set
        // `userInfo["revealSidebarIfHidden"] == true` to trigger the reveal.
        // Programmatic posters (restore flows, background reconcile, etc.)
        // leave the flag off and will not silently un-hide the sidebar.
        // Closing pop-outs deliberately does not post this notification at all.
        if notification.userInfo?["revealSidebarIfHidden"] as? Bool == true {
            revealSidebarIfHidden()
        }

        selectThreadForNavigation(
            threadId: threadId,
            tabIdentifier: tabIdentifier,
            centerInSidebar: centerInSidebar,
            scrollRowToVisible: !centerInSidebar
        )
    }

    @objc private func handleMainWindowDidBecomeKey(_ notification: Notification) {
        currentDetailVC?.currentTerminalView()?.markAsActiveSurface()
        markFocusedThreadCompletionSeenIfNeeded()
    }

    @objc private func handleVisibleThreadCompletionDetected(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID,
              threadId == focusedThreadIdForCompletionRead(),
              view.window?.isKeyWindow == true else { return }
        ThreadManager.shared.markThreadCompletionSeen(threadId: threadId)
    }

    @objc private func handleOpenExternalLinkInApp(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let threadId = userInfo["threadId"] as? UUID,
              let url = userInfo["url"] as? URL,
              let identifier = userInfo["identifier"] as? String,
              let title = userInfo["title"] as? String,
              let iconRawValue = userInfo["iconType"] as? String,
              let iconType = WebTabIconType(rawValue: iconRawValue) else { return }
        let customTitle = userInfo["customTitle"] as? String

        let openTabInMainWindow = { [weak self] in
            guard let self,
                  let detailVC = self.currentDetailVC,
                  detailVC.thread.id == threadId else { return false }
            detailVC.loadViewIfNeeded()
            detailVC.openWebTab(
                url: url,
                identifier: identifier,
                title: title,
                customTitle: customTitle,
                iconType: iconType
            )
            return true
        }

        switch ExternalLinkOpenRouting.resolve(
            isThreadPoppedOut: PopoutWindowManager.shared.isThreadPoppedOut(threadId),
            isCurrentMainThread: currentDetailVC?.thread.id == threadId
        ) {
        case .poppedOutThreadWindow:
            guard let controller = PopoutWindowManager.shared.threadWindows[threadId] else { return }
            controller.detailVC.loadViewIfNeeded()
            controller.detailVC.openWebTab(
                url: url,
                identifier: identifier,
                title: title,
                customTitle: customTitle,
                iconType: iconType
            )
            PopoutWindowManager.shared.bringToFront(threadId: threadId)

        case .currentMainThread:
            _ = openTabInMainWindow()

        case .selectThreadInMainWindow:
            threadListVC.selectThread(byId: threadId)
            if openTabInMainWindow() {
                return
            }
            DispatchQueue.main.async {
                _ = openTabInMainWindow()
            }
        }
    }

    @objc private func handleProjectVisibilityChanged(_ notification: Notification) {
        guard let projectId = notification.userInfo?["projectId"] as? UUID,
              let isHidden = notification.userInfo?["isHidden"] as? Bool,
              isHidden else { return }

        let selectedInHiddenProject = threadListVC.selectedThreadFromState()?.projectId == projectId
        let hadProjectPopouts = PopoutWindowManager.shared.closePopouts(forProjectId: projectId)
        guard selectedInHiddenProject || hadProjectPopouts else { return }

        threadListVC.selectFirstAvailableThread()
        if threadListVC.selectedThreadFromState() == nil {
            showEmptyState()
        }
    }

    @objc private func recentlyArchivedTapped(_ sender: NSButton) {
        if let existing = recentlyArchivedPopover, existing.isShown {
            existing.close()
            return
        }

        let popover = NSPopover()
        popover.contentViewController = RecentlyArchivedPopoverViewController()
        popover.behavior = .transient
        popover.animates = true
        recentlyArchivedPopover = popover

        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }

    @objc private func settingsTapped() {
        if let existing = settingsWindowController?.window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsVC = SettingsSplitViewController()
        let window = NSWindow(contentViewController: settingsVC)
        window.title = String(localized: .AppStrings.settingsWindowTitle)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 900, height: 640))
        window.minSize = NSSize(width: 700, height: 500)
        window.center()
        window.delegate = self

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showEmptyState(skipTerminalCache: Bool = false) {
        if !skipTerminalCache {
            currentDetailVC?.cacheTerminalViewsForReuse()
        }
        currentDetailVC = nil
        ThreadManager.shared.setActiveThread(nil)
        clearCurrentThreadToolbarStrip()
        preserveSidebarWidthDuringContentChange {
            contentContainerVC.setContent(emptyStateVC)
        }
    }

    // MARK: - Pop-out Windows

    private func presentDetachedThreadPlaceholder(_ thread: MagentThread) {
        currentDetailVC?.cacheTerminalViewsForReuse()
        currentDetailVC = nil
        let placeholder = DetachedThreadPlaceholderView(thread: thread)
        placeholder.onShowWindow = { PopoutWindowManager.shared.bringToFront(threadId: thread.id) }
        placeholder.onReturnToMain = {
            PopoutWindowManager.shared.returnThreadToMain(thread.id)
        }
        preserveSidebarWidthDuringContentChange {
            contentContainerVC.setContent(placeholder)
        }
    }

    func popOutCurrentThread() {
        guard let detailVC = currentDetailVC else { return }
        let thread = detailVC.thread
        guard !thread.isMain else { return }
        guard !ThreadManager.shared.pendingThreadIds.contains(thread.id) else { return }

        detailVC.cacheTerminalViewsForReuse()
        currentDetailVC = nil
        clearCurrentThreadToolbarStrip()
        PopoutWindowManager.shared.popOutThread(thread, from: view.window)
        selectFallbackMainThread(afterPoppingOut: thread.id)
        threadListVC.refreshThreadRowInPlace(threadId: thread.id)
    }

    @objc private func handleThreadReturnedToMain(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID else { return }
        if threadListVC.diffInspectionThreadID == threadId {
            threadListVC.setDiffInspectionContextToSelectedThread()
            if shouldFocusMainWindowAfterThreadReturn() {
                focusMainWindowAndCurrentThread()
            }
        }
        threadListVC.refreshThreadRowInPlace(threadId: threadId)
    }

    @objc private func handleThreadPoppedOut(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID else { return }
        if threadListVC.selectedThreadID == threadId {
            selectFallbackMainThread(afterPoppingOut: threadId)
        }
        threadListVC.refreshThreadRowInPlace(threadId: threadId)
    }

    @objc private func handlePopOutThreadRequested(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID else { return }
        // Only replace the main content with the detached placeholder when the
        // currently active thread is the one being popped out.
        if let detailVC = currentDetailVC, detailVC.thread.id == threadId {
            popOutCurrentThread()
        } else if let thread = ThreadManager.shared.threads.first(where: { $0.id == threadId }) {
            PopoutWindowManager.shared.popOutThread(thread, from: view.window)
            if threadListVC.selectedThreadID == threadId {
                selectFallbackMainThread(afterPoppingOut: threadId)
            }
            threadListVC.refreshThreadRowInPlace(threadId: thread.id)
        }
    }

    private func selectFallbackMainThread(afterPoppingOut threadId: UUID) {
        let fallback = ThreadManager.shared.threads.first { thread in
            thread.id != threadId && !PopoutWindowManager.shared.isThreadPoppedOut(thread.id)
        }
        guard let fallback else {
            showEmptyState()
            return
        }
        // Fallback selection happens as a side-effect of pop-out (including drop-to-replace
        // and move-between-popouts). The user's scroll position in the sidebar should not
        // jump to wherever the fallback row happens to live.
        threadListVC.selectThread(byId: fallback.id, scrollRowToVisible: false)
    }

    private func focusMainWindowAndCurrentThread() {
        NSApp.activate(ignoringOtherApps: true)
        view.window?.makeKeyAndOrderFront(nil)
        currentDetailVC?.focusCurrentTabForNavigation()
    }

    private func shouldFocusMainWindowAfterThreadReturn() -> Bool {
        // If the user is actively working in another pop-out window, do not
        // steal focus back to the main window just because a different
        // pop-out thread was returned to main.
        if let keyWindow = NSApp.keyWindow,
           PopoutWindowManager.shared.isPopoutWindow(keyWindow) {
            return false
        }
        return true
    }

    private func preserveSidebarWidthDuringContentChange(_ change: () -> Void) {
        let preservedWidth = currentSidebarWidth() ?? preferredSidebarWidth
        enforcedSidebarWidth = preservedWidth
        change()
        restoreSidebarWidth(preservedWidth)
        DispatchQueue.main.async { [weak self] in
            self?.restoreSidebarWidth(preservedWidth)
            DispatchQueue.main.async { [weak self] in
                if self?.enforcedSidebarWidth == preservedWidth {
                    self?.enforcedSidebarWidth = nil
                }
            }
        }
    }

    private func currentSidebarWidth() -> CGFloat? {
        guard let sidebarItem else { return nil }
        let width = sidebarItem.viewController.view.frame.width
        guard width.isFinite, width > 0 else { return nil }
        return SidebarWidthRange.clamp(width)
    }

    private func resolvedSavedSidebarWidth() -> CGFloat {
        guard sidebarItem != nil else { return Self.defaultSidebarWidth }
        let savedWidth = UserDefaults.standard.object(forKey: Self.sidebarWidthDefaultsKey) as? Double
        let targetWidth = CGFloat(savedWidth ?? Double(Self.defaultSidebarWidth))
        return SidebarWidthRange.clamp(targetWidth)
    }

    private func restoreSidebarWidth(_ width: CGFloat?) {
        guard let width else { return }
        guard sidebarItem != nil else { return }
        guard splitViewItems.count >= 2 else { return }
        let clampedWidth = SidebarWidthRange.clamp(width)
        if let currentWidth = currentSidebarWidth(), abs(currentWidth - clampedWidth) <= 0.5 {
            preferredSidebarWidth = clampedWidth
            return
        }

        preferredSidebarWidth = clampedWidth
        isRestoringSidebarWidth = true
        defer { isRestoringSidebarWidth = false }
        splitView.layoutSubtreeIfNeeded()
        splitView.setPosition(clampedWidth, ofDividerAt: 0)
        threadListVC.refreshSidebarLayout(forceColumnRefit: true)
    }

    override func splitView(
        _ splitView: NSSplitView,
        constrainSplitPosition proposedPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard dividerIndex == 0 else {
            return proposedPosition
        }
        let allowsMovement = isSidebarDividerDragActive
            || isTogglingSidebarCollapse
            || sidebarItem?.isCollapsed == true
        return SidebarSplitPositionPolicy.position(
            proposed: proposedPosition,
            preferred: preferredSidebarWidth,
            enforced: enforcedSidebarWidth,
            allowsMovement: allowsMovement
        )
    }

    private func selectThreadForNavigation(
        threadId: UUID,
        thread threadSnapshot: MagentThread? = nil,
        tabIdentifier: String?,
        centerInSidebar: Bool,
        scrollRowToVisible: Bool
    ) {
        DevSessionLog.log(.navigation, "select-thread-for-navigation", fields: [
            "centerInSidebar": centerInSidebar,
            "scrollRowToVisible": scrollRowToVisible,
            "tabIdentifier": tabIdentifier,
            "threadId": threadId,
        ])
        let resolvedThread = ThreadManager.shared.threads.first(where: { $0.id == threadId }) ?? threadSnapshot
        guard let resolvedThread else {
            DevSessionLog.log(.navigation, "select-thread aborted missing thread", fields: [
                "threadId": threadId,
            ])
            return
        }

        if let tabIdentifier,
           PopoutWindowManager.shared.isTabDetached(sessionName: tabIdentifier) {
            DevSessionLog.log(.navigation, "select-thread routed to detached tab", fields: [
                "session": tabIdentifier,
                "threadId": threadId,
            ])
            PopoutWindowManager.shared.bringToFront(sessionName: tabIdentifier)
            markFocusedThreadCompletionSeenIfNeeded()
            return
        }

        if PopoutWindowManager.shared.isThreadPoppedOut(threadId) {
            DevSessionLog.log(.navigation, "select-thread routed to popped-out thread", fields: [
                "threadId": threadId,
                "thread": resolvedThread.name,
            ])
            if let tabIdentifier,
               let popout = PopoutWindowManager.shared.threadWindows[threadId],
               let tabIndex = popout.detailVC.displayIndex(forIdentifier: tabIdentifier) {
                popout.detailVC.selectTab(at: tabIndex)
            }
            PopoutWindowManager.shared.bringToFront(threadId: threadId)
            threadListVC.setDiffInspectionContext(threadId: threadId, isPopoutContext: true)
            threadListVC.centerAndPulseThreadRow(byId: threadId)
            markFocusedThreadCompletionSeenIfNeeded()
            return
        }

        let alreadyShowing = currentDetailVC?.thread.id == threadId
        DevSessionLog.log(.navigation, "select-thread will show in main", fields: [
            "alreadyShowing": alreadyShowing,
            "threadId": threadId,
            "thread": resolvedThread.name,
        ])
        ThreadManager.shared.setActiveThread(threadId)
        _ = threadListVC.selectThread(
            byId: threadId,
            scrollRowToVisible: scrollRowToVisible,
            forceNotifyDelegate: false,
            notifyDelegate: false
        )
        if centerInSidebar {
            threadListVC.centerAndPulseThreadRow(byId: threadId)
        }
        showThread(resolvedThread)

        if let tabIdentifier,
           let detailVC = currentDetailVC,
           let tabIndex = detailVC.displayIndex(forIdentifier: tabIdentifier) {
            detailVC.selectTab(at: tabIndex)
        } else if alreadyShowing || tabIdentifier == nil {
            currentDetailVC?.focusCurrentTabForNavigation()
        }

        markFocusedThreadCompletionSeenIfNeeded()
        threadListVC.refreshDiffPanelForSelectedThread()
    }
}

// MARK: - ThreadListDelegate

extension SplitViewController: ThreadListDelegate {
    func threadList(_ controller: ThreadListViewController, didSelectThread thread: MagentThread) {
        selectThreadForNavigation(
            threadId: thread.id,
            thread: thread,
            tabIdentifier: nil,
            centerInSidebar: false,
            scrollRowToVisible: true
        )
    }

    func threadList(_ controller: ThreadListViewController, didRenameThread thread: MagentThread) {
        // Update thread reference and rebind onCopy closures to new tmux session names.
        // Existing terminal connections survive rename since tmux rename-session keeps clients attached.
        guard currentDetailVC?.thread.id == thread.id else { return }
        currentDetailVC?.handleRename(thread)
    }

    func threadList(_ controller: ThreadListViewController, didArchiveThread thread: MagentThread) {
        if currentDetailVC?.thread.id == thread.id {
            showEmptyState(skipTerminalCache: true)
        }
    }

    func threadList(_ controller: ThreadListViewController, didDeleteThread thread: MagentThread) {
        if currentDetailVC?.thread.id == thread.id {
            showEmptyState(skipTerminalCache: true)
        }
    }

    func threadListDidRequestSettings(_ controller: ThreadListViewController) {
        settingsTapped()
    }
}

// MARK: - NSToolbarDelegate

extension SplitViewController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        if itemIdentifier == .sidebarTrackingSeparator {
            return MainWindowChromeLayout.sidebarTrackingSeparator(for: splitView)
        }
        if itemIdentifier == Self.currentThreadToolbarItemId {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = String(localized: .ThreadStrings.threadInfoMainWorktree)
            item.paletteLabel = item.label
            configureCurrentThreadToolbarStackIfNeeded()
            currentThreadToolbarStrip.translatesAutoresizingMaskIntoConstraints = false
            if !didInstallCurrentThreadToolbarSizingConstraints {
                didInstallCurrentThreadToolbarSizingConstraints = true
                let preferredStripWidth = currentThreadToolbarStrip.widthAnchor.constraint(
                    greaterThanOrEqualToConstant: ThreadToolbarCapsuleLayout.preferredThreadSummaryWidth
                )
                ThreadToolbarCapsuleLayout.configurePreferredThreadSummaryWidth(preferredStripWidth)
                NSLayoutConstraint.activate([
                    preferredStripWidth,
                    currentThreadToolbarStrip.widthAnchor.constraint(
                        lessThanOrEqualToConstant: ThreadToolbarCapsuleLayout.maximumThreadSummaryWidth
                    ),
                    currentThreadToolbarStack.widthAnchor.constraint(
                        greaterThanOrEqualToConstant: ThreadToolbarCapsuleLayout.minimumToolbarContentWidth
                    ),
                    currentThreadToolbarStack.widthAnchor.constraint(
                        lessThanOrEqualToConstant: ThreadToolbarCapsuleLayout.maximumToolbarContentWidth
                    ),
                ])
            }
            item.view = currentThreadToolbarStack
            refreshCurrentThreadToolbarStrip()
            refreshCurrentThreadToolbarActions()
            return item
        }
        if itemIdentifier == Self.recentlyArchivedToolbarItemId {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let title = "Recently Archived"
            item.label = title
            item.toolTip = title
            let button = NSButton()
            button.image = NSImage(systemSymbolName: "archivebox", accessibilityDescription: title)
            button.bezelStyle = .texturedRounded
            button.target = self
            button.action = #selector(recentlyArchivedTapped(_:))
            button.isBordered = false
            item.view = button
            return item
        }
        if itemIdentifier == Self.addRepositoryToolbarItemId {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let title = String(localized: .AppStrings.repositoryAddToolbarTitle)
            item.label = title
            item.toolTip = title
            let button = NSButton()
            let imageConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
            button.image = NSImage(
                systemSymbolName: "folder.badge.plus",
                accessibilityDescription: title
            )?.withSymbolConfiguration(imageConfiguration)
            button.bezelStyle = .texturedRounded
            button.target = threadListVC
            button.action = #selector(ThreadListViewController.addRepoButtonTapped(_:))
            button.isBordered = false
            item.view = button
            return item
        }
        if itemIdentifier == Self.pendingPromptRecoveryToolbarItemId {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let title = String(localized: .ThreadStrings.threadShowRecoveredPrompts)
            item.label = title
            item.toolTip = title
            let button = NSButton()
            button.title = ""
            button.image = pendingPromptRecoveryToolbarImage(accessibilityDescription: title)
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.bezelStyle = .texturedRounded
            button.target = self
            button.action = #selector(pendingPromptRecoveryTapped(_:))
            button.isBordered = false
            item.view = button
            pendingPromptRecoveryToolbarButton = button
            return item
        }
        if itemIdentifier == Self.settingsToolbarItemId {
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let settingsTitle = String(localized: .CommonStrings.commonSettings)
            item.label = settingsTitle
            item.toolTip = settingsTitle
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: settingsTitle)
            item.target = self
            item.action = #selector(settingsTapped)
            return item
        }
        return nil
    }

    private func pendingPromptRecoveryToolbarImage(accessibilityDescription: String) -> NSImage? {
        NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: accessibilityDescription)
            ?? NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: accessibilityDescription)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        MainWindowChromeLayout.defaultToolbarItemIdentifiers(
            currentThread: Self.currentThreadToolbarItemId,
            addRepository: Self.addRepositoryToolbarItemId,
            recentlyArchived: Self.recentlyArchivedToolbarItemId,
            settings: Self.settingsToolbarItemId
        )
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .sidebarTrackingSeparator,
            Self.currentThreadToolbarItemId,
            .flexibleSpace,
            Self.addRepositoryToolbarItemId,
            Self.pendingPromptRecoveryToolbarItemId,
            Self.recentlyArchivedToolbarItemId,
            Self.settingsToolbarItemId,
        ]
    }
}

extension SplitViewController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        if closingWindow == settingsWindowController?.window {
            settingsWindowController = nil
        }
    }
}
