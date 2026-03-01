import Cocoa

// MARK: - Helpers

private let imageExtensions: Set<String> = [
    "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "bmp", "tiff", "tif",
]

private func isImageFile(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return imageExtensions.contains(ext)
}

private enum ImageDiffMode {
    case added, deleted, modified
}

private func detectImageDiffState(from chunk: String) -> ImageDiffMode {
    if chunk.contains("new file") || chunk.contains("--- /dev/null") {
        return .added
    }
    if chunk.contains("deleted file") || chunk.contains("+++ /dev/null") {
        return .deleted
    }
    return .modified
}

/// Extracts the old path from a `rename from <path>` line in a diff chunk.
private func extractRenameFrom(_ chunk: String) -> String? {
    for line in chunk.components(separatedBy: "\n") {
        if line.hasPrefix("rename from ") {
            return String(line.dropFirst("rename from ".count))
        }
    }
    return nil
}

// MARK: - Resize Handle

fileprivate final class DiffDividerResizeHandle: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}

// MARK: - Flipped Stack Clip View

private final class FlippedDiffClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - ImageDiffContentView

private final class ImageDiffContentView: NSView {

    private let mode: ImageDiffMode
    private var beforeImageView: NSImageView?
    private var afterImageView: NSImageView?
    private var beforeLabel: NSTextField?
    private var afterLabel: NSTextField?
    private var heightConstraint: NSLayoutConstraint!

    private static let maxImageHeight: CGFloat = 300
    private static let labelHeight: CGFloat = 18
    private static let padding: CGFloat = 12

    init(mode: ImageDiffMode) {
        self.mode = mode
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor(resource: .textSecondary)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    private func makeImageView() -> NSImageView {
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyDown
        iv.imageAlignment = .alignCenter
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.wantsLayer = true
        iv.layer?.cornerRadius = 4
        iv.layer?.borderWidth = 1
        iv.layer?.borderColor = NSColor(resource: .textSecondary).withAlphaComponent(0.2).cgColor
        return iv
    }

    private func setupLayout() {
        let topPadding = Self.padding
        let imageTop = topPadding + Self.labelHeight + 4

        switch mode {
        case .modified:
            let bLabel = makeLabel("Before")
            let aLabel = makeLabel("After")
            let bImage = makeImageView()
            let aImage = makeImageView()

            addSubview(bLabel)
            addSubview(aLabel)
            addSubview(bImage)
            addSubview(aImage)

            // Arrow between the two images
            let arrow = NSTextField(labelWithString: "\u{2192}")
            arrow.font = .systemFont(ofSize: 16, weight: .regular)
            arrow.textColor = NSColor(resource: .textSecondary)
            arrow.alignment = .center
            arrow.translatesAutoresizingMaskIntoConstraints = false
            arrow.setContentHuggingPriority(.required, for: .horizontal)
            addSubview(arrow)

            heightConstraint = heightAnchor.constraint(equalToConstant: 200)

            NSLayoutConstraint.activate([
                heightConstraint,

                bLabel.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
                bLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
                bLabel.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -4),

                aLabel.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
                aLabel.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 4),
                aLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),

                arrow.centerYAnchor.constraint(equalTo: bImage.centerYAnchor),
                arrow.centerXAnchor.constraint(equalTo: centerXAnchor),
                arrow.widthAnchor.constraint(equalToConstant: 24),

                bImage.topAnchor.constraint(equalTo: topAnchor, constant: imageTop),
                bImage.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.padding),
                bImage.trailingAnchor.constraint(equalTo: arrow.leadingAnchor, constant: -4),

                aImage.topAnchor.constraint(equalTo: topAnchor, constant: imageTop),
                aImage.leadingAnchor.constraint(equalTo: arrow.trailingAnchor, constant: 4),
                aImage.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.padding),

