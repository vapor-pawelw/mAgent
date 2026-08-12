import Cocoa
import GhosttyBridge
import MagentCore

// MARK: - AppBackgroundView

/// NSView that keeps its layer background synced with the .appBackground color asset
/// across both light and dark appearance changes.
final class AppBackgroundView: NSView {
    var onEffectiveAppearanceChanged: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
        onEffectiveAppearanceChanged?()
    }

    private func updateBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
        }
    }
}

@MainActor
final class ReusableTerminalViewCache {
    static let shared = ReusableTerminalViewCache()

    static let maxIdleAge: TimeInterval = 60 * 60

    private struct Entry {
        let sessionName: String
        let view: TerminalSurfaceView
        var reuseKey: String
        let cachedAt: Date
        var lastAccessedAt: Date
    }

    private var entriesBySession: [String: Entry] = [:]
    private var fifoSessionNames: [String] = []

    func take(sessionName: String, reuseKey: String) -> TerminalSurfaceView? {
        pruneExpiredEntries()
        guard var entry = entriesBySession.removeValue(forKey: sessionName) else { return nil }
        guard entry.reuseKey == reuseKey else {
            fifoSessionNames.removeAll { $0 == sessionName }
            entry.view.freeSurfaceForShutdown()
            return nil
        }
        fifoSessionNames.removeAll { $0 == sessionName }
        entry.lastAccessedAt = Date()
        return entry.view
    }

    func store(_ view: TerminalSurfaceView, sessionName: String, reuseKey: String) {
        pruneExpiredEntries()
        if var existing = entriesBySession[sessionName], existing.view === view {
            existing.reuseKey = reuseKey
            existing.lastAccessedAt = Date()
            entriesBySession[sessionName] = existing
            fifoSessionNames.removeAll { $0 == sessionName }
            fifoSessionNames.append(sessionName)
            view.preserveSurfaceOnDetach = true
            return
        }
        remove(sessionName: sessionName)

        view.preserveSurfaceOnDetach = true
        view.removeFromSuperview()
        view.isHidden = true

        let now = Date()
        entriesBySession[sessionName] = Entry(
            sessionName: sessionName,
            view: view,
            reuseKey: reuseKey,
            cachedAt: now,
            lastAccessedAt: now
        )
        fifoSessionNames.append(sessionName)
        evictOverflowIfNeeded()
    }

    func remove(sessionName: String) {
        let entry = entriesBySession.removeValue(forKey: sessionName)
        fifoSessionNames.removeAll { $0 == sessionName }
        entry?.view.freeSurfaceForShutdown()
    }

    func removeAll() {
        let views = entriesBySession.values.map(\.view)
        entriesBySession.removeAll()
        fifoSessionNames.removeAll()
        for view in views {
            view.freeSurfaceForShutdown()
        }
    }

    func pruneToConfiguredLimit() {
        pruneExpiredEntries()
        evictOverflowIfNeeded()
    }

    func handleMemoryPressure(_ pressure: TerminalSurfaceCachePressure) {
        pruneExpiredEntries()
        trim(to: TerminalSurfaceCachePolicy.retainedCount(
            currentCount: entriesBySession.count,
            pressure: pressure
        ))
    }

    /// Evict cached views whose sessions are about to be killed (archive/delete).
    /// This prevents ghostty from calling _exit() when the PTY closes on a cached surface.
    func evictSessions(_ sessionNames: [String]) {
        for name in sessionNames {
            remove(sessionName: name)
        }
    }

    private func pruneExpiredEntries(now: Date = Date()) {
        let expiredSessionNames = entriesBySession.compactMap { sessionName, entry -> String? in
            guard now.timeIntervalSince(entry.lastAccessedAt) > Self.maxIdleAge else { return nil }
            return sessionName
        }
        guard !expiredSessionNames.isEmpty else { return }
        for sessionName in expiredSessionNames {
            remove(sessionName: sessionName)
        }
    }

    private func evictOverflowIfNeeded() {
        guard let maxCachedViews = PersistenceService.shared.loadSettings().terminalSurfaceCacheLimit else { return }
        trim(to: maxCachedViews)
    }

    private func trim(to retainedCount: Int) {
        while entriesBySession.count > retainedCount {
            guard let oldestSessionName = fifoSessionNames.first else { return }
            remove(sessionName: oldestSessionName)
        }
    }
}

// MARK: - ThreadDetailViewController

final class ThreadDetailViewController: NSViewController {
    let isPopoutContext: Bool
    static let lastOpenedThreadDefaultsKey = "MagentLastOpenedThreadID"
    static let lastOpenedTabDefaultsKey = "MagentLastOpenedSessionName"
    static let promptTOCPositionDefaultsPrefix = "MagentPromptTOCPosition"
    static let promptTOCSizeDefaultsPrefix = "MagentPromptTOCSize"
    static let promptTOCVisibilityDefaultsKey = "MagentPromptTOCVisibilityHidden"
    static let promptTOCPinnedDefaultsKey = "MagentPromptTOCPinned"
    static let promptTOCMinimumWidth: CGFloat = 320
    static let promptTOCMinimumHeight: CGFloat = 250
    static let promptTOCCollapsedWidth: CGFloat = 185
    static let promptTOCCollapsedHeight: CGFloat = 36

    let showsHeaderInfoStrip: Bool
    var thread: MagentThread
    let threadManager = ThreadManager.shared
    let headerInfoStrip = PopoutInfoStripView()
    let tabBarStack = NSStackView()
    let fixedTabBarStack = NSStackView()
    let tabBarScrollView = TabBarScrollView()
    let tabScrollLeftButton = NSButton()
    let tabScrollRightButton = NSButton()
    let terminalContainer: NSView = AppBackgroundView()
    let topBar = NSStackView()
    let openPRButton = MiddleClickButton()
    let openInJiraButton = MiddleClickButton()
    let openInXcodeButton = NSButton()
    let openInFinderButton = NSButton()
    let resyncLocalPathsButton = NSButton()
    let archiveThreadButton = NSButton()
    let reviewButton = NSButton()
    let continueInButton = NSButton()
    let exportContextButton = NSButton()
    let popOutThreadButton = NSButton()
    let terminalBannerOverlay = BannerOverlayView()
    let scrollOverlay = TerminalScrollOverlayView()
    let togglePromptTOCButton = NSButton()
    let addTabButton = NSButton()
    let floatingScrollToBottomButton = TerminalScrollToBottomPillButton()

    // MARK: - Tab Slot Model
    /// Display-order mapping: `tabSlots[i]` tells what content `tabItems[i]` shows.
    enum TabSlot: Equatable {
        case terminal(sessionName: String)
        case diff
        case web(identifier: String)
        case draft(identifier: String)
        case chat(identifier: String)

        var focusTarget: ThreadTabFocusTarget {
            let contentKind: ThreadTabContentKind = switch self {
            case .terminal:
                .terminal
            case .diff:
                .web
            case .web:
                .web
            case .draft:
                .draft
            case .chat:
                .chat
            }
            return ThreadTabFocusResolver.focusTarget(for: contentKind)
        }
        func identity(permanentTerminalSessionName: String?) -> ThreadTabIdentity {
            switch self {
            case .terminal(let sessionName):
                return .terminal(
                    sessionName: sessionName,
                    permanentTerminalSessionName: permanentTerminalSessionName
                )
            case .diff:
                return .permanentDiff
            case .web(let identifier):
                return .web(identifier)
            case .draft(let identifier):
                return .draft(identifier)
            case .chat(let identifier):
                return .chat(identifier)
            }
        }

        var displayOrderIdentifier: String? {
            switch self {
            case .terminal(let sessionName): "terminal:\(sessionName)"
            case .web(let identifier): "web:\(identifier)"
            case .draft(let identifier): "draft:\(identifier)"
            case .chat(let identifier): "chat:\(identifier)"
            case .diff: nil
            }
        }
    }
    var tabItems: [TabItemView] = []
    var tabSlots: [TabSlot] = []
    /// Terminal views indexed by `thread.tmuxSessionNames` (creation order, NOT display order).
    var terminalViews: [TerminalSurfaceView] = []
    /// Web tab entries in creation order (NOT display order).
    var webTabs: [WebTabEntry] = []
    var draftTabs: [DraftTabEntry] = []
    var chatTabs: [ChatTabEntry] = []
    var chatRequestTasksByIdentifier: [String: Task<Void, Never>] = [:]
    var chatRequestTaskTokensByIdentifier: [String: UUID] = [:]
    var chatCoordinatedRequestIDsByIdentifier: [String: UUID] = [:]
    var chatPendingAssistantMessageIDsByIdentifier: [String: UUID] = [:]
    var chatStreamingAssistantMessageIDsByIdentifier: [String: [String: UUID]] = [:]
    var chatStreamingAssistantMessageIndicesByIdentifier: [String: [String: Int]] = [:]
    var chatTabIndicesByIdentifier: [String: Int] = [:]
    var chatStreamingCheckpointTasksByIdentifier: [String: Task<Void, Never>] = [:]
    var chatDraftPersistenceTasksByIdentifier: [String: Task<Void, Never>] = [:]
    var chatPersistenceScheduleState = ChatPersistenceScheduleState()
    var chatStreamingUIRefreshTasksByIdentifier: [String: Task<Void, Never>] = [:]
    var chatStreamingLastUIRefreshAtByIdentifier: [String: Date] = [:]
    var chatSteerChannelsByIdentifier: [String: AgentChatSteerChannel] = [:]
    var chatQueuedPromptsByIdentifier: [String: [(messageID: UUID, text: String, attachments: [PersistedChatAttachment])]] = [:]
    var chatAutoRenameTasksByIdentifier: [String: Task<Void, Never>] = [:]
    var onChatRequestActivityChanged: ((Bool) -> Void)?
    var activeDraftTabId: String?
    var activeWebTabId: String?
    var activeChatTabId: String?
    var currentTabIndex = 0
    /// Number of leading fixed tabs that cannot be closed/reordered.
    static let permanentTabCount = 2
    var permanentTerminalSessionName: String?
    var pinnedCount = 0
    /// Placeholder views shown for detached tabs, keyed by sessionName.
    var detachedTabPlaceholders: [String: DetachedTabPlaceholderView] = [:]
    var loadingOverlay: NSView?
    var loadingLabel: NSTextField?
    var loadingDetailLabel: NSTextField?
    var loadingPollTimer: Timer?
    /// Debounces the reveal of `loadingOverlay` so fast-path session prep
    /// (e.g. revisiting a known-good thread) never shows the overlay at all.
    /// Cancelled by `dismissLoadingOverlay()`.
    var loadingOverlayRevealTimer: Timer?
    var loadingOverlaySessionName: String?
    /// Set to true while `injectAfterStart` has a prompt in-flight; prevents the
    /// poll timer from dismissing the overlay before keys are actually sent.
    var loadingOverlayWaitingForInjection = false
    var loadingOverlayInjectionObservers: [NSObjectProtocol] = []
    var initialPromptFailureBanner: BannerView?
    var initialPromptFailureBannerSessionName: String?
    var initialPromptFailureBannerTopConstraint: NSLayoutConstraint?
    var pendingPromptBanner: BannerView?
    var pendingPromptBannerSessionName: String?
    var pendingPromptBannerTopConstraint: NSLayoutConstraint?
    var recoveryBanner: BannerView?
    var recoveryBannerTopConstraint: NSLayoutConstraint?
    var agentShellBanner: BannerView?
    var agentShellBannerSessionName: String?
    var agentShellBannerPendingSessionName: String?
    var agentShellBannerRevealTask: Task<Void, Never>?
    var agentStartRequestedSessions: Set<String> = []
    private var pendingPromptRecoveryReminderState = PendingPromptRecoveryReminderState()
    var showsPendingPromptRecoveryReminder: Bool {
        pendingPromptRecoveryReminderState.isReminderVisible
    }

