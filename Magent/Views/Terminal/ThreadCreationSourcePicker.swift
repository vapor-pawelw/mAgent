import AppKit
import MagentCore

struct ThreadCreationSourceOption {
    let descriptor: ThreadCreationSourceDescriptor
    let subtitle: String?
    let signEmoji: String?
    let icon: ThreadIcon
    let sectionColor: NSColor?
    let sectionID: UUID?
    let isContextThread: Bool
}

private final class ThreadCreationSourceCapsuleView: NSView {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let inlineMainIconView = NSImageView()
    private let subtitleLabel = NSTextField(labelWithString: "")
    private var sectionColor: NSColor?
    private let sectionMarkerLayer = CAShapeLayer()
    private var textTrailingConstraint: NSLayoutConstraint?

    override var wantsUpdateLayer: Bool { true }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(sectionMarkerLayer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        inlineMainIconView.translatesAutoresizingMaskIntoConstraints = false
        inlineMainIconView.image = NSImage(
            systemSymbolName: "house.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        inlineMainIconView.imageScaling = .scaleProportionallyDown
        inlineMainIconView.isHidden = true

        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.maximumNumberOfLines = 1

        let titleStack = NSStackView(views: [titleLabel, inlineMainIconView])
        titleStack.orientation = .horizontal
        titleStack.alignment = .firstBaseline
        titleStack.spacing = 4
        titleStack.detachesHiddenViews = true

        let textStack = NSStackView(views: [titleStack, subtitleLabel])
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 2
        textStack.detachesHiddenViews = true

        let contentStack = NSStackView(views: [iconView, textStack])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 8
        contentStack.detachesHiddenViews = true
        addSubview(contentStack)

        let textTrailingConstraint = textStack.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -12
        )
        self.textTrailingConstraint = textTrailingConstraint
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 42),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            inlineMainIconView.widthAnchor.constraint(equalToConstant: 11),
            inlineMainIconView.heightAnchor.constraint(equalToConstant: 11),
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            textTrailingConstraint,
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(option: ThreadCreationSourceOption, showThreadIcons: Bool) {
        let descriptor = option.descriptor
        let symbolName = descriptor.isMainWorktree ? "house.fill" : option.icon.symbolName
        iconView.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: descriptor.displayName
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        iconView.isHidden = !showThreadIcons
        inlineMainIconView.isHidden = showThreadIcons || !descriptor.isMainWorktree

        titleLabel.stringValue = ThreadRowBadgeLayout.primaryText(
            descriptor.displayName,
            signEmoji: descriptor.isMainWorktree ? nil : option.signEmoji
        )
        subtitleLabel.stringValue = option.subtitle ?? ""
        subtitleLabel.isHidden = option.subtitle == nil
        sectionColor = option.sectionColor
        let iconTint = descriptor.isMainWorktree
            ? NSColor.labelColor
            : (option.sectionColor ?? NSColor.appPrimary)
        iconView.contentTintColor = iconTint
        inlineMainIconView.contentTintColor = .labelColor
        needsDisplay = true
    }

    func configure(branchName: String, showThreadIcons: Bool) {
        iconView.image = NSImage(
            systemSymbolName: "arrow.triangle.branch",
            accessibilityDescription: branchName
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        iconView.isHidden = !showThreadIcons
        inlineMainIconView.isHidden = true
        iconView.contentTintColor = NSColor.appPrimary
        titleLabel.stringValue = String(localized: .ThreadStrings.threadCreationBranchSource)
        subtitleLabel.stringValue = branchName
        subtitleLabel.isHidden = false
        sectionColor = nil
        needsDisplay = true
    }

    func reserveTrailingSpaceForChevron() {
        textTrailingConstraint?.constant = -32
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            sectionMarkerLayer.fillColor = ThreadCapsuleSectionMarkerStyle.color(
                sectionColor: sectionColor,
                isSelected: false
            ).cgColor
        }
        layer?.borderWidth = 0
        layer?.cornerRadius = ThreadCapsuleSectionMarkerStyle.capsuleCornerRadius
    }

    override func layout() {
        super.layout()
        let capsuleRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let points = ThreadCapsuleSectionMarkerStyle.vertices(in: capsuleRect, isFlipped: isFlipped)
        guard let first = points.first else {
            sectionMarkerLayer.path = nil
            return
        }
        let path = CGMutablePath()
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.closeSubpath()
        sectionMarkerLayer.frame = bounds
        sectionMarkerLayer.path = path
    }
}

private final class ThreadCreationSourceOptionButton: NSButton {
    private let capsule = ThreadCreationSourceCapsuleView()
    var onSelect: (() -> Void)?

    init(option: ThreadCreationSourceOption, showThreadIcons: Bool) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        title = ""
        target = self
        action = #selector(selected)

