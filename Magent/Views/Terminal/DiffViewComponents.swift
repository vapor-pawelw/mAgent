import Cocoa

// MARK: - Resize Handle

final class DiffDividerResizeHandle: NSView {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeUpDown)
    }
}

// MARK: - Flipped Stack Clip View

final class FlippedDiffClipView: NSClipView {
    override var isFlipped: Bool { true }
}

// MARK: - ImageDiffContentView

final class ImageDiffContentView: NSView {

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

// MARK: - HunkView

final class HunkView: NSView {

    private let headerView = NSView()
    private let chevronImage = NSImageView()
    private let headerLabel = NSTextField(labelWithString: "")
    private let contentTextView = NSTextView()
    private var contentHeightConstraint: NSLayoutConstraint!
    private var expandedBottomConstraint: NSLayoutConstraint!
    private var collapsedBottomConstraint: NSLayoutConstraint!

    var isExpanded: Bool = true {
        didSet {
            contentTextView.isHidden = !isExpanded
            // Deactivate first, then activate to avoid momentary constraint conflicts
            if isExpanded {
                collapsedBottomConstraint.isActive = false
                expandedBottomConstraint.isActive = true
                contentHeightConstraint.isActive = true
            } else {
                expandedBottomConstraint.isActive = false
                contentHeightConstraint.isActive = false
                collapsedBottomConstraint.isActive = true
            }
            chevronImage.image = NSImage(
                systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil
            )
        }
    }

    init(headerLine: String, content: NSAttributedString) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setup(headerLine: headerLine, content: content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setup(headerLine: String, content: NSAttributedString) {
        // Header bar (clickable)
        headerView.wantsLayer = true
        headerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(headerView)

        let click = NSClickGestureRecognizer(target: self, action: #selector(headerClicked))
        headerView.addGestureRecognizer(click)

        // Small chevron
        chevronImage.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevronImage.contentTintColor = diffHunkColor
        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
        chevronImage.symbolConfiguration = config
        chevronImage.translatesAutoresizingMaskIntoConstraints = false
        chevronImage.setContentHuggingPriority(.required, for: .horizontal)
        headerView.addSubview(chevronImage)

        // @@ header text
        headerLabel.stringValue = headerLine
        headerLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        headerLabel.textColor = diffHunkColor
        headerLabel.lineBreakMode = .byTruncatingTail
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(headerLabel)

        // Content text view
        contentTextView.isEditable = false
        contentTextView.isSelectable = true
        contentTextView.isRichText = true
        contentTextView.drawsBackground = false
        contentTextView.textContainerInset = NSSize(width: 8, height: 2)
        contentTextView.isVerticallyResizable = false
        contentTextView.isHorizontallyResizable = false
        contentTextView.textContainer?.widthTracksTextView = true
        contentTextView.autoresizingMask = [.width]
        contentTextView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentTextView)

        contentTextView.textStorage?.setAttributedString(content)

        let contentHeight = calculateDiffTextHeight(for: content)
        contentHeightConstraint = contentTextView.heightAnchor.constraint(equalToConstant: contentHeight)

        expandedBottomConstraint = contentTextView.bottomAnchor.constraint(equalTo: bottomAnchor)
        collapsedBottomConstraint = headerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        collapsedBottomConstraint.isActive = false

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 20),

            chevronImage.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            chevronImage.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            chevronImage.widthAnchor.constraint(equalToConstant: 8),
            chevronImage.heightAnchor.constraint(equalToConstant: 8),

            headerLabel.leadingAnchor.constraint(equalTo: chevronImage.trailingAnchor, constant: 4),
            headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: headerView.trailingAnchor, constant: -8),

            contentTextView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            contentTextView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentTextView.trailingAnchor.constraint(equalTo: trailingAnchor),
            expandedBottomConstraint,
            contentHeightConstraint,
        ])
    }

    func updateContentWidth(_ width: CGFloat) {
        guard let textStorage = contentTextView.textStorage else { return }
        let attrStr = NSAttributedString(attributedString: textStorage)
        contentHeightConstraint.constant = calculateDiffTextHeight(for: attrStr, width: width - 16)
    }

    @objc private func headerClicked() {
        isExpanded.toggle()
    }
}
