import Cocoa
import WebKit

private final class DiffDividerResizeHandle: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}

private final class DiffHostView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
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

final class InlineDiffViewController: NSViewController, WKNavigationDelegate, WKScriptMessageHandler {
    private let closeButton = NSButton()
    private let expandCollapseButton = NSButton()
    private let headerLabel = NSTextField(labelWithString: "")
    private let resizeHandle = DiffDividerResizeHandle()
    private let loadingOverlay = NSView()
    private let loadingSpinner = NSProgressIndicator()
    private let summaryFilesLabel = NSTextField(labelWithString: "")
    private let summaryAddedLabel = NSTextField(labelWithString: "")
    private let summaryDeletedLabel = NSTextField(labelWithString: "")
    private let reviewMenuButton = NSButton(title: "Review ▾", target: nil, action: nil)
    private let viewMenuButton = NSButton(title: "Files ▾", target: nil, action: nil)
    private let webView: WKWebView
    private var headerBar: NSView?
    private var resizeHandleHeightConstraint: NSLayoutConstraint?
    private var headerBarHeightConstraint: NSLayoutConstraint?
    private var showsInlineChrome = true

    private var isRendererReady = false
    private var pendingJavaScriptCalls: [String] = []
    private var allExpanded = true
    private var didRevealWebView = false
    private var currentWorktreePath: String?
    private var currentFileCountSummary: Int = 0
    private var currentReviewedFileCountSummary: Int = 0

    var onClose: (() -> Void)?
    var onImageClick: ((_ imageView: NSImageView, _ image: NSImage) -> Void)?
    /// Called during drag with the delta (positive = drag up = diff taller).
    var onResizeDrag: ((_ phase: NSPanGestureRecognizer.State, _ deltaY: CGFloat) -> Void)?
    var onReviewedFilesChanged: (([String: String]) -> Void)?

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
        loadingOverlay.addSubview(loadingSpinner)

        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleResizeDrag(_:)))
        resizeHandle.addGestureRecognizer(panGesture)

        view.addSubview(resizeHandle)
        view.addSubview(headerBar)
        view.addSubview(webView)
        view.addSubview(loadingOverlay)

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

            webView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            loadingOverlay.topAnchor.constraint(equalTo: webView.topAnchor),
            loadingOverlay.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            loadingOverlay.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            loadingOverlay.bottomAnchor.constraint(equalTo: webView.bottomAnchor),

            loadingSpinner.centerXAnchor.constraint(equalTo: loadingOverlay.centerXAnchor),
            loadingSpinner.centerYAnchor.constraint(equalTo: loadingOverlay.centerYAnchor),
        ])
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
        resizeHandleHeightConstraint?.constant = showsInlineChrome ? 6 : 0
        headerBarHeightConstraint?.constant = 40
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
        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    private func applyAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let backgroundColor = NSColor(resource: .appBackground)
            let background = backgroundColor.cgColor
            view.layer?.backgroundColor = background
            webView.layer?.backgroundColor = background
            loadingOverlay.layer?.backgroundColor = background
            if #available(macOS 12.0, *) {
                webView.underPageBackgroundColor = backgroundColor
            }
        }
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        evaluateRendererCall("window.magentDiffRenderer?.setTheme(\(jsonString(isDark ? "dark" : "light")))")
    }

    private func showLoadingOverlay() {
        didRevealWebView = false
        loadingOverlay.isHidden = false
        loadingOverlay.alphaValue = 1
        loadingSpinner.startAnimation(nil)
        webView.alphaValue = 0
        webView.isHidden = true
    }

    private func hideLoadingOverlay() {
        guard !didRevealWebView else { return }
        didRevealWebView = true
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

    private func evaluateRendererCall(_ javaScript: String) {
        guard isRendererReady else {
            pendingJavaScriptCalls.append(javaScript)
            return
        }
        webView.evaluateJavaScript(javaScript)
    }

    private func flushPendingJavaScriptCalls() {
        let calls = pendingJavaScriptCalls
        pendingJavaScriptCalls.removeAll()
        for call in calls {
            webView.evaluateJavaScript(call)
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
        allowsReviewMarkers: Bool = true,
        showsSpinner: Bool = true
    ) {
        currentWorktreePath = worktreePath
        headerLabel.stringValue = "DIFF (\(fileCount) files)"
        expandCollapseButton.isEnabled = true
        expandCollapseButton.alphaValue = 1
        reviewMenuButton.isEnabled = allowsReviewMarkers
        reviewMenuButton.alphaValue = allowsReviewMarkers ? 1 : 0.5
        viewMenuButton.isEnabled = true
        viewMenuButton.alphaValue = 1
        allExpanded = true
        updateExpandCollapseButton()
        if showsSpinner || !didRevealWebView {
            showLoadingOverlay()
        }

        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let payload = jsonPayload([
            "patch": rawDiff,
            "themeType": isDark ? "dark" : "light",
            "reviewedFileSignatures": reviewedFileSignatures,
            "allowsReviewMarkers": allowsReviewMarkers,
        ])
        evaluateRendererCall("window.magentDiffRenderer?.setDiff(\(payload))")
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
        evaluateRendererCall("window.magentDiffRenderer?.setMessage(\(jsonString(message)))")
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

    // MARK: - WKNavigationDelegate / WKScriptMessageHandler

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.applyAppearance()
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
                self.isRendererReady = true
                self.applyAppearance()
                self.flushPendingJavaScriptCalls()
            } else if type == "rendered" {
                let fileCount = body["fileCount"] as? Int ?? self.currentFileCountSummary
                let reviewedCount = body["reviewedCount"] as? Int ?? self.currentReviewedFileCountSummary
                self.currentFileCountSummary = max(0, fileCount)
                self.currentReviewedFileCountSummary = max(0, reviewedCount)
                self.refreshSummaryFilesLabel()
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
                NSLog("[DiffRenderer] %@", errorMessage)
            } else if type == "reviewedStateChanged" {
                let reviewed = body["reviewedFileSignatures"] as? [String: String] ?? [:]
                let fileCount = body["fileCount"] as? Int ?? self.currentFileCountSummary
                let reviewedCount = body["reviewedCount"] as? Int ?? reviewed.count
                self.currentFileCountSummary = max(0, fileCount)
                self.currentReviewedFileCountSummary = max(0, reviewedCount)
                self.refreshSummaryFilesLabel()
                self.onReviewedFilesChanged?(reviewed)
            } else if type == "scrolledToFile", let filePath {
                NotificationCenter.default.post(
                    name: .magentDiffViewerScrolledToFile,
                    object: nil,
                    userInfo: ["filePath": filePath]
                )
            }
        }
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
}