                bImage.heightAnchor.constraint(equalTo: aImage.heightAnchor),
            ])

            beforeImageView = bImage
            afterImageView = aImage
            beforeLabel = bLabel
            afterLabel = aLabel

        case .added:
            let label = makeLabel("New")
            let imageView = makeImageView()
            addSubview(label)
            addSubview(imageView)

            heightConstraint = heightAnchor.constraint(equalToConstant: 200)

            NSLayoutConstraint.activate([
                heightConstraint,
                label.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
                label.centerXAnchor.constraint(equalTo: centerXAnchor),

                imageView.topAnchor.constraint(equalTo: topAnchor, constant: imageTop),
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Self.padding),
                imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.padding),
            ])

            afterImageView = imageView

        case .deleted:
            let label = makeLabel("Deleted")
            let imageView = makeImageView()
            addSubview(label)
            addSubview(imageView)

            heightConstraint = heightAnchor.constraint(equalToConstant: 200)

            NSLayoutConstraint.activate([
                heightConstraint,
                label.topAnchor.constraint(equalTo: topAnchor, constant: topPadding),
                label.centerXAnchor.constraint(equalTo: centerXAnchor),

                imageView.topAnchor.constraint(equalTo: topAnchor, constant: imageTop),
                imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                imageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Self.padding),
                imageView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Self.padding),
            ])

            beforeImageView = imageView
        }
    }

    func setImages(before: NSImage?, after: NSImage?) {
        beforeImageView?.image = before
        afterImageView?.image = after

        let imageTop = Self.padding + Self.labelHeight + 4
        let bottomPadding = Self.padding

        // Compute the height needed based on image aspect ratios and available width
        let availableWidth: CGFloat
        switch mode {
        case .modified:
            availableWidth = max((bounds.width - Self.padding * 2 - 24) / 2, 100)
        case .added, .deleted:
            availableWidth = max(bounds.width - Self.padding * 2, 100)
        }

        var maxH: CGFloat = 60 // minimum content area
        for image in [before, after].compactMap({ $0 }) {
            let aspect = image.size.height / max(image.size.width, 1)
            let h = min(availableWidth * aspect, Self.maxImageHeight)
            maxH = max(maxH, h)
        }

        heightConstraint.constant = imageTop + maxH + bottomPadding
    }
}

// MARK: - DiffSectionView

private final class DiffSectionView: NSView {

    let filePath: String
    private let headerView = NSView()
    private let chevronImage = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let statsLabel = NSTextField(labelWithString: "")
    private let contentTextView = NSTextView()
    private var contentHeightConstraint: NSLayoutConstraint!

    // Image mode properties
    private let isImageMode: Bool
    private var imageContentView: ImageDiffContentView?

    var isExpanded: Bool = true {
        didSet {
            if isImageMode {
                imageContentView?.isHidden = !isExpanded
            } else {
                contentTextView.isHidden = !isExpanded
            }
            contentHeightConstraint?.isActive = isExpanded
            chevronImage.image = NSImage(
                systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil
            )
        }
    }

    var onToggle: (() -> Void)?

    /// Text diff init
    init(filePath: String, content: NSAttributedString, additions: Int, deletions: Int) {
        self.filePath = filePath
        self.isImageMode = false
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupHeader(statsText: Self.statsString(additions: additions, deletions: deletions))
        setupContent(content)
    }

