import Cocoa

// MARK: - InlineDiffViewController

final class InlineDiffViewController: NSViewController {

    let scrollView = NSScrollView()
    let sectionsStackView = NSStackView()
    private let closeButton = NSButton()
    let expandCollapseButton = NSButton()
    let headerLabel = NSTextField(labelWithString: "")
    private let resizeHandle = DiffDividerResizeHandle()

    // Sticky header
    private let stickyHeader = NSView()
    private let stickyChevron = NSImageView()
    private let stickyPathLabel = NSTextField(labelWithString: "")
    private let stickyStatsStack = NSStackView()
    private var stickyTopConstraint: NSLayoutConstraint!
    private weak var currentStickySection: DiffSectionView?

    var sectionViews: [DiffSectionView] = []
    var allExpanded = true

    var worktreePath: String?
    var mergeBase: String?

    var onClose: (() -> Void)?
    /// Called during drag with the delta (positive = drag up = diff taller).
    var onResizeDrag: ((_ phase: NSPanGestureRecognizer.State, _ deltaY: CGFloat) -> Void)?

    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NSLog("[DiffVC] viewDidLoad start")
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
        NSLog("[DiffVC] calling setupUI")
        setupUI()
        NSLog("[DiffVC] viewDidLoad done")
    }

    private func setupUI() {
        NSLog("[DiffVC] setupUI: creating views")
        // Resize handle at the top (6px drag area)
        resizeHandle.wantsLayer = true
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false

        // Separator line inside the handle
        let separatorLine = NSView()
        separatorLine.wantsLayer = true
        separatorLine.layer?.backgroundColor = NSColor(resource: .textSecondary).withAlphaComponent(0.4).cgColor
        separatorLine.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.addSubview(separatorLine)

        // Header bar
        let headerBar = NSView()
        headerBar.wantsLayer = true
        headerBar.layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
        headerBar.translatesAutoresizingMaskIntoConstraints = false

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

        // Sections stack view
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

        // Drag-to-resize gesture on handle
        let panGesture = NSPanGestureRecognizer(target: self, action: #selector(handleResizeDrag(_:)))
        resizeHandle.addGestureRecognizer(panGesture)

        NSLog("[DiffVC] setupUI: adding subviews to hierarchy")
        // Add subviews FIRST (before any cross-view constraints)
        view.addSubview(scrollView)
        view.addSubview(stickyHeader)
        view.addSubview(headerBar)
        view.addSubview(resizeHandle)

        NSLog("[DiffVC] setupUI: setting up sticky header")
        // Setup sticky header (AFTER views are in hierarchy so constraints have common ancestor)
        setupStickyHeader()

        // Enable scroll observation for sticky header
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        NSLog("[DiffVC] setupUI: activating main constraints")
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
        NSLog("[DiffVC] setupUI: done")
    }

    // MARK: - Sticky Header

    private func setupStickyHeader() {
        NSLog("[DiffVC] setupStickyHeader: configuring views")
        stickyHeader.wantsLayer = true
        stickyHeader.layer?.backgroundColor = NSColor(resource: .textSecondary).withAlphaComponent(0.08).cgColor
        stickyHeader.translatesAutoresizingMaskIntoConstraints = false
        stickyHeader.isHidden = true

        // Click gesture
        let click = NSClickGestureRecognizer(target: self, action: #selector(stickyHeaderClicked))
        stickyHeader.addGestureRecognizer(click)

        // Chevron
        stickyChevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        stickyChevron.contentTintColor = NSColor(resource: .textSecondary)
        stickyChevron.translatesAutoresizingMaskIntoConstraints = false
        stickyChevron.setContentHuggingPriority(.required, for: .horizontal)
        stickyHeader.addSubview(stickyChevron)

        // File path
        stickyPathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        stickyPathLabel.textColor = diffHeaderColor
        stickyPathLabel.lineBreakMode = .byTruncatingHead
        stickyPathLabel.translatesAutoresizingMaskIntoConstraints = false
        stickyHeader.addSubview(stickyPathLabel)

        // Stats
        stickyStatsStack.orientation = .horizontal
        stickyStatsStack.spacing = 4
        stickyStatsStack.translatesAutoresizingMaskIntoConstraints = false
        stickyStatsStack.setContentHuggingPriority(.required, for: .horizontal)
        stickyStatsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        stickyHeader.addSubview(stickyStatsStack)

        NSLog("[DiffVC] setupStickyHeader: creating constraints (stickyHeader.superview=%@, scrollView.superview=%@)",
              String(describing: stickyHeader.superview), String(describing: scrollView.superview))
        stickyTopConstraint = stickyHeader.topAnchor.constraint(equalTo: scrollView.topAnchor)

        NSLog("[DiffVC] setupStickyHeader: activating constraints")
        NSLayoutConstraint.activate([
            stickyTopConstraint,
            stickyHeader.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            stickyHeader.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            stickyHeader.heightAnchor.constraint(equalToConstant: 24),

            stickyChevron.leadingAnchor.constraint(equalTo: stickyHeader.leadingAnchor, constant: 8),
            stickyChevron.centerYAnchor.constraint(equalTo: stickyHeader.centerYAnchor),
            stickyChevron.widthAnchor.constraint(equalToConstant: 10),
            stickyChevron.heightAnchor.constraint(equalToConstant: 10),

            stickyPathLabel.leadingAnchor.constraint(equalTo: stickyChevron.trailingAnchor, constant: 6),
            stickyPathLabel.centerYAnchor.constraint(equalTo: stickyHeader.centerYAnchor),
            stickyPathLabel.trailingAnchor.constraint(lessThanOrEqualTo: stickyStatsStack.leadingAnchor, constant: -8),

            stickyStatsStack.trailingAnchor.constraint(equalTo: stickyHeader.trailingAnchor, constant: -12),
            stickyStatsStack.centerYAnchor.constraint(equalTo: stickyHeader.centerYAnchor),
        ])
    }

    @objc private func handleScrollChange() {
        let visibleY = scrollView.contentView.bounds.origin.y

        var candidateSection: DiffSectionView?
        var nextSectionHeaderY: CGFloat?

        for (i, section) in sectionViews.enumerated() {
            let frame = section.convert(section.bounds, to: sectionsStackView)
            // Section whose header top is above visibleY but whose bottom is below
            if frame.origin.y <= visibleY && frame.maxY > visibleY {
                candidateSection = section
                if i + 1 < sectionViews.count {
                    let nextFrame = sectionViews[i + 1].convert(sectionViews[i + 1].bounds, to: sectionsStackView)
                    nextSectionHeaderY = nextFrame.origin.y
                }
                break
            }
        }

        guard let section = candidateSection else {
            stickyHeader.isHidden = true
            currentStickySection = nil
            return
        }

        // Don't show sticky header if the section's own header is still visible
        let sectionFrame = section.convert(section.bounds, to: sectionsStackView)
        if sectionFrame.origin.y >= visibleY {
            stickyHeader.isHidden = true
            currentStickySection = nil
            return
        }

        // Show and update sticky header
        stickyHeader.isHidden = false
        currentStickySection = section
        stickyPathLabel.stringValue = section.filePath
        populateStatsStack(stickyStatsStack, additions: section.additions, deletions: section.deletions, isImage: section.isImageMode)
        stickyChevron.image = NSImage(
            systemSymbolName: section.isExpanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )

        // Push-up effect: next section's header pushes sticky header up
        if let nextY = nextSectionHeaderY {
            let overlap = visibleY + 24 - nextY
            if overlap > 0 {
                stickyTopConstraint.constant = -overlap
            } else {
                stickyTopConstraint.constant = 0
            }
        } else {
            stickyTopConstraint.constant = 0
        }
    }

    @objc private func stickyHeaderClicked() {
        guard let section = currentStickySection else { return }
        // onToggle already toggles isExpanded — don't toggle it here too
        section.onToggle?()
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

    func updateExpandCollapseButton() {
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
}