        capsule.configure(option: option, showThreadIcons: showThreadIcons)
        addSubview(capsule)
        NSLayoutConstraint.activate([
            capsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            capsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            capsule.topAnchor.constraint(equalTo: topAnchor),
            capsule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func selected() {
        onSelect?()
    }
}

final class ThreadCreationSourcePicker: NSView {
    private let selectedCapsule = ThreadCreationSourceCapsuleView()
    private let chevron = NSImageView()
    private let button = NSButton()
    private var popover: NSPopover?
    private var selectedThreadID: UUID?

    var onSelect: ((ThreadCreationSourceOption) -> Void)?
    var showThreadIcons = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = NSImage(
            systemSymbolName: "chevron.down",
            accessibilityDescription: String(localized: .ThreadStrings.threadCreationChooseSource)
        )?.withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        chevron.contentTintColor = .secondaryLabelColor

        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.title = ""
        button.toolTip = String(localized: .ThreadStrings.threadCreationChooseSource)
        button.target = self
        button.action = #selector(showOptions)

        addSubview(selectedCapsule)
        selectedCapsule.reserveTrailingSpaceForChevron()
        addSubview(chevron)
        addSubview(button)
        NSLayoutConstraint.activate([
            selectedCapsule.leadingAnchor.constraint(equalTo: leadingAnchor),
            selectedCapsule.trailingAnchor.constraint(equalTo: trailingAnchor),
            selectedCapsule.topAnchor.constraint(equalTo: topAnchor),
            selectedCapsule.bottomAnchor.constraint(equalTo: bottomAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 12),
            chevron.heightAnchor.constraint(equalToConstant: 12),
            button.leadingAnchor.constraint(equalTo: leadingAnchor),
            button.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: topAnchor),
            button.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(option: ThreadCreationSourceOption) {
        selectedThreadID = option.descriptor.threadID
        selectedCapsule.configure(option: option, showThreadIcons: showThreadIcons)
    }

    func showBranch(name: String) {
        selectedThreadID = nil
        selectedCapsule.configure(branchName: name, showThreadIcons: showThreadIcons)
    }

    @objc private func showOptions() {
        guard let options = representedOptions, !options.isEmpty else { return }
        let visibleRows = min(options.count, 7)
        let viewportHeight = CGFloat(visibleRows * 48 + 20)
        let centeringPadding = max((viewportHeight - 42) / 2, 10)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(
            top: centeringPadding,
            left: 10,
            bottom: centeringPadding,
            right: 10
        )
        stack.frame = NSRect(
            x: 0,
            y: 0,
            width: 400,
            height: CGFloat(options.count * 48) + (centeringPadding * 2)
        )
        stack.autoresizingMask = [.width]

        let popover = NSPopover()
        var selectedButton: NSButton?
        var previousButton: NSButton?
        var insertedGroupSpacing = false
        for option in options {
            let isPreferred = option.descriptor.isMainWorktree || option.isContextThread
            if !isPreferred, !insertedGroupSpacing, let previousButton {
                stack.setCustomSpacing(16, after: previousButton)
                insertedGroupSpacing = true
            }

            let optionButton = ThreadCreationSourceOptionButton(
                option: option,
                showThreadIcons: showThreadIcons
            )
            optionButton.onSelect = { [weak self, weak popover] in
                popover?.performClose(nil)
                self?.onSelect?(option)
            }
            stack.addArrangedSubview(optionButton)
            optionButton.widthAnchor.constraint(equalToConstant: 380).isActive = true
            if option.descriptor.threadID == selectedThreadID {
                selectedButton = optionButton
            }
            previousButton = optionButton
        }
        let groupSpacing: CGFloat = insertedGroupSpacing ? 10 : 0
        stack.frame.size.height = CGFloat(options.count * 48)
            + (centeringPadding * 2)
            + groupSpacing

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = options.count > 7
        scrollView.autohidesScrollers = true
        scrollView.documentView = stack

        let controller = NSViewController()
        controller.view = scrollView
        controller.preferredContentSize = NSSize(
            width: 400,
            height: viewportHeight
        )
        popover.contentViewController = controller
        popover.behavior = .transient
        self.popover = popover
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        center(selectedButton: selectedButton, in: scrollView, contentView: stack)
    }

    private func center(
        selectedButton: NSButton?,
        in scrollView: NSScrollView,
        contentView: NSView
    ) {
        guard let selectedButton else { return }
        DispatchQueue.main.async {
            contentView.layoutSubtreeIfNeeded()
            scrollView.layoutSubtreeIfNeeded()
            let buttonFrame = selectedButton.convert(selectedButton.bounds, to: contentView)
            let originY = ThreadCreationSourcePickerScrollGeometry.centeredOrigin(
                itemMidY: buttonFrame.midY,
                viewportHeight: scrollView.contentView.bounds.height,
                contentHeight: contentView.bounds.height
            )
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: originY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    private var representedOptions: [ThreadCreationSourceOption]?

    func setOptions(_ options: [ThreadCreationSourceOption]) {
        representedOptions = options
    }
}