    /// Image diff init
    init(filePath: String, imageDiffMode: ImageDiffMode) {
        self.filePath = filePath
        self.isImageMode = true
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupHeader(statsText: "image")
        setupImageContent(mode: imageDiffMode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static func statsString(additions: Int, deletions: Int) -> String {
        var statsText = ""
        if additions > 0 { statsText += "+\(additions)" }
        if deletions > 0 {
            if !statsText.isEmpty { statsText += " " }
            statsText += "-\(deletions)"
        }
        return statsText
    }

    private func setupHeader(statsText: String) {
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(resource: .textSecondary).withAlphaComponent(0.08).cgColor
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)

        // Click gesture on header
        let click = NSClickGestureRecognizer(target: self, action: #selector(headerClicked))
        headerView.addGestureRecognizer(click)

        // Chevron
        chevronImage.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevronImage.contentTintColor = NSColor(resource: .textSecondary)
        chevronImage.translatesAutoresizingMaskIntoConstraints = false
        chevronImage.setContentHuggingPriority(.required, for: .horizontal)
        headerView.addSubview(chevronImage)

        // File path
        pathLabel.stringValue = filePath
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        pathLabel.textColor = NSColor(red: 0.8, green: 0.8, blue: 0.6, alpha: 1.0)
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(pathLabel)

        // Stats
        statsLabel.stringValue = statsText
        statsLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statsLabel.textColor = NSColor(resource: .textSecondary)
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsLabel.setContentHuggingPriority(.required, for: .horizontal)
        statsLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        headerView.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 24),

            chevronImage.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            chevronImage.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            chevronImage.widthAnchor.constraint(equalToConstant: 10),
            chevronImage.heightAnchor.constraint(equalToConstant: 10),

            pathLabel.leadingAnchor.constraint(equalTo: chevronImage.trailingAnchor, constant: 6),
            pathLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: statsLabel.leadingAnchor, constant: -8),

            statsLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            statsLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])
    }

    private func setupContent(_ attributedContent: NSAttributedString) {
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.isRichText = true
        contentTextView.drawsBackground = false
        contentTextView.textContainerInset = NSSize(width: 8, height: 4)
        contentTextView.isVerticallyResizable = false
        contentTextView.isHorizontallyResizable = false
        contentTextView.textContainer?.widthTracksTextView = true
        contentTextView.autoresizingMask = [.width]
        contentTextView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentTextView)

        contentTextView.textStorage?.setAttributedString(attributedContent)

        // Calculate height from content
        let contentHeight = calculateTextHeight(for: attributedContent)
        contentHeightConstraint = contentTextView.heightAnchor.constraint(equalToConstant: contentHeight)

        NSLayoutConstraint.activate([
            contentTextView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentTextView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentTextView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentHeightConstraint,
        ])
    }

    private func setupImageContent(mode: ImageDiffMode) {
        let imageView = ImageDiffContentView(mode: mode)
        addSubview(imageView)

        contentHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 200)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentHeightConstraint,
        ])

        imageContentView = imageView
    }

    func setImages(before: NSImage?, after: NSImage?) {
        imageContentView?.setImages(before: before, after: after)
        // Update the outer height constraint to match what ImageDiffContentView computed
        if let icv = imageContentView {
            icv.layoutSubtreeIfNeeded()
            // Read back the height from the inner constraint
            contentHeightConstraint.constant = icv.fittingSize.height
        }
    }

    private func calculateTextHeight(for attrStr: NSAttributedString) -> CGFloat {
        // Use a temporary layout manager to measure height
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: max(bounds.width - 16, 300), height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 5
        let textStorage = NSTextStorage(attributedString: attrStr)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + 8
        return max(height, 20)
    }

    func updateContentWidth(_ width: CGFloat) {
        guard !isImageMode else { return }
        guard let textStorage = contentTextView.textStorage else { return }
        let attrStr = NSAttributedString(attributedString: textStorage)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(size: NSSize(width: max(width - 16, 300), height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 5
        let storage = NSTextStorage(attributedString: attrStr)
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + 8
        contentHeightConstraint.constant = max(height, 20)
    }

    @objc private func headerClicked() {
        onToggle?()
    }
}

// MARK: - InlineDiffViewController

final class InlineDiffViewController: NSViewController {

    private let scrollView = NSScrollView()
    private let sectionsStackView = NSStackView()
    private let closeButton = NSButton()
    private let expandCollapseButton = NSButton()
    private let headerLabel = NSTextField(labelWithString: "")
    private let resizeHandle = DiffDividerResizeHandle()

    private var sectionViews: [DiffSectionView] = []
    private var allExpanded = true

    private var worktreePath: String?
    private var mergeBase: String?

    var onClose: (() -> Void)?
    /// Called during drag with the delta (positive = drag up = diff taller).
    var onResizeDrag: ((_ phase: NSPanGestureRecognizer.State, _ deltaY: CGFloat) -> Void)?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
        setupUI()
    }

    private func setupUI() {
        // Resize handle at the top (6px drag area)
        resizeHandle.wantsLayer = true
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resizeHandle)

        // Separator line inside the handle
        let separatorLine = NSView()
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = NSColor(resource: .textSecondary).withAlphaComponent(0.4).cgColor
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.addSubview(separatorLine)

        // Header bar
        let headerBar = NSView()
        headerBar.wantsLayer = true
        headerBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerBar)

        headerLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        headerLabel.textColor = NSColor(resource: .textSecondary)
        headerLabel.stringValue = "DIFF"
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(headerLabel)

        // Expand/collapse all toggle
        expandCollapseButton.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "Collapse All")
        expandCollapseButton.contentTintColor = NSColor(resource: .textSecondary)
        expandCollapseButton.bezelStyle = .inline
        expandCollapseButton.isBordered = false
        expandCollapseButton.target = self
        expandCollapseButton.action = #selector(toggleExpandCollapseAll)
        expandCollapseButton.toolTip = "Collapse All"
        expandCollapseButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(expandCollapseButton)

        // Close button
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close Diff")
        closeButton.contentTintColor = NSColor(resource: .textSecondary)
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        headerBar.addSubview(closeButton)

        // Sections stack view (replaces single text view)
        sectionsStackView.orientation = .vertical
        sectionsStackView.alignment = .leading
        sectionsStackView.spacing = 0
        sectionsStackView.translatesAutoresizingMaskIntoConstraints = false

        let flippedClip = FlippedDiffClipView()
        flippedClip.drawsBackground = false
        scrollView.contentView = flippedClip
        scrollView.documentView = sectionsStackView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Drag-to-resize gesture on handle
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleResizeDrag(_:)))
        resizeHandle.addGestureRecognizer(panGesture)

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

            scrollView.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            sectionsStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            sectionsStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            sectionsStackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
        ])
    }

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
        // Negative y means drag up = diff gets taller
        onResizeDrag?(gesture.state, -translation.y)
        if gesture.state == .changed {
            gesture.setTranslation(.zero, in: view)
        }
    }

    // MARK: - Content

    func setDiffContent(_ rawDiff: String, fileCount: Int, worktreePath: String?, mergeBase: String?) {
        self.worktreePath = worktreePath
        self.mergeBase = mergeBase

        headerLabel.stringValue = "DIFF (\(fileCount) files)"

        // Clear old sections
        for sv in sectionsStackView.arrangedSubviews {
            sectionsStackView.removeArrangedSubview(sv)
            sv.removeFromSuperview()
        }
        sectionViews.removeAll()

        // Split diff into per-file chunks and create section views
        let chunks = splitDiffIntoFileChunks(rawDiff)
        for (path, chunkContent) in chunks {
            let section: DiffSectionView

            if isImageFile(path) {
                let state = detectImageDiffState(from: chunkContent)
                section = DiffSectionView(filePath: path, imageDiffMode: state)
                loadImages(for: section, path: path, chunk: chunkContent, state: state)
            } else {
                let (additions, deletions) = countStats(in: chunkContent)
                let attributed = parseDiffChunk(chunkContent)
                section = DiffSectionView(
                    filePath: path,
                    content: attributed,
                    additions: additions,
                    deletions: deletions
                )
            }

            section.onToggle = { [weak self, weak section] in
                guard let self, let section else { return }
                section.isExpanded.toggle()
                self.syncExpandCollapseState()
                self.scrollSectionIntoViewIfNeeded(section)
            }
            sectionViews.append(section)
            sectionsStackView.addArrangedSubview(section)
            section.leadingAnchor.constraint(equalTo: sectionsStackView.leadingAnchor).isActive = true
            section.trailingAnchor.constraint(equalTo: sectionsStackView.trailingAnchor).isActive = true
        }
    }

    // MARK: - Image Loading

    private func loadImages(for section: DiffSectionView, path: String, chunk: String, state: ImageDiffMode) {
        guard let worktreePath else { return }
        let mergeBase = self.mergeBase
        let beforePath = extractRenameFrom(chunk) ?? path

        Task {
            var beforeImage: NSImage?
            var afterImage: NSImage?

            // Load before image (from git ref)
            if state != .added, let ref = mergeBase {
                if let data = await GitService.shared.fileData(
                    atRef: ref,
                    relativePath: beforePath,
                    worktreePath: worktreePath
                ) {
                    beforeImage = NSImage(data: data)
                }
            }

            // Load after image (from working tree)
            if state != .deleted {
                let fileURL = URL(fileURLWithPath: worktreePath).appendingPathComponent(path)
                if let data = try? Data(contentsOf: fileURL) {
                    afterImage = NSImage(data: data)
                }
            }

            await MainActor.run {
                section.setImages(before: beforeImage, after: afterImage)
            }
        }
    }

    func expandFile(_ relativePath: String, collapseOthers: Bool) {
        for section in sectionViews {
            if section.filePath == relativePath {
                section.isExpanded = true
            } else if collapseOthers {
                section.isExpanded = false
            }
        }
        syncExpandCollapseState()
        // Scroll to the expanded section
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let section = self.sectionViews.first(where: { $0.filePath == relativePath }) {
                self.scrollSectionIntoViewIfNeeded(section)
            }
        }
    }

    private func syncExpandCollapseState() {
        allExpanded = sectionViews.allSatisfy(\.isExpanded)
        updateExpandCollapseButton()
    }

    func expandAll() {
        // Find the section currently visible at the top of the scroll viewport
        let visibleY = scrollView.contentView.bounds.origin.y
        var anchorSection: DiffSectionView?
        var anchorOffsetBefore: CGFloat = 0
        for section in sectionViews {
            let frame = section.convert(section.bounds, to: sectionsStackView)
            if frame.maxY > visibleY {
                anchorSection = section
                anchorOffsetBefore = frame.origin.y - visibleY
                break
            }
        }

        for section in sectionViews {
            section.isExpanded = true
        }
        allExpanded = true
        updateExpandCollapseButton()

        // Restore scroll so the anchor section stays in the same viewport position
        if let anchor = anchorSection {
            sectionsStackView.layoutSubtreeIfNeeded()
            let newFrame = anchor.convert(anchor.bounds, to: sectionsStackView)
            let newScrollY = newFrame.origin.y - anchorOffsetBefore
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(newScrollY, 0)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    func collapseAll() {
        for section in sectionViews {
            section.isExpanded = false
        }
        allExpanded = false
        updateExpandCollapseButton()
    }

    func scrollToFile(_ relativePath: String) {
        guard let section = sectionViews.first(where: { $0.filePath == relativePath }) else { return }
        scrollSectionIntoViewIfNeeded(section)
    }

    private func scrollSectionIntoViewIfNeeded(_ section: DiffSectionView) {
        let sectionFrame = section.convert(section.bounds, to: sectionsStackView)
        scrollView.contentView.scrollToVisible(sectionFrame)
    }

    // MARK: - Diff Splitting

    private func splitDiffIntoFileChunks(_ rawDiff: String) -> [(path: String, content: String)] {
        var chunks: [(path: String, content: String)] = []
        let lines = rawDiff.components(separatedBy: "\n")

        var currentPath = ""
        var currentLines: [String] = []

        for line in lines {
            if line.hasPrefix("diff --git") {
                // Save previous chunk if any
                if !currentPath.isEmpty {
                    chunks.append((path: currentPath, content: currentLines.joined(separator: "\n")))
                }
                // Extract path from "diff --git a/path b/path"
                let parts = line.components(separatedBy: " b/")
                currentPath = parts.count >= 2 ? (parts.last ?? "") : ""
                currentLines = [line]
            } else {
                currentLines.append(line)
            }
        }

        // Save last chunk
        if !currentPath.isEmpty {
            chunks.append((path: currentPath, content: currentLines.joined(separator: "\n")))
        }

        return chunks
    }

    private func countStats(in chunk: String) -> (additions: Int, deletions: Int) {
        var adds = 0
        var dels = 0
        for line in chunk.components(separatedBy: "\n") {
            if line.hasPrefix("+") && !line.hasPrefix("+++") {
                adds += 1
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                dels += 1
            }
        }
        return (adds, dels)
    }

    // MARK: - Diff Parsing (per-chunk)

    private func parseDiffChunk(_ raw: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = raw.components(separatedBy: "\n")

        let defaultFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let headerFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)

        let addColor = NSColor(red: 0.35, green: 0.75, blue: 0.35, alpha: 1.0)
        let delColor = NSColor(red: 0.9, green: 0.35, blue: 0.35, alpha: 1.0)
        let hunkColor = NSColor(red: 0.45, green: 0.65, blue: 0.85, alpha: 1.0)
        let headerColor = NSColor(red: 0.8, green: 0.8, blue: 0.6, alpha: 1.0)
        let contextColor = NSColor(resource: .textSecondary)

        for line in lines {
            let attrs: [NSAttributedString.Key: Any]

            if line.hasPrefix("diff --git") {
                // Skip the diff --git line itself — it's shown in the section header
                continue
            } else if line.hasPrefix("+++") || line.hasPrefix("---") {
                attrs = [.font: headerFont, .foregroundColor: headerColor]
            } else if line.hasPrefix("@@") {
                attrs = [.font: defaultFont, .foregroundColor: hunkColor]
            } else if line.hasPrefix("+") {
                attrs = [
                    .font: defaultFont,
                    .foregroundColor: addColor,
                    .backgroundColor: addColor.withAlphaComponent(0.08),
                ]
            } else if line.hasPrefix("-") {
                attrs = [
                    .font: defaultFont,
                    .foregroundColor: delColor,
                    .backgroundColor: delColor.withAlphaComponent(0.08),
                ]
            } else if line.hasPrefix("new file") || line.hasPrefix("deleted file") ||
                        line.hasPrefix("index ") || line.hasPrefix("Binary") ||
                        line.hasPrefix("rename") || line.hasPrefix("similarity") {
                attrs = [.font: defaultFont, .foregroundColor: contextColor.withAlphaComponent(0.6)]
            } else {
                attrs = [.font: defaultFont, .foregroundColor: contextColor]
            }

            result.append(NSAttributedString(string: line + "\n", attributes: attrs))
        }

        return result
    }
}