    @discardableResult
    func dismissTopUserDismissibleBannerFromKeyboard() -> Bool {
        terminalBannerOverlay.dismissTopUserDismissibleBannerFromKeyboard()
    }
    var preparedSessions: Set<String> = []
    var reusableSurfacePreparedSessions: Set<String> = []
    var sessionPreparationTasks: [String: Task<Bool, Never>] = [:]
    var sessionPreparationTaskTokens: [String: UUID] = [:]
    var backgroundSessionPreparationTask: Task<Void, Never>?
    var startupOverlayRequiredSessions: Set<String> = []
    var emptyStateView: NSView?
    var promptTOCView: PromptTableOfContentsView?
    var promptTOCTopConstraint: NSLayoutConstraint?
    var promptTOCTrailingConstraint: NSLayoutConstraint?
    var promptTOCWidthConstraint: NSLayoutConstraint?
    var promptTOCHeightConstraint: NSLayoutConstraint?
    var promptTOCFloatingConstraints: [NSLayoutConstraint] = []
    var promptTOCPinnedConstraints: [NSLayoutConstraint] = []
    var terminalTrailingToViewConstraint: NSLayoutConstraint?
    var terminalTrailingToPromptTOCConstraint: NSLayoutConstraint?
    var promptTOCPinnedWidthConstraint: NSLayoutConstraint?
    var promptTOCPinnedResizeStartWidth: CGFloat = 0
    var isPromptTOCPinned = false
    var promptTOCRefreshTask: Task<Void, Never>?
    var promptTOCPeriodicRefreshTask: Task<Void, Never>?
    var promptTOCNavigationTask: Task<Void, Never>?
    var promptTOCNavigationGeneration: UUID?
    var promptTOCEmptyCaptureRetryAttemptedSessions: Set<String> = []
    var promptTOCEntries: [PromptTOCEntry] = []
    var promptTOCTranscriptRefinedSignatures: [String: String] = [:]
    var promptTOCTranscriptRefinementInFlightSessions: Set<String> = []
    var promptTOCSessionName: String?
    var scrollOverlayTrailingConstraint: NSLayoutConstraint?
    var scrollOverlayBottomConstraint: NSLayoutConstraint?
    var scrollOverlayDragStartTrailing: CGFloat = 16
    var scrollOverlayDragStartBottom: CGFloat = 16
    var scrollFABRefreshTask: Task<Void, Never>?
    var isScrollFABVisible = false
    var scrollFABAnimationGeneration: UInt = 0

    var promptTOCDragStartOrigin: NSPoint = .zero
    var promptTOCExpandedSize: NSSize = NSSize(width: 320, height: 250)
    var promptTOCResizeStartSize: NSSize = .zero
    var promptTOCResizeStartTop: CGFloat = 0
    var promptTOCResizeStartTrailing: CGFloat = 0
    var promptTOCCanShowForCurrentTab = false
    var showScrollToBottomIndicator = true
    var showTerminalScrollOverlay = true
    var showPromptTOCOverlay = true
    var currentTerminalMouseWheelBehavior: TerminalMouseWheelBehavior?
    /// Number of local terminal-tab creations currently in flight where this
    /// controller should own selection/reconciliation and ignore external
    /// structure-rebuild churn from `magentThreadsDidChange`.
    var localAutoSwitchTabCreationsInFlight = 0

    // MARK: - Inline Diff Viewer
    var diffVC: InlineDiffViewController?
    var isLoadingDiffViewer = false
    /// The commit hash currently shown in the diff viewer, or nil for working-tree diff.
    var currentDiffCommitHash: String? = nil
    /// When true, the diff viewer shows working-tree changes only (ignores base branch).
    var currentDiffForceWorkingTree: Bool = false
    var terminalBottomToView: NSLayoutConstraint?
    var terminalBottomToDiff: NSLayoutConstraint?
    var diffHeightConstraint: NSLayoutConstraint?
    var diffImageOverlay: DiffImageOverlayView?
    var isDiffDragging = false
    var diffDragStartHeight: CGFloat = 0
    var diffTabTitleRefreshGeneration = 0
    static let diffMinHeight: CGFloat = 100
    static let diffDefaultRatio: CGFloat = 0.7
    static let diffHeightKey = "InlineDiffViewController.height"
    static let diffMaxFileCount = 2_000
    static let diffMaxLineCount = 60_000
    static let diffTabTitle = "Diff"
    static let terminalTabTitle = "Terminal"

    let prJiraSeparator = VerticalSeparatorView()
    let pinSeparator = VerticalSeparatorView()
    let fixedTabsSeparator = VerticalSeparatorView()
    let archiveSeparator = VerticalSeparatorView()

    private var usesMainWindowToolbarThreadBar: Bool {
        showsHeaderInfoStrip && !isPopoutContext
    }

    init(thread: MagentThread, showsHeaderInfoStrip: Bool = true, isPopoutContext: Bool = false) {
        self.isPopoutContext = isPopoutContext
        self.showsHeaderInfoStrip = showsHeaderInfoStrip
        self.thread = thread
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = AppBackgroundView()
        rootView.onEffectiveAppearanceChanged = { [weak self] in
            self?.refreshTerminalChromeAppearance()
        }
        view = rootView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor

        GhosttyAppManager.shared.initialize()

        setupUI()
        startPeriodicPromptTOCRefresh()
        refreshOpenPRButtonIcon()
        refreshJiraButton()
        refreshXcodeButton()
        refreshReviewButtonVisibility()
        ensureLoadingOverlay()
        // Guarantee the thread switch shows *something* even before the async
        // setupTabs() reaches its own overlay calls. Debounced reveal keeps
        // fast-path switches flash-free; setupTabs either overwrites this label
        // (via startLoadingOverlayTracking / showCreationOverlay) or dismisses
        // it explicitly along every exit path.
        loadingLabel?.stringValue = "Loading thread..."
        revealLoadingOverlay(after: 0.25)
        currentTerminalMouseWheelBehavior = PersistenceService.shared.loadSettings().terminalMouseWheelBehavior

        // Observe Keep Alive changes (from sidebar thread context menu)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleKeepAliveChanged(_:)),
            name: .magentKeepAliveChanged,
            object: nil
        )

