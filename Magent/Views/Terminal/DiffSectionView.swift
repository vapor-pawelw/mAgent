import Cocoa

// MARK: - DiffSectionView

final class DiffSectionView: NSView {

    let filePath: String
    let additions: Int
    let deletions: Int
    let isImageMode: Bool

    private let headerView = NSView()
    private let chevronImage = NSImageView()
    private let pathLabel = NSTextField(labelWithString: "")
    private let statsStack = NSStackView()

    // Text mode
    private let hunksStackView = NSStackView()
    private var hunkViews: [HunkView] = []
    private var preambleTextView: NSTextView?
    private var preambleHeightConstraint: NSLayoutConstraint?

    // Image mode
    private var imageContentView: ImageDiffContentView?
    private var imageHeightConstraint: NSLayoutConstraint?

    // Expand/collapse constraints
    private var expandedBottomConstraint: NSLayoutConstraint!
    private var collapsedBottomConstraint: NSLayoutConstraint!

    var isExpanded: Bool = true {
        didSet {
            if isImageMode {
                imageContentView?.isHidden = !isExpanded
            } else {
                hunksStackView.isHidden = !isExpanded
            }
            // Deactivate first, then activate to avoid momentary constraint conflicts
            if isExpanded {
                collapsedBottomConstraint.isActive = false
                expandedBottomConstraint.isActive = true
            } else {
                expandedBottomConstraint.isActive = false
                collapsedBottomConstraint.isActive = true
            }
            chevronImage.image = NSImage(
                systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil
            )
        }
    }

    var onToggle: (() -> Void)?

    /// Text diff init — takes raw chunk string and splits into collapsible hunks.
    init(filePath: String, rawChunk: String, additions: Int, deletions: Int) {
        self.filePath = filePath
        self.additions = additions
        self.deletions = deletions
        self.isImageMode = false
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupHeader()
        setupContent(rawChunk)
    }

    /// Image diff init
    init(filePath: String, imageDiffMode: ImageDiffMode) {
        self.filePath = filePath
        self.additions = 0
        self.deletions = 0
        self.isImageMode = true
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupHeader()
        setupImageContent(mode: imageDiffMode)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupHeader() {
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
        pathLabel.textColor = diffHeaderColor
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(pathLabel)

        // Stats stack (colored +N / -N)
        statsStack.orientation = .horizontal
        statsStack.spacing = 4
        statsStack.translatesAutoresizingMaskIntoConstraints = false
        statsStack.setContentHuggingPriority(.required, for: .horizontal)
        statsStack.setContentCompressionResistancePriority(.required, for: .horizontal)
        populateStatsStack(statsStack, additions: additions, deletions: deletions, isImage: isImageMode)
        headerView.addSubview(statsStack)

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
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: statsStack.leadingAnchor, constant: -8),

            statsStack.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -12),
            statsStack.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
        ])
    }

    private func setupContent(_ rawChunk: String) {
        hunksStackView.orientation = .vertical
        hunksStackView.alignment = .leading
        hunksStackView.spacing = 0
        hunksStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hunksStackView)

        let lines = rawChunk.components(separatedBy: "\n")

        // Split into preamble + hunk groups
        var preambleLines: [String] = []
        var hunks: [(header: String, lines: [String])] = []
        var currentHunkHeader: String?
        var currentHunkLines: [String] = []

        for line in lines {
            if line.hasPrefix("diff --git") {
                continue
            }

            if line.hasPrefix("@@") {
                // Save previous hunk if any
                if let header = currentHunkHeader {
                    hunks.append((header: header, lines: currentHunkLines))
                }
                currentHunkHeader = line
                currentHunkLines = []
            } else if currentHunkHeader != nil {
                currentHunkLines.append(line)
            } else {
                preambleLines.append(line)
            }
        }

        // Save last hunk
        if let header = currentHunkHeader {
            hunks.append((header: header, lines: currentHunkLines))
        }

        // Add preamble if non-empty
        if !preambleLines.isEmpty && !preambleLines.allSatisfy({ $0.isEmpty }) {
            let preambleAttr = parseDiffLines(preambleLines)
            let textView = NSTextView()
            textView.isEditable = false
            textView.isSelectable = true
            textView.isRichText = true
            textView.drawsBackground = false
            textView.textContainerInset = NSSize(width: 8, height: 2)
            textView.isVerticallyResizable = false
            textView.isHorizontallyResizable = false
            textView.textContainer?.widthTracksTextView = true
            textView.autoresizingMask = [.width]
            textView.translatesAutoresizingMaskIntoConstraints = false
            textView.textStorage?.setAttributedString(preambleAttr)

            let height = calculateDiffTextHeight(for: preambleAttr)
            let hc = textView.heightAnchor.constraint(equalToConstant: height)
            hc.isActive = true

            hunksStackView.addArrangedSubview(textView)
            textView.leadingAnchor.constraint(equalTo: hunksStackView.leadingAnchor).isActive = true
            textView.trailingAnchor.constraint(equalTo: hunksStackView.trailingAnchor).isActive = true

            preambleTextView = textView
            preambleHeightConstraint = hc
        }

        // Add hunk views
        for hunk in hunks {
            let hunkContent = parseDiffLines(hunk.lines)
            let hunkView = HunkView(headerLine: hunk.header, content: hunkContent)
            hunkViews.append(hunkView)
            hunksStackView.addArrangedSubview(hunkView)
            hunkView.leadingAnchor.constraint(equalTo: hunksStackView.leadingAnchor).isActive = true
            hunkView.trailingAnchor.constraint(equalTo: hunksStackView.trailingAnchor).isActive = true
        }

        expandedBottomConstraint = hunksStackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        collapsedBottomConstraint = headerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        collapsedBottomConstraint.isActive = false

        NSLayoutConstraint.activate([
            hunksStackView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            hunksStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hunksStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            expandedBottomConstraint,
        ])
    }

    private func setupImageContent(mode: ImageDiffMode) {
        let imageView = ImageDiffContentView(mode: mode)
        addSubview(imageView)

        let ihc = imageView.heightAnchor.constraint(equalToConstant: 200)
        imageHeightConstraint = ihc

        expandedBottomConstraint = imageView.bottomAnchor.constraint(equalTo: bottomAnchor)
        collapsedBottomConstraint = headerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        collapsedBottomConstraint.isActive = false

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            expandedBottomConstraint,
            ihc,
        ])

        imageContentView = imageView
    }

    func setImages(before: NSImage?, after: NSImage?) {
        imageContentView?.setImages(before: before, after: after)
        // Update the outer height constraint to match what ImageDiffContentView computed
        if let icv = imageContentView {
            icv.layoutSubtreeIfNeeded()
            imageHeightConstraint?.constant = icv.fittingSize.height
        }
    }

    func updateContentWidth(_ width: CGFloat) {
        guard !isImageMode else { return }
        // Update preamble
        if let preamble = preambleTextView,
           let constraint = preambleHeightConstraint,
           let textStorage = preamble.textStorage {
            let attrStr = NSAttributedString(attributedString: textStorage)
            constraint.constant = calculateDiffTextHeight(for: attrStr, width: width - 16)
        }
        // Update hunk views
        for hunkView in hunkViews {
            hunkView.updateContentWidth(width)
        }
    }

    @objc private func headerClicked() {
        onToggle?()
    }
}
