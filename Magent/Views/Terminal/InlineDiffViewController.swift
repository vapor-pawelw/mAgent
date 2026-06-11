import Cocoa
import WebKit

private final class DiffDividerResizeHandle: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}

private final class DiffHostView: NSView {
    var onAppearanceChange: (() -> Void)?
    var onPerformKeyEquivalent: ((NSEvent) -> Bool)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onPerformKeyEquivalent?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class WeakDiffScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

private struct PendingDiffRendererCall {
    let javaScript: String
    let completion: ((Any?, (any Error)?) -> Void)?
}

private enum DiffSearchMode: String, CaseIterable {
    case caseInsensitive
    case caseSensitive
    case regex

    static let defaultsKey = "InlineDiffViewController.searchMode"

    var title: String {
        switch self {
        case .caseInsensitive: "Case Insensitive"
        case .caseSensitive: "Case Sensitive"
        case .regex: "Regex"
        }
    }

    var tooltip: String {
        switch self {
        case .caseInsensitive: "Case Insensitive"
        case .caseSensitive: "Case Sensitive"
        case .regex: "Regex"
        }
    }

    static var persisted: DiffSearchMode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
                  let mode = DiffSearchMode(rawValue: raw) else {
                return .caseInsensitive
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
        }
    }
}

final class InlineDiffViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    nonisolated private static let maxLineCountedFileBytes = 5 * 1024 * 1024
    nonisolated private static let lineCountChunkSize = 64 * 1024

    private let closeButton = NSButton()
    private let expandCollapseButton = NSButton()
    private let headerLabel = NSTextField(labelWithString: "")
    private let resizeHandle = DiffDividerResizeHandle()
    private let loadingOverlay = NSView()
    private let loadingSpinner = NSProgressIndicator()
    private let loadingMessageLabel = NSTextField(labelWithString: "")
    private let summaryFilesLabel = NSTextField(labelWithString: "")
    private let summaryAddedLabel = NSTextField(labelWithString: "")
    private let summaryDeletedLabel = NSTextField(labelWithString: "")
    private let reviewMenuButton = NSButton(title: "Review ▾", target: nil, action: nil)
    private let viewMenuButton = NSButton(title: "Files ▾", target: nil, action: nil)
    private let commitReviewBannerView = NSView()
    private let commitReviewIconView = NSImageView()
    private let commitReviewLabel = NSTextField(labelWithString: "")
    private let currentChangesButton = NSButton(title: String(localized: .ThreadStrings.diffCommitReviewCurrentChanges), target: nil, action: nil)
    private let findBar = NSStackView()
    private let findField = NSSearchField()
    private let findModeButton = NSPopUpButton()
    private let findPreviousButton = NSButton()
    private let findNextButton = NSButton()
    private let findDoneButton = NSButton()
    private let findStatusLabel = NSTextField(labelWithString: "")
    private let webView: WKWebView
    private var headerBar: NSView?
    private var resizeHandleHeightConstraint: NSLayoutConstraint?
    private var headerBarHeightConstraint: NSLayoutConstraint?
    private var commitReviewLabelTrailingConstraint: NSLayoutConstraint?
    private var currentChangesButtonLeadingConstraint: NSLayoutConstraint?
    private var currentChangesButtonTrailingConstraint: NSLayoutConstraint?
    private var showsInlineChrome = true

    private var isRendererReady = false
    private var pendingJavaScriptCalls: [PendingDiffRendererCall] = []
    private var allExpanded = true
    private var didRevealWebView = false
    private var currentWorktreePath: String?
    private var currentFileCountSummary: Int = 0
    private var currentReviewedFileCountSummary: Int = 0
    private var loadingWatchdog: Timer?
    private var rendererReadinessTask: Task<Void, Never>?
    private var searchDebounceTimer: Timer?
    private var searchMode: DiffSearchMode = .persisted
    private var loadingGeneration = 0
    private var fileLineCountsGeneration = 0
    private var fileLineCountsTask: Task<Void, Never>?
    private var currentRenderDiagnosticSummary = "no render requested"

    private static let rendererLoadTimeout: TimeInterval = 12

    var onClose: (() -> Void)?
    var onImageClick: ((_ imageView: NSImageView, _ image: NSImage) -> Void)?
    /// Called during drag with the delta (positive = drag up = diff taller).
    var onResizeDrag: ((_ phase: NSPanGestureRecognizer.State, _ deltaY: CGFloat) -> Void)?
    var onReviewedFilesChanged: (([String: String]) -> Void)?
    var onReturnToCurrentChanges: (() -> Void)?
    var onReviewProgressChanged: ((_ reviewedCount: Int, _ fileCount: Int) -> Void)?
    var onCollapsedFilesChanged: (([String: Bool]) -> Void)?
    var onFileActionsMenuRequested: ((_ filePath: String, _ point: NSPoint) -> Void)?
    var onTextContextMenuRequested: ((_ selectedText: String, _ fallbackText: String, _ lineFilePath: String?, _ lineNumber: Int?, _ point: NSPoint) -> Void)?

    init() {
        let userContentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(nibName: nil, bundle: nil)

        webView.navigationDelegate = self

        userContentController.add(WeakDiffScriptMessageHandler(delegate: self), name: "diffRenderer")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func setShowsInlineChrome(_ showsInlineChrome: Bool) {
        self.showsInlineChrome = showsInlineChrome
        guard isViewLoaded else { return }
        applyChromeMode()
    }

    override func loadView() {
        let hostView = DiffHostView()
        hostView.onAppearanceChange = { [weak self] in
            self?.applyAppearance()
        }
        hostView.onPerformKeyEquivalent = { [weak self] event in
            self?.handleKeyEquivalent(event) ?? false
        }
        view = hostView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        setupUI()
        applyChromeMode()
        applyAppearance()
        showLoadingOverlay()
        loadRenderer()
    }

    private func setupUI() {
        resizeHandle.wantsLayer = true
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        let separatorLine = NSView()
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = NSColor(resource: .textSecondary).withAlphaComponent(0.4).cgColor
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.addSubview(separatorLine)

        let headerBar = NSView()
        headerBar.wantsLayer = true
        headerBar.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        self.headerBar = headerBar

        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = NSColor(resource: .textSecondary)
        headerLabel.stringValue = "DIFF"
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerLabel)

        expandCollapseButton.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "Collapse All")
        expandCollapseButton.contentTintColor = NSColor(resource: .textSecondary)
        expandCollapseButton.bezelStyle = .inline
        expandCollapseButton.isBordered = false
        expandCollapseButton.target = self
        expandCollapseButton.action = #selector(toggleExpandCollapseAll)
        expandCollapseButton.toolTip = "Collapse All"
        expandCollapseButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(expandCollapseButton)

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close Diff")
        closeButton.contentTintColor = NSColor(resource: .textSecondary)
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(closeButton)

        summaryFilesLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        summaryFilesLabel.textColor = NSColor(resource: .textSecondary)
        summaryFilesLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryFilesLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        headerBar.addSubview(summaryFilesLabel)

        summaryAddedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        summaryAddedLabel.textColor = .systemGreen
        summaryAddedLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryAddedLabel.isHidden = true
        headerBar.addSubview(summaryAddedLabel)

        summaryDeletedLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        summaryDeletedLabel.textColor = .systemRed
        summaryDeletedLabel.translatesAutoresizingMaskIntoConstraints = false
        summaryDeletedLabel.isHidden = true
        headerBar.addSubview(summaryDeletedLabel)

        reviewMenuButton.bezelStyle = .rounded
        reviewMenuButton.controlSize = .small
        reviewMenuButton.isBordered = true
        reviewMenuButton.target = self
        reviewMenuButton.action = #selector(showReviewMenu)
        reviewMenuButton.translatesAutoresizingMaskIntoConstraints = false
        reviewMenuButton.isHidden = true
        headerBar.addSubview(reviewMenuButton)

        viewMenuButton.bezelStyle = .rounded
        viewMenuButton.controlSize = .small
        viewMenuButton.isBordered = true
        viewMenuButton.target = self
        viewMenuButton.action = #selector(showViewMenu)
        viewMenuButton.translatesAutoresizingMaskIntoConstraints = false
        viewMenuButton.isHidden = true
        headerBar.addSubview(viewMenuButton)

        commitReviewBannerView.wantsLayer = true
        commitReviewBannerView.layer?.cornerRadius = 6
        commitReviewBannerView.layer?.borderWidth = 1
        commitReviewBannerView.translatesAutoresizingMaskIntoConstraints = false
        commitReviewBannerView.isHidden = true
        headerBar.addSubview(commitReviewBannerView)

        commitReviewIconView.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "Commit review")
        commitReviewIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        commitReviewIconView.translatesAutoresizingMaskIntoConstraints = false
        commitReviewBannerView.addSubview(commitReviewIconView)

        commitReviewLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        commitReviewLabel.lineBreakMode = .byTruncatingMiddle
        commitReviewLabel.translatesAutoresizingMaskIntoConstraints = false
        commitReviewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        commitReviewLabel.setContentHuggingPriority(.required, for: .horizontal)
        commitReviewBannerView.addSubview(commitReviewLabel)

        currentChangesButton.bezelStyle = .rounded
        currentChangesButton.controlSize = .small
        currentChangesButton.target = self
        currentChangesButton.action = #selector(returnToCurrentChangesTapped)
        currentChangesButton.translatesAutoresizingMaskIntoConstraints = false
        commitReviewBannerView.addSubview(currentChangesButton)

        findField.placeholderString = "Find in diff"
        findField.controlSize = .small
        findField.sendsSearchStringImmediately = true
        findField.sendsWholeSearchString = false
        findField.translatesAutoresizingMaskIntoConstraints = false
        findField.delegate = self

        findModeButton.controlSize = .small
        findModeButton.bezelStyle = .rounded
        findModeButton.translatesAutoresizingMaskIntoConstraints = false
        findModeButton.setContentHuggingPriority(.required, for: .horizontal)
        findModeButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        findModeButton.target = self
        findModeButton.action = #selector(searchModeChanged)
        for mode in DiffSearchMode.allCases {
            findModeButton.addItem(withTitle: mode.title)
            findModeButton.lastItem?.representedObject = mode.rawValue
            findModeButton.lastItem?.toolTip = mode.tooltip
        }
        findModeButton.selectItem(withTitle: searchMode.title)
        findModeButton.toolTip = searchMode.tooltip

        findPreviousButton.image = NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "Previous")
        findNextButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Next")
        findDoneButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Close Search")
        for button in [findPreviousButton, findNextButton, findDoneButton] {
            button.bezelStyle = .rounded
            button.isBordered = true
            button.controlSize = .small
            button.imageScaling = .scaleProportionallyDown
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setContentHuggingPriority(.required, for: .horizontal)
        }
        findPreviousButton.target = self
        findPreviousButton.action = #selector(findPrevious)
        findNextButton.target = self
        findNextButton.action = #selector(findNext)
        findDoneButton.target = self
        findDoneButton.action = #selector(hideFindBar)

        findStatusLabel.font = .systemFont(ofSize: 11)
        findStatusLabel.textColor = .secondaryLabelColor
        findStatusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        findBar.orientation = .horizontal
        findBar.spacing = 6
        findBar.alignment = .centerY
        findBar.translatesAutoresizingMaskIntoConstraints = false
        findBar.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        findBar.wantsLayer = true
        findBar.layer?.cornerRadius = 8
        findBar.layer?.borderWidth = 1
        findBar.isHidden = true
        findBar.addArrangedSubview(findField)
        findBar.addArrangedSubview(findModeButton)
        findBar.addArrangedSubview(findPreviousButton)
        findBar.addArrangedSubview(findNextButton)
        findBar.addArrangedSubview(findStatusLabel)
        findBar.addArrangedSubview(findDoneButton)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.wantsLayer = true
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = 0
        webView.isHidden = true

        loadingOverlay.wantsLayer = true
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.isHidden = false

        loadingSpinner.style = .spinning
        loadingSpinner.controlSize = .regular
        loadingSpinner.isDisplayedWhenStopped = false
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false

        loadingMessageLabel.font = .systemFont(ofSize: 12, weight: .regular)
        loadingMessageLabel.textColor = NSColor(resource: .textSecondary)
        loadingMessageLabel.alignment = .center
        loadingMessageLabel.lineBreakMode = .byWordWrapping
        loadingMessageLabel.maximumNumberOfLines = 3
        loadingMessageLabel.isHidden = true
        loadingMessageLabel.translatesAutoresizingMaskIntoConstraints = false

        let loadingStack = NSStackView(views: [loadingSpinner, loadingMessageLabel])
        loadingStack.orientation = .vertical
        loadingStack.alignment = .centerX
        loadingStack.spacing = 10
        loadingStack.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.addSubview(loadingStack)

        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleResizeDrag(_:)))
        resizeHandle.addGestureRecognizer(panGesture)

        view.addSubview(resizeHandle)
        view.addSubview(headerBar)
        headerBar.addSubview(findBar)
        view.addSubview(webView)
        view.addSubview(loadingOverlay)

        commitReviewLabelTrailingConstraint = commitReviewLabel.trailingAnchor.constraint(
            equalTo: commitReviewBannerView.trailingAnchor,
            constant: -8
        )
        currentChangesButtonLeadingConstraint = currentChangesButton.leadingAnchor.constraint(
            equalTo: commitReviewLabel.trailingAnchor,
            constant: 10
        )
        currentChangesButtonTrailingConstraint = currentChangesButton.trailingAnchor.constraint(
            equalTo: commitReviewBannerView.trailingAnchor,
            constant: -6
        )

        NSLayoutConstraint.activate([
            resizeHandle.topAnchor.constraint(equalTo: view.topAnchor),
            resizeHandle.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            resizeHandle.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            {
                let c = resizeHandle.heightAnchor.constraint(equalToConstant: 6)
                resizeHandleHeightConstraint = c
                return c
            }(),

            separatorLine.centerYAnchor.constraint(equalTo: resizeHandle.centerYAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: resizeHandle.leadingAnchor, constant: 8),
            separatorLine.trailingAnchor.constraint(equalTo: resizeHandle.trailingAnchor, constant: -8),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),

            headerBar.topAnchor.constraint(equalTo: resizeHandle.bottomAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            {
                let c = headerBar.heightAnchor.constraint(equalToConstant: 40)
                headerBarHeightConstraint = c
                return c
            }(),

            headerLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            headerLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 16),
            closeButton.heightAnchor.constraint(equalToConstant: 16),

            expandCollapseButton.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -6),
            expandCollapseButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            expandCollapseButton.widthAnchor.constraint(equalToConstant: 16),
            expandCollapseButton.heightAnchor.constraint(equalToConstant: 16),

            summaryFilesLabel.leadingAnchor.constraint(equalTo: headerBar.leadingAnchor, constant: 12),
            summaryFilesLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            summaryDeletedLabel.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -12),
            summaryDeletedLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            summaryAddedLabel.trailingAnchor.constraint(equalTo: summaryDeletedLabel.leadingAnchor, constant: -12),
            summaryAddedLabel.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            reviewMenuButton.trailingAnchor.constraint(equalTo: summaryAddedLabel.leadingAnchor, constant: -12),
            reviewMenuButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            viewMenuButton.trailingAnchor.constraint(equalTo: reviewMenuButton.leadingAnchor, constant: -8),
            viewMenuButton.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),

            commitReviewBannerView.leadingAnchor.constraint(equalTo: summaryFilesLabel.trailingAnchor, constant: 12),
            commitReviewBannerView.trailingAnchor.constraint(lessThanOrEqualTo: viewMenuButton.leadingAnchor, constant: -12),
            commitReviewBannerView.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            commitReviewBannerView.heightAnchor.constraint(equalToConstant: 28),

            commitReviewIconView.leadingAnchor.constraint(equalTo: commitReviewBannerView.leadingAnchor, constant: 8),
            commitReviewIconView.centerYAnchor.constraint(equalTo: commitReviewBannerView.centerYAnchor),
            commitReviewIconView.widthAnchor.constraint(equalToConstant: 16),

            commitReviewLabel.leadingAnchor.constraint(equalTo: commitReviewIconView.trailingAnchor, constant: 6),
            commitReviewLabel.centerYAnchor.constraint(equalTo: commitReviewBannerView.centerYAnchor),

            currentChangesButton.centerYAnchor.constraint(equalTo: commitReviewBannerView.centerYAnchor),

            findBar.centerYAnchor.constraint(equalTo: headerBar.centerYAnchor),
            findBar.trailingAnchor.constraint(equalTo: headerBar.trailingAnchor, constant: -8),
            findBar.leadingAnchor.constraint(greaterThanOrEqualTo: headerLabel.trailingAnchor, constant: 12),
            findField.widthAnchor.constraint(equalToConstant: 220),
            findModeButton.widthAnchor.constraint(equalToConstant: 150),
            findPreviousButton.widthAnchor.constraint(equalToConstant: 24),
            findPreviousButton.heightAnchor.constraint(equalToConstant: 24),
            findNextButton.widthAnchor.constraint(equalToConstant: 24),
            findNextButton.heightAnchor.constraint(equalToConstant: 24),
            findDoneButton.widthAnchor.constraint(equalToConstant: 24),
            findDoneButton.heightAnchor.constraint(equalToConstant: 24),

            webView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingOverlay.topAnchor.constraint(equalTo: webView.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: webView.bottomAnchor),

            loadingStack.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingStack.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
            loadingStack.leadingAnchor.constraint(greaterThanOrEqualTo: loadingOverlay.leadingAnchor, constant: 24),
            loadingStack.trailingAnchor.constraint(lessThanOrEqualTo: loadingOverlay.trailingAnchor, constant: -24),
        ])

        commitReviewLabelTrailingConstraint?.isActive = true
    }

    private func applyChromeMode() {
        resizeHandle.isHidden = !showsInlineChrome
        headerBar?.isHidden = false
        headerLabel.isHidden = !showsInlineChrome
        expandCollapseButton.isHidden = !showsInlineChrome
        closeButton.isHidden = !showsInlineChrome
        summaryFilesLabel.isHidden = showsInlineChrome
        summaryAddedLabel.isHidden = showsInlineChrome
        summaryDeletedLabel.isHidden = showsInlineChrome
        reviewMenuButton.isHidden = showsInlineChrome
        viewMenuButton.isHidden = showsInlineChrome
        if showsInlineChrome {
            commitReviewBannerView.isHidden = true
        }
        resizeHandleHeightConstraint?.constant = showsInlineChrome ? 6 : 0
        headerBarHeightConstraint?.constant = 40
        applySearchMode()
    }

    private func loadRenderer() {
        guard let indexURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "DiffRenderer/dist"
        ) ?? Bundle.main.url(
            forResource: "index",
            withExtension: "html"
        ) else {
            setDiffUnavailableMessage("Diff renderer resources are missing.")
            return
        }

        configureDocumentStartThemeScript()
        startRendererReadinessPolling()
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    private func applyAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let backgroundColor = NSColor(resource: .appBackground)
            let background = backgroundColor.cgColor
            view.layer?.backgroundColor = background
            webView.layer?.backgroundColor = background
            loadingOverlay.layer?.backgroundColor = background
            commitReviewBannerView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
            commitReviewBannerView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.55).cgColor
            findBar.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.94).cgColor
            findBar.layer?.borderColor = NSColor.separatorColor.cgColor
            if #available(macOS 12.0, *) {
                webView.underPageBackgroundColor = backgroundColor
            }
        }
        commitReviewIconView.contentTintColor = .controlAccentColor
        commitReviewLabel.textColor = .controlAccentColor
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        evaluateRendererCall("window.magentDiffRenderer?.setTheme(\(jsonString(isDark ? "dark" : "light")))")
    }

    private func showLoadingOverlay() {
        loadingGeneration += 1
        let generation = loadingGeneration
        didRevealWebView = false
        loadingMessageLabel.isHidden = true
        loadingMessageLabel.stringValue = ""
        loadingOverlay.isHidden = false
        loadingOverlay.alphaValue = 1
        loadingSpinner.startAnimation(nil)
        webView.alphaValue = 0
        webView.isHidden = true
        loadingWatchdog?.invalidate()
        loadingWatchdog = Timer.scheduledTimer(withTimeInterval: Self.rendererLoadTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.didRevealWebView,
                      self.loadingGeneration == generation else { return }
                self.handleLoadingTimeout()
            }
        }
    }

    private func hideLoadingOverlay() {
        guard !didRevealWebView else { return }
        didRevealWebView = true
        loadingWatchdog?.invalidate()
        loadingWatchdog = nil
        loadingMessageLabel.isHidden = true
        loadingMessageLabel.stringValue = ""
        loadingSpinner.stopAnimation(nil)
        webView.alphaValue = 0
        webView.isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            webView.animator().alphaValue = 1
            loadingOverlay.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.loadingOverlay.isHidden = true
                self.loadingOverlay.alphaValue = 1
            }
        }
    }

    private func showLoadingFailure(_ message: String) {
        loadingSpinner.stopAnimation(nil)
        loadingMessageLabel.stringValue = message
        loadingMessageLabel.isHidden = false
    }

    private func handleLoadingTimeout() {
        showLoadingFailure(String(localized: .ThreadStrings.diffRendererTimedOut))
        logRendererFailure(
            "timeout",
            detail: "rendererReady=\(isRendererReady) pendingCalls=\(pendingJavaScriptCalls.count) webViewLoading=\(webView.isLoading) estimatedProgress=\(webView.estimatedProgress)"
        )
        captureRendererDiagnosticSnapshot()
    }

    private func captureRendererDiagnosticSnapshot() {
        let script = """
        (() => {
          const root = document.getElementById("root");
          const bodyText = document.body?.innerText ?? "";
          return {
            readyState: document.readyState,
            url: location.href,
            rendererType: typeof window.magentDiffRenderer,
            rootChildCount: root ? root.childElementCount : -1,
            rootTextLength: root ? root.innerText.length : -1,
            bodyTextLength: bodyText.length,
            bodyTextStart: bodyText.slice(0, 240),
            theme: document.documentElement.dataset.theme || ""
          };
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.logRendererFailure("timeout diagnostic probe failed", detail: error.localizedDescription)
                } else {
                    self.logRendererFailure("timeout diagnostic snapshot", detail: self.diagnosticDescription(result))
                }
            }
        }
    }

    private func logRendererFailure(_ reason: String, detail: String?) {
        NSLog(
            "[DiffRenderer] failure reason=%@ context=%@ detail=%@",
            reason,
            currentRenderDiagnosticSummary,
            detail ?? "nil"
        )
    }

    private func diagnosticDescription(_ value: Any?) -> String {
        guard let value else { return "nil" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private func configureDocumentStartThemeScript() {
        let bootstrap = rendererBootstrapTheme()
        let script = """
        (() => {
          const theme = \(jsonString(bootstrap.themeType));
          const background = \(jsonString(bootstrap.backgroundHex));
          document.documentElement.dataset.theme = theme;
          document.documentElement.style.background = background;
          document.documentElement.style.colorScheme = theme;
          const style = document.createElement("style");
          style.textContent = `html, body, #root { background: ${background} !important; }`;
          (document.head || document.documentElement).appendChild(style);
        })();
        """
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.addUserScript(WKUserScript(
            source: script,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
    }

    private func rendererBootstrapTheme() -> (themeType: String, backgroundHex: String) {
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var backgroundHex = isDark ? "#111315" : "#f6f7f8"
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            if let srgb = NSColor(resource: .appBackground)
                .usingColorSpace(.sRGB) {
                backgroundHex = String(
                    format: "#%02X%02X%02X",
                    Int(round(srgb.redComponent * 255)),
                    Int(round(srgb.greenComponent * 255)),
                    Int(round(srgb.blueComponent * 255))
                )
            }
        }
        return (isDark ? "dark" : "light", backgroundHex)
    }

    private func evaluateRendererCall(
        _ javaScript: String,
        completion: ((Any?, (any Error)?) -> Void)? = nil
    ) {
        guard isRendererReady else {
            pendingJavaScriptCalls.append(PendingDiffRendererCall(javaScript: javaScript, completion: completion))
            return
        }
        evaluateRendererJavaScript(javaScript, completion: completion)
    }

    private func flushPendingJavaScriptCalls() {
        let calls = pendingJavaScriptCalls
        pendingJavaScriptCalls.removeAll()
        for call in calls {
            evaluateRendererJavaScript(call.javaScript, completion: call.completion)
        }
    }

    private func evaluateRendererJavaScript(
        _ javaScript: String,
        completion: ((Any?, (any Error)?) -> Void)?
    ) {
        webView.evaluateJavaScript(javaScript) { result, error in
            guard let completion else { return }
            Task { @MainActor in
                completion(result, error)
            }
        }
    }

    private func jsonString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let string = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return string
    }

    private func jsonPayload(_ payload: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let commandModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.charactersIgnoringModifiers == "f", commandModifiers == [.command] {
            showFindBar()
            return true
        }
        if event.charactersIgnoringModifiers == "g", commandModifiers == [.command] {
            findNext()
            return true
        }
        if event.charactersIgnoringModifiers == "g", commandModifiers == [.command, .shift] {
            findPrevious()
            return true
        }
        if event.keyCode == 53, !findBar.isHidden {
            hideFindBar()
            return true
        }
        return false
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func toggleExpandCollapseAll() {
        if allExpanded {
            collapseAll()
        } else {
            expandAll()
        }
    }

    @objc private func checkAllReviewedFiles() {
        evaluateRendererCall("window.magentDiffRenderer?.setAllReviewed(true)")
    }

    @objc private func uncheckAllReviewedFiles() {
        evaluateRendererCall("window.magentDiffRenderer?.setAllReviewed(false)")
    }

    @objc private func collapseAllFilesFromMenu() {
        collapseAll()
    }

    @objc private func expandAllFilesFromMenu() {
        expandAll()
    }

    @objc private func showReviewMenu() {
        let menu = NSMenu()
        let checkAll = NSMenuItem(title: "Check all", action: #selector(checkAllReviewedFiles), keyEquivalent: "")
        checkAll.target = self
        let uncheckAll = NSMenuItem(title: "Uncheck all", action: #selector(uncheckAllReviewedFiles), keyEquivalent: "")
        uncheckAll.target = self
        menu.addItem(checkAll)
        menu.addItem(uncheckAll)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: reviewMenuButton.bounds.height + 4),
            in: reviewMenuButton
        )
    }

    @objc private func returnToCurrentChangesTapped() {
        onReturnToCurrentChanges?()
    }

    @objc private func showViewMenu() {
        let menu = NSMenu()
        let collapseAll = NSMenuItem(title: "Collapse all", action: #selector(collapseAllFilesFromMenu), keyEquivalent: "")
        collapseAll.target = self
        let expandAll = NSMenuItem(title: "Expand all", action: #selector(expandAllFilesFromMenu), keyEquivalent: "")
        expandAll.target = self
        menu.addItem(collapseAll)
        menu.addItem(expandAll)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: viewMenuButton.bounds.height + 4),
            in: viewMenuButton
        )
    }

    private func updateExpandCollapseButton() {
        if allExpanded {
            expandCollapseButton.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "Collapse All")
            expandCollapseButton.toolTip = "Collapse All"
        } else {
            expandCollapseButton.image = NSImage(systemSymbolName: "rectangle.expand.vertical", accessibilityDescription: "Expand All")
            expandCollapseButton.toolTip = "Expand All"
        }
    }

    @objc private func handleResizeDrag(_ gesture: NSPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        onResizeDrag?(gesture.state, translation.y)
        if gesture.state == .changed {
            gesture.setTranslation(.zero, in: view)
        }
    }

    // MARK: - Content

    func setDiffContent(
        _ rawDiff: String,
        fileCount: Int,
        worktreePath: String?,
        mergeBase: String?,
        reviewedFileSignatures: [String: String] = [:],
        collapsedFileStates: [String: Bool] = [:],
        allowsReviewMarkers: Bool = true,
        showsSpinner: Bool = true,
        allowsTrailingFileContext: Bool = true
    ) {
        currentWorktreePath = worktreePath
        currentRenderDiagnosticSummary = renderDiagnosticSummary(
            rawDiff: rawDiff,
            fileCount: fileCount,
            worktreePath: worktreePath,
            mergeBase: mergeBase,
            reviewedFileSignatures: reviewedFileSignatures,
            allowsReviewMarkers: allowsReviewMarkers
        )
        headerLabel.stringValue = "DIFF (\(fileCount) files)"
        expandCollapseButton.isEnabled = true
        expandCollapseButton.alphaValue = 1
        reviewMenuButton.isEnabled = allowsReviewMarkers
        reviewMenuButton.alphaValue = allowsReviewMarkers ? 1 : 0.5
        reviewMenuButton.isHidden = showsInlineChrome || !allowsReviewMarkers
        viewMenuButton.isEnabled = true
        viewMenuButton.alphaValue = 1
        viewMenuButton.isHidden = showsInlineChrome
        allExpanded = !collapsedFileStates.values.contains(true)
        updateExpandCollapseButton()
        if showsSpinner || !didRevealWebView {
            showLoadingOverlay()
        }

        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let payload = jsonPayload([
            "patch": rawDiff,
            "themeType": isDark ? "dark" : "light",
            "reviewedFileSignatures": reviewedFileSignatures,
            "collapsedFileStates": collapsedFileStates,
            "fileLineCounts": [:],
            "allowsReviewMarkers": allowsReviewMarkers,
        ])
        evaluateRendererCall("window.magentDiffRenderer?.setDiff(\(payload))") { [weak self] _, error in
            guard let self else { return }
            if let error {
                self.logRendererFailure("setDiff evaluation failed", detail: error.localizedDescription)
                self.setDiffUnavailableMessage("Diff renderer failed: \(error.localizedDescription)")
                return
            }
            // `setDiff` renders synchronously. The renderer normally posts a `rendered`
            // message that hides the spinner, but WKScriptMessage delivery can fail
            // independently of JavaScript evaluation. Do not leave the tab spinning
            // forever when the DOM has already been updated.
            if !self.didRevealWebView {
                self.hideLoadingOverlay()
            }
        }
        scheduleFileLineCountUpdate(
            rawDiff: rawDiff,
            worktreePath: worktreePath,
            enabled: allowsTrailingFileContext
        )
    }

    func setDiffContext(_ title: String?, showsCurrentChangesButton: Bool) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        commitReviewLabel.stringValue = trimmed
        currentChangesButton.isHidden = !showsCurrentChangesButton
        commitReviewLabelTrailingConstraint?.isActive = !showsCurrentChangesButton
        currentChangesButtonLeadingConstraint?.isActive = showsCurrentChangesButton
        currentChangesButtonTrailingConstraint?.isActive = showsCurrentChangesButton
        applySearchMode()
    }

    func setCommitReviewContext(_ title: String?) {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        setDiffContext(
            trimmed.isEmpty ? nil : String(localized: .ThreadStrings.diffCommitReviewViewingCommit(trimmed)),
            showsCurrentChangesButton: true
        )
    }

    func setDiffSummary(fileCount: Int, additions: Int, deletions: Int) {
        currentFileCountSummary = fileCount
        currentReviewedFileCountSummary = 0
        refreshSummaryFilesLabel()
        summaryAddedLabel.stringValue = "+\(additions)"
        summaryDeletedLabel.stringValue = "-\(deletions)"
    }

    private func refreshSummaryFilesLabel() {
        summaryFilesLabel.stringValue = "\(currentFileCountSummary) files changed (\(currentReviewedFileCountSummary) reviewed)"
    }

    func setDiffUnavailableMessage(_ message: String) {
        currentRenderDiagnosticSummary = "message=\(message)"
        headerLabel.stringValue = "DIFF"
        expandCollapseButton.isEnabled = false
        expandCollapseButton.alphaValue = 0.45
        reviewMenuButton.isEnabled = false
        reviewMenuButton.alphaValue = 0.45
        viewMenuButton.isEnabled = false
        viewMenuButton.alphaValue = 0.45
        allExpanded = true
        updateExpandCollapseButton()
        showLoadingOverlay()
        evaluateRendererCall("window.magentDiffRenderer?.setMessage(\(jsonString(message)))") { [weak self] _, _ in
            guard let self, !self.didRevealWebView else { return }
            self.hideLoadingOverlay()
        }
    }

    private func renderDiagnosticSummary(
        rawDiff: String,
        fileCount: Int,
        worktreePath: String?,
        mergeBase: String?,
        reviewedFileSignatures: [String: String],
        allowsReviewMarkers: Bool
    ) -> String {
        let lineCount = rawDiff.utf8.reduce(into: 0) { count, byte in
            if byte == 10 { count += 1 }
        } + (rawDiff.isEmpty ? 0 : 1)
        return [
            "files=\(fileCount)",
            "patchChars=\(rawDiff.count)",
            "patchBytes=\(rawDiff.utf8.count)",
            "patchLines=\(lineCount)",
            "reviewedSignatures=\(reviewedFileSignatures.count)",
            "allowsReviewMarkers=\(allowsReviewMarkers)",
            "mergeBase=\(mergeBase ?? "nil")",
            "worktree=\(worktreePath ?? "nil")",
        ].joined(separator: " ")
    }

    func expandFile(_ relativePath: String, collapseOthers: Bool) {
        if collapseOthers, !allExpanded {
            expandAll()
        }
        scrollToFile(relativePath)
    }

    func expandAll() {
        allExpanded = true
        updateExpandCollapseButton()
        evaluateRendererCall("window.magentDiffRenderer?.setCollapsed(false)")
    }

    func collapseAll() {
        allExpanded = false
        updateExpandCollapseButton()
        evaluateRendererCall("window.magentDiffRenderer?.setCollapsed(true)")
    }

    func scrollToFile(_ relativePath: String) {
        evaluateRendererCall("window.magentDiffRenderer?.scrollToFile(\(jsonString(relativePath)))")
    }

    @objc private func showFindBar() {
        findBar.isHidden = false
        applySearchMode()
        view.window?.makeFirstResponder(findField)
        if !findField.stringValue.isEmpty {
            scheduleSearchUpdate()
        }
    }

    @objc private func hideFindBar() {
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = nil
        findBar.isHidden = true
        findStatusLabel.stringValue = ""
        findField.stringValue = ""
        evaluateRendererCall("window.magentDiffRenderer?.clearSearch()")
        applySearchMode()
        view.window?.makeFirstResponder(webView)
    }

    @objc private func findNext() {
        guard !findField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFindBar()
            return
        }
        evaluateRendererCall("window.magentDiffRenderer?.findNext()")
    }

    @objc private func findPrevious() {
        guard !findField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showFindBar()
            return
        }
        evaluateRendererCall("window.magentDiffRenderer?.findPrevious()")
    }

    @objc private func searchModeChanged() {
        guard let raw = findModeButton.selectedItem?.representedObject as? String,
              let mode = DiffSearchMode(rawValue: raw) else { return }
        searchMode = mode
        DiffSearchMode.persisted = mode
        findModeButton.toolTip = mode.tooltip
        updateSearch()
    }

    private func scheduleSearchUpdate() {
        searchDebounceTimer?.invalidate()
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSearch()
            }
        }
    }

    private func updateSearch() {
        let query = findField.stringValue
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            findStatusLabel.stringValue = ""
            evaluateRendererCall("window.magentDiffRenderer?.clearSearch()")
            return
        }
        let payload = jsonPayload([
            "query": query,
            "mode": searchMode.rawValue,
        ])
        evaluateRendererCall("window.magentDiffRenderer?.setSearch(\(payload))")
    }

    private func updateSearchStatus(current: Int, total: Int) {
        if total == 0 {
            findStatusLabel.stringValue = findField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? ""
                : "No matches"
            findPreviousButton.isEnabled = false
            findNextButton.isEnabled = false
        } else {
            findStatusLabel.stringValue = "\(current)/\(total)"
            findPreviousButton.isEnabled = true
            findNextButton.isEnabled = true
        }
    }

    private func applySearchMode() {
        let isSearching = !findBar.isHidden
        expandCollapseButton.isHidden = isSearching || !showsInlineChrome
        closeButton.isHidden = isSearching || !showsInlineChrome
        summaryAddedLabel.isHidden = isSearching || showsInlineChrome
        summaryDeletedLabel.isHidden = isSearching || showsInlineChrome
        reviewMenuButton.isHidden = isSearching || showsInlineChrome
        viewMenuButton.isHidden = isSearching || showsInlineChrome
        commitReviewBannerView.isHidden = isSearching || showsInlineChrome || commitReviewLabel.stringValue.isEmpty
    }

    // MARK: - WKNavigationDelegate / WKScriptMessageHandler

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyAppearance()
            self.flushRendererCallsIfReady()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.setDiffUnavailableMessage(message)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.setDiffUnavailableMessage(message)
        }
    }

    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            guard message.name == "diffRenderer",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }

            let errorMessage = body["message"] as? String
            let filePath = body["filePath"] as? String

            if type == "ready" {
                self.markRendererReady()
            } else if type == "rendered" {
                let fileCount = body["fileCount"] as? Int ?? self.currentFileCountSummary
                let reviewedCount = body["reviewedCount"] as? Int ?? self.currentReviewedFileCountSummary
                self.currentFileCountSummary = max(0, fileCount)
                self.currentReviewedFileCountSummary = max(0, reviewedCount)
                self.refreshSummaryFilesLabel()
                self.onReviewProgressChanged?(
                    self.currentReviewedFileCountSummary,
                    self.currentFileCountSummary
                )
                self.hideLoadingOverlay()
            } else if type == "hunkToggle" {
                let hunkId = body["hunkId"] as? String ?? "unknown"
                let changed = body["changed"] as? Int ?? -1
                let ignored = body["ignored"] as? Bool ?? false
                let collapsed = body["collapsed"] as? Bool ?? false
                let source = body["source"] as? String ?? "unknown"
                let detail = body["detail"] as? Int ?? -1
                NSLog(
                    "[DiffRenderer] hunk toggle id=%@ changedRows=%d ignored=%@ collapsed=%@ source=%@ detail=%d",
                    hunkId,
                    changed,
                    ignored.description,
                    collapsed.description,
                    source,
                    detail
                )
            } else if type == "requestHunkContext" {
                let hunkId = body["hunkId"] as? String ?? ""
                let filePath = body["filePath"] as? String ?? ""
                let startLine = body["startLine"] as? Int ?? 1
                let endLine = body["endLine"] as? Int ?? startLine
                self.respondWithHunkContext(
                    hunkId: hunkId,
                    filePath: filePath,
                    startLine: startLine,
                    endLine: endLine
                )
            } else if type == "error", let errorMessage {
                let source = body["source"] as? String ?? "renderer"
                let stack = body["stack"] as? String
                let rendererFileCount = body["fileCount"] as? Int
                let patchLength = body["patchLength"] as? Int
                self.logRendererFailure(
                    source,
                    detail: [
                        "message=\(errorMessage)",
                        stack.map { "stack=\($0)" },
                        rendererFileCount.map { "rendererFileCount=\($0)" },
                        patchLength.map { "patchLength=\($0)" },
                    ].compactMap { $0 }.joined(separator: " ")
                )
            } else if type == "reviewedStateChanged" {
                let reviewed = body["reviewedFileSignatures"] as? [String: String] ?? [:]
                let fileCount = body["fileCount"] as? Int ?? self.currentFileCountSummary
                let reviewedCount = body["reviewedCount"] as? Int ?? reviewed.count
                self.currentFileCountSummary = max(0, fileCount)
                self.currentReviewedFileCountSummary = max(0, reviewedCount)
                self.refreshSummaryFilesLabel()
                self.onReviewProgressChanged?(
                    self.currentReviewedFileCountSummary,
                    self.currentFileCountSummary
                )
                self.onReviewedFilesChanged?(reviewed)
            } else if type == "collapsedStateChanged" {
                let states = body["collapsedFileStates"] as? [String: Bool] ?? [:]
                self.onCollapsedFilesChanged?(states)
            } else if type == "fileActionsMenuRequested", let filePath {
                let x = body["anchorX"] as? Double ?? 0
                let y = body["anchorY"] as? Double ?? 0
                let webViewPoint = NSPoint(
                    x: min(max(0, x), self.webView.bounds.width),
                    y: min(max(0, y), self.webView.bounds.height)
                )
                let viewPoint = self.view.convert(webViewPoint, from: self.webView)
                self.onFileActionsMenuRequested?(filePath, viewPoint)
            } else if type == "textContextMenuRequested" {
                let selectedText = body["selectedText"] as? String ?? ""
                let fallbackText = body["fallbackText"] as? String ?? ""
                let lineFilePath = body["lineFilePath"] as? String
                let lineNumber = body["lineNumber"] as? Int
                let x = body["anchorX"] as? Double ?? 0
                let y = body["anchorY"] as? Double ?? 0
                let webViewPoint = NSPoint(
                    x: min(max(0, x), self.webView.bounds.width),
                    y: min(max(0, y), self.webView.bounds.height)
                )
                let viewPoint = self.view.convert(webViewPoint, from: self.webView)
                self.onTextContextMenuRequested?(selectedText, fallbackText, lineFilePath, lineNumber, viewPoint)
            } else if type == "searchStateChanged" {
                let current = body["current"] as? Int ?? 0
                let total = body["total"] as? Int ?? 0
                self.updateSearchStatus(current: current, total: total)
            } else if type == "scrolledToFile", let filePath {
                NotificationCenter.default.post(
                    name: .magentDiffViewerScrolledToFile,
                    object: nil,
                    userInfo: ["filePath": filePath]
                )
            }
        }
    }

    private func flushRendererCallsIfReady() {
        guard !isRendererReady else { return }
        webView.evaluateJavaScript("typeof window.magentDiffRenderer !== 'undefined'") { [weak self] result, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      !self.isRendererReady,
                      (result as? Bool) == true else { return }
                self.markRendererReady()
            }
        }
    }

    private func startRendererReadinessPolling() {
        rendererReadinessTask?.cancel()
        rendererReadinessTask = Task { @MainActor [weak self] in
            for _ in 0..<48 {
                guard let self, !Task.isCancelled else { return }
                if self.isRendererReady { return }
                self.flushRendererCallsIfReady()
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    private func markRendererReady() {
        guard !isRendererReady else { return }
        isRendererReady = true
        rendererReadinessTask?.cancel()
        rendererReadinessTask = nil
        applyAppearance()
        flushPendingJavaScriptCalls()
    }

    private func respondWithHunkContext(hunkId: String, filePath: String, startLine: Int, endLine: Int) {
        guard !hunkId.isEmpty,
              let worktreePath = currentWorktreePath,
              !filePath.isEmpty else { return }

        let url = URL(fileURLWithPath: worktreePath).appendingPathComponent(filePath)
        let lines: [String]
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            lines = content.components(separatedBy: .newlines)
        } catch {
            let payload = jsonPayload([
                "hunkId": hunkId,
                "startLine": max(1, startLine),
                "lines": []
            ])
            evaluateRendererCall("window.magentDiffRenderer?.showHunkContext(\(payload))")
            return
        }

        let start = max(1, startLine)
        let end = min(lines.count, max(start, endLine))
        var context: [String] = []
        if start <= end {
            for index in start...end {
                context.append(lines[index - 1])
            }
        }

        let payload = jsonPayload([
            "hunkId": hunkId,
            "startLine": start,
            "lines": context
        ])
        evaluateRendererCall("window.magentDiffRenderer?.showHunkContext(\(payload))")
    }

    private func scheduleFileLineCountUpdate(rawDiff: String, worktreePath: String?, enabled: Bool) {
        fileLineCountsTask?.cancel()
        fileLineCountsGeneration += 1
        let generation = fileLineCountsGeneration
        guard enabled else { return }

        fileLineCountsTask = Task.detached(priority: .utility) { [rawDiff, worktreePath] in
            let counts = Self.fileLineCounts(rawDiff: rawDiff, worktreePath: worktreePath)
            guard !Task.isCancelled, !counts.isEmpty else { return }
            await MainActor.run { [weak self] in
                guard let self,
                      self.fileLineCountsGeneration == generation else { return }
                let payload = jsonPayload(counts)
                self.evaluateRendererCall("window.magentDiffRenderer?.setFileLineCounts(\(payload))")
            }
        }
    }

    nonisolated private static func fileLineCounts(rawDiff: String, worktreePath: String?) -> [String: Int] {
        guard let worktreePath else { return [:] }

        let rootURL = URL(fileURLWithPath: worktreePath)
        var counts: [String: Int] = [:]
        for line in rawDiff.components(separatedBy: .newlines) where line.hasPrefix("+++ ") {
            let path = normalizedDiffPath(String(line.dropFirst(4)))
            guard !path.isEmpty,
                  path != "/dev/null",
                  counts[path] == nil else { continue }

            let url = rootURL.appendingPathComponent(path)
            guard let lineCount = Self.lineCountIfReasonable(url: url) else { continue }
            counts[path] = lineCount
        }
        return counts
    }

    nonisolated private static func lineCountIfReasonable(url: URL) -> Int? {
        guard let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              resourceValues.isRegularFile == true,
              let byteCount = resourceValues.fileSize,
              byteCount <= Self.maxLineCountedFileBytes else {
            return nil
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var newlineCount = 0
        var lastByte: UInt8?
        while true {
            let data = handle.readData(ofLength: Self.lineCountChunkSize)
            if data.isEmpty { break }
            for byte in data {
                if byte == 10 { newlineCount += 1 }
                lastByte = byte
            }
        }

        guard let lastByte else { return 0 }
        return newlineCount + (lastByte == 10 ? 0 : 1)
    }

    nonisolated private static func normalizedDiffPath(_ rawPath: String) -> String {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("\""), path.hasSuffix("\""), path.count >= 2 {
            path.removeFirst()
            path.removeLast()
        }
        if path.hasPrefix("a/") || path.hasPrefix("b/") {
            path.removeFirst(2)
        }
        return path
    }
}

extension InlineDiffViewController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSSearchField === findField else { return }
        scheduleSearchUpdate()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === findField else { return false }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            let goForward = NSApp.currentEvent?.modifierFlags.contains(.shift) != true
            goForward ? findNext() : findPrevious()
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideFindBar()
            return true
        }
        return false
    }
}
