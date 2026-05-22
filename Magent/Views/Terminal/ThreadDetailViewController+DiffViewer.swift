import Cocoa
import MagentCore

private func diffLineCount(_ diffContent: String) -> Int {
    guard !diffContent.isEmpty else { return 0 }
    return diffContent.utf8.reduce(into: 1) { count, byte in
        if byte == 10 {
            count += 1
        }
    }
}

private func diffTooLargeMessage(fileCount: Int, lineCount: Int) -> String? {
    if fileCount > ThreadDetailViewController.diffMaxFileCount {
        return "Diff is too large (\(fileCount) files)."
    }
    if lineCount > ThreadDetailViewController.diffMaxLineCount {
        return "Diff is too large (\(lineCount) lines)."
    }
    return nil
}

private final class DiffFileActionMenuTarget: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction() {
        action()
    }
}

final class DiffImageOverlayView: NSView {
    private let dimView = NSView()
    private let imageCardView = NSView()
    private let imageView = NSImageView()
    private let sourceRectProvider: () -> NSRect?
    private let initialSourceRect: NSRect
    private let image: NSImage
    private var isPresented = false
    private var isDismissing = false

    var onDismiss: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(image: NSImage, sourceRect: NSRect, sourceRectProvider: @escaping () -> NSRect?) {
        self.image = image
        self.initialSourceRect = sourceRect
        self.sourceRectProvider = sourceRectProvider
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.zPosition = 500
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        dimView.frame = bounds
        if isPresented, !isDismissing {
            imageCardView.frame = targetFrame(for: bounds)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            dismiss(animated: true)
            return
        }
        super.keyDown(with: event)
    }

    func present() {
        layoutSubtreeIfNeeded()
        imageCardView.frame = initialSourceRect
        dimView.alphaValue = 0
        alphaValue = 1
        window?.makeFirstResponder(self)

        let targetFrame = targetFrame(for: bounds)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dimView.animator().alphaValue = 1
            imageCardView.animator().frame = targetFrame
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                self?.isPresented = true
            }
        }
    }

    func dismiss(animated: Bool) {
        guard !isDismissing else { return }
        isDismissing = true

        guard animated else {
            finishDismissal()
            return
        }

        let targetRect = sourceRectProvider() ?? initialSourceRect
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dimView.animator().alphaValue = 0
            imageCardView.animator().frame = targetRect
        } completionHandler: {
            Task { @MainActor [weak self] in
                self?.finishDismissal()
            }
        }
    }

    private func setup() {
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleOverlayClick))
        addGestureRecognizer(click)

        dimView.wantsLayer = true
        dimView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        dimView.alphaValue = 0
        dimView.autoresizingMask = [.width, .height]
        addSubview(dimView)

        imageCardView.wantsLayer = true
        imageCardView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.35).cgColor
        imageCardView.layer?.shadowOpacity = 1
        imageCardView.layer?.shadowRadius = 30
        imageCardView.layer?.shadowOffset = CGSize(width: 0, height: -8)
        addSubview(imageCardView)

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.frame = imageCardView.bounds
        imageView.autoresizingMask = [.width, .height]
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageCardView.addSubview(imageView)
    }

    @objc private func handleOverlayClick() {
        dismiss(animated: true)
    }

    @MainActor
    private func finishDismissal() {
        removeFromSuperview()
        onDismiss?()
    }

    private func targetFrame(for bounds: NSRect) -> NSRect {
        let horizontalInset = min(max(bounds.width * 0.08, 32), 96)
        let verticalInset = min(max(bounds.height * 0.1, 32), 120)
        let availableRect = bounds.insetBy(dx: horizontalInset, dy: verticalInset)
        guard availableRect.width > 0, availableRect.height > 0 else { return initialSourceRect }

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return availableRect }

        let scale = min(
            availableRect.width / imageSize.width,
            availableRect.height / imageSize.height,
            1
        )
        let renderedSize = NSSize(
            width: max(imageSize.width * scale, 120),
            height: max(imageSize.height * scale, 120)
        )
        return NSRect(
            x: availableRect.midX - renderedSize.width / 2,
            y: availableRect.midY - renderedSize.height / 2,
            width: min(renderedSize.width, availableRect.width),
            height: min(renderedSize.height, availableRect.height)
        ).integral
    }
}

extension ThreadDetailViewController {

    // MARK: - Inline Diff Viewer