        // Observe dead session notifications for mid-use terminal replacement
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeadSessionsNotification(_:)),
            name: .magentDeadSessionsDetected,
            object: nil
        )

        // Observe agent completion notifications for tab dot indicators
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAgentCompletionNotification(_:)),
            name: .magentAgentCompletionDetected,
            object: nil
        )

        // Observe agent waiting-for-input notifications for tab dot indicators
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAgentWaitingNotification(_:)),
            name: .magentAgentWaitingForInput,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAgentBusyNotification(_:)),
            name: .magentAgentBusySessionsChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAgentShellStateChanged),
            name: .magentAgentShellStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAgentRateLimitNotification(_:)),
            name: .magentAgentRateLimitChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTerminalCorruptionNotification(_:)),
            name: .magentTerminalCorruptionChanged,
            object: nil
        )

        // Observe PR info changes for button title updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePullRequestInfoChanged),
            name: .magentPullRequestInfoChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleJiraTicketInfoChanged),
            name: .magentJiraTicketInfoChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePromptTOCVisibilityChanged),
            name: .magentPromptTOCVisibilityChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsChanged(_:)),
            name: .magentSettingsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSectionsDidChange),
            name: .magentSectionsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThreadsDidChange),
            name: .magentThreadsDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabAutoRenameStateChanged(_:)),
            name: .magentTabAutoRenameStateChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDiffFileCountChanged(_:)),
            name: .magentDiffFileCountChanged,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowDiffViewerNotification(_:)),
            name: .magentShowDiffViewer,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleHideDiffViewerNotification(_:)),
            name: .magentHideDiffViewer,
            object: nil
        )

        // Observe ghostty scrollbar updates to show/hide floating scroll-to-bottom button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollbarUpdate(_:)),
            name: GhosttyAppManager.ghosttyScrollbarUpdated,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThreadCreationFinished(_:)),
            name: .magentThreadCreationFinished,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabWillCloseNotification(_:)),
            name: .magentTabWillClose,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInitialPromptInjectionFailedNotification(_:)),
            name: .magentInitialPromptInjectionFailed,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAgentKeysInjectedNotification(_:)),
            name: .magentAgentKeysInjected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePendingPromptInjectionNotification(_:)),
            name: .magentPendingPromptInjection,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePendingPromptRecoveryNotification(_:)),
            name: .magentPendingPromptRecovery,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTabReturnedToThread(_:)),
            name: .magentTabReturnedToThread,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stageChatStateForPersistence),
            name: .magentStageChatStateForPersistence,
            object: nil
        )

        refreshRecoveryBanner()
        refreshAgentShellBanner()

        Task {
            await setupTabs()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        clampPromptTOCPositionIfNeeded()
        refreshTabScrollArrowsVisibility()
    }


    /// Clean up views that live outside our own view hierarchy (e.g. on window.contentView)
    /// before this controller is removed. Called from SplitContentContainerViewController.setContent
    /// since deinit can't access @MainActor properties.
    func cleanUpBeforeRemoval() {
        cancelAgentShellBannerReveal()
        promptTOCPeriodicRefreshTask?.cancel()
        promptTOCPeriodicRefreshTask = nil
        promptTOCNavigationTask?.cancel()
        promptTOCNavigationTask = nil
        promptTOCNavigationGeneration = nil
        if !chatDraftPersistenceTasksByIdentifier.isEmpty {
            persistChatTabs()
        }
        chatDraftPersistenceTasksByIdentifier.values.forEach { $0.cancel() }
        chatDraftPersistenceTasksByIdentifier.removeAll()
        notifyDiffTabDidDeactivate()
        hideDiffViewer()
        // DiffImageOverlayView lives on window.contentView, not on our view,
        // so it survives view controller replacement and blocks all mouse events.
        diffImageOverlay?.removeFromSuperview()
        diffImageOverlay = nil
        loadingOverlay?.removeFromSuperview()
        loadingOverlay = nil
    }

    deinit {
        promptTOCPeriodicRefreshTask?.cancel()
        promptTOCNavigationTask?.cancel()
        promptTOCRefreshTask?.cancel()
        scrollFABRefreshTask?.cancel()
        backgroundSessionPreparationTask?.cancel()
        agentShellBannerRevealTask?.cancel()
        sessionPreparationTasks.values.forEach { $0.cancel() }
        let chatRequestTasks = chatRequestTasksByIdentifier.values
        let chatStreamingCheckpointTasks = chatStreamingCheckpointTasksByIdentifier.values
        chatRequestTaskTokensByIdentifier.removeAll()
        chatPendingAssistantMessageIDsByIdentifier.removeAll()
        chatStreamingAssistantMessageIDsByIdentifier.removeAll()
        chatStreamingAssistantMessageIndicesByIdentifier.removeAll()
        chatTabIndicesByIdentifier.removeAll()
        chatStreamingCheckpointTasksByIdentifier.removeAll()
        chatRequestTasks.forEach { $0.cancel() }
        chatStreamingCheckpointTasks.forEach { $0.cancel() }
        chatDraftPersistenceTasksByIdentifier.values.forEach { $0.cancel() }
        chatDraftPersistenceTasksByIdentifier.removeAll()
        chatStreamingUIRefreshTasksByIdentifier.values.forEach { $0.cancel() }
        chatStreamingUIRefreshTasksByIdentifier.removeAll()
        chatStreamingLastUIRefreshAtByIdentifier.removeAll()
        chatSteerChannelsByIdentifier.removeAll()
        chatQueuedPromptsByIdentifier.removeAll()
        dismissInitialPromptFailureBanner()
        dismissPendingPromptBanner()
        NotificationCenter.default.removeObserver(self)
    }

    func cacheTerminalViewsForReuse() {
        for (index, sessionName) in thread.tmuxSessionNames.enumerated() {
            guard index < terminalViews.count else { continue }
            // Skip sessions whose views are in a pop-out window, not here
            guard !PopoutWindowManager.shared.isTabDetached(sessionName: sessionName) else { continue }
            ReusableTerminalViewCache.shared.store(
                terminalViews[index],
                sessionName: sessionName,
                reuseKey: terminalReuseKey(for: sessionName)
            )
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        tabBarStack.orientation = .horizontal
        tabBarStack.spacing = 4
        tabBarStack.alignment = .centerY
        tabBarStack.translatesAutoresizingMaskIntoConstraints = false

        fixedTabBarStack.orientation = .horizontal
        fixedTabBarStack.spacing = 4
        fixedTabBarStack.alignment = .centerY
        fixedTabBarStack.translatesAutoresizingMaskIntoConstraints = false
        fixedTabBarStack.setContentHuggingPriority(.required, for: .horizontal)
        fixedTabBarStack.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureTabBarScrollView()

        // PR/Jira buttons live in a `PopoutInfoStripView`'s capsule action row when
        // either our own header strip is shown (main window) OR the embedding pop-out
        // window installs them into its own info strip. They only fall back to the
        // top bar with textured chrome when neither host exists.
        let prJiraHostedInInfoStrip = showsHeaderInfoStrip || isPopoutContext
        let prJiraBezelStyle: NSButton.BezelStyle = prJiraHostedInInfoStrip ? .inline : .texturedRounded
        let prJiraControlSize: NSControl.ControlSize = prJiraHostedInInfoStrip ? .small : .regular

        openPRButton.bezelStyle = prJiraBezelStyle
        openPRButton.controlSize = prJiraControlSize
        openPRButton.image = openPRButtonImage(for: .unknown)
        openPRButton.imageScaling = .scaleProportionallyDown
        openPRButton.target = self
        openPRButton.action = #selector(openPRTapped(_:))
        openPRButton.toolTip = "Open Pull Request\n\(externalLinkTooltip(clickDestinationInApp: prefersInAppExternalLinks()))"
        ThreadToolbarCapsuleLayout.configureActionButton(openPRButton)

        openInJiraButton.bezelStyle = prJiraBezelStyle
        openInJiraButton.controlSize = prJiraControlSize
        openInJiraButton.image = jiraButtonImage()
        openInJiraButton.imageScaling = .scaleProportionallyDown
        openInJiraButton.target = self
        openInJiraButton.action = #selector(openInJiraTapped)
        openInJiraButton.toolTip = String(localized: .ThreadStrings.threadOpenInJira) + "\n" + externalLinkTooltip(clickDestinationInApp: prefersInAppExternalLinks())
        openInJiraButton.isHidden = true
        ThreadToolbarCapsuleLayout.configureActionButton(openInJiraButton)

        openInXcodeButton.bezelStyle = .texturedRounded
        openInXcodeButton.imageScaling = .scaleProportionallyDown
        openInXcodeButton.target = self
        openInXcodeButton.action = #selector(openInXcodeTapped)
        openInXcodeButton.toolTip = String(localized: .ThreadStrings.threadOpenProject)
        openInXcodeButton.isHidden = true

        openInFinderButton.bezelStyle = .texturedRounded
        openInFinderButton.image = finderButtonImage()
        openInFinderButton.imageScaling = .scaleProportionallyDown
        openInFinderButton.target = self
        openInFinderButton.action = #selector(openInFinderTapped)
        openInFinderButton.toolTip = thread.isMain
            ? String(localized: .ThreadStrings.threadOpenProjectRootInFinder)
            : String(localized: .ThreadStrings.threadOpenWorktreeInFinder)

        resyncLocalPathsButton.bezelStyle = .texturedRounded
        resyncLocalPathsButton.image = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: "Sync local-only files"
        )
        resyncLocalPathsButton.imageScaling = .scaleProportionallyDown
        resyncLocalPathsButton.target = self
        resyncLocalPathsButton.action = #selector(resyncLocalPathsTapped)
        resyncLocalPathsButton.toolTip = "Sync local-only files"
        resyncLocalPathsButton.isHidden = resyncLocalPathsButtonShouldBeHidden()


        archiveThreadButton.bezelStyle = .texturedRounded
        archiveThreadButton.image = NSImage(
            systemSymbolName: "archivebox",
            accessibilityDescription: String(localized: .ThreadStrings.threadArchiveTitle)
        )
        archiveThreadButton.target = self
        archiveThreadButton.action = #selector(archiveThreadTapped)
        archiveThreadButton.isHidden = thread.isMain

        popOutThreadButton.bezelStyle = .texturedRounded
        popOutThreadButton.image = NSImage(
            systemSymbolName: "macwindow.on.rectangle",
            accessibilityDescription: "Open thread in separate window"
        )
        popOutThreadButton.target = self
        popOutThreadButton.action = #selector(popOutThreadTapped)
        popOutThreadButton.toolTip = "Open thread in separate window"
        popOutThreadButton.isHidden = !shouldShowTopBarPopOutButton()

        reviewButton.bezelStyle = .texturedRounded
        reviewButton.image = NSImage(systemSymbolName: "text.magnifyingglass", accessibilityDescription: String(localized: .NotificationStrings.reviewChanges))
        reviewButton.target = self
        reviewButton.action = #selector(reviewButtonTapped)
        reviewButton.toolTip = String(localized: .NotificationStrings.reviewButtonTooltip)
        reviewButton.isHidden = true

        continueInButton.bezelStyle = .texturedRounded
        continueInButton.image = NSImage(systemSymbolName: "arrowshape.turn.up.forward", accessibilityDescription: "Continue in...")
        continueInButton.target = self
        continueInButton.action = #selector(continueInButtonTapped(_:))
        continueInButton.toolTip = "Continue in another agent"

        exportContextButton.bezelStyle = .texturedRounded
        exportContextButton.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: String(localized: .NotificationStrings.contextExport))
        exportContextButton.target = self
        exportContextButton.action = #selector(exportContextButtonTapped)
        exportContextButton.toolTip = "Export terminal context as Markdown"

        togglePromptTOCButton.bezelStyle = .texturedRounded
        togglePromptTOCButton.imageScaling = .scaleProportionallyDown
        togglePromptTOCButton.target = self
        togglePromptTOCButton.action = #selector(togglePromptTOCTapped)

        addTabButton.bezelStyle = .texturedRounded
        addTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Tab")
        addTabButton.target = self
        addTabButton.action = #selector(addTabTapped)
        let addTabContextMenu = NSMenu()
        addTabContextMenu.delegate = self
        addTabButton.menu = addTabContextMenu
        updatePromptTOCToggleButtonState(canShow: false)

        tabScrollLeftButton.bezelStyle = .texturedRounded
        tabScrollLeftButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Scroll tabs left")
        tabScrollLeftButton.imageScaling = .scaleProportionallyDown
        tabScrollLeftButton.target = self
        tabScrollLeftButton.action = #selector(tabScrollLeftTapped)
        tabScrollLeftButton.toolTip = "Scroll tabs left"
        tabScrollLeftButton.isHidden = true

        tabScrollRightButton.bezelStyle = .texturedRounded
        tabScrollRightButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Scroll tabs right")
        tabScrollRightButton.imageScaling = .scaleProportionallyDown
        tabScrollRightButton.target = self
        tabScrollRightButton.action = #selector(tabScrollRightTapped)
        tabScrollRightButton.toolTip = "Scroll tabs right"
        tabScrollRightButton.isHidden = true

        refreshPrimaryToolbarTint()

        prJiraSeparator.translatesAutoresizingMaskIntoConstraints = false
        prJiraSeparator.isHidden = true
        prJiraSeparator.setContentHuggingPriority(.required, for: .horizontal)
        prJiraSeparator.setContentCompressionResistancePriority(.required, for: .horizontal)
        prJiraSeparator.setContentHuggingPriority(.required, for: .vertical)
        prJiraSeparator.setContentCompressionResistancePriority(.required, for: .vertical)

        archiveSeparator.translatesAutoresizingMaskIntoConstraints = false
        archiveSeparator.isHidden = thread.isMain
        archiveSeparator.setContentHuggingPriority(.required, for: .horizontal)
        archiveSeparator.setContentCompressionResistancePriority(.required, for: .horizontal)
        archiveSeparator.setContentHuggingPriority(.required, for: .vertical)
        archiveSeparator.setContentCompressionResistancePriority(.required, for: .vertical)

        fixedTabsSeparator.translatesAutoresizingMaskIntoConstraints = false
        fixedTabsSeparator.isHidden = true
        fixedTabsSeparator.setContentHuggingPriority(.required, for: .horizontal)
        fixedTabsSeparator.setContentCompressionResistancePriority(.required, for: .horizontal)
        fixedTabsSeparator.setContentHuggingPriority(.required, for: .vertical)
        fixedTabsSeparator.setContentCompressionResistancePriority(.required, for: .vertical)

        topBar.orientation = .horizontal
        topBar.spacing = 4
        topBar.alignment = .centerY
        topBar.detachesHiddenViews = true
        topBar.translatesAutoresizingMaskIntoConstraints = false
        configureTopBarLayout(prJiraHostedInInfoStrip: prJiraHostedInInfoStrip)

        terminalContainer.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.wantsLayer = true
        terminalContainer.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
        (terminalContainer as? AppBackgroundView)?.onEffectiveAppearanceChanged = { [weak self] in
            self?.refreshTerminalChromeAppearance()
        }

        view.addSubview(topBar)
        if showsHeaderInfoStrip, !usesMainWindowToolbarThreadBar {
            headerInfoStrip.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(headerInfoStrip)
            headerInfoStrip.installActionButtons([openPRButton, openInJiraButton])
        }
        view.addSubview(terminalContainer)
        setupPromptTOCOverlay()

        terminalBottomToView = terminalContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        terminalTrailingToViewConstraint = terminalContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)

        if usesMainWindowToolbarThreadBar {
            NSLayoutConstraint.activate([
                topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
                topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                topBar.heightAnchor.constraint(equalToConstant: 32),

                terminalContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
                terminalContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                terminalTrailingToViewConstraint!,
                terminalBottomToView!,
            ])
        } else if showsHeaderInfoStrip {
            NSLayoutConstraint.activate([
                headerInfoStrip.topAnchor.constraint(equalTo: view.topAnchor),
                headerInfoStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                headerInfoStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                headerInfoStrip.heightAnchor.constraint(equalToConstant: 48),

                topBar.topAnchor.constraint(equalTo: headerInfoStrip.bottomAnchor, constant: 4),
                topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                topBar.heightAnchor.constraint(equalToConstant: 32),

                terminalContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
                terminalContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                terminalTrailingToViewConstraint!,
                terminalBottomToView!,
            ])
        } else {
            NSLayoutConstraint.activate([
                topBar.topAnchor.constraint(equalTo: view.topAnchor, constant: 4),
                topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
                topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
                topBar.heightAnchor.constraint(equalToConstant: 32),

                terminalContainer.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 4),
                terminalContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                terminalTrailingToViewConstraint!,
                terminalBottomToView!,
            ])
        }

        setupTerminalBannerOverlay()
        setupScrollFAB()
        setupScrollOverlay()
        refreshOverlayVisibilitySettings()
        refreshTerminalChromeAppearance()
        refreshHeaderInfoStrip()
        restorePromptTOCPinnedState()
    }

    func mainWindowThreadBarToolbarActions() -> [NSView] {
        guard usesMainWindowToolbarThreadBar else { return [] }
        return [openPRButton, openInJiraButton]
    }

    func setupTerminalBannerOverlay() {
        terminalBannerOverlay.translatesAutoresizingMaskIntoConstraints = false
        terminalContainer.addSubview(terminalBannerOverlay)
        NSLayoutConstraint.activate([
            terminalBannerOverlay.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
            terminalBannerOverlay.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
            terminalBannerOverlay.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
            terminalBannerOverlay.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
        ])
        bringTerminalBannerOverlayToFront()
    }

    func bringTerminalBannerOverlayToFront() {
        guard terminalBannerOverlay.superview === terminalContainer else { return }
        terminalContainer.addSubview(terminalBannerOverlay, positioned: .above, relativeTo: nil)
    }

    // MARK: - Tab Setup

    private func setupTabs(requireStartupOverlayForInitialSession: Bool = false) async {
        // If the thread is still being created (worktree + tmux setup in progress),
        // show the creation overlay and wait for the magentThreadCreationFinished notification.
        if threadManager.pendingThreadIds.contains(thread.id) {
            await MainActor.run { showCreationOverlay() }
            return
        }

        if let latest = threadManager.threads.first(where: { $0.id == thread.id }) {
            thread = latest
        }

        // Determine tab order with pinned tabs first
        let pinnedSet = Set(thread.pinnedTmuxSessions)

        var sessions: [String] = thread.tmuxSessionNames
        let hasNonTerminalTabsOnly = sessions.isEmpty && (!thread.persistedWebTabs.isEmpty || !thread.persistedDraftTabs.isEmpty || !thread.persistedChatTabs.isEmpty)

        if sessions.isEmpty && !hasNonTerminalTabsOnly {
            // Thread has no tabs at all — create a fallback terminal session so the user
            // still has somewhere to land when opening an otherwise empty thread.
            let fallbackName = await makeUniqueFallbackTerminalSessionName(existingSessions: sessions)
            sessions = [fallbackName]
            // Pass nil — this is a plain terminal fallback, not an agent session.
            // Using an agent type here would cause agent resume/recovery to trigger
            // incorrectly when this session is recreated.
            threadManager.registerFallbackSession(fallbackName, for: thread.id, agentType: nil)
            // Refresh local copy after manager update
            if let latest = threadManager.threads.first(where: { $0.id == thread.id }) {
                thread = latest
            }
        }

        if TabPinningState.needsPlainPrimaryFallback(
            sessions: sessions,
            agentSessions: Set(thread.agentTmuxSessions)
        ) {
            let fallbackName = await makeUniqueFallbackTerminalSessionName(existingSessions: sessions)
            sessions.insert(fallbackName, at: 0)
            // Legacy/current threads can contain only agent sessions. The fixed
            // Terminal tab still needs a plain terminal primary, but adding it
            // must not steal selection from the user's last selected agent tab.
            threadManager.registerFallbackSession(
                fallbackName,
                for: thread.id,
                agentType: nil,
                selectFallback: false
            )
            if let latest = threadManager.threads.first(where: { $0.id == thread.id }) {
                thread = latest
            }
        }

        let preferredPrimarySession = TabPinningState.preferredPrimarySession(
            sessions: sessions,
            agentSessions: Set(thread.agentTmuxSessions),
            canonicalPrimarySession: thread.tmuxSessionNames.first
        )
        let display = TabPinningState.sessionDisplayOrder(
            sessions: sessions,
            canonicalPrimarySession: preferredPrimarySession
        )
        let primarySessionName = display.primary
        permanentTerminalSessionName = primarySessionName
        let orderedMovableSessions = TabPinningState.orderedMovableSessions(
            movableSessions: display.movable,
            pinnedSessions: pinnedSet
        )
        let pinnedMovableCount = orderedMovableSessions.prefix { pinnedSet.contains($0) }.count
        let sessionDisplayOrder = [primarySessionName] + orderedMovableSessions
        pinnedCount = TabPinningState.pinnedBoundary(
            fixedCount: Self.permanentTabCount,
            pinnedMovableCount: pinnedMovableCount,
            totalCount: orderedMovableSessions.count + Self.permanentTabCount
        )
        let defaults = UserDefaults.standard
        let defaultsThreadId = defaults
            .string(forKey: Self.lastOpenedThreadDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        let defaultsSession = defaults.string(forKey: Self.lastOpenedTabDefaultsKey)
        let initialIndex = hasNonTerminalTabsOnly ? nil : TabRestoreSelectionResolver.resolveInitialTerminalIndex(
            orderedSessions: sessionDisplayOrder,
            threadId: thread.id,
            defaultsThreadId: defaultsThreadId,
            defaultsIdentifier: defaultsSession,
            lastSelectedIdentifier: thread.lastSelectedTabIdentifier,
            magentBusySessions: thread.magentBusySessions
        )

        await MainActor.run {
            preparedSessions.removeAll()
            sessionPreparationTasks.values.forEach { $0.cancel() }
            sessionPreparationTasks.removeAll()
            sessionPreparationTaskTokens.removeAll()
            backgroundSessionPreparationTask?.cancel()
            backgroundSessionPreparationTask = nil

            for terminalView in terminalViews {
                terminalView.removeFromSuperview()
            }
            terminalViews.removeAll()
            reusableSurfacePreparedSessions.removeAll()
            tabItems.removeAll()

            // Clear any existing web/draft/chat tabs from a previous setupTabs call
            for wt in webTabs { wt.view?.removeFromSuperview() }
            webTabs.removeAll()
            for dt in draftTabs { dt.viewController?.view.removeFromSuperview() }
            draftTabs.removeAll()
            for ct in chatTabs { ct.viewController?.view.removeFromSuperview() }
            tabSlots.removeAll()
            activeWebTabId = nil
            activeDraftTabId = nil
            activeChatTabId = nil

            createTabItem(title: Self.terminalTabTitle, closable: false, pinned: false)
            tabSlots.append(.terminal(sessionName: primarySessionName))
            createTabItem(title: Self.diffTabTitle, closable: false, pinned: false)
            tabSlots.append(.diff)

            for (i, sessionName) in orderedMovableSessions.enumerated() {
                let title = thread.displayName(for: sessionName, at: i + 1)
                let displayIndex = tabItems.count
                let isPinnedAtDisplayIndex = TabPinningState.isPinnedMovableIndex(
                    displayIndex,
                    pinnedBoundary: pinnedCount,
                    fixedCount: Self.permanentTabCount
                )
                createTabItem(title: title, closable: true, pinned: isPinnedAtDisplayIndex)
                tabSlots.append(.terminal(sessionName: sessionName))
            }

            // Restore the selected surface first. A cache hit can cancel the
            // debounced overlay before secondary tabs and non-terminal views are
            // reconstructed.
            var selectedTerminalView: TerminalSurfaceView?
            var selectedSessionName: String?
            if let initialIndex, sessionDisplayOrder.indices.contains(initialIndex) {
                let sessionName = sessionDisplayOrder[initialIndex]
                if thread.tmuxSessionNames.contains(sessionName) {
                    selectedSessionName = sessionName
                    selectedTerminalView = makeTerminalView(for: sessionName)
                    if reusableSurfacePreparedSessions.contains(sessionName),
                       !requireStartupOverlayForInitialSession {
                        cancelLoadingOverlayReveal()
                    }
                }
            }

            // terminalViews stays parallel to canonical tmuxSessionNames order.
            terminalViews = thread.tmuxSessionNames.map { sessionName in
                if sessionName == selectedSessionName, let selectedTerminalView {
                    return selectedTerminalView
                }
                return makeTerminalView(for: sessionName)
            }

            // Restore persisted web tabs (pages load lazily on selection).
            // Pinned web tabs are inserted into the pinned section; unpinned appended at end.
            restoreWebTabItems()

            // Restore persisted draft tabs (view controllers created lazily on selection).
            restoreDraftTabItems()
            restoreChatTabItems()
            restorePersistedTabDisplayOrder()

            let validChatIdentifiers = Set(chatTabs.map(\.identifier))
            let staleRunningChatIdentifiers = chatRequestTasksByIdentifier.keys.filter { !validChatIdentifiers.contains($0) }
            for identifier in staleRunningChatIdentifiers {
                chatRequestTasksByIdentifier[identifier]?.cancel()
                chatRequestTasksByIdentifier.removeValue(forKey: identifier)
            }
            let staleCheckpointIdentifiers = chatStreamingCheckpointTasksByIdentifier.keys.filter { !validChatIdentifiers.contains($0) }
            for identifier in staleCheckpointIdentifiers {
                chatStreamingCheckpointTasksByIdentifier[identifier]?.cancel()
                chatStreamingCheckpointTasksByIdentifier.removeValue(forKey: identifier)
            }
            chatRequestTaskTokensByIdentifier = chatRequestTaskTokensByIdentifier.filter { validChatIdentifiers.contains($0.key) }
            chatPendingAssistantMessageIDsByIdentifier = chatPendingAssistantMessageIDsByIdentifier.filter { validChatIdentifiers.contains($0.key) }
            chatStreamingAssistantMessageIDsByIdentifier = chatStreamingAssistantMessageIDsByIdentifier.filter { validChatIdentifiers.contains($0.key) }
            for staleID in chatSteerChannelsByIdentifier.keys where !validChatIdentifiers.contains(staleID) {
                chatSteerChannelsByIdentifier.removeValue(forKey: staleID)
            }
            chatQueuedPromptsByIdentifier = chatQueuedPromptsByIdentifier.filter { validChatIdentifiers.contains($0.key) }

            rebuildTabBar()
            rebindAllTabActions()
        }

        // Non-terminal thread: skip terminal session setup entirely, just restore the
        // selected draft/web/chat tab instead of inventing a fallback tmux session name.
        if hasNonTerminalTabsOnly {
            await MainActor.run {
                let selectedIndex = resolveLastSelectedSlotIndex() ?? tabSlots.indices.first { index in
                    switch tabSlots[index] {
                    case .web, .draft, .chat: return true
                    case .terminal, .diff: return false
                    }
                }
                if let selectedIndex {
                    selectTab(at: selectedIndex)
                }
                dismissLoadingOverlay()
            }
            return
        }

        // Resolve whether the last-selected tab was a non-terminal tab (web/draft/chat).
        // If so, we still prepare terminal sessions in the background but select the
        // non-terminal tab at the end.
        let nonTerminalSlotIndex: Int? = await MainActor.run {
            resolveLastSelectedSlotIndex().flatMap { idx in
                guard idx < tabSlots.count else { return nil }
                switch tabSlots[idx] {
                case .web, .draft, .chat: return idx
                case .diff: return idx
                case .terminal: return nil
                }
            }
        }

        guard let initialIndex else {
            await MainActor.run { dismissLoadingOverlay() }
            return
        }

        let initialSessionName = sessionDisplayOrder[initialIndex]
        let canFastPathInitialSession = await MainActor.run {
            threadManager.isSessionPreparedFastPath(
                sessionName: initialSessionName,
                thread: thread,
                hasReusableTerminalSurface: reusableSurfacePreparedSessions.contains(initialSessionName)
            )
        }
        let startupOverlayAction = ThreadStartupOverlayDecision.action(
            isRestoringTerminalTab: nonTerminalSlotIndex == nil,
            requiresStartupOverlay: requireStartupOverlayForInitialSession,
            canFastPathSelectedSession: canFastPathInitialSession
        )
        let initialAgentType = startupOverlayAction == .skip
            ? nil
            : await threadManager.loadingOverlayAgentType(
                for: thread,
                sessionName: initialSessionName
            )

        await MainActor.run {
            // Only show terminal loading overlay if we're actually restoring to a terminal tab.
            if nonTerminalSlotIndex == nil {
                switch startupOverlayAction {
                case .skip:
                    dismissLoadingOverlay()
                case .track:
                    startLoadingOverlayTracking(sessionName: initialSessionName, agentType: initialAgentType)
                }

                if requireStartupOverlayForInitialSession {
                    requireStartupOverlay(for: initialSessionName)
                }
            }

            // Initialize indicator dots from thread model
            for (i, slot) in tabSlots.enumerated() where i < tabItems.count {
                switch slot {
                case .terminal(let sessionName):
                    tabItems[i].hasUnreadCompletion = thread.unreadCompletionSessions.contains(sessionName)
                    tabItems[i].hasWaitingForInput = thread.waitingForInputSessions.contains(sessionName)
                    tabItems[i].hasBusy = thread.busySessions.contains(sessionName)
                    tabItems[i].hasRateLimit = thread.rateLimitedSessions[sessionName] != nil
                    tabItems[i].isRateLimitPropagated = thread.rateLimitedSessions[sessionName]?.isPropagated ?? false
                    tabItems[i].rateLimitTooltip = rateLimitTooltip(for: sessionName)
                    tabItems[i].isSessionDead = thread.deadSessions.contains(sessionName)
                    tabItems[i].hasTerminalCorruption = threadManager.isTerminalCorrupted(sessionName: sessionName)
                case .chat(let identifier):
                    tabItems[i].hasUnreadCompletion = thread.unreadCompletionSessions.contains(identifier)
                case .diff:
                    tabItems[i].hasUnreadDiff = isDiffUnread()
                case .web, .draft:
                    continue
                }
            }
            refreshTabTooltips()

            // If restoring to a non-terminal tab, select it immediately before terminal prep.
            // Dismiss the startup "Loading thread..." overlay here — startLoadingOverlayTracking
            // was skipped above (nonTerminalSlotIndex != nil), so nothing else will.
            if let slotIndex = nonTerminalSlotIndex {
                selectTab(at: slotIndex)
                dismissLoadingOverlay()
            }
        }

        let recreatedInitialSession = await ensureSessionPrepared(sessionName: initialSessionName) { [weak self] action in
            guard let self,
                  initialSessionName == self.loadingOverlaySessionName else { return }
            self.updateLoadingOverlayDetail(action?.loadingOverlayDetail)
        }

        await MainActor.run {
            if nonTerminalSlotIndex == nil {
                // Resolve the display index from session name — web tab restoration may have
                // shifted indices since initialIndex was computed.
                let resolvedIndex = displayIndex(forSession: initialSessionName) ?? initialIndex
                let selected = selectPreparedTab(at: resolvedIndex)
                if !selected {
                    // Do not leave a blank terminal area on startup if the initial
                    // prepared attach misses. Keep loading visible and retry through
                    // the full selection path, which revalidates/recreates as needed.
                    loadingLabel?.stringValue = "Preparing terminal session..."
                    updateLoadingOverlayDetail("Initial terminal attach missed; retrying tmux/session validation.")
                    selectTab(at: resolvedIndex)
                    return
                }
                let keepStartupOverlay = initialAgentType != nil
                    && (recreatedInitialSession || consumeStartupOverlayRequirement(for: initialSessionName))
                if !keepStartupOverlay {
                    dismissLoadingOverlay()
                }
            }
            prepareSessionsInBackground(sessionDisplayOrder.enumerated().compactMap { offset, sessionName in
                offset == initialIndex ? nil : sessionName
            })
        }
    }

    func currentSessionName() -> String? {
        guard currentTabIndex >= 0, currentTabIndex < tabSlots.count else { return nil }
        if case .terminal(let name) = tabSlots[currentTabIndex] { return name }
        return nil
    }

    func currentSlot() -> TabSlot? {
        guard currentTabIndex >= 0, currentTabIndex < tabSlots.count else { return nil }
        return tabSlots[currentTabIndex]
    }

    func isDiffUnread() -> Bool {
        guard let current = thread.currentDiffFingerprint else { return false }
        return current != thread.lastSeenDiffFingerprint
    }

    func focusCurrentTabForNavigation() {
        guard !tabSlots.isEmpty else { return }
        let index = min(max(currentTabIndex, 0), tabSlots.count - 1)
        selectTab(at: index)
    }

    func focusCurrentTabContent() {
        guard let currentSlot = currentSlot() else { return }
        switch currentSlot.focusTarget {
        case .terminalSurface:
            if let tv = currentTerminalView(), tv.superview != nil, !tv.isHidden {
                view.window?.makeFirstResponder(tv)
            }
        case .webContent:
            guard let activeWebTabId,
                  let webTab = webTabs.first(where: { $0.identifier == activeWebTabId }) else { return }
            webTab.view?.focusWebContent()
        case .draftPrompt:
            guard let activeDraftTabId,
                  let draftTab = draftTabs.first(where: { $0.identifier == activeDraftTabId }) else { return }
            draftTab.viewController?.focusPromptInput()
        case .chatComposer:
            guard let activeChatTabId,
                  let chatTab = chatTabs.first(where: { $0.identifier == activeChatTabId }) else { return }
            chatTab.viewController?.focusComposer()
        }
    }

    /// Look up a terminal view by tmux session name (not display index).
    func terminalView(forSession name: String) -> TerminalSurfaceView? {
        guard let idx = thread.tmuxSessionNames.firstIndex(of: name) else { return nil }
        guard idx < terminalViews.count else { return nil }
        return terminalViews[idx]
    }

    /// The terminal view for the currently selected tab, or nil for non-terminal tabs.
    func currentTerminalView() -> TerminalSurfaceView? {
        guard let name = currentSessionName() else { return nil }
        return terminalView(forSession: name)
    }

    /// Display index for a given terminal session name, or nil.
    func displayIndex(forSession name: String) -> Int? {
        tabSlots.firstIndex(of: .terminal(sessionName: name))
    }

    /// Display index for a given web tab identifier, or nil.
    func displayIndex(forWebIdentifier id: String) -> Int? {
        tabSlots.firstIndex(of: .web(identifier: id))
    }

    /// Display index for any persisted tab identifier (terminal session name,
    /// web/draft/chat identifier), or nil.
    func displayIndex(forIdentifier id: String) -> Int? {
        slotIndex(forIdentifier: id)
    }

    /// Resolve the last-selected tab slot index from persisted state.
    /// Checks UserDefaults (current app session) first, then the per-thread persisted identifier.
    func resolveLastSelectedSlotIndex() -> Int? {
        let defaults = UserDefaults.standard
        let defaultsThreadId = defaults
            .string(forKey: Self.lastOpenedThreadDefaultsKey)
            .flatMap(UUID.init(uuidString:))
        let defaultsIdentifier = defaults.string(forKey: Self.lastOpenedTabDefaultsKey)

        // Priority 1: UserDefaults (current app session, matches this thread)
        if defaultsThreadId == thread.id, let id = defaultsIdentifier,
           let idx = slotIndex(forIdentifier: id) {
            return idx
        }
        // Priority 2: Per-thread persisted identifier (survives app restart)
        if let id = thread.lastSelectedTabIdentifier,
           let idx = slotIndex(forIdentifier: id) {
            return idx
        }
        return nil
    }

    /// Find the tab slot index for a given identifier (session name or non-terminal id).
    private func slotIndex(forIdentifier id: String) -> Int? {
        tabSlots.firstIndex { slot in
            switch slot {
            case .terminal(let name): return name == id
            case .diff: return id == "__diff__"
            case .web(let identifier): return identifier == id
            case .draft(let identifier): return identifier == id
            case .chat(let identifier): return identifier == id
            }
        }
    }

    func updateTerminalScrollControlsState() {
        refreshOverlayVisibilitySettings()
        scrollOverlay.isScrollEnabled = currentSessionName() != nil
        scheduleScrollFABVisibilityRefresh()
    }

    func refreshOverlayVisibilitySettings() {
        let settings = PersistenceService.shared.loadSettings()
        showScrollToBottomIndicator = settings.showScrollToBottomIndicator
        showTerminalScrollOverlay = settings.showTerminalScrollOverlay
        showPromptTOCOverlay = settings.showPromptTOCOverlay

        scrollOverlay.isHidden = !showTerminalScrollOverlay
        if !showScrollToBottomIndicator {
            setScrollFABVisible(false)
        }
        applyPromptTOCVisibility()
    }

    func makeTerminalView(for sessionName: String) -> TerminalSurfaceView {
        let reuseKey = terminalReuseKey(for: sessionName)
        let resolvedThread = latestThreadSnapshot()
        let view: TerminalSurfaceView
        if let cachedView = ReusableTerminalViewCache.shared.take(
            sessionName: sessionName,
            reuseKey: reuseKey
        ) {
            view = cachedView
            reusableSurfacePreparedSessions.insert(sessionName)
        } else {
            let tmuxCommand = buildTmuxCommand(for: sessionName)
            view = TerminalSurfaceView(
                workingDirectory: resolvedThread.worktreePath,
                command: tmuxCommand
            )
            reusableSurfacePreparedSessions.remove(sessionName)
        }
        // Tag the view with its tmux session so `GhosttyAppManager` can
        // synchronously free its surface from the `TmuxService` pre-kill
        // hook before the backing tmux session dies (prevents libghostty's
        // PTY-close `_exit()`). Must be set on both create and reuse paths,
        // and kept in sync on tmux session rename — see `handleRename`.
        view.tmuxSessionName = sessionName
        configureTerminalViewHandlers(view, sessionName: sessionName)
        return view
    }

    private func makeUniqueFallbackTerminalSessionName(existingSessions: [String]) async -> String {
        let settings = PersistenceService.shared.loadSettings()
        let slug = TmuxSessionNaming.repoSlug(from:
            settings.projects.first(where: { $0.id == thread.projectId })?.name ?? "project"
        )
        let firstTabSlug = TmuxSessionNaming.sanitizeForTmux(Self.terminalTabTitle)
        let baseName: String
        if thread.isMain {
            baseName = TmuxSessionNaming.buildSessionName(repoSlug: slug, threadName: nil, tabSlug: firstTabSlug)
        } else {
            baseName = TmuxSessionNaming.buildSessionName(repoSlug: slug, threadName: thread.name, tabSlug: firstTabSlug)
        }

        var candidate = baseName
        var suffix = 2
        while await threadManager.isTabNameTaken(candidate, existingNames: existingSessions) {
            candidate = "\(baseName)-\(suffix)"
            suffix += 1
        }
        return candidate
    }

    func rebuildDetachedTerminalView(for sessionName: String) {
        guard let termIdx = thread.tmuxSessionNames.firstIndex(of: sessionName),
              termIdx < terminalViews.count else { return }

        let existingView = terminalViews[termIdx]
        guard existingView.superview == nil else { return }

        ReusableTerminalViewCache.shared.remove(sessionName: sessionName)
        terminalViews[termIdx] = makeTerminalView(for: sessionName)
    }

    private func configureTerminalViewHandlers(_ view: TerminalSurfaceView, sessionName: String) {
        view.onCopy = { [sessionName = sessionName] in
            Task { await TmuxService.shared.copySelectionToClipboard(sessionName: sessionName) }
        }
        view.onBecomeFirstResponder = { [weak self] in
            self?.postFocusedThreadContextChangedIfKeyWindow()
        }
        view.onUserInteraction = { [weak self] in
            self?.postFocusedThreadContextChangedIfKeyWindow()
        }
        view.onEscapeKey = { [weak self] in
            self?.schedulePromptTOCRefreshAfterEscape()
        }
        view.onSubmitLine = { [weak self, sessionName = sessionName] line in
            Task { @MainActor [weak self] in
                await self?.handleSubmittedLine(line, sessionName: sessionName)
            }
        }
        view.onScroll = { [weak self] in
            self?.scheduleScrollFABVisibilityRefresh()
        }
        view.resolveTmuxMouseOpenableURL = { [sessionName = sessionName] in
            await TmuxService.shared.recentMouseOpenableURL(sessionName: sessionName)
        }
        view.resolveTmuxVisibleOpenableURL = { [sessionName = sessionName] xFraction, yFraction in
            await TmuxService.shared.visibleOpenableURL(
                sessionName: sessionName,
                xFraction: xFraction,
                yFraction: yFraction
            )
        }
        view.openURLHandler = { [weak self] url, openOppositeDestination in
            self?.openTerminalLink(url, openOppositeDestination: openOppositeDestination)
        }
    }

    private func openTerminalLink(_ url: URL, openOppositeDestination: Bool) {
        let forceInApp: Bool?
        if openOppositeDestination {
            forceInApp = !prefersInAppExternalLinks()
        } else {
            forceInApp = nil
        }
        openExternalWebDestination(
            url: url,
            identifier: "web:\(url.absoluteString)",
            title: WebURLNormalizer.shortHost(from: url) ?? url.absoluteString,
            iconType: .web,
            forceInApp: forceInApp
        )
    }

    func terminalReuseKey(for sessionName: String) -> String {
        Self.terminalReuseKey(for: latestThreadSnapshot(), sessionName: sessionName)
    }

    private func latestThreadSnapshot() -> MagentThread {
        threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
    }

    static func terminalReuseKey(for thread: MagentThread, sessionName: String) -> String {
        let isAgentSession = thread.agentTmuxSessions.contains(sessionName)
        return TerminalSurfaceReuseIdentity(
            threadID: thread.id,
            sessionName: sessionName,
            worktreePath: thread.worktreePath,
            isAgentSession: isAgentSession,
            agentType: isAgentSession ? thread.sessionAgentTypes[sessionName] : nil,
            sessionCreatedAt: thread.sessionCreatedAts[sessionName]
        ).cacheKey
    }

    private func buildTmuxCommand(for sessionName: String) -> String {
        Self.buildTmuxCommand(for: sessionName, in: latestThreadSnapshot())
    }

    static func buildTmuxCommand(for sessionName: String, in thread: MagentThread) -> String {
        let threadManager = ThreadManager.shared
        let settings = PersistenceService.shared.loadSettings()
        let isAgentSession = thread.agentTmuxSessions.contains(sessionName)
        let selectedAgentType = threadManager.agentType(for: thread, sessionName: sessionName)

        let project = settings.projects.first(where: { $0.id == thread.projectId })
        let projectName = project?.name ?? "project"
        let wd = thread.worktreePath
        let projectPath: String
        if thread.isMain {
            projectPath = wd
        } else {
            projectPath = project?.repoPath ?? wd
        }

        var envParts = [
            "export MAGENT_PROJECT_PATH=\(projectPath)",
            "export MAGENT_PROJECT_NAME=\(projectName)",
            "export MAGENT_THREAD_ID=\(thread.id.uuidString)",
        ]
        if thread.isMain {
            envParts.append("export MAGENT_WORKTREE_NAME=main")
        } else {
            envParts.append("export MAGENT_WORKTREE_PATH=\(wd)")
            envParts.append("export MAGENT_WORKTREE_NAME=\(thread.name)")
        }
        if let selectedAgentType {
            envParts.append("export MAGENT_AGENT_TYPE=\(selectedAgentType.rawValue)")
        }
        let envExports = envParts.joined(separator: " && ")

        let envExportsWithSocket = envExports + " && export MAGENT_SOCKET=\(IPCSocketServer.socketPath)"

        let startCmd: String
        if isAgentSession, let selectedAgentType {
            let resumeSessionID = thread.sessionConversationIDs[sessionName]
            startCmd = threadManager.agentStartCommand(
                settings: settings,
                projectId: thread.projectId,
                agentType: selectedAgentType,
                envExports: envExportsWithSocket,
                workingDirectory: wd,
                resumeSessionID: resumeSessionID
            )
        } else {
            startCmd = threadManager.terminalStartCommand(
                envExports: envExportsWithSocket,
                workingDirectory: wd
            )
        }

        let sq = ShellExecutor.shellQuote
        let quotedWd = sq(wd)
        let quotedStartCmd = sq(startCmd)
        let ensureTerminalFeatures = TmuxService.ensureTerminalFeaturesShellCommand()
        let tmuxInner = "tmux send-keys -t \(sessionName) -X cancel 2>/dev/null; tmux attach-session -t \(sessionName) 2>/dev/null || { tmux new-session -d -s \(sessionName) -c \(quotedWd) \(quotedStartCmd) && { \(ensureTerminalFeatures); } && tmux attach-session -t \(sessionName); }"
        return "/bin/sh -c \(sq(tmuxInner))"
    }

    func postFocusedThreadContextChangedIfKeyWindow() {
        guard view.window?.isKeyWindow == true else { return }
        NotificationCenter.default.post(
            name: .magentFocusedThreadContextChanged,
            object: self,
            userInfo: [
                "threadId": thread.id,
                "isPopoutContext": isPopoutContext,
            ]
        )
    }

    /// Handles `magentTabWillClose` posted by `removeTabBySessionName` immediately before
    /// it mutates the model.  Running synchronously on the MainActor ensures the
    /// Ghostty surface is freed (via removeFromSuperview → viewDidMoveToWindow → destroySurface)
    /// before ghostty_app_tick can see the zombie surface and crash.
    ///
    /// This covers both the IPC path (which never calls removeFromSuperview directly) and acts
    /// as an early-cleanup fast-path for the GUI path (where closeTab's MainActor.run block
    /// will subsequently find the index already gone and return via its bounds-guard).
    @objc private func handleTabWillCloseNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo else {
            NSLog("[TabClose] handleTabWillClose: missing userInfo")
            return
        }
        guard let threadId = userInfo["threadId"] as? UUID else {
            NSLog("[TabClose] handleTabWillClose: missing threadId in userInfo")
            return
        }
        guard threadId == thread.id else {
            NSLog("[TabClose] handleTabWillClose: ignoring notification for threadId=\(threadId), current thread=\(thread.id)")
            return
        }
        guard let sessionName = userInfo["sessionName"] as? String else {
            NSLog("[TabClose] handleTabWillClose: missing sessionName for threadId=\(threadId)")
            return
        }

        // Find display index via tabSlots.
        guard let displayIndex = tabSlots.firstIndex(of: .terminal(sessionName: sessionName)) else {
            NSLog("[TabClose] handleTabWillClose: session \(sessionName) missing from tabSlots for threadId=\(threadId)")
            return
        }
        // Find terminal array index.
        guard let termIdx = thread.tmuxSessionNames.firstIndex(of: sessionName),
              termIdx < terminalViews.count else {
            NSLog("[TabClose] handleTabWillClose: session \(sessionName) missing from thread/terminalViews for threadId=\(threadId); tmuxSessions=\(thread.tmuxSessionNames.count) terminalViews=\(terminalViews.count)")
            return
        }

        GhosttyAppManager.log("handleTabWillClose: threadId=\(threadId) session=\(sessionName) displayIndex=\(displayIndex)")
        let wasPinned = currentTabGroups().pinned.contains(displayIndex)

        // Remove the surface view.  This triggers viewDidMoveToWindow(nil) → destroySurface()
        // → ghostty_surface_free, preventing the zombie-surface crash.
        terminalViews[termIdx].removeFromSuperview()
        terminalViews.remove(at: termIdx)

        if displayIndex < tabItems.count {
            tabItems.remove(at: displayIndex)
        }
        if displayIndex < tabSlots.count {
            tabSlots.remove(at: displayIndex)
        }

        // Keep the movable pinned boundary in sync.
        if wasPinned {
            pinnedCount -= 1
            pinnedCount = TabPinningState.clampedPinnedBoundary(
                pinnedCount,
                fixedCount: Self.permanentTabCount,
                totalCount: tabSlots.count
            )
        }
        if sessionName == permanentTerminalSessionName {
            permanentTerminalSessionName = nil
        }

        // Prune our local thread copy so subsequent index lookups stay correct.
        thread.tmuxSessionNames.removeAll { $0 == sessionName }
        thread.pinnedTmuxSessions.removeAll { $0 == sessionName }
        thread.customTabNames.removeValue(forKey: sessionName)
        thread.manuallyRenamedTabs.remove(sessionName)
        thread.agentTmuxSessions.removeAll { $0 == sessionName }
        thread.unreadCompletionSessions.remove(sessionName)
        thread.busySessions.remove(sessionName)
        thread.waitingForInputSessions.remove(sessionName)
        thread.hasUnsubmittedInputSessions.remove(sessionName)
        threadManager.clearInitialPromptInjectionFailure(for: sessionName)
        startupOverlayRequiredSessions.remove(sessionName)
        ReusableTerminalViewCache.shared.remove(sessionName: sessionName)

        rebindAllTabActions()
        rebuildTabBar()

        if tabItems.isEmpty {
            showEmptyState()
        } else {
            let newIndex = min(displayIndex, tabItems.count - 1)
            selectTab(at: newIndex)
        }
    }

    @objc private func handleKeepAliveChanged(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let threadId = userInfo["threadId"] as? UUID,
              threadId == thread.id else { return }
        // Refresh from the manager's fresh state.
        if let freshThread = threadManager.threads.first(where: { $0.id == thread.id }) {
            thread.isKeepAlive = freshThread.isKeepAlive
            thread.didOfferKeepAlivePromotion = freshThread.didOfferKeepAlivePromotion
            thread.protectedTmuxSessions = freshThread.protectedTmuxSessions
        }
        refreshTabStatusIndicators()
        rebindAllTabActions()
        refreshHeaderInfoStrip()
    }

    @objc private func handleDeadSessionsNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let threadId = userInfo["threadId"] as? UUID,
              threadId == thread.id,
              let deadSessions = userInfo["deadSessions"] as? [String] else { return }

        for sessionName in deadSessions {
            guard let displayIdx = displayIndex(forSession: sessionName),
                  displayIdx < tabItems.count else { continue }

            if displayIdx == currentTabIndex {
                // The visible session was auto-recreated by checkForDeadSessions.
                // Replace the terminal view so the user sees the fresh session.
                if let termIdx = thread.tmuxSessionNames.firstIndex(of: sessionName),
                   termIdx < terminalViews.count {
                    let oldView = terminalViews[termIdx]
                    oldView.removeFromSuperview()
                    ReusableTerminalViewCache.shared.remove(sessionName: sessionName)

                    let newView = makeTerminalView(for: sessionName)
                    terminalViews[termIdx] = newView
                    selectTab(at: displayIdx)
                }
                tabItems[displayIdx].isSessionDead = false
            } else {
                // Background dead sessions — just dim the tab.
                tabItems[displayIdx].isSessionDead = true
            }
        }
        refreshTabTooltips()
        refreshAgentShellBanner()
    }

    @objc private func handleAgentCompletionNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let threadId = userInfo["threadId"] as? UUID,
              threadId == thread.id,
              let unreadSessions = userInfo["unreadSessions"] as? Set<String> else { return }

        thread.unreadCompletionSessions = unreadSessions
        refreshTabStatusIndicators()
        refreshTabTooltips()
        threadManager.refreshGitStateAfterAgentCompletion()
        refreshDiffForAgentCompletion()
        syncTransientState()
        schedulePromptTOCRefresh()
        refreshHeaderInfoStrip()
    }

    @objc private func handleInitialPromptInjectionFailedNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let sessionName = userInfo["sessionName"] as? String,
              thread.tmuxSessionNames.contains(sessionName) else {
            return
        }
        // Pending banner is no longer needed — failure banner takes over
        if pendingPromptBannerSessionName == sessionName {
            dismissPendingPromptBanner()
        }
        refreshInitialPromptFailureBanner()
    }

    @objc private func handleAgentKeysInjectedNotification(_ notification: Notification) {
        guard let sessionName = notification.userInfo?["sessionName"] as? String else { return }
        let includedInitialPrompt = (notification.userInfo?["includedInitialPrompt"] as? Bool) == true

        // Dismiss pending-injection UI only when this completion actually sent the prompt.
        if includedInitialPrompt, pendingPromptBannerSessionName == sessionName {
            dismissPendingPromptBanner()
        }

        guard includedInitialPrompt else { return }
        guard threadManager.initialPromptInjectionFailure(for: sessionName) != nil else { return }
        threadManager.clearInitialPromptInjectionFailure(for: sessionName)
        refreshInitialPromptFailureBanner()
    }

    @objc private func handleAgentShellStateChanged() {
        agentStartRequestedSessions = agentStartRequestedSessions.filter {
            threadManager.isAgentSessionAtShell($0)
        }
        refreshAgentShellBanner()
    }

    @objc private func handlePendingPromptInjectionNotification(_ notification: Notification) {
        guard let sessionName = notification.userInfo?["sessionName"] as? String,
              thread.tmuxSessionNames.contains(sessionName) else {
            return
        }
        refreshPendingPromptBanner()
    }

    @objc private func handleAgentWaitingNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let threadId = userInfo["threadId"] as? UUID,
              threadId == thread.id,
              let waitingSessions = userInfo["waitingSessions"] as? Set<String> else { return }

        thread.waitingForInputSessions = waitingSessions
        for (i, slot) in tabSlots.enumerated() where i < tabItems.count {
            if case .terminal(let sessionName) = slot {
                tabItems[i].hasWaitingForInput = waitingSessions.contains(sessionName)
            }
        }
        refreshTabTooltips()
        syncTransientState()
        refreshHeaderInfoStrip()
    }

    @objc private func handleAgentBusyNotification(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let threadId = userInfo["threadId"] as? UUID,
              threadId == thread.id,
              let busySessions = userInfo["busySessions"] as? Set<String> else { return }

        thread.busySessions = busySessions
        for (i, slot) in tabSlots.enumerated() where i < tabItems.count {
            if case .terminal(let sessionName) = slot {
                tabItems[i].hasBusy = busySessions.contains(sessionName)
            }
        }
        refreshTabTooltips()
        syncTransientState()
        refreshHeaderInfoStrip()
    }

    @objc private func handleAgentRateLimitNotification(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID,
              threadId == thread.id,
              let latest = threadManager.threads.first(where: { $0.id == thread.id }) else { return }

        thread.rateLimitedSessions = latest.rateLimitedSessions
        thread.unreadRateLimitSessions = latest.unreadRateLimitSessions
        for (i, slot) in tabSlots.enumerated() where i < tabItems.count {
            if case .terminal(let sessionName) = slot {
                let info = thread.rateLimitedSessions[sessionName]
                tabItems[i].hasRateLimit = info != nil
                tabItems[i].isRateLimitPropagated = info?.isPropagated ?? false
                tabItems[i].rateLimitAgentType = info?.agentType
                tabItems[i].rateLimitTooltip = rateLimitTooltip(for: sessionName)
                tabItems[i].hasUnreadRateLimit = thread.unreadRateLimitSessions.contains(sessionName)
            }
        }
        refreshTabTooltips()
        refreshHeaderInfoStrip()
    }

    @objc private func handleTerminalCorruptionNotification(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID,
              threadId == thread.id else { return }

        for (i, slot) in tabSlots.enumerated() where i < tabItems.count {
            if case .terminal(let sessionName) = slot {
                tabItems[i].hasTerminalCorruption = threadManager.isTerminalCorrupted(sessionName: sessionName)
            } else {
                tabItems[i].hasTerminalCorruption = false
            }
        }
        refreshTabTooltips()
    }

    @objc private func handleThreadCreationFinished(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID,
              threadId == thread.id else { return }

        dismissLoadingOverlay()

        guard notification.userInfo?["error"] == nil else {
            // Thread creation failed; the pending thread will be removed from the sidebar.
            return
        }

        // Thread is ready — reload tabs now that sessions exist.
        // Web-only threads (no tmux sessions) are handled inside setupTabs which
        // selects the first web tab automatically.
        refreshHeaderInfoStrip()
        Task { await setupTabs(requireStartupOverlayForInitialSession: true) }
    }

    func showCreationOverlay() {
        ensureLoadingOverlay()
        loadingLabel?.stringValue = "Creating thread..."
        // Immediate reveal — thread creation (worktree + tmux) always exceeds the
        // debounce window, so the user should see feedback right away.
        revealLoadingOverlay(after: 0)
    }

    @objc private func handlePullRequestInfoChanged() {
        syncTransientState()
    }

    @objc private func handleJiraTicketInfoChanged() {
        guard let latest = threadManager.threads.first(where: { $0.id == thread.id }) else { return }
        thread.actualBranch = latest.actualBranch
        thread.verifiedJiraTicket = latest.verifiedJiraTicket
        refreshJiraButton()
        refreshHeaderInfoStrip()
    }

    @objc private func handleShowDiffViewerNotification(_ notification: Notification) {
        if let threadId = notification.userInfo?["threadId"] as? UUID {
            guard threadId == thread.id else { return }
        } else {
            guard !isPopoutContext else { return }
        }
        let filePath = notification.userInfo?["filePath"] as? String
        let commitHash = notification.userInfo?["commitHash"] as? String
        let commitTitle = notification.userInfo?["commitTitle"] as? String
        let forceWorkingTree = (notification.userInfo?["mode"] as? String) == "uncommitted"
        showDiffViewer(scrollToFile: filePath, commitHash: commitHash, commitTitle: commitTitle, forceWorkingTreeDiff: forceWorkingTree)
    }

    @objc private func handleHideDiffViewerNotification(_ notification: Notification) {
        if let threadId = notification.userInfo?["threadId"] as? UUID {
            guard threadId == thread.id else { return }
        } else {
            guard !isPopoutContext else { return }
        }
        hideDiffViewer()
    }

    @objc private func handleDiffFileCountChanged(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID,
              threadId == thread.id,
              let fileCount = notification.userInfo?["fileCount"] as? Int else { return }
        if fileCount == 0 {
            clearCurrentDiffReviewStateIfNeeded()
        }
        updateDiffTabTitle(fileCount: fileCount, reviewedCount: thread.diffReviewedFileSignatures.count)
    }

    @objc private func handleSectionsDidChange() {
        refreshHeaderInfoStrip()
    }

    @objc private func handleThreadsDidChange() {
        guard let latest = threadManager.threads.first(where: { $0.id == thread.id }) else { return }
        let previous = thread
        let didTabStructureChange =
            ThreadTabStructureFingerprint(thread: previous)
            != ThreadTabStructureFingerprint(thread: latest)
        let canApplyRenameInPlace = ThreadTabStructureFingerprint.isTabSessionRename(
            from: previous,
            to: latest
        )

        if canApplyRenameInPlace || (!didTabStructureChange && previous.customTabNames != latest.customTabNames) {
            handleRename(latest)
        } else {
            thread = latest
        }

        if didTabStructureChange && !canApplyRenameInPlace {
            // Local Cmd+T / draft-to-agent flows run a two-phase placeholder→session
            // reconciliation and explicitly own selection. Rebuilding via setupTabs()
            // during that window can transiently jump between tabs.
            if !TabStructureRebuildGate.shouldRunSetupTabsAfterStructureChange(
                localAutoSwitchTabCreationsInFlight: localAutoSwitchTabCreationsInFlight
            ) {
                popOutThreadButton.isHidden = !shouldShowTopBarPopOutButton()
                refreshHeaderInfoStrip()
                return
            }
            Task { await setupTabs() }
        }

        popOutThreadButton.isHidden = !shouldShowTopBarPopOutButton()
        refreshHeaderInfoStrip()
    }

    @objc private func handleTabAutoRenameStateChanged(_ notification: Notification) {
        guard let sessionName = notification.userInfo?["sessionName"] as? String,
              let isInProgress = notification.userInfo?["isInProgress"] as? Bool,
              let index = tabSlots.firstIndex(of: .terminal(sessionName: sessionName)),
              tabItems.indices.contains(index) else { return }
        tabItems[index].isAutoRenaming = isInProgress
    }

    @objc private func handleSettingsChanged(_ notification: Notification) {
        let settings = PersistenceService.shared.loadSettings()
        refreshPrimaryToolbarTint()
        tabItems.forEach { $0.refreshPrimaryColor() }
        draftTabs.forEach { $0.viewController?.refreshPrimaryColor() }
        promptTOCView?.refreshPrimaryColor()
        diffVC?.refreshPrimaryColor()
        let previousMouseWheelBehavior = currentTerminalMouseWheelBehavior
        currentTerminalMouseWheelBehavior = settings.terminalMouseWheelBehavior

        if let previousMouseWheelBehavior,
           previousMouseWheelBehavior != settings.terminalMouseWheelBehavior {
            // Wheel behavior is a surface-time Ghostty setting, so update the shared
            // embedded prefs before recreating any terminal surfaces.
            GhosttyAppManager.shared.applyEmbeddedPreferences(
                embeddedPreferences(for: settings),
                effectiveAppearance: view.effectiveAppearance
            )
            reloadTerminalViewsForUpdatedTerminalPreferences()
        }
        resyncLocalPathsButton.isHidden = resyncLocalPathsButtonShouldBeHidden()
        popOutThreadButton.isHidden = !shouldShowTopBarPopOutButton()
        refreshOpenPRButtonIcon()
        refreshJiraButton()
        refreshOverlayVisibilitySettings()
        updateTerminalScrollControlsState()
        refreshHeaderInfoStrip()
    }

    private func refreshPrimaryToolbarTint() {
        AppTheme.tintToolbarButtons([
            addTabButton,
            reviewButton,
            continueInButton,
            tabScrollLeftButton,
            tabScrollRightButton,
            exportContextButton,
            resyncLocalPathsButton,
            popOutThreadButton,
            togglePromptTOCButton,
        ])
    }

    private func reloadTerminalViewsForUpdatedTerminalPreferences() {
        guard !terminalViews.isEmpty else { return }

        ReusableTerminalViewCache.shared.removeAll()
        for terminalView in terminalViews {
            terminalView.removeFromSuperview()
        }

        terminalViews = thread.tmuxSessionNames.map(makeTerminalView(for:))

        let selectedIndex = min(currentTabIndex, tabSlots.count - 1)
        selectTab(at: selectedIndex)
    }

    func resyncLocalPathsButtonShouldBeHidden() -> Bool {
        let settings = PersistenceService.shared.loadSettings()
        let project = settings.projects.first(where: { $0.id == thread.projectId })
        guard let project else { return true }
        guard project.hasCopyLocalFileSyncEntries else { return true }
        let projectId = thread.projectId

        let activeProjectThreadCount = threadManager.threads.lazy.filter {
            !$0.isArchived && $0.projectId == projectId
        }.count
        return activeProjectThreadCount < 2
    }

    private var topBarButtons: [NSButton] {
        [
            addTabButton,
            openInXcodeButton,
            openInFinderButton,
            openPRButton,
            openInJiraButton,
            reviewButton,
            exportContextButton,
            resyncLocalPathsButton,
            popOutThreadButton,
            archiveThreadButton,
            tabScrollLeftButton,
            tabScrollRightButton,
        ]
    }

    private func refreshTerminalChromeAppearance() {
        guard isViewLoaded else { return }

        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            view.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
            terminalContainer.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
            archiveThreadButton.image = NSImage(
                systemSymbolName: "archivebox",
                accessibilityDescription: String(localized: .ThreadStrings.threadArchiveTitle)
            )
            reviewButton.image = NSImage(
                systemSymbolName: "text.magnifyingglass",
                accessibilityDescription: String(localized: .NotificationStrings.reviewChanges)
            )
            exportContextButton.image = NSImage(
                systemSymbolName: "square.and.arrow.up",
                accessibilityDescription: String(localized: .NotificationStrings.contextExport)
            )
            resyncLocalPathsButton.image = NSImage(
                systemSymbolName: "arrow.triangle.2.circlepath",
                accessibilityDescription: "Sync local-only files"
            )
            popOutThreadButton.image = NSImage(
                systemSymbolName: "macwindow.on.rectangle",
                accessibilityDescription: "Open thread in separate window"
            )
            addTabButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Tab")
            updatePromptTOCToggleButtonState(canShow: promptTOCCanShowForCurrentTab)
            refreshPrimaryToolbarTint()

            for button in topBarButtons {
                button.appearance = view.effectiveAppearance
                button.needsDisplay = true
            }

            topBar.needsDisplay = true
            pinSeparator.needsDisplay = true
            fixedTabsSeparator.needsDisplay = true
        }
    }

    func refreshHeaderInfoStrip() {
        guard isViewLoaded, showsHeaderInfoStrip else { return }
        let latest = threadManager.threads.first(where: { $0.id == thread.id }) ?? thread
        headerInfoStrip.refresh(from: latest)
    }

    private func shouldShowTopBarPopOutButton() -> Bool {
        guard showsHeaderInfoStrip else { return false }
        guard !thread.isMain else { return false }
        return !PopoutWindowManager.shared.isThreadPoppedOut(thread.id)
    }

    private func embeddedPreferences(for settings: AppSettings) -> GhosttyEmbeddedPreferences {
        let appearanceMode: GhosttyEmbeddedAppearanceMode
        switch settings.appAppearanceMode {
        case .system:
            appearanceMode = .system
        case .light:
            appearanceMode = .light
        case .dark:
            appearanceMode = .dark
        }

        let mouseWheelBehavior: GhosttyEmbeddedMouseWheelBehavior
        switch settings.terminalMouseWheelBehavior {
        case .magentDefaultScroll:
            mouseWheelBehavior = .magentDefaultScroll
        case .inheritGhosttyGlobal:
            mouseWheelBehavior = .inheritGhosttyGlobal
        case .allowAppsToCapture:
            mouseWheelBehavior = .allowAppsToCapture
        }

        return GhosttyEmbeddedPreferences(
            appearanceMode: appearanceMode,
            mouseWheelBehavior: mouseWheelBehavior
        )
    }

    func refreshInitialPromptFailureBanner() {
        guard let sessionName = currentSessionName(),
              let failure = threadManager.initialPromptInjectionFailure(for: sessionName) else {
            dismissInitialPromptFailureBanner()
            refreshAgentShellBanner()
            return
        }
        showInitialPromptFailureBanner(sessionName: sessionName, failure: failure)
    }

    func refreshAgentShellBanner() {
        guard let sessionName = currentSessionName(),
              isAgentShellBannerCandidate(sessionName: sessionName) else {
            cancelAgentShellBannerReveal()
            dismissAgentShellBanner()
            return
        }
        guard threadManager.isAgentSessionAtShell(sessionName) else {
            dismissAgentShellBanner()
            return
        }
        guard agentShellBannerSessionName != sessionName || agentShellBanner == nil else { return }
        guard agentShellBannerPendingSessionName != sessionName else { return }

        dismissAgentShellBanner()
        cancelAgentShellBannerReveal()
        agentShellBannerPendingSessionName = sessionName
        agentShellBannerRevealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: AgentShellRelaunchOfferPolicy.revealDelay)
            guard !Task.isCancelled, let self else { return }

            for recheck in 0...AgentShellRelaunchOfferPolicy.maximumRecheckCount {
                guard self.isAgentShellBannerCandidate(sessionName: sessionName) else {
                    self.agentShellBannerRevealTask = nil
                    self.agentShellBannerPendingSessionName = nil
                    return
                }
                if self.threadManager.isAgentSessionAtShell(sessionName) {
                    self.agentShellBannerRevealTask = nil
                    self.agentShellBannerPendingSessionName = nil
                    self.showAgentShellBannerIfEligible(sessionName: sessionName)
                    return
                }
                guard recheck < AgentShellRelaunchOfferPolicy.maximumRecheckCount else { break }
                try? await Task.sleep(for: AgentShellRelaunchOfferPolicy.recheckInterval)
                guard !Task.isCancelled else { return }
            }

            self.agentShellBannerRevealTask = nil
            self.agentShellBannerPendingSessionName = nil
        }
    }

    private func isAgentShellBannerCandidate(sessionName: String) -> Bool {
        guard initialPromptFailureBanner == nil,
              pendingPromptBanner == nil,
              recoveryBanner == nil,
              currentSessionName() == sessionName,
              !agentStartRequestedSessions.contains(sessionName) else { return false }

        let currentThread = latestThreadSnapshot()
        guard let sessionIndex = currentThread.tmuxSessionNames.firstIndex(of: sessionName) else {
            return false
        }
        return AgentShellRelaunchOfferPolicy.isCandidate(
            isTrackedAgentSession: currentThread.agentTmuxSessions.contains(sessionName),
            configuredAgentType: currentThread.sessionAgentTypes[sessionName],
            displayName: currentThread.displayName(for: sessionName, at: sessionIndex)
        )
    }

    private func showAgentShellBannerIfEligible(sessionName: String) {
        guard isAgentShellBannerCandidate(sessionName: sessionName),
              threadManager.isAgentSessionAtShell(sessionName) else { return }

        let banner = BannerView(config: BannerConfig(
            message: "The agent has exited and this tab is back at its shell.",
            style: .info,
            duration: nil,
            isDismissible: true,
            actions: [BannerAction(title: "Start Agent") { [weak self] in
                guard let self else { return }
                let injection = self.threadManager.effectiveInjection(for: self.thread.projectId)
                self.agentStartRequestedSessions.insert(sessionName)
                if self.threadManager.relaunchAgentInExistingSession(
                    sessionName: sessionName,
                    agentContext: injection.agentContext,
                    agentType: self.thread.sessionAgentTypes[sessionName]
                ) {
                    self.dismissAgentShellBanner()
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(15))
                        guard let self else { return }
                        self.agentStartRequestedSessions.remove(sessionName)
                        self.refreshAgentShellBanner()
                    }
                } else {
                    self.agentStartRequestedSessions.remove(sessionName)
                }
            }]
        ))
        banner.translatesAutoresizingMaskIntoConstraints = false
        terminalBannerOverlay.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: terminalBannerOverlay.topAnchor, constant: 12),
            banner.centerXAnchor.constraint(equalTo: terminalBannerOverlay.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: terminalBannerOverlay.leadingAnchor, constant: 20),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: terminalBannerOverlay.trailingAnchor, constant: -20),
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ])
        agentShellBanner = banner
        agentShellBannerSessionName = sessionName
        bringTerminalBannerOverlayToFront()
    }

    private func dismissAgentShellBanner() {
        agentShellBanner?.removeFromSuperview()
        agentShellBanner = nil
        agentShellBannerSessionName = nil
    }

    private func cancelAgentShellBannerReveal() {
        agentShellBannerRevealTask?.cancel()
        agentShellBannerRevealTask = nil
        agentShellBannerPendingSessionName = nil
    }

    private func copyPromptToPasteboard(_ prompt: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)
    }

    private func retryInitialPromptInjection(
        sessionName: String,
        failure: ThreadManager.InitialPromptInjectionFailureInfo
    ) {
        let injection = threadManager.effectiveInjection(for: thread.projectId)
        if failure.requiresAgentRelaunch {
            let relaunched = threadManager.relaunchAgentInExistingSession(
                sessionName: sessionName,
                initialPrompt: failure.prompt,
                shouldSubmitInitialPrompt: failure.shouldSubmitInitialPrompt,
                agentContext: injection.agentContext,
                agentType: failure.agentType
            )
            if !relaunched {
                threadManager.injectAfterStart(
                    sessionName: sessionName,
                    terminalCommand: "",
                    agentContext: injection.agentContext,
                    initialPrompt: failure.prompt,
                    shouldSubmitInitialPrompt: failure.shouldSubmitInitialPrompt,
                    agentType: failure.agentType
                )
            }
        } else {
            threadManager.injectAfterStart(
                sessionName: sessionName,
                terminalCommand: "",
                agentContext: injection.agentContext,
                initialPrompt: failure.prompt,
                shouldSubmitInitialPrompt: failure.shouldSubmitInitialPrompt,
                agentType: failure.agentType
            )
        }
        refreshInitialPromptFailureBanner()
    }

    private func restartPromptInjection(
        sessionName: String,
        promptInfo: ThreadManager.InitialPromptInjectionFailureInfo
    ) {
        let injection = threadManager.effectiveInjection(for: thread.projectId)
        let relaunched = threadManager.relaunchAgentInExistingSession(
            sessionName: sessionName,
            initialPrompt: promptInfo.prompt,
            shouldSubmitInitialPrompt: promptInfo.shouldSubmitInitialPrompt,
            agentContext: injection.agentContext,
            agentType: promptInfo.agentType
        )
        guard relaunched else {
            BannerManager.shared.show(
                message: "Could not restart this tab. Try manual prompt injection or open a new agent tab.",
                style: .warning
            )
            return
        }
        dismissInitialPromptFailureBanner()
        refreshPendingPromptBanner()
    }

    private func showInitialPromptFailureBanner(
        sessionName: String,
        failure: ThreadManager.InitialPromptInjectionFailureInfo
    ) {
        dismissAgentShellBanner()
        if initialPromptFailureBannerSessionName == sessionName,
           initialPromptFailureBanner != nil {
            return
        }

        dismissInitialPromptFailureBanner()

        let banner = BannerView(config: BannerConfig(
            message: failure.requiresAgentRelaunch
                ? "The agent stopped during launch and this tab is now at a shell prompt."
                : "Initial prompt injection failed for this tab.",
            style: .warning,
            duration: nil,
            isDismissible: false,
            actions: [
                BannerAction(title: failure.requiresAgentRelaunch ? "Relaunch Agent" : "Inject Prompt") { [weak self] in
                    guard let self else { return }
                    self.retryInitialPromptInjection(sessionName: sessionName, failure: failure)
                },
                BannerAction(title: "Restart Tab") { [weak self] in
                    guard let self else { return }
                    self.restartPromptInjection(sessionName: sessionName, promptInfo: failure)
                },
                BannerAction(title: "Copy Prompt") { [weak self] in
                    guard let self else { return }
                    self.copyPromptToPasteboard(failure.prompt)
                    self.threadManager.clearTrackedInitialPromptInjection(for: sessionName)
                    self.refreshInitialPromptFailureBanner()
                },
                BannerAction(title: "Already Injected") { [weak self] in
                    guard let self else { return }
                    self.threadManager.clearTrackedInitialPromptInjection(for: sessionName)
                    self.refreshInitialPromptFailureBanner()
                },
            ]
        ))
        bringTerminalBannerOverlayToFront()
        banner.translatesAutoresizingMaskIntoConstraints = false
        terminalBannerOverlay.addSubview(banner)
        let topConstraint = banner.topAnchor.constraint(equalTo: terminalBannerOverlay.topAnchor, constant: 12)
        NSLayoutConstraint.activate([
            topConstraint,
            banner.centerXAnchor.constraint(equalTo: terminalBannerOverlay.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: terminalBannerOverlay.leadingAnchor, constant: 20),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: terminalBannerOverlay.trailingAnchor, constant: -20),
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ])

        initialPromptFailureBanner = banner
        initialPromptFailureBannerSessionName = sessionName
        initialPromptFailureBannerTopConstraint = topConstraint
    }

    // MARK: - Pending Prompt Injection Banner

    func refreshPendingPromptBanner() {
        guard let sessionName = currentSessionName(),
              let pending = threadManager.pendingPromptInjection(for: sessionName) else {
            dismissPendingPromptBanner()
            refreshAgentShellBanner()
            return
        }
        showPendingPromptBanner(sessionName: sessionName, pending: pending)
    }

    private func showPendingPromptBanner(
        sessionName: String,
        pending: ThreadManager.InitialPromptInjectionFailureInfo
    ) {
        dismissAgentShellBanner()
        if pendingPromptBannerSessionName == sessionName,
           pendingPromptBanner != nil {
            return
        }

        dismissPendingPromptBanner()

        let banner = BannerView(config: BannerConfig(
            message: "Prompt will be injected once the agent is ready.",
            style: .info,
            duration: nil,
            isDismissible: false,
            actions: [
                BannerAction(title: "Copy Prompt") { [weak self] in
                    self?.copyPromptToPasteboard(pending.prompt)
                },
                BannerAction(title: "Restart Tab") { [weak self] in
                    guard let self else { return }
                    self.dismissPendingPromptBanner()
                    self.restartPromptInjection(sessionName: sessionName, promptInfo: pending)
                },
                BannerAction(title: "Inject Now") { [weak self] in
                    guard let self else { return }
                    self.dismissPendingPromptBanner()
                    self.threadManager.injectPendingPromptNow(
                        sessionName: sessionName,
                        prompt: pending.prompt,
                        shouldSubmitInitialPrompt: pending.shouldSubmitInitialPrompt,
                        agentType: pending.agentType
                    )
                },
            ]
        ))
        bringTerminalBannerOverlayToFront()
        banner.translatesAutoresizingMaskIntoConstraints = false
        terminalBannerOverlay.addSubview(banner)
        let topConstraint = banner.topAnchor.constraint(equalTo: terminalBannerOverlay.topAnchor, constant: 12)
        NSLayoutConstraint.activate([
            topConstraint,
            banner.centerXAnchor.constraint(equalTo: terminalBannerOverlay.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: terminalBannerOverlay.leadingAnchor, constant: 20),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: terminalBannerOverlay.trailingAnchor, constant: -20),
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ])

        pendingPromptBanner = banner
        pendingPromptBannerSessionName = sessionName
        pendingPromptBannerTopConstraint = topConstraint
    }

    private func dismissPendingPromptBanner() {
        pendingPromptBanner?.removeFromSuperview()
        pendingPromptBanner = nil
        pendingPromptBannerSessionName = nil
        pendingPromptBannerTopConstraint = nil
    }

    private func dismissInitialPromptFailureBanner() {
        initialPromptFailureBanner?.removeFromSuperview()
        initialPromptFailureBanner = nil
        initialPromptFailureBannerSessionName = nil
        initialPromptFailureBannerTopConstraint = nil
    }

    // MARK: - Pending Prompt Recovery Banner

    @objc private func handlePendingPromptRecoveryNotification(_ notification: Notification) {
        guard let threadId = notification.userInfo?["threadId"] as? UUID,
              threadId == thread.id else {
            return
        }
        refreshRecoveryBanner()
    }

    @objc private func handleTabReturnedToThread(_ notification: Notification) {
        guard let sessionName = notification.userInfo?["sessionName"] as? String,
              let threadId = notification.userInfo?["threadId"] as? UUID,
              threadId == thread.id else { return }
        returnDetachedTab(sessionName: sessionName)
    }

    func refreshRecoveryBanner() {
        let recoveries = threadManager.pendingPromptRecoveries(for: thread.id)
        guard let first = recoveries.first else {
            pendingPromptRecoveryReminderState.setRecoverablePromptsAvailable(false)
            dismissRecoveryBanner()
            postPendingPromptRecoveryReminderChanged()
            refreshAgentShellBanner()
            return
        }

        pendingPromptRecoveryReminderState.setRecoverablePromptsAvailable(true)
        if pendingPromptRecoveryReminderState.isReminderVisible {
            dismissRecoveryBanner()
            postPendingPromptRecoveryReminderChanged()
            return
        }
        showRecoveryBanner(recovery: first, total: recoveries.count)
    }

    func redisplayDismissedRecoveryBanner() {
        pendingPromptRecoveryReminderState.reminderActivated()
        postPendingPromptRecoveryReminderChanged()
        refreshRecoveryBanner()
    }

    private func showRecoveryBanner(
        recovery: ThreadManager.PendingPromptRecoveryInfo,
        total: Int
    ) {
        dismissAgentShellBanner()
        // Already showing — skip (actions will refresh on next cycle).
        guard recoveryBanner == nil else { return }

        let threadId = thread.id
        let countSuffix = total > 1 ? " (\(total) prompts)" : ""
        let promptPreview = recovery.prompt.magentPromptPreview(maxLength: 140, singleLine: true)
        let promptDetails = recovery.prompt.magentPromptPreview(maxLength: 500, singleLine: false)
        let banner = BannerView(config: BannerConfig(
            message: "Unsubmitted tab prompt recovered for this thread.\(countSuffix)\nPreview: \(promptPreview)",
            style: .warning,
            duration: nil,
            isDismissible: true,
            actions: [
                BannerAction(title: "Copy Prompt") { [weak self] in
                    self?.copyPromptToPasteboard(recovery.prompt)
                },
                BannerAction(title: "Reopen as Thread") { [weak self] in
                    guard let self else { return }
                    let prefill = AgentLaunchSheetPrefill(
                        prompt: recovery.prompt,
                        description: nil,
                        branchName: nil,
                        agentType: recovery.agentType,
                        modelId: recovery.modelId,
                        reasoningLevel: recovery.reasoningLevel,
                        selectionRaw: recovery.agentType?.rawValue ?? "terminal",
                        isDraft: false
                    )
                    self.threadManager.removePendingPromptRecovery(for: threadId, tempFileURL: recovery.tempFileURL)
                    self.dismissRecoveryBanner()
                    NotificationCenter.default.post(
                        name: .magentRecoveryReopenRequested,
                        object: nil,
                        userInfo: [
                            "projectId": recovery.projectId,
                            "tempFileURL": recovery.tempFileURL,
                            "prefill": prefill,
                        ]
                    )
                    // Show next recovery banner if any remain.
                    self.refreshRecoveryBanner()
                },
                BannerAction(title: "Discard") { [weak self] in
                    guard let self else { return }
                    guard self.confirmDiscardRecoveredPrompt() else { return }
                    try? FileManager.default.removeItem(at: recovery.tempFileURL)
                    self.threadManager.removePendingPromptRecovery(for: threadId, tempFileURL: recovery.tempFileURL)
                    self.dismissRecoveryBanner()
                    // Show next recovery banner if any remain.
                    self.refreshRecoveryBanner()
                },
            ],
            details: promptDetails,
            detailsCollapsedTitle: "Show More",
            detailsExpandedTitle: "Hide More"
        ))
        // Dismiss just hides the banner — data stays alive and the banner reappears
        // next time the thread is selected.
        banner.onDismiss = { [weak self] in
            guard let self else { return }
            self.pendingPromptRecoveryReminderState.bannerDismissed(hasRecoverablePrompts: true)
            self.dismissRecoveryBanner()
            self.postPendingPromptRecoveryReminderChanged()
        }
        bringTerminalBannerOverlayToFront()
        banner.translatesAutoresizingMaskIntoConstraints = false
        terminalBannerOverlay.addSubview(banner)
        let topConstraint = banner.topAnchor.constraint(equalTo: terminalBannerOverlay.topAnchor, constant: 12)
        NSLayoutConstraint.activate([
            topConstraint,
            banner.centerXAnchor.constraint(equalTo: terminalBannerOverlay.centerXAnchor),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: terminalBannerOverlay.leadingAnchor, constant: 20),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: terminalBannerOverlay.trailingAnchor, constant: -20),
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
        ])

        recoveryBanner = banner
        recoveryBannerTopConstraint = topConstraint
        pendingPromptRecoveryReminderState.bannerBecameVisible(hasRecoverablePrompts: true)
        postPendingPromptRecoveryReminderChanged()
    }

    private func confirmDiscardRecoveredPrompt() -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: .ThreadStrings.threadDiscardRecoveredPromptTitle)
        alert.informativeText = String(localized: .ThreadStrings.threadDiscardRecoveredPromptMessage)
        let discardButton = alert.addButton(withTitle: String(localized: .ThreadStrings.threadDiscardRecoveredPromptButton))
        discardButton.hasDestructiveAction = true
        alert.addButton(withTitle: String(localized: .CommonStrings.commonCancel))
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func dismissRecoveryBanner() {
        recoveryBanner?.removeFromSuperview()
        recoveryBanner = nil
        recoveryBannerTopConstraint = nil
    }

    private func postPendingPromptRecoveryReminderChanged() {
        NotificationCenter.default.post(
            name: .magentPendingPromptRecoveryReminderChanged,
            object: self
        )
    }

}

final class VerticalSeparatorView: NSView {
    static var separatorColor: NSColor { .tertiaryLabelColor }

    override var intrinsicContentSize: NSSize { NSSize(width: 1, height: 18) }
    override func draw(_ dirtyRect: NSRect) {
        Self.separatorColor.setFill()
        bounds.fill()
    }
}
