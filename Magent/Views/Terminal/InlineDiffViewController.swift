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
    private let webView: WKWebView

    private var isRendererReady = false
    private var pendingJavaScriptCalls: [String] = []
    private var allExpanded = true

    var onClose: (() -> Void)?
    var onImageClick: ((_ imageView: NSImageView, _ image: NSImage) -> Void)?
    /// Called during drag with the delta (positive = drag up = diff taller).
    var onResizeDrag: ((_ phase: NSPanGestureRecognizer.State, _ deltaY: CGFloat) -> Void)?

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

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.alphaValue = 0

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
            resizeHandle.heightAnchor.constraint(equalToConstant: 6),

            separatorLine.centerYAnchor.constraint(equalTo: resizeHandle.centerYAnchor),
            separatorLine.leadingAnchor.constraint(equalTo: resizeHandle.leadingAnchor, constant: 8),
            separatorLine.trailingAnchor.constraint(equalTo: resizeHandle.trailingAnchor, constant: -8),
            separatorLine.heightAnchor.constraint(equalToConstant: 1),

            headerBar.topAnchor.constraint(equalTo: resizeHandle.bottomAnchor),
            headerBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerBar.heightAnchor.constraint(equalToConstant: 24),

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

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    private func applyAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            let background = NSColor(resource: .appBackground).cgColor
            view.layer?.backgroundColor = background
            loadingOverlay.layer?.backgroundColor = background
        }
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        evaluateRendererCall("window.magentDiffRenderer?.setTheme(\(jsonString(isDark ? "dark" : "light")))")
    }

    private func showLoadingOverlay() {
        loadingOverlay.isHidden = false
        loadingSpinner.startAnimation(nil)
        webView.alphaValue = 0
    }

    private func hideLoadingOverlay() {
        loadingSpinner.stopAnimation(nil)
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

    func setDiffContent(_ rawDiff: String, fileCount: Int, worktreePath: String?, mergeBase: String?) {
        headerLabel.stringValue = "DIFF (\(fileCount) files)"
        expandCollapseButton.isEnabled = true
        expandCollapseButton.alphaValue = 1
        allExpanded = true
        updateExpandCollapseButton()
        showLoadingOverlay()

        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let payload = jsonPayload([
            "patch": rawDiff,
            "themeType": isDark ? "dark" : "light",
        ])
        evaluateRendererCall("window.magentDiffRenderer?.setDiff(\(payload))")
    }

    func setDiffUnavailableMessage(_ message: String) {
        headerLabel.stringValue = "DIFF"
        expandCollapseButton.isEnabled = false
        expandCollapseButton.alphaValue = 0.45
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
                self.hideLoadingOverlay()
            } else if type == "error", let errorMessage {
                NSLog("[DiffRenderer] %@", errorMessage)
            } else if type == "scrolledToFile", let filePath {
                NotificationCenter.default.post(
                    name: .magentDiffViewerScrolledToFile,
                    object: nil,
                    userInfo: ["filePath": filePath]
                )
            }
        }
    }
}