    func updateDiffTabTitle(fileCount: Int, reviewedCount: Int? = nil) {
        guard let diffIndex = tabSlots.firstIndex(of: .diff), diffIndex < tabItems.count else { return }
        guard fileCount > 0 else {
            tabItems[diffIndex].titleLabel.stringValue = "Diff"
            return
        }

        if let reviewedCount {
            let reviewedCount = min(max(0, reviewedCount), fileCount)
            let isFullyReviewed = reviewedCount >= fileCount
            let suffix = isFullyReviewed ? " ✅" : ""
            tabItems[diffIndex].titleLabel.stringValue = "Diff (\(reviewedCount)/\(fileCount))\(suffix)"
        } else {
            tabItems[diffIndex].titleLabel.stringValue = "Diff (\(fileCount))"
        }
    }

    func clearCurrentDiffReviewStateIfNeeded() {
        guard !thread.diffReviewedFileSignatures.isEmpty || !thread.diffCollapsedFileStates.isEmpty else { return }
        threadManager.updateDiffReviewedFileSignatures(for: thread.id, signatures: [:])
        threadManager.updateDiffCollapsedFileStates(for: thread.id, states: [:])
        thread.diffReviewedFileSignatures = [:]
        thread.diffCollapsedFileStates = [:]
    }

    func showDiffFileActionsMenu(filePath: String, at point: NSPoint, in diffViewController: InlineDiffViewController) {
        let fileURL = URL(fileURLWithPath: thread.worktreePath, isDirectory: true)
            .appendingPathComponent(filePath)
            .standardizedFileURL

        let menu = NSMenu()
        let finderTarget = DiffFileActionMenuTarget { [weak self] in
            self?.showDiffFileInFinder(fileURL: fileURL, relativePath: filePath)
        }
        let finderItem = NSMenuItem(title: "Open in Finder", action: #selector(DiffFileActionMenuTarget.performAction), keyEquivalent: "")
        finderItem.target = finderTarget
        finderItem.representedObject = finderTarget
        finderItem.image = OpenActionIcons.finderIcon(size: 16)
        menu.addItem(finderItem)

        let openTarget = DiffFileActionMenuTarget { [weak self] in
            self?.openDiffFile(fileURL: fileURL, relativePath: filePath)
        }
        let (openTitle, openIcon) = defaultOpenMenuPresentation(for: fileURL)
        let openItem = NSMenuItem(title: openTitle, action: #selector(DiffFileActionMenuTarget.performAction), keyEquivalent: "")
        openItem.target = openTarget
        openItem.representedObject = openTarget
        openItem.image = openIcon
        menu.addItem(openItem)

        menu.popUp(positioning: nil, at: point, in: diffViewController.view)
    }

    func showDiffTextContextMenu(
        selectedText: String,
        fallbackText: String,
        lineFilePath: String?,
        lineNumber: Int?,
        at point: NSPoint,
        in diffViewController: InlineDiffViewController
    ) {
        let textToCopy = selectedText.isEmpty ? fallbackText : selectedText
        guard !textToCopy.isEmpty else { return }
        let menu = NSMenu()

        let copyTarget = DiffFileActionMenuTarget {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(textToCopy, forType: .string)
        }
        let copyItem = NSMenuItem(title: "Copy", action: #selector(DiffFileActionMenuTarget.performAction), keyEquivalent: "")
        copyItem.target = copyTarget
        copyItem.representedObject = copyTarget
        copyItem.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: "Copy")
        menu.addItem(copyItem)

        if let lineFilePath,
           !lineFilePath.isEmpty,
           let lineNumber,
           lineNumber > 0 {
            let fileURL = URL(fileURLWithPath: thread.worktreePath, isDirectory: true)
                .appendingPathComponent(lineFilePath)
                .standardizedFileURL
            if FileManager.default.fileExists(atPath: fileURL.path) {
                menu.addItem(.separator())
                let (openTitle, openIcon) = defaultOpenMenuPresentation(for: fileURL)
                let supportsLineOpening = lineOpenCommand(for: fileURL, line: lineNumber) != nil
                let menuTitle = supportsLineOpening ? "\(openTitle) on line \(lineNumber)" : openTitle
                let openLineTarget = DiffFileActionMenuTarget { [weak self] in
                    self?.openDiffFileAtLineIfSupported(fileURL, line: lineNumber)
                }
                let openLineItem = NSMenuItem(
                    title: menuTitle,
                    action: #selector(DiffFileActionMenuTarget.performAction),
                    keyEquivalent: ""
                )
                openLineItem.target = openLineTarget
                openLineItem.representedObject = openLineTarget
                openLineItem.image = openIcon
                menu.addItem(openLineItem)
            }
        }

        menu.popUp(positioning: nil, at: point, in: diffViewController.view)
    }

    private func openDiffFileAtLineIfSupported(_ fileURL: URL, line: Int) {
        guard line > 0,
              let command = lineOpenCommand(for: fileURL, line: line) else {
            NSWorkspace.shared.open(fileURL)
            return
        }

        let process = Process()
        process.executableURL = command.executableURL
        process.arguments = command.arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                NSWorkspace.shared.open(fileURL)
            }
        } catch {
            NSWorkspace.shared.open(fileURL)
        }
    }

    private struct LineOpenCommand {
        let executableURL: URL
        let arguments: [String]
    }

    private func lineOpenCommand(for fileURL: URL, line: Int) -> LineOpenCommand? {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: fileURL),
              let bundle = Bundle(url: appURL) else { return nil }
        let bundleIdentifier = bundle.bundleIdentifier ?? ""
        let executableName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String

        if bundleIdentifier == "com.apple.dt.Xcode" {
            return LineOpenCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: ["xed", "--line", String(line), fileURL.path]
            )
        }

        if bundleIdentifier == "com.microsoft.VSCode" || bundleIdentifier == "com.microsoft.VSCodeInsiders" {
            let commandName = bundleIdentifier == "com.microsoft.VSCodeInsiders" ? "code-insiders" : "code"
            if let executableURL = bundledVSCodeCLI(appURL: appURL, commandName: commandName)
                ?? shellExecutableURL(named: commandName) {
                return LineOpenCommand(
                    executableURL: executableURL,
                    arguments: ["-g", "\(fileURL.path):\(line)"]
                )
            }
        }

        if bundleIdentifier.hasPrefix("com.sublimetext.") {
            if let executableURL = shellExecutableURL(named: "subl") {
                return LineOpenCommand(
                    executableURL: executableURL,
                    arguments: ["\(fileURL.path):\(line)"]
                )
            }
        }

        if bundleIdentifier.hasPrefix("dev.zed.") || bundleIdentifier == "dev.zed.Zed" {
            if let executableURL = shellExecutableURL(named: "zed") ?? shellExecutableURL(named: "zeditor") {
                return LineOpenCommand(
                    executableURL: executableURL,
                    arguments: ["\(fileURL.path):\(line)"]
                )
            }
        }

        if bundleIdentifier.hasPrefix("com.jetbrains.") || bundleIdentifier == "com.google.android.studio" {
            if let executableURL = jetBrainsExecutableURL(appURL: appURL, executableName: executableName) {
                return LineOpenCommand(
                    executableURL: executableURL,
                    arguments: ["--line", String(line), fileURL.path]
                )
            }
        }

        return nil
    }

    private func bundledVSCodeCLI(appURL: URL, commandName: String) -> URL? {
        let candidate = appURL
            .appendingPathComponent("Contents/Resources/app/bin", isDirectory: true)
            .appendingPathComponent(commandName)
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private func jetBrainsExecutableURL(appURL: URL, executableName: String?) -> URL? {
        guard let executableName else { return nil }
        let candidate = appURL
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(executableName)
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate : nil
    }

    private func shellExecutableURL(named name: String) -> URL? {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
        ]
            .map { URL(fileURLWithPath: $0, isDirectory: true).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private func defaultOpenMenuPresentation(for fileURL: URL) -> (String, NSImage?) {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: fileURL) else {
            return (
                "Open File",
                NSImage(systemSymbolName: "doc", accessibilityDescription: "Open File")
            )
        }

        let appName = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        icon.isTemplate = false
        return ("Open with \(appName)", icon)
    }

    private func openDiffFile(fileURL: URL, relativePath: String) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            BannerManager.shared.show(
                message: "Could not open \(relativePath) because the file is missing.",
                style: .warning
            )
            return
        }
        NSWorkspace.shared.open(fileURL)
    }

    private func showDiffFileInFinder(fileURL: URL, relativePath: String) {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            BannerManager.shared.show(
                message: "Could not open \(relativePath) in Finder because the file is missing.",
                style: .warning
            )
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    func setDiffViewerVisible(_ visible: Bool) {
        guard let vc = diffVC else { return }
        vc.view.isHidden = !visible
    }

    func notifyDiffTabDidActivate() {
        NotificationCenter.default.post(
            name: .magentDiffTabDidActivate,
            object: nil,
            userInfo: ["threadId": thread.id]
        )
    }

    func notifyDiffTabDidDeactivate() {
        NotificationCenter.default.post(
            name: .magentDiffTabDidDeactivate,
            object: nil,
            userInfo: ["threadId": thread.id]
        )
    }

    func selectDiffTab(displayIndex: Int) {
        notifyDiffTabDidActivate()
        for (i, item) in tabItems.enumerated() {
            item.isSelected = (i == displayIndex)
            if case .diff = tabSlots[i] {
                item.hasUnreadDiff = isDiffUnread()
            }
        }

        for tv in terminalViews where tv.superview != nil {
            tv.isHidden = true
        }
        hideActiveWebTab()
        hideActiveDraftTab()
        hideActiveChatTab()
        hideEmptyState()

        currentTabIndex = displayIndex
        threadManager.markDiffSeen(for: thread.id)
        if let latest = threadManager.threads.first(where: { $0.id == thread.id }) {
            thread = latest
        }
        if displayIndex < tabItems.count {
            tabItems[displayIndex].hasUnreadDiff = isDiffUnread()
        }
        postFocusedThreadContextChangedIfKeyWindow()
        showDiffViewer()
    }

    private func isDiffTabSelected() -> Bool {
        guard currentTabIndex >= 0, currentTabIndex < tabSlots.count else { return false }
        if case .diff = tabSlots[currentTabIndex] { return true }
        return false
    }

    func showDiffViewer(scrollToFile: String? = nil, commitHash: String? = nil, commitTitle: String? = nil, forceWorkingTreeDiff: Bool = false) {
        NSLog("[DiffViewer] showDiffViewer called, scrollToFile=%@, commitHash=%@, diffVC=%@, isLoading=%d, view.window=%@",
              scrollToFile ?? "nil", commitHash ?? "nil", String(describing: diffVC), isLoadingDiffViewer ? 1 : 0,
              String(describing: view.window))

        if let existing = diffVC {
            setDiffViewerVisible(isDiffTabSelected())
            // If the commit context or working-tree mode changed, reload the viewer entirely
            if currentDiffCommitHash != commitHash || currentDiffForceWorkingTree != forceWorkingTreeDiff {
                hideDiffViewer()
                // Fall through to create new viewer below
            } else {
                if let file = scrollToFile {
                    existing.expandFile(file, collapseOthers: false)
                }
                return
            }
        }

        // Prevent duplicate creation if async load is already in progress
        guard !isLoadingDiffViewer else { return }
        isLoadingDiffViewer = true
        currentDiffForceWorkingTree = forceWorkingTreeDiff

        let worktreePath = thread.worktreePath
        let baseBranch = thread.isMain ? nil : threadManager.resolveBaseBranch(for: thread)
        NSLog("[DiffViewer] starting async load, baseBranch=%@, worktreePath=%@, commitHash=%@",
              baseBranch ?? "HEAD", worktreePath, commitHash ?? "nil")
        Task {
            let diffContent: String?
            let mergeBase: String?
            let entries: [FileDiffEntry]
            let tooLargeMessage: String?

            if let commitHash {
                // Show diff for a specific commit (git show)
                async let entriesTask = GitService.shared.commitDiffStats(
                    worktreePath: worktreePath,
                    commitHash: commitHash
                )
                entries = await entriesTask
                mergeBase = "\(commitHash)^"
                if let message = diffTooLargeMessage(fileCount: entries.count, lineCount: 0) {
                    diffContent = nil
                    tooLargeMessage = message
                } else {
                    let content = await GitService.shared.commitDiffContent(
                        worktreePath: worktreePath,
                        commitHash: commitHash
                    )
                    diffContent = content
                    if let content {
                        tooLargeMessage = diffTooLargeMessage(fileCount: entries.count, lineCount: diffLineCount(content))
                    } else {
                        tooLargeMessage = nil
                    }
                }
            } else if let baseBranch, !forceWorkingTreeDiff {
                async let mergeBaseTask = GitService.shared.mergeBase(
                    worktreePath: worktreePath,
                    baseBranch: baseBranch
                )
                async let entriesTask = GitService.shared.threadDiffTabStats(
                    worktreePath: worktreePath,
                    baseBranch: baseBranch
                )
                entries = await entriesTask
                mergeBase = await mergeBaseTask
                if let message = diffTooLargeMessage(fileCount: entries.count, lineCount: 0) {
                    diffContent = nil
                    tooLargeMessage = message
                } else {
                    let content = await GitService.shared.diffContent(
                        worktreePath: worktreePath,
                        baseBranch: baseBranch
                    )
                    diffContent = content
                    if let content {
                        tooLargeMessage = diffTooLargeMessage(fileCount: entries.count, lineCount: diffLineCount(content))
                    } else {
                        tooLargeMessage = nil
                    }
                }
            } else {
                // Uncommitted changes only (working tree vs HEAD)
                async let entriesTask = GitService.shared.workingTreeDiffStats(worktreePath: worktreePath)
                entries = await entriesTask
                mergeBase = "HEAD"
                if let message = diffTooLargeMessage(fileCount: entries.count, lineCount: 0) {
                    diffContent = nil
                    tooLargeMessage = message
                } else {
                    let content = await GitService.shared.workingTreeDiffContent(worktreePath: worktreePath)
                    diffContent = content
                    if let content {
                        tooLargeMessage = diffTooLargeMessage(fileCount: entries.count, lineCount: diffLineCount(content))
                    } else {
                        tooLargeMessage = nil
                    }
                }
            }

            let fileCount = entries.count
            let additions = entries.reduce(0) { $0 + $1.additions }
            let deletions = entries.reduce(0) { $0 + $1.deletions }
            NSLog("[DiffViewer] got %d entries, entering MainActor", fileCount)

            await MainActor.run {
                NSLog("[DiffViewer] MainActor.run start, diffVC=%@, view.window=%@",
                      String(describing: diffVC), String(describing: view.window))

                // Double-check diffVC wasn't created while we were loading
                guard diffVC == nil else {
                    isLoadingDiffViewer = false
                    if let file = scrollToFile {
                        diffVC?.expandFile(file, collapseOthers: false)
                    }
                    return
                }

                let vc = InlineDiffViewController()
                vc.setShowsInlineChrome(false)
                vc.onClose = { [weak self] in
                    self?.hideDiffViewer()
                }
                vc.onImageClick = { [weak self] imageView, image in
                    self?.presentDiffImageOverlay(from: imageView, image: image)
                }
                vc.onResizeDrag = { [weak self] phase, delta in
                    self?.handleDiffResizeDrag(phase: phase, delta: delta)
                }
                vc.onReviewedFilesChanged = { [weak self] signatures in
                    guard let self else { return }
                    threadManager.updateDiffReviewedFileSignatures(for: thread.id, signatures: signatures)
                    if let latest = threadManager.threads.first(where: { $0.id == thread.id }) {
                        thread = latest
                    }
                }
                vc.onReturnToCurrentChanges = { [weak self] in
                    guard let self else { return }
                    NotificationCenter.default.post(
                        name: .magentDiffCommitReviewBackRequested,
                        object: nil,
                        userInfo: ["threadId": self.thread.id]
                    )
                }
                vc.onReviewProgressChanged = { [weak self] reviewedCount, fileCount in
                    self?.updateDiffTabTitle(fileCount: fileCount, reviewedCount: commitHash == nil ? reviewedCount : nil)
                }
                vc.onCollapsedFilesChanged = { [weak self] states in
                    guard let self else { return }
                    threadManager.updateDiffCollapsedFileStates(for: thread.id, states: states)
                    if let latest = threadManager.threads.first(where: { $0.id == thread.id }) {
                        thread = latest
                    }
                }
                vc.onFileActionsMenuRequested = { [weak self, weak vc] filePath, point in
                    guard let self, let vc else { return }
                    self.showDiffFileActionsMenu(filePath: filePath, at: point, in: vc)
                }
                vc.onTextContextMenuRequested = { [weak self, weak vc] selectedText, fallbackText, lineFilePath, lineNumber, point in
                    guard let self, let vc else { return }
                    self.showDiffTextContextMenu(
                        selectedText: selectedText,
                        fallbackText: fallbackText,
                        lineFilePath: lineFilePath,
                        lineNumber: lineNumber,
                        at: point,
                        in: vc
                    )
                }
                NSLog("[DiffViewer] addChild")
                addChild(vc)

                NSLog("[DiffViewer] accessing vc.view")
                let diffView = vc.view
                diffView.translatesAutoresizingMaskIntoConstraints = false
                NSLog("[DiffViewer] adding diffView to view hierarchy")
                terminalContainer.addSubview(diffView)
                diffView.isHidden = !self.isDiffTabSelected()
                NSLayoutConstraint.activate([
                    diffView.topAnchor.constraint(equalTo: terminalContainer.topAnchor),
                    diffView.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor),
                    diffView.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor),
                    diffView.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor),
                ])
                NSLog("[DiffViewer] constraints activated")

                vc.setCommitReviewContext(commitHash == nil ? nil : (commitTitle ?? commitHash))
                if let message = tooLargeMessage {
                    vc.setDiffUnavailableMessage(message)
                } else if diffContent == nil {
                    self.updateDiffTabTitle(fileCount: 0)
                    if commitHash == nil {
                        self.clearCurrentDiffReviewStateIfNeeded()
                    }
                    vc.setDiffSummary(fileCount: 0, additions: 0, deletions: 0)
                    let message = commitHash == nil
                        ? String(localized: .ThreadStrings.diffCommitReviewNoChanges)
                        : String(localized: .ThreadStrings.diffCommitReviewNoCommitChanges)
                    vc.setDiffUnavailableMessage(message)
                } else if let diffContent {
                    self.updateDiffTabTitle(
                        fileCount: fileCount,
                        reviewedCount: commitHash == nil ? self.thread.diffReviewedFileSignatures.count : nil
                    )
                    vc.setDiffSummary(fileCount: fileCount, additions: additions, deletions: deletions)
                    NSLog("[DiffViewer] calling setDiffContent")
                    vc.setDiffContent(
                        diffContent,
                        fileCount: fileCount,
                        worktreePath: worktreePath,
                        mergeBase: mergeBase,
                        reviewedFileSignatures: commitHash == nil ? self.thread.diffReviewedFileSignatures : [:],
                        collapsedFileStates: commitHash == nil ? self.thread.diffCollapsedFileStates : [:],
                        allowsReviewMarkers: commitHash == nil,
                        showsSpinner: true
                    )
                }
                diffVC = vc
                currentDiffCommitHash = commitHash
                isLoadingDiffViewer = false
                NSLog("[DiffViewer] setDiffContent done")

                if let file = scrollToFile, tooLargeMessage == nil {
                    DispatchQueue.main.async {
                        NSLog("[DiffViewer] expandFile %@", file)
                        vc.expandFile(file, collapseOthers: false)
                        NSLog("[DiffViewer] expandFile done")
                    }
                }
                NSLog("[DiffViewer] showDiffViewer complete")
            }
        }
    }

    func hideDiffViewer() {
        dismissDiffImageOverlay(animated: false)
        guard let vc = diffVC else { return }
        vc.view.removeFromSuperview()
        vc.removeFromParent()
        diffVC = nil
        currentDiffCommitHash = nil
        currentDiffForceWorkingTree = false
        isLoadingDiffViewer = false
    }

    func refreshDiffViewerIfVisible() {
        // Don't refresh when viewing a specific commit's diff — it doesn't change
        guard diffVC != nil, currentDiffCommitHash == nil else { return }
        let worktreePath = thread.worktreePath
        let baseBranch = thread.isMain ? nil : threadManager.resolveBaseBranch(for: thread)
        let forceWorkingTree = currentDiffForceWorkingTree
        Task {
            let diffContent: String?
            let mergeBase: String?
            let entries: [FileDiffEntry]
            let tooLargeMessage: String?

            if let baseBranch, !forceWorkingTree {
                async let mergeBaseTask = GitService.shared.mergeBase(
                    worktreePath: worktreePath,
                    baseBranch: baseBranch
                )
                async let entriesTask = GitService.shared.threadDiffTabStats(
                    worktreePath: worktreePath,
                    baseBranch: baseBranch
                )
                entries = await entriesTask
                mergeBase = await mergeBaseTask
                if let message = diffTooLargeMessage(fileCount: entries.count, lineCount: 0) {
                    diffContent = nil
                    tooLargeMessage = message
                } else {
                    let content = await GitService.shared.diffContent(
                        worktreePath: worktreePath,
                        baseBranch: baseBranch
                    )
                    diffContent = content
                    if let content {
                        tooLargeMessage = diffTooLargeMessage(fileCount: entries.count, lineCount: diffLineCount(content))
                    } else {
                        tooLargeMessage = nil
                    }
                }
            } else {
                async let entriesTask = GitService.shared.workingTreeDiffStats(worktreePath: worktreePath)
                entries = await entriesTask
                mergeBase = "HEAD"
                if let message = diffTooLargeMessage(fileCount: entries.count, lineCount: 0) {
                    diffContent = nil
                    tooLargeMessage = message
                } else {
                    let content = await GitService.shared.workingTreeDiffContent(worktreePath: worktreePath)
                    diffContent = content
                    if let content {
                        tooLargeMessage = diffTooLargeMessage(fileCount: entries.count, lineCount: diffLineCount(content))
                    } else {
                        tooLargeMessage = nil
                    }
                }
            }

            await MainActor.run {
                if let message = tooLargeMessage {
                    self.diffVC?.setDiffUnavailableMessage(message)
                } else if let content = diffContent {
                    self.updateDiffTabTitle(
                        fileCount: entries.count,
                        reviewedCount: self.thread.diffReviewedFileSignatures.count
                    )
                    let additions = entries.reduce(0) { $0 + $1.additions }
                    let deletions = entries.reduce(0) { $0 + $1.deletions }
                    self.diffVC?.setDiffSummary(fileCount: entries.count, additions: additions, deletions: deletions)
                    self.diffVC?.setDiffContent(
                        content,
                        fileCount: entries.count,
                        worktreePath: worktreePath,
                        mergeBase: mergeBase,
                        reviewedFileSignatures: self.thread.diffReviewedFileSignatures,
                        collapsedFileStates: self.thread.diffCollapsedFileStates,
                        allowsReviewMarkers: true,
                        showsSpinner: false
                    )
                } else {
                    self.updateDiffTabTitle(fileCount: 0)
                    self.clearCurrentDiffReviewStateIfNeeded()
                    self.diffVC?.setDiffSummary(fileCount: 0, additions: 0, deletions: 0)
                    self.diffVC?.setDiffUnavailableMessage(String(localized: .ThreadStrings.diffCommitReviewNoChanges))
                }
            }
        }
    }

    func handleDiffResizeDrag(phase: NSPanGestureRecognizer.State, delta: CGFloat) {
        switch phase {
        case .began:
            isDiffDragging = true
            diffDragStartHeight = diffHeightConstraint?.constant ?? 200

        case .changed:
            let currentHeight = diffHeightConstraint?.constant ?? 200
            let availableHeight = terminalContainer.frame.height + currentHeight
            let maxHeight = availableHeight - 60
            let newHeight = max(min(currentHeight + delta, maxHeight), Self.diffMinHeight)
            diffHeightConstraint?.constant = newHeight

        case .ended, .cancelled:
            isDiffDragging = false
            if let h = diffHeightConstraint?.constant {
                UserDefaults.standard.set(h, forKey: Self.diffHeightKey)
            }

        default:
            break
        }
    }

    func presentDiffImageOverlay(from sourceImageView: NSImageView, image: NSImage) {
        dismissDiffImageOverlay(animated: false)

        let hostView = view.window?.contentView ?? view

        let sourceRectProvider: () -> NSRect? = { [weak sourceImageView, weak hostView] in
            guard let sourceImageView, let hostView, sourceImageView.window === hostView.window else { return nil }
            let rectInWindow = sourceImageView.convert(sourceImageView.bounds, to: nil)
            return hostView.convert(rectInWindow, from: nil)
        }

        guard let sourceRect = sourceRectProvider() else { return }

        let overlay = DiffImageOverlayView(
            image: image,
            sourceRect: sourceRect,
            sourceRectProvider: sourceRectProvider
        )
        overlay.onDismiss = { [weak self, weak overlay] in
            guard let self, let overlay, self.diffImageOverlay === overlay else { return }
            self.diffImageOverlay = nil
        }

        hostView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: hostView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
        hostView.layoutSubtreeIfNeeded()

        diffImageOverlay = overlay
        overlay.present()
    }

    func dismissDiffImageOverlay(animated: Bool) {
        diffImageOverlay?.dismiss(animated: animated)
    }
}
