import Cocoa
import MagentCore

private final class ActivityProgressIndicatorView: NSView {
    private let indicatorLayer = CAShapeLayer()
    private static let rotationKey = "activity-progress-rotation"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        indicatorLayer.fillColor = NSColor.clear.cgColor
        indicatorLayer.lineWidth = 1.5
        indicatorLayer.lineCap = .round
        indicatorLayer.strokeStart = 0
        indicatorLayer.strokeEnd = 0.72
        layer?.addSublayer(indicatorLayer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        indicatorLayer.frame = bounds
        indicatorLayer.path = CGPath(
            ellipseIn: bounds.insetBy(dx: 1.25, dy: 1.25),
            transform: nil
        )
    }

    func setColor(_ color: NSColor) {
        indicatorLayer.strokeColor = color.cgColor
    }

    func startAnimation() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              indicatorLayer.animation(forKey: Self.rotationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = CGFloat.pi * 2
        animation.duration = 0.8
        animation.repeatCount = .infinity
        indicatorLayer.add(animation, forKey: Self.rotationKey)
    }

    func stopAnimation() {
        indicatorLayer.removeAnimation(forKey: Self.rotationKey)
    }
}

/// A compact, borderless priority indicator.
private final class PriorityIndicatorView: RightClickMenuView {
    let label: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        tf.backgroundColor = .clear
        tf.isBordered = false
        tf.isEditable = false
        tf.lineBreakMode = .byClipping
        tf.maximumNumberOfLines = 1
        tf.setContentHuggingPriority(.required, for: .horizontal)
        tf.setContentCompressionResistancePriority(.required, for: .horizontal)
        return tf
    }()
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

}

/// A flat status item used in the capsule's status row.
/// Hosts either a text label or an icon image view (or both).
private final class TopBorderBadge: RightClickMenuView {
    let label: NSTextField = {
        let tf = NSTextField(labelWithString: "")
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.font = .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        tf.lineBreakMode = .byClipping
        tf.maximumNumberOfLines = 1
        tf.setContentHuggingPriority(.required, for: .horizontal)
        tf.setContentCompressionResistancePriority(.required, for: .horizontal)
        tf.backgroundColor = .clear
        tf.isBordered = false
        tf.isEditable = false
        return tf
    }()

    let iconView: NSImageView = {
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.setContentHuggingPriority(.required, for: .horizontal)
        iv.setContentCompressionResistancePriority(.required, for: .horizontal)
        iv.isHidden = true
        return iv
    }()

    let progressIndicator: ActivityProgressIndicatorView = {
        let indicator = ActivityProgressIndicatorView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.setContentHuggingPriority(.required, for: .horizontal)
        indicator.setContentCompressionResistancePriority(.required, for: .horizontal)
        indicator.isHidden = true
        return indicator
    }()

    private let cornerDot: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.isHidden = true
        return view
    }()

    private let contentStack: NSStackView
    private var contentEdgeConstraints: [NSLayoutConstraint] = []
    private var iconSizeConstraints: [NSLayoutConstraint] = []

    override init(frame frameRect: NSRect) {
        contentStack = NSStackView(views: [])
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = 3
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(progressIndicator)
        contentStack.addArrangedSubview(label)
        addSubview(contentStack)
        addSubview(cornerDot)

        contentEdgeConstraints = [
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        iconSizeConstraints = [
            iconView.widthAnchor.constraint(equalToConstant: ThreadRowBadgeLayout.standardStatusIconSize),
            iconView.heightAnchor.constraint(equalToConstant: ThreadRowBadgeLayout.standardStatusIconSize),
        ]
        NSLayoutConstraint.activate(contentEdgeConstraints + iconSizeConstraints + [
            progressIndicator.widthAnchor.constraint(equalToConstant: ThreadRowBadgeLayout.compactLeadingStatusIconSize),
            progressIndicator.heightAnchor.constraint(equalToConstant: ThreadRowBadgeLayout.compactLeadingStatusIconSize),
            cornerDot.widthAnchor.constraint(equalToConstant: 2),
            cornerDot.heightAnchor.constraint(equalToConstant: 2),
            cornerDot.trailingAnchor.constraint(equalTo: trailingAnchor),
            cornerDot.topAnchor.constraint(equalTo: topAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateColors(appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.clear.cgColor
            self.layer?.borderColor = NSColor.clear.cgColor
            self.layer?.borderWidth = 0
            self.label.textColor = NSColor.secondaryLabelColor
            self.cornerDot.layer?.backgroundColor = NSColor.systemRed.cgColor
            self.cornerDot.layer?.cornerRadius = 1
        }
    }

    func setCornerDotVisible(_ isVisible: Bool) {
        cornerDot.isHidden = !isVisible
    }

    func setContentInsets(horizontal: CGFloat, vertical: CGFloat) {
        contentEdgeConstraints[0].constant = horizontal
        contentEdgeConstraints[1].constant = -horizontal
        contentEdgeConstraints[2].constant = vertical
        contentEdgeConstraints[3].constant = -vertical
    }

    func setIconSize(_ size: CGFloat) {
        iconSizeConstraints.forEach { $0.constant = size }
    }
}

private final class TextBaselineImageView: NSImageView {
    override var baselineOffsetFromBottom: CGFloat { 0 }
}

final class ThreadCell: NSTableCellView {

    // MARK: - SF Symbol Cache

    /// Caches SF Symbol NSImages to avoid repeated allocation during cell reconfiguration.
    /// Keyed by symbol name. Thread-safe via main-thread-only access (NSTableCellView).
    private static var symbolImageCache: [String: NSImage] = [:]

    static func cachedSymbolImage(_ name: String) -> NSImage? {
        if let cached = symbolImageCache[name] { return cached }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        symbolImageCache[name] = image
        return image
    }

    /// Returns the Jira brand icon if available in the asset catalog, otherwise the "ticket" SF Symbol.
    static func jiraMarkerImage() -> NSImage? {
        if let cached = symbolImageCache["_jiraMarker"] { return cached }
        let image: NSImage?
        if let jiraIcon = NSImage(named: NSImage.Name("JiraIcon")) {
            let sized = (jiraIcon.copy() as? NSImage) ?? jiraIcon
            sized.size = NSSize(width: jiraMarkerWidth, height: jiraMarkerWidth)
            sized.isTemplate = false
            image = sized
        } else {
            image = cachedSymbolImage("ticket")
        }
        if let image { symbolImageCache["_jiraMarker"] = image }
        return image
    }

    /// Returns a larger Jira brand icon for the top-border badge. Cached separately
    /// from `jiraMarkerImage()` so the inline 10pt marker instance isn't resized.
    static func jiraBadgeIconImage() -> NSImage? {
        if let cached = symbolImageCache["_jiraBadge"] { return cached }
        let image: NSImage?
        if let jiraIcon = NSImage(named: NSImage.Name("JiraIcon")) {
            let sized = (jiraIcon.copy() as? NSImage) ?? jiraIcon
            sized.size = NSSize(width: jiraBadgeIconSize, height: jiraBadgeIconSize)
            sized.isTemplate = false
            image = sized
        } else {
            image = cachedSymbolImage("ticket")
        }
        if let image { symbolImageCache["_jiraBadge"] = image }
        return image
    }

    // MARK: - Constants

    private static let leadingIconSize: CGFloat = 16
    private static let dirtyDotSize: CGFloat = 7
    private static let jiraMarkerWidth: CGFloat = 10
    private static let jiraBadgeIconSize: CGFloat = 13
    private static let pinMarkerWidth: CGFloat = 12
    private static let archiveMarkerWidth: CGFloat = 12
    private static let trailingMarkerSpacing: CGFloat = 4
    private static let contentTopInset: CGFloat =
        AlwaysEmphasizedRowView.capsuleVerticalInset
        + AlwaysEmphasizedRowView.capsuleBorderInset
        + ThreadRowBadgeLayout.topContentPadding
    private static let contentBottomInset: CGFloat =
        AlwaysEmphasizedRowView.capsuleVerticalInset
        + AlwaysEmphasizedRowView.capsuleBorderInset
        + ThreadRowBadgeLayout.bottomContentPadding

    private var subtitleLabel: NSTextField?
    private var jiraStatusBadge: StatusBadgeView?
    private var prStatusBadge: StatusBadgeView?
    private var primaryDirtyDot: NSImageView?
    private var secondaryDirtyDot: NSImageView?
    private var inlineMainIconView: NSImageView?
    private var inlineMainIconWidthConstraint: NSLayoutConstraint?
    private var inlineMainIconHeightConstraint: NSLayoutConstraint?
    private var popoutImageView: NSImageView?
    private var pinImageView: NSImageView?
    private(set) var archiveButton: NSButton?
    private var trailingStackView: NSStackView?
    private var trailingStackCenterYConstraint: NSLayoutConstraint?
    private weak var secondaryRowStack: NSStackView?
    private weak var statusRowStack: NSStackView?
    private weak var contentStack: NSStackView?
    private var leadingStackConstraint: NSLayoutConstraint?
    private var durationLabel: NSTextField?
    private var durationTimer: Timer?
    private var currentDurationSince: Date?
    private var isCurrentDurationBusy = false
    /// 5-dot priority capsule rendered first in the leading workflow-status group.
    /// Hidden (detached from the stack) when the thread has no priority set.
    private var priorityCapsule: PriorityIndicatorView?
    private var claudeRateLimitBadge: TopBorderBadge?
    private var codexRateLimitBadge: TopBorderBadge?
    private var keepAliveBadge: TopBorderBadge?
    private var favoriteBadge: TopBorderBadge?
    private var pinnedBadge: TopBorderBadge?
    private var hiddenBadge: TopBorderBadge?
    private var stoppedSessionsBadge: TopBorderBadge?
    private var jiraSyncBadge: TopBorderBadge?
    private var hasInstalledTextTrailingConstraint = false
    private var isConfiguredAsMain = false
    private var isConfiguredThreadHidden = false
    private var showsRenamePulse = false
    private var hasUnreadCompletion = false
    private var hasWaitingForInput = false
    private var hasAllDead = false
    private var configuredSectionColor: NSColor?
    private var highlightedTicketField: NSTextField?
    private var highlightedTicketKey: String?
    private var highlightedTicketBaseColor: NSColor?

    private static let renamePulseAnimationKey = "rename-label-pulse"

    var onArchive: (() -> Void)?
    var priorityMenuProvider: (() -> NSMenu)?
    var pullRequestMenuProvider: (() -> NSMenu?)?
    var jiraMenuProvider: (() -> NSMenu?)?
    var onUnpin: (() -> Void)?
    var onRemoveFavorite: (() -> Void)?
    var onToggleHidden: (() -> Void)?

    private static func descriptionFont() -> NSFont {
        .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    }

    private static func metadataFont() -> NSFont {
        .systemFont(ofSize: 10)
    }

    private static func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    static func uniformSidebarRowHeight(maxDescriptionLines: Int, narrowThreads: Bool = false) -> CGFloat {
        sidebarRowHeight(descriptionLines: max(1, maxDescriptionLines), hasSubtitle: true, narrowThreads: narrowThreads)
    }

    /// Estimate how many lines the description text will occupy given available width.
    static func estimatedDescriptionLineCount(text: String, maxLines: Int, availableWidth: CGFloat) -> Int {
        let font = descriptionFont()
        let textWidth = (text as NSString).size(withAttributes: [.font: font]).width
        let lines = max(1, Int(ceil(textWidth / max(1, availableWidth))))
        return min(lines, max(1, maxLines))
    }

    /// Minimum content height: configured description lines plus the status row.
    static func minimumContentHeight(narrowThreads: Bool) -> CGFloat {
        let descLines = narrowThreads ? 1 : 2
        let minBlock = lineHeight(for: descriptionFont()) * CGFloat(descLines)
            + ThreadRowBadgeLayout.statusRowHeight
            + ThreadRowBadgeLayout.textToStatusRowSpacing
        return max(leadingIconSize, minBlock)
    }

    /// Compute row height based on actual visible content lines.
    static func sidebarRowHeight(
        descriptionLines: Int,
        hasSubtitle: Bool,
        narrowThreads: Bool = false
    ) -> CGFloat {
        let descHeight = lineHeight(for: descriptionFont()) * CGFloat(max(1, descriptionLines))
        var titleBlockHeight = descHeight
        if hasSubtitle {
            titleBlockHeight += lineHeight(for: metadataFont()) + ThreadRowBadgeLayout.titleToSubtitleSpacing
        }
        titleBlockHeight += ThreadRowBadgeLayout.statusRowHeight
            + ThreadRowBadgeLayout.textToStatusRowSpacing
        let contentHeight = max(leadingIconSize, titleBlockHeight, minimumContentHeight(narrowThreads: narrowThreads))
        return ceil(contentHeight + contentTopInset + contentBottomInset)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }


    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateMainTextColorForSelection()
            updateMainIconTintForSelection()
            updateTopBorderBadgeColors()
            updateLeadingIconTint()
            updateDirtyDotColors()
            updateBranchTicketHighlightAppearance()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, showsRenamePulse {
            applyRenamePulse(true)
        }
    }

    /// Reparents imageView and textField into a horizontal stack.
    /// The first row shows the description/name; the second row shows branch/worktree metadata.
    /// Safe to call multiple times — only runs once.
    func ensureLeadingStack() {
        guard primaryDirtyDot == nil, let iv = imageView, let tf = textField else { return }

        let primaryDot = makeDirtyDot()
        let secondaryDot = makeDirtyDot()
        primaryDirtyDot = primaryDot
        secondaryDirtyDot = secondaryDot

        let inlineMainIcon = TextBaselineImageView()
        inlineMainIcon.translatesAutoresizingMaskIntoConstraints = false
        inlineMainIcon.image = Self.cachedSymbolImage("house.fill")
        inlineMainIcon.imageScaling = .scaleProportionallyDown
        inlineMainIcon.setContentHuggingPriority(.required, for: .horizontal)
        inlineMainIcon.setContentCompressionResistancePriority(.required, for: .horizontal)
        inlineMainIcon.isHidden = true
        inlineMainIconView = inlineMainIcon
        let inlineMainIconSize = ThreadRowBadgeLayout.inlineMainWorktreeIconSize(
            titleFont: Self.descriptionFont()
        )
        let inlineMainIconWidthConstraint = inlineMainIcon.widthAnchor.constraint(
            equalToConstant: inlineMainIconSize
        )
        let inlineMainIconHeightConstraint = inlineMainIcon.heightAnchor.constraint(
            equalToConstant: inlineMainIconSize
        )
        self.inlineMainIconWidthConstraint = inlineMainIconWidthConstraint
        self.inlineMainIconHeightConstraint = inlineMainIconHeightConstraint
        NSLayoutConstraint.activate([
            inlineMainIconWidthConstraint,
            inlineMainIconHeightConstraint,
        ])
        updateInlineMainIconSize(titleFont: Self.descriptionFont())

        let subtitle = NSTextField(labelWithString: "")
        subtitle.translatesAutoresizingMaskIntoConstraints = false
        subtitle.font = Self.metadataFont()
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.maximumNumberOfLines = 1
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitle.setContentHuggingPriority(.defaultHigh, for: .vertical)
        subtitle.isHidden = true
        subtitleLabel = subtitle

        let jiraBadge = StatusBadgeView()
        jiraBadge.isHidden = true
        jiraStatusBadge = jiraBadge

        let prBadge = StatusBadgeView()
        prBadge.isHidden = true
        prStatusBadge = prBadge

        iv.removeFromSuperview()
        tf.removeFromSuperview()

        NSLayoutConstraint.activate([
            iv.widthAnchor.constraint(equalToConstant: Self.leadingIconSize),
            iv.heightAnchor.constraint(equalToConstant: Self.leadingIconSize),
        ])

        tf.wantsLayer = true
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configurePrimaryTextFieldLayout(maxLines: 1, wraps: false)

        let titleRow = NSStackView(views: [tf, inlineMainIcon])
        titleRow.orientation = .horizontal
        titleRow.alignment = .firstBaseline
        titleRow.spacing = 4
        titleRow.detachesHiddenViews = true
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let primaryRow = NSStackView(views: [primaryDot, titleRow])
        primaryRow.orientation = .horizontal
        primaryRow.alignment = .centerY
        primaryRow.spacing = 4
        primaryRow.detachesHiddenViews = true
        primaryRow.translatesAutoresizingMaskIntoConstraints = false

        let secondaryRow = NSStackView(views: [secondaryDot, subtitle])
        secondaryRow.orientation = .horizontal
        secondaryRow.alignment = .centerY
        secondaryRow.spacing = 4
        subtitle.alphaValue = ThreadRowContentOpacity.secondaryLine
        secondaryRow.translatesAutoresizingMaskIntoConstraints = false

        let textRowsStack = NSStackView(views: [primaryRow, secondaryRow])
        textRowsStack.orientation = .vertical
        textRowsStack.alignment = .leading
        textRowsStack.spacing = ThreadRowBadgeLayout.titleToSubtitleSpacing
        textRowsStack.detachesHiddenViews = true
        textRowsStack.translatesAutoresizingMaskIntoConstraints = false
        textRowsStack.identifier = NSUserInterfaceItemIdentifier("threadTextRows")

        let statusRow = NSStackView()
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 4
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        statusRow.identifier = NSUserInterfaceItemIdentifier("threadStatusRow")
        statusRow.heightAnchor.constraint(equalToConstant: ThreadRowBadgeLayout.statusRowHeight).isActive = true

        let verticalStack = NSStackView(views: [textRowsStack, statusRow])
        verticalStack.orientation = .vertical
        verticalStack.alignment = .leading
        verticalStack.spacing = ThreadRowBadgeLayout.titleToSubtitleSpacing
        verticalStack.setCustomSpacing(ThreadRowBadgeLayout.textToStatusRowSpacing, after: textRowsStack)
        verticalStack.detachesHiddenViews = true
        verticalStack.translatesAutoresizingMaskIntoConstraints = false
        verticalStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        verticalStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        secondaryRowStack = secondaryRow
        statusRowStack = statusRow
        contentStack = verticalStack
        let stack = NSStackView(views: [iv, verticalStack])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.alignment = .centerY
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        if let trailingStackView {
            trailingStackCenterYConstraint?.isActive = false
            let centerConstraint = switch ThreadRowBadgeLayout.trailingMarkerVerticalAnchor {
            case .textRows:
                trailingStackView.centerYAnchor.constraint(equalTo: textRowsStack.centerYAnchor)
            }
            centerConstraint.isActive = true
            trailingStackCenterYConstraint = centerConstraint
        }

        let statusRowTrailingConstraint = statusRow.trailingAnchor.constraint(
            equalTo: verticalStack.trailingAnchor
        )

        let leadingConstraint = stack.leadingAnchor.constraint(
            equalTo: leadingAnchor,
            constant: ThreadListViewController.sidebarHorizontalInset
        )
        leadingStackConstraint = leadingConstraint

        var constraints = [
            leadingConstraint,
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            verticalStack.topAnchor.constraint(equalTo: topAnchor, constant: Self.contentTopInset),
            verticalStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.contentBottomInset),
            statusRowTrailingConstraint,
        ]
        if let trailingStack = trailingStackView {
            constraints.append(
                textRowsStack.trailingAnchor.constraint(
                    lessThanOrEqualTo: trailingStack.leadingAnchor,
                    constant: -6
                )
            )
            constraints.append(
                verticalStack.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -ThreadListViewController.sidebarTrailingInset
                )
            )
        } else {
            constraints.append(verticalStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -ThreadListViewController.sidebarTrailingInset))
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func setLeadingOffset(_ offset: CGFloat) {
        leadingStackConstraint?.constant = ThreadListViewController.sidebarHorizontalInset + offset
    }

    private func makeDirtyDot() -> NSImageView {
        let dot = NSImageView()
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.setContentHuggingPriority(.required, for: .horizontal)
        dot.setContentCompressionResistancePriority(.required, for: .horizontal)
        dot.isHidden = true
        NSLayoutConstraint.activate([
            dot.widthAnchor.constraint(equalToConstant: Self.dirtyDotSize),
            dot.heightAnchor.constraint(equalToConstant: Self.dirtyDotSize),
        ])
        return dot
    }

    private func setDimmedAppearance(isHidden: Bool, isArchiving: Bool) {
        let dimmed = isHidden || isArchiving
        let contentAlpha = ThreadRowContentOpacity.contentOpacity(isDimmed: dimmed)
        // The status row now follows the same dimming as the rest of the in-capsule content.
        for sub in subviews {
            sub.alphaValue = contentAlpha
        }
        bottomRightBadgeStack?.alphaValue = 1.0
        bottomLeftBadgeStack?.alphaValue = 1.0
        statusRowStack?.alphaValue = 1.0
        subtitleLabel?.alphaValue = ThreadRowContentOpacity.secondaryLine
    }

    private func applyRenamePulse(_ active: Bool) {
        guard let tf = textField else { return }
        tf.layer?.removeAnimation(forKey: Self.renamePulseAnimationKey)
        if active {
            tf.textColor = .appPrimary
            guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                  window != nil else {
                tf.layer?.opacity = 1.0
                return
            }
            let anim = CABasicAnimation(keyPath: "opacity")
            anim.fromValue = 1.0
            anim.toValue = 0.3
            anim.autoreverses = true
            anim.duration = 1.2
            anim.repeatCount = .infinity
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            tf.layer?.add(anim, forKey: Self.renamePulseAnimationKey)
        } else {
            tf.layer?.opacity = 1.0
        }
    }

    private func ensureTrailingStack() {
        guard trailingStackView == nil else { return }

        let popoutIV = NSImageView()
        popoutIV.translatesAutoresizingMaskIntoConstraints = false
        popoutIV.setContentHuggingPriority(.required, for: .horizontal)
        popoutIV.setContentCompressionResistancePriority(.required, for: .horizontal)
        popoutIV.image = Self.cachedSymbolImage("macwindow.on.rectangle")
        popoutIV.contentTintColor = .systemPurple
        popoutIV.toolTip = "Open in separate window"
        popoutIV.isHidden = true

        let pinIV = NSImageView()
        pinIV.translatesAutoresizingMaskIntoConstraints = false
        pinIV.setContentHuggingPriority(.required, for: .horizontal)

        let archiveBtn = NSButton()
        archiveBtn.translatesAutoresizingMaskIntoConstraints = false
        archiveBtn.setContentHuggingPriority(.required, for: .horizontal)
        archiveBtn.isBordered = false
        archiveBtn.image = Self.cachedSymbolImage("archivebox.fill")
        archiveBtn.contentTintColor = .tertiaryLabelColor
        archiveBtn.toolTip = "Work delivered — ready to archive"
        archiveBtn.target = self
        archiveBtn.action = #selector(archiveButtonClicked)
        archiveBtn.isHidden = true
        archiveBtn.identifier = NSUserInterfaceItemIdentifier("threadArchiveButton")

        let stack = NSStackView(views: [archiveBtn, popoutIV, pinIV])
        stack.orientation = .horizontal
        stack.spacing = Self.trailingMarkerSpacing
        stack.distribution = .fill
        stack.alignment = .centerY
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(stack)

        let trailingAlignmentInset = AlwaysEmphasizedRowView.capsuleTrailingInset + AlwaysEmphasizedRowView.capsuleContentHPadding

        let centerConstraint = stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([
            centerConstraint,
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailingAlignmentInset),
            popoutIV.widthAnchor.constraint(equalToConstant: 15),
            popoutIV.heightAnchor.constraint(equalToConstant: 15),
            pinIV.widthAnchor.constraint(equalToConstant: Self.pinMarkerWidth),
            pinIV.heightAnchor.constraint(equalToConstant: Self.pinMarkerWidth),
            archiveBtn.widthAnchor.constraint(equalToConstant: Self.archiveMarkerWidth),
            archiveBtn.heightAnchor.constraint(equalToConstant: Self.archiveMarkerWidth),
        ])
        trailingStackView = stack
        trailingStackCenterYConstraint = centerConstraint
        popoutImageView = popoutIV
        pinImageView = pinIV
        archiveButton = archiveBtn

        if !hasInstalledTextTrailingConstraint {
            hasInstalledTextTrailingConstraint = true
        }
    }

    func configure(
        with thread: MagentThread,
        sectionColor: NSColor?,
        leadingOffset: CGFloat = 0,
        maxDescriptionLines: Int = 2,
        showThreadIcon: Bool = true,
        showWorktreeName: Bool = false,
        isAutoRenaming: Bool = false
    ) {
        isConfiguredAsMain = false
        isConfiguredThreadHidden = thread.isSidebarHidden
        ensureTrailingStack()
        ensureLeadingStack()
        inlineMainIconView?.isHidden = true
        setLeadingOffset(leadingOffset)
        setDimmedAppearance(isHidden: thread.isSidebarHidden, isArchiving: thread.isArchiving)

        let worktreeName = (thread.worktreePath as NSString).lastPathComponent
        let branchName = (thread.actualBranch ?? thread.branchName).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBranchName = branchName.isEmpty ? thread.name : branchName

        let trimmedDescription = thread.taskDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDescription = !(trimmedDescription?.isEmpty ?? true)
        let primaryBaseText = hasDescription ? (trimmedDescription ?? resolvedBranchName) : resolvedBranchName
        let primaryText = ThreadRowBadgeLayout.primaryText(
            primaryBaseText,
            signEmoji: thread.signEmoji
        )
        let clampedDescriptionLines = max(1, maxDescriptionLines)
        let subtitleText = ThreadRowBadgeLayout.subtitleText(
            hasDescription: hasDescription,
            branchName: resolvedBranchName,
            worktreeName: worktreeName,
            showWorktreeName: showWorktreeName
        )
        let branchWorktreeLine = subtitleText ?? resolvedBranchName

        if hasDescription {
            // Keep description wrapping stable across selection/unread state changes.
            textField?.font = Self.descriptionFont()
        } else {
            textField?.font = thread.hasUnreadAgentCompletion
                ? Self.descriptionFont()
                : .preferredFont(forTextStyle: .body)
        }
        let showsJiraState = AppFeatures.jiraSyncEnabled
        let deadSessions = thread.hasAllSessionsDead
        if showsJiraState && thread.jiraUnassigned {
            textField?.textColor = .tertiaryLabelColor
        } else {
            textField?.textColor = .labelColor
        }
        contentStack?.alphaValue = ThreadRowContentOpacity.contentGroupOpacity(isInactive: deadSessions)
        if hasDescription {
            // With description: primary = description, secondary = branch · worktree.
            textField?.stringValue = primaryText
            configurePrimaryTextFieldLayout(
                maxLines: clampedDescriptionLines,
                wraps: clampedDescriptionLines > 1
            )
            subtitleLabel?.stringValue = subtitleText ?? resolvedBranchName
            subtitleLabel?.textColor = showsJiraState && thread.jiraUnassigned ? .tertiaryLabelColor : .secondaryLabelColor
            subtitleLabel?.isHidden = false
            setDirtyDot(primaryDirtyDot, visible: false)
            setDirtyDot(secondaryDirtyDot, visible: thread.isDirty)
        } else {
            // Without description, the optional second line is reserved for the worktree name.
            textField?.stringValue = primaryText
            configurePrimaryTextFieldLayout(maxLines: 1, wraps: false)
            if let subtitleText {
                subtitleLabel?.stringValue = subtitleText
                subtitleLabel?.textColor = .secondaryLabelColor
                subtitleLabel?.isHidden = false
            } else {
                subtitleLabel?.stringValue = ""
                subtitleLabel?.isHidden = true
            }
            setDirtyDot(primaryDirtyDot, visible: thread.isDirty)
            setDirtyDot(secondaryDirtyDot, visible: false)
        }

        // Highlight the detected Jira key in the branch and place PR/Jira state in the status row.
        let cellSettings = PersistenceService.shared.loadSettings()
        let jiraEnabled = cellSettings.jiraIntegrationEnabled && cellSettings.jiraTicketDetectionEnabled
        let ticketKey = jiraEnabled ? thread.effectiveJiraTicketKey(settings: cellSettings) : nil
        let branchTicketKey = jiraEnabled
            ? thread.detectedBranchTicketKey(allowedPrefixes: cellSettings.jiraTicketDetectionPrefixFilterSet)
            : nil
        applyBranchTicketHighlight(
            ticketKey: branchTicketKey,
            branchWorktreeLine: branchWorktreeLine,
            primaryText: primaryText,
            hasDescription: hasDescription
        )
        let badgeFontSize = ThreadRowBadgeLayout.compactTextFontSize
        let showJiraBadges = cellSettings.showJiraStatusBadges
        let showPRBadges = cellSettings.showPRStatusBadges

        if let ticketKey {
            if showJiraBadges, let verified = thread.verifiedJiraTicket, !verified.status.isEmpty {
                jiraStatusBadge?.configure(
                    text: verified.status,
                    style: StatusBadgeView.jiraStyle(forCategoryKey: verified.statusCategoryKey),
                    fontSize: badgeFontSize
                )
                jiraStatusBadge?.isHidden = false
                jiraStatusBadge?.toolTip = String(
                    localized: .ThreadStrings.threadJiraStatusBadgeTooltip(ticketKey, verified.status)
                )
            } else {
                jiraStatusBadge?.isHidden = true
                jiraStatusBadge?.toolTip = nil
            }
        } else {
            jiraStatusBadge?.isHidden = true
            jiraStatusBadge?.toolTip = nil
        }

        if let pr = thread.pullRequestInfo {
            let prAlpha: CGFloat = thread.hasStalePullRequestInfo ? 0.5 : 1.0
            let stalePrefix = thread.hasStalePullRequestInfo
                ? String(localized: .ThreadStrings.threadPullRequestStaleTooltipPrefix) + "\n"
                : ""
            if showPRBadges {
                prStatusBadge?.configure(
                    text: ThreadRowBadgeLayout.pullRequestBadgeText(
                        number: pr.shortLabel,
                        status: pr.statusText
                    ),
                    style: StatusBadgeView.prStyle(for: pr),
                    fontSize: badgeFontSize
                )
                prStatusBadge?.isHidden = false
                prStatusBadge?.alphaValue = prAlpha
                prStatusBadge?.toolTip = stalePrefix + String(
                    localized: .ThreadStrings.threadPullRequestBadgeTooltip(pr.displayLabel, pr.statusText)
                )
            } else {
                prStatusBadge?.isHidden = true
                prStatusBadge?.alphaValue = 1.0
                prStatusBadge?.toolTip = nil
            }
        } else {
            prStatusBadge?.isHidden = true
            prStatusBadge?.alphaValue = 1.0
            prStatusBadge?.toolTip = nil
        }

        let detailedTooltip = buildDetailedTooltip(
            description: trimmedDescription,
            branchName: resolvedBranchName,
            worktreeName: worktreeName,
            prLabel: thread.pullRequestInfo.map { "\($0.displayLabel) (\($0.statusText))" },
            statuses: statusDescriptions(for: thread)
        )
        toolTip = detailedTooltip
        imageView?.toolTip = detailedTooltip
        textField?.toolTip = detailedTooltip
        subtitleLabel?.toolTip = detailedTooltip
        primaryDirtyDot?.toolTip = detailedTooltip
        secondaryDirtyDot?.toolTip = detailedTooltip

        imageView?.image = Self.cachedSymbolImage(thread.threadIcon.symbolName)
            ?? Self.cachedSymbolImage("terminal")
        imageView?.isHidden = !showThreadIcon
        hasUnreadCompletion = thread.hasUnreadAgentCompletion
        hasWaitingForInput = thread.hasWaitingForInput
        hasAllDead = thread.hasAllSessionsDead
        subtitleLabel?.alphaValue = ThreadRowContentOpacity.secondaryLine
        updateStatusItemOpacities()
        configuredSectionColor = sectionColor
        updateLeadingIconTint()


        if thread.isFavorite {
            ensureFavoriteBadge()
            favoriteBadge?.isHidden = false
            favoriteBadge?.toolTip = "Favorite thread"
        } else {
            favoriteBadge?.isHidden = true
            favoriteBadge?.toolTip = nil
        }

        if thread.isPinned {
            ensurePinnedBadge()
            pinnedBadge?.isHidden = false
            pinnedBadge?.toolTip = "Pinned thread"
            pinImageView?.isHidden = true
        } else {
            pinnedBadge?.isHidden = true
            pinnedBadge?.toolTip = nil
            pinImageView?.isHidden = true
        }

        if thread.isSidebarHidden {
            ensureHiddenBadge()
            hiddenBadge?.isHidden = false
            hiddenBadge?.toolTip = "Hidden thread"
        } else {
            hiddenBadge?.isHidden = true
            hiddenBadge?.toolTip = nil
        }

        configureStoppedSessionsBadge(isStopped: deadSessions)

        if thread.syncWithJira {
            ensureJiraSyncBadge()
            jiraSyncBadge?.isHidden = false
            jiraSyncBadge?.toolTip = "Auto-syncing description and priority from Jira"
        } else {
            jiraSyncBadge?.isHidden = true
            jiraSyncBadge?.toolTip = nil
        }
        let showKeepAliveShield = ThreadRowBadgeLayout.showsKeepAliveBadge(
            isKeepAlive: thread.isKeepAlive
        )
        if showKeepAliveShield {
            ensureKeepAliveBadge()
            keepAliveBadge?.toolTip = "Keep Alive — protected from idle eviction"
            keepAliveBadge?.isHidden = false
            if thread.isPinned { ensurePinnedBadge() }
        } else {
            keepAliveBadge?.isHidden = true
            keepAliveBadge?.toolTip = nil
        }

        let isPopout = PopoutWindowManager.shared.isThreadPoppedOut(thread.id)
        popoutImageView?.isHidden = !isPopout

        archiveButton?.isHidden = !thread.showArchiveSuggestion

        // Rate limit uses the trailing agent glyph badge.
        configureRateLimitBadge(
            isExpiredAndResumable: thread.isRateLimitExpiredAndResumable,
            isBlocked: thread.isBlockedByRateLimit,
            isPropagatedOnly: thread.isRateLimitPropagatedOnly,
            tooltip: rateLimitTooltip(for: thread),
            rateLimitedAgentTypes: thread.rateLimitedAgentTypes,
            directlyRateLimitedAgentTypes: thread.directlyRateLimitedAgentTypes
        )

        configureDuration(
            since: cellSettings.showBusyStateDuration ? thread.busyStateSince : nil,
            isBusy: thread.activityDurationState == .busy
        )
        configurePriority(thread.priority)
        updateTrailingStatusOrder()
        updateTopBorderBadgeColors()
        configureInteractiveBadgeMenus()

        syncRowVisibility()
        showsRenamePulse = isAutoRenaming
        applyRenamePulse(isAutoRenaming)
    }

    func configureAsMain(
        isUnreadCompletion: Bool = false,
        isBusy: Bool = false,
        isWaitingForInput: Bool = false,
        isDirty: Bool = false,
        isBlockedByRateLimit: Bool = false,
        isRateLimitExpiredAndResumable: Bool = false,
        isRateLimitPropagatedOnly: Bool = false,
        rateLimitTooltip: String? = nil,
        rateLimitedAgentTypes: Set<AgentType> = [],
        directlyRateLimitedAgentTypes: Set<AgentType> = [],
        currentBranch: String? = nil,
        busyStateSince: Date? = nil,
        leadingOffset: CGFloat = 0,
        showThreadIcon: Bool = true,
        signEmoji: String? = nil,
        hasAllSessionsDead: Bool = false
    ) {
        isConfiguredAsMain = true
        isConfiguredThreadHidden = false
        highlightedTicketField = nil
        highlightedTicketKey = nil
        highlightedTicketBaseColor = nil
        ensureTrailingStack()
        ensureLeadingStack()
        setLeadingOffset(leadingOffset)
        setDimmedAppearance(isHidden: false, isArchiving: false)

        textField?.stringValue = ThreadRowBadgeLayout.primaryText("Main worktree", signEmoji: signEmoji)
        contentStack?.alphaValue = ThreadRowContentOpacity.contentGroupOpacity(isInactive: hasAllSessionsDead)
        textField?.font = .systemFont(
            ofSize: NSFont.systemFontSize,
            weight: isUnreadCompletion ? .bold : .semibold
        )
        updateInlineMainIconSize(titleFont: textField?.font)
        updateMainTextColorForSelection()
        configurePrimaryTextFieldLayout(maxLines: 1, wraps: false)

        pinImageView?.isHidden = true
        popoutImageView?.isHidden = true
        archiveButton?.isHidden = true

        let resolvedBranch = currentBranch?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolvedBranch, !resolvedBranch.isEmpty {
            subtitleLabel?.stringValue = resolvedBranch
            subtitleLabel?.textColor = .secondaryLabelColor
            subtitleLabel?.isHidden = false
        } else {
            subtitleLabel?.stringValue = ""
            subtitleLabel?.isHidden = true
        }

        imageView?.image = nil
        imageView?.image = Self.cachedSymbolImage("house.fill")
        switch ThreadRowBadgeLayout.mainWorktreeIconPlacement(showThreadIcons: showThreadIcon) {
        case .leading:
            imageView?.isHidden = false
            inlineMainIconView?.isHidden = true
        case .inlineAfterTitle:
            imageView?.isHidden = true
            inlineMainIconView?.isHidden = false
        }
        updateMainIconTintForSelection()

        setDirtyDot(primaryDirtyDot, visible: false)
        setDirtyDot(secondaryDirtyDot, visible: isDirty)
        hasAllDead = hasAllSessionsDead
        configureStoppedSessionsBadge(isStopped: hasAllSessionsDead)
        prStatusBadge?.isHidden = true
        jiraStatusBadge?.isHidden = true

        let detailedTooltip = buildDetailedTooltip(
            description: "Main worktree",
            branchName: (resolvedBranch?.isEmpty == false ? resolvedBranch : nil) ?? "Unknown branch",
            worktreeName: "Main worktree",
            prLabel: nil,
            statuses: mainStatusDescriptions(
                isDirty: isDirty,
                isRateLimitExpiredAndResumable: isRateLimitExpiredAndResumable,
                rateLimitTooltip: rateLimitTooltip,
                isBlockedByRateLimit: isBlockedByRateLimit,
                isWaitingForInput: isWaitingForInput,
                isBusy: isBusy,
                isUnreadCompletion: isUnreadCompletion
            )
        )
        toolTip = detailedTooltip
        imageView?.toolTip = detailedTooltip
        inlineMainIconView?.toolTip = detailedTooltip
        textField?.toolTip = detailedTooltip
        subtitleLabel?.toolTip = detailedTooltip
        primaryDirtyDot?.toolTip = detailedTooltip
        secondaryDirtyDot?.toolTip = detailedTooltip

        // Rate limit uses the same trailing agent glyph badge as non-main threads.
        configureRateLimitBadge(
            isExpiredAndResumable: isRateLimitExpiredAndResumable,
            isBlocked: isBlockedByRateLimit,
            isPropagatedOnly: isRateLimitPropagatedOnly,
            tooltip: rateLimitTooltip,
            rateLimitedAgentTypes: rateLimitedAgentTypes,
            directlyRateLimitedAgentTypes: directlyRateLimitedAgentTypes
        )

        let showDuration = PersistenceService.shared.loadSettings().showBusyStateDuration
        configureDuration(since: showDuration ? busyStateSince : nil, isBusy: isBusy)
        // The main worktree row doesn't carry a priority.
        configurePriority(nil)
        updateTrailingStatusOrder()
        updateTopBorderBadgeColors()

        syncRowVisibility()
    }

    private func updateInlineMainIconSize(titleFont: NSFont?) {
        guard let titleFont else { return }
        let size = ThreadRowBadgeLayout.inlineMainWorktreeIconSize(titleFont: titleFont)
        inlineMainIconView?.symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: size,
            weight: .semibold
        )
        inlineMainIconWidthConstraint?.constant = size
        inlineMainIconHeightConstraint?.constant = size
    }

    private func syncRowVisibility() {
        let subtitleVisible = !(subtitleLabel?.isHidden ?? true)
        let secondaryDotVisible = !(secondaryDirtyDot?.isHidden ?? true)
        secondaryRowStack?.isHidden = !subtitleVisible && !secondaryDotVisible

    }

    private func applyBranchTicketHighlight(
        ticketKey: String?,
        branchWorktreeLine: String,
        primaryText: String,
        hasDescription: Bool
    ) {
        let target = hasDescription ? branchWorktreeLine : primaryText
        let field = hasDescription ? subtitleLabel : textField
        highlightedTicketField = field
        highlightedTicketKey = ticketKey
        highlightedTicketBaseColor = field?.textColor
        field?.stringValue = target
        updateBranchTicketHighlightAppearance()
    }

    private func updateBranchTicketHighlightAppearance() {
        guard let field = highlightedTicketField,
              let ticketKey = highlightedTicketKey,
              let font = field.font,
              let baseColor = highlightedTicketBaseColor else { return }
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = field.alignment
        paragraphStyle.lineBreakMode = field.lineBreakMode
        let isDarkSelection = backgroundStyle == .emphasized
            && effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let renderedBaseColor = isDarkSelection ? NSColor.white : baseColor
        guard let attributedText = ThreadRowBadgeLayout.highlightedTicketText(
            field.stringValue,
            ticketKey: ticketKey,
            font: font,
            baseColor: renderedBaseColor,
            highlightColor: NSColor.appPrimary,
            paragraphStyle: paragraphStyle
        ) else { return }
        field.attributedStringValue = attributedText
    }

    private func configurePrimaryTextFieldLayout(maxLines: Int, wraps: Bool) {
        guard let textField else { return }
        textField.maximumNumberOfLines = max(1, maxLines)
        textField.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail

        guard let cell = textField.cell as? NSTextFieldCell else { return }
        cell.wraps = wraps
        // Multi-line descriptions should wrap and show an ellipsis on overflow.
        cell.truncatesLastVisibleLine = wraps
        cell.usesSingleLineMode = !wraps
    }

    // MARK: - Rate limit badge

    /// Shows/hides one trailing rate-limit icon per rate-limited agent type.
    private func configureRateLimitBadge(
        isExpiredAndResumable: Bool,
        isBlocked: Bool,
        isPropagatedOnly: Bool,
        tooltip: String?,
        rateLimitedAgentTypes: Set<AgentType> = [],
        directlyRateLimitedAgentTypes: Set<AgentType> = []
    ) {
        let showBadge = isExpiredAndResumable || isBlocked
        guard showBadge else {
            claudeRateLimitBadge?.isHidden = true
            claudeRateLimitBadge?.setCornerDotVisible(false)
            codexRateLimitBadge?.isHidden = true
            codexRateLimitBadge?.setCornerDotVisible(false)
            return
        }

        // When we know the agent types, show one badge per agent.
        // Fall back to showing a single Claude badge when agent type is unknown.
        let agentsToShow: [AgentType] = rateLimitedAgentTypes.isEmpty
            ? [.claude]
            : AgentType.allCases.filter { rateLimitedAgentTypes.contains($0) && $0 != .custom }

        for agent in [AgentType.claude, .codex] {
            let badge = ensureRateLimitBadge(for: agent)
            guard agentsToShow.contains(agent) else {
                badge.isHidden = true
                badge.setCornerDotVisible(false)
                continue
            }

            badge.label.isHidden = true
            badge.iconView.isHidden = false
            badge.iconView.image = Self.agentIconImage(for: agent)

            if isExpiredAndResumable {
                badge.iconView.contentTintColor = .systemGreen
                badge.toolTip = "\(agent.displayName) rate limit lifted — ready to resume"
            } else {
                badge.iconView.contentTintColor = .systemRed
                badge.toolTip = tooltip.map { "\(agent.displayName): \($0)" }
                    ?? "\(agent.displayName) rate limit reached"
            }
            badge.isHidden = false
            badge.setCornerDotVisible(directlyRateLimitedAgentTypes.contains(agent))
        }
        updateTopBorderBadgeColors()
    }

    // MARK: - Bottom metadata badges

    private static func durationFont() -> NSFont {
        .monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    }

    private var durationBadge: TopBorderBadge?
    /// Holds workflow metadata on the leading side of the status row.
    private weak var bottomLeftBadgeStack: NSStackView?
    /// Holds local state indicators on the trailing side of the status row.
    private var bottomRightBadgeStack: NSStackView?

    private func ensureBottomRightBadgeStack() {
        guard bottomRightBadgeStack == nil else { return }
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        statusRowStack?.addArrangedSubview(stack)
        bottomRightBadgeStack = stack
    }

    @discardableResult
    private func ensureRateLimitBadge(for agent: AgentType) -> TopBorderBadge {
        switch agent {
        case .claude:
            if let existing = claudeRateLimitBadge { return existing }
        case .codex:
            if let existing = codexRateLimitBadge { return existing }
        case .custom:
            if let existing = claudeRateLimitBadge { return existing }
        }

        ensureBottomRightBadgeStack()
        let badge = TopBorderBadge()
        badge.label.isHidden = true
        badge.isHidden = true
        bottomRightBadgeStack?.insertArrangedSubview(badge, at: 0)

        switch agent {
        case .claude, .custom:
            claudeRateLimitBadge = badge
        case .codex:
            codexRateLimitBadge = badge
        }
        return badge
    }

    private static func agentIconImage(for agent: AgentType) -> NSImage? {
        switch agent {
        case .claude, .custom:
            return NSImage(resource: .claudeIcon)
        case .codex:
            return NSImage(resource: .codexIcon)
        }
    }

    private func ensureDurationLabel() {
        guard durationLabel == nil else { return }

        let badge = TopBorderBadge()
        badge.iconView.isHidden = true
        badge.progressIndicator.isHidden = true
        badge.isHidden = true
        badge.label.isHidden = true
        badge.setIconSize(ThreadRowBadgeLayout.compactLeadingStatusIconSize)

        let capsule = PriorityIndicatorView()
        capsule.label.font = Self.priorityDotsFont()
        capsule.isHidden = true

        let stack = NSStackView(views: [capsule])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.detachesHiddenViews = true
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.setContentCompressionResistancePriority(.required, for: .horizontal)
        if let statusRowStack {
            statusRowStack.insertArrangedSubview(stack, at: 0)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            statusRowStack.insertArrangedSubview(spacer, at: 1)
        }

        bottomLeftBadgeStack = stack
        durationBadge = badge
        durationLabel = badge.label
        priorityCapsule = capsule

        ensureBottomRightBadgeStack()
        bottomRightBadgeStack?.addArrangedSubview(badge)

        updateTopBorderBadgeColors()
    }

    private static func priorityDotsFont() -> NSFont {
        // Monospaced so the dot string always occupies the same width regardless of level.
        .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
    }

    private enum PriorityLevel: Int {
        case lowest = 1, low, medium, high, highest

        init(raw: Int) {
            self = PriorityLevel(rawValue: raw) ?? .highest
        }

        /// Tint color for the priority capsule label.
        /// systemYellow is invisible on white, so medium maps to systemOrange in light mode.
        func tintColor(isDark: Bool) -> NSColor {
            switch self {
            case .lowest:  return NSColor.systemBlue.withAlphaComponent(isDark ? 0.75 : 1.0)
            case .low:     return NSColor.systemGreen.withAlphaComponent(isDark ? 0.80 : 1.0)
            case .medium:  return isDark ? NSColor.systemYellow.withAlphaComponent(0.80) : NSColor.systemOrange
            case .high:    return NSColor.systemOrange.withAlphaComponent(isDark ? 0.80 : 1.0)
            case .highest: return NSColor.systemRed.withAlphaComponent(isDark ? 0.75 : 1.0)
            }
        }
    }

    private static func priorityTintColor(forLevel level: Int, isDark: Bool) -> NSColor {
        PriorityLevel(raw: level).tintColor(isDark: isDark)
    }

    /// Builds the 5-character cumulative dot string for a given priority level.
    /// ●○○○○, ●●○○○, ●●●○○, ●●●●○, ●●●●●. Empty string for `nil`/out-of-range.
    private static func priorityDotsString(forLevel level: Int) -> String {
        let filled = max(0, min(5, level))
        return String(repeating: "●", count: filled) + String(repeating: "○", count: 5 - filled)
    }

    private static func priorityLabel(forLevel level: Int) -> String {
        switch level {
        case 1: return "Lowest"
        case 2: return "Low"
        case 3: return "Medium"
        case 4: return "High"
        default: return "Highest"
        }
    }

    private func configurePriority(_ priority: Int?) {
        ensureDurationLabel()
        guard let capsule = priorityCapsule else { return }
        guard let priority, (1...5).contains(priority) else {
            capsule.label.stringValue = ""
            capsule.isHidden = true
            capsule.toolTip = nil
            return
        }
        capsule.label.stringValue = Self.priorityDotsString(forLevel: priority)
        let isDarkForPriority = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        capsule.label.textColor = Self.priorityTintColor(forLevel: priority, isDark: isDarkForPriority)
        capsule.isHidden = false
        capsule.toolTip = "Priority \(priority): \(Self.priorityLabel(forLevel: priority))"
        capsule.needsDisplay = true
    }

    private func configureInteractiveBadgeMenus() {
        priorityCapsule?.contextualMenuProvider = { [weak self] in
            self?.priorityMenuProvider?() ?? NSMenu()
        }
        favoriteBadge?.contextualMenuProvider = { [weak self] in
            self?.singleActionMenu(
                title: String(localized: .ThreadStrings.threadRemoveFromFavorites),
                action: #selector(ThreadCell.removeFavoriteFromBadge)
            ) ?? NSMenu()
        }
        pinnedBadge?.contextualMenuProvider = { [weak self] in
            self?.singleActionMenu(title: String(localized: .CommonStrings.commonUnpin), action: #selector(ThreadCell.unpinFromBadge)) ?? NSMenu()
        }
        hiddenBadge?.contextualMenuProvider = { [weak self] in
            self?.singleActionMenu(title: String(localized: .CommonStrings.commonUnhide), action: #selector(ThreadCell.toggleHiddenFromBadge)) ?? NSMenu()
        }
        prStatusBadge?.contextualMenuProvider = { [weak self] in
            self?.pullRequestMenuProvider?()
        }
        jiraStatusBadge?.contextualMenuProvider = { [weak self] in
            self?.jiraMenuProvider?()
        }
        durationBadge?.contextualMenuProvider = { [weak self] in
            guard let self,
                  self.durationBadge?.isHidden == false,
                  let text = self.durationBadge?.toolTip,
                  !text.isEmpty else { return nil }
            let menu = NSMenu()
            menu.addItem(.sectionHeader(title: text))
            let actions = ThreadRowBadgeLayout.activityBadgeMenuActions(
                isBusy: self.isCurrentDurationBusy,
                isMainWorktree: self.isConfiguredAsMain
            )
            var actionItems: [NSMenuItem] = []
            for action in actions {
                switch action {
                case .toggleHidden where self.onToggleHidden != nil:
                    let title = self.isConfiguredThreadHidden
                        ? String(localized: .CommonStrings.commonUnhide)
                        : String(localized: .CommonStrings.commonHide)
                    let hideItem = NSMenuItem(
                        title: title,
                        action: #selector(toggleHiddenFromBadge),
                        keyEquivalent: ""
                    )
                    hideItem.target = self
                    hideItem.image = ThreadContextMenuItemPresentation.hiddenStateImage(
                        isHidden: self.isConfiguredThreadHidden
                    )
                    actionItems.append(hideItem)
                case .archive where self.onArchive != nil:
                    let archiveItem = NSMenuItem(
                        title: String(localized: .ThreadStrings.threadArchiveMenuTitle),
                        action: #selector(archiveButtonClicked),
                        keyEquivalent: ""
                    )
                    archiveItem.target = self
                    archiveItem.image = ThreadContextMenuItemPresentation.archiveImage
                    actionItems.append(archiveItem)
                case .toggleHidden, .archive:
                    break
                }
            }
            if !actionItems.isEmpty {
                menu.addItem(.separator())
                actionItems.forEach { menu.addItem($0) }
            }
            return menu
        }
    }

    private func singleActionMenu(title: String, action: Selector) -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc private func removeFavoriteFromBadge() {
        onRemoveFavorite?()
    }

    @objc private func unpinFromBadge() {
        onUnpin?()
    }

    @objc private func toggleHiddenFromBadge() {
        onToggleHidden?()
    }

    private func ensureKeepAliveBadge() {
        guard keepAliveBadge == nil else { return }
        ensureBottomRightBadgeStack()
        let badge = TopBorderBadge()
        badge.label.isHidden = true
        badge.iconView.image = Self.cachedSymbolImage("shield.righthalf.filled")
        badge.iconView.contentTintColor = .systemCyan
        badge.iconView.isHidden = false
        badge.isHidden = true
        bottomRightBadgeStack?.addArrangedSubview(badge)
        keepAliveBadge = badge
    }

    private func ensureFavoriteBadge() {
        if favoriteBadge == nil {
            let badge = TopBorderBadge()
            badge.label.isHidden = true
            badge.iconView.image = Self.cachedSymbolImage("heart.fill")
            badge.iconView.imageAlignment = .alignCenter
            badge.iconView.imageScaling = .scaleProportionallyDown
            badge.setIconSize(ThreadRowBadgeLayout.compactLeadingStatusIconSize)
            badge.iconView.contentTintColor = NSColor.appPrimary
            badge.iconView.isHidden = false
            badge.isHidden = true
            favoriteBadge = badge
        }
    }

    private func ensurePinnedBadge() {
        if pinnedBadge == nil {
            let badge = TopBorderBadge()
            badge.label.isHidden = true
            badge.iconView.image = Self.cachedSymbolImage("pin.fill")
            badge.iconView.imageAlignment = .alignCenter
            badge.iconView.imageScaling = .scaleProportionallyDown
            badge.setIconSize(ThreadRowBadgeLayout.compactLeadingStatusIconSize)
            badge.iconView.contentTintColor = NSColor.appPrimary
            badge.iconView.isHidden = false
            badge.isHidden = true
            pinnedBadge = badge
        }
    }

    private func ensureHiddenBadge() {
        if hiddenBadge == nil {
            let badge = TopBorderBadge()
            badge.label.isHidden = true
            badge.iconView.image = Self.cachedSymbolImage("eye.slash.fill")
            badge.iconView.imageAlignment = .alignCenter
            badge.iconView.imageScaling = .scaleProportionallyDown
            badge.iconView.contentTintColor = .secondaryLabelColor
            badge.iconView.isHidden = false
            badge.isHidden = true
            hiddenBadge = badge
        }
    }

    private func ensureStoppedSessionsBadge() {
        if stoppedSessionsBadge == nil {
            let badge = TopBorderBadge()
            badge.label.isHidden = true
            badge.iconView.image = Self.cachedSymbolImage(
                ThreadRowBadgeLayout.stoppedSessionsBadge.symbolName
            )
            badge.iconView.imageAlignment = .alignCenter
            badge.iconView.imageScaling = .scaleProportionallyDown
            badge.iconView.isHidden = false
            badge.isHidden = true
            stoppedSessionsBadge = badge
        }
    }

    private func configureStoppedSessionsBadge(isStopped: Bool) {
        if isStopped {
            ensureStoppedSessionsBadge()
            stoppedSessionsBadge?.isHidden = false
            stoppedSessionsBadge?.toolTip = String(localized: .ThreadStrings.threadSessionsStoppedTooltip)
        } else {
            stoppedSessionsBadge?.isHidden = true
            stoppedSessionsBadge?.toolTip = nil
        }
    }

    private func ensureJiraSyncBadge() {
        ensureBottomRightBadgeStack()
        if jiraSyncBadge == nil {
            let badge = TopBorderBadge()
            badge.label.isHidden = true
            badge.iconView.image = Self.jiraBadgeIconImage()
            // Brand asset — do NOT set contentTintColor or the colored mark
            // would render as a monochrome silhouette.
            badge.iconView.contentTintColor = nil
            badge.iconView.isHidden = false
            badge.isHidden = true
            jiraSyncBadge = badge
        }
        if let badge = jiraSyncBadge, badge.superview !== bottomRightBadgeStack {
            bottomRightBadgeStack?.addArrangedSubview(badge)
        }
    }

    private func updateTrailingStatusOrder() {
        guard let leadingStack = bottomLeftBadgeStack,
              let trailingStack = bottomRightBadgeStack else { return }

        let leadingItems = ThreadRowBadgeLayout.LeadingStatusItem.allCases.compactMap { item -> NSView? in
            switch item {
            case .priority: priorityCapsule
            case .jiraStatus: jiraStatusBadge
            case .pullRequestStatus: prStatusBadge
            }
        }
        let trailingItems = ThreadRowBadgeLayout.TrailingStatusItem.allCases.flatMap { item -> [NSView] in
            switch item {
            case .rateLimit: [claudeRateLimitBadge, codexRateLimitBadge].compactMap { $0 }
            case .jiraSync: [jiraSyncBadge].compactMap { $0 }
            case .keepAlive: [keepAliveBadge].compactMap { $0 }
            case .stoppedSessions: [stoppedSessionsBadge].compactMap { $0 }
            case .hidden: [hiddenBadge].compactMap { $0 }
            case .pinned: [pinnedBadge].compactMap { $0 }
            case .favorite: [favoriteBadge].compactMap { $0 }
            case .activityDuration: [durationBadge].compactMap { $0 }
            }
        }
        let statusItems = leadingItems + trailingItems

        for item in statusItems {
            (item.superview as? NSStackView)?.removeArrangedSubview(item)
            item.removeFromSuperview()
        }
        for item in leadingItems {
            leadingStack.addArrangedSubview(item)
        }
        for item in trailingItems {
            trailingStack.addArrangedSubview(item)
        }
    }

    private func updateTopBorderBadgeColors() {
        durationBadge?.updateColors(appearance: effectiveAppearance)
        updateDurationBadgeColors()
        claudeRateLimitBadge?.updateColors(appearance: effectiveAppearance)
        codexRateLimitBadge?.updateColors(appearance: effectiveAppearance)
        keepAliveBadge?.updateColors(appearance: effectiveAppearance)
        favoriteBadge?.updateColors(appearance: effectiveAppearance)
        pinnedBadge?.updateColors(appearance: effectiveAppearance)
        hiddenBadge?.updateColors(appearance: effectiveAppearance)
        stoppedSessionsBadge?.updateColors(appearance: effectiveAppearance)
        jiraSyncBadge?.updateColors(appearance: effectiveAppearance)
        let descriptionColor = textField?.textColor ?? .labelColor
        favoriteBadge?.iconView.contentTintColor = descriptionColor
        pinnedBadge?.iconView.contentTintColor = descriptionColor
        hiddenBadge?.iconView.contentTintColor = descriptionColor
        let stoppedSessionsColor: NSColor = switch ThreadRowBadgeLayout.stoppedSessionsBadge.tone {
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .red: .systemRed
        }
        stoppedSessionsBadge?.iconView.contentTintColor = BadgeForegroundStyle.color(
            tintColor: stoppedSessionsColor,
            appearance: effectiveAppearance
        )
        updateStatusItemOpacities()
        if let popout = popoutImageView {
            popout.contentTintColor = .systemPurple
        }
    }

    private func updateStatusItemOpacities() {
        statusRowStack?.alphaValue = 1
        bottomRightBadgeStack?.alphaValue = 1
        priorityCapsule?.alphaValue = 1
        favoriteBadge?.alphaValue = 1
        pinnedBadge?.alphaValue = 1
        hiddenBadge?.alphaValue = 1
        stoppedSessionsBadge?.alphaValue = 1
    }


    private func configureDuration(since: Date?, isBusy: Bool) {
        ensureDurationLabel()
        currentDurationSince = since
        isCurrentDurationBusy = isBusy
        if let since {
            refreshDurationText(since: since)
            updateDurationPresentation()
            startDurationTimer()
        } else {
            durationLabel?.stringValue = ""
            durationLabel?.isHidden = true
            durationBadge?.iconView.isHidden = true
            durationBadge?.progressIndicator.stopAnimation()
            durationBadge?.progressIndicator.isHidden = true
            durationBadge?.isHidden = true
            durationBadge?.toolTip = nil
            stopDurationTimer()
        }
    }

    private func refreshDurationText(since: Date) {
        let elapsed = max(0, Int(Date().timeIntervalSince(since)))
        let badge = ThreadRowBadgeLayout.activityBadge(
            forElapsed: elapsed,
            isBusy: isCurrentDurationBusy,
            isMainWorktree: isConfiguredAsMain
        )
        durationLabel?.stringValue = ""
        switch badge?.label {
        case .stale:
            durationBadge?.iconView.image = Self.cachedSymbolImage("zzz")
            durationBadge?.iconView.isHidden = false
            durationBadge?.progressIndicator.stopAnimation()
            durationBadge?.progressIndicator.isHidden = true
        case .busy:
            durationBadge?.iconView.isHidden = true
            durationBadge?.progressIndicator.isHidden = false
            durationBadge?.progressIndicator.startAnimation()
        case nil:
            durationBadge?.iconView.isHidden = true
            durationBadge?.progressIndicator.stopAnimation()
            durationBadge?.progressIndicator.isHidden = true
        }
        updateDurationBadgeColors()
        let text = elapsedDurationText(elapsed)
        if isCurrentDurationBusy {
            durationBadge?.toolTip = String(localized: .ThreadStrings.threadBusyDurationTooltip(text))
        } else {
            let relative = RelativeDateTimeFormatter().localizedString(for: since, relativeTo: Date())
            durationBadge?.toolTip = String(localized: .ThreadStrings.threadLastActivityTooltip(relative))
        }
        updateDurationPresentation()
    }

    private func updateDurationPresentation() {
        let elapsed = currentDurationSince.map { max(0, Int(Date().timeIntervalSince($0))) }
        let hasBadge = elapsed.flatMap {
            ThreadRowBadgeLayout.activityBadge(
                forElapsed: $0,
                isBusy: isCurrentDurationBusy,
                isMainWorktree: isConfiguredAsMain
            )
        } != nil
        durationBadge?.isHidden = !hasBadge
        if !hasBadge {
            durationBadge?.iconView.isHidden = true
            durationBadge?.progressIndicator.stopAnimation()
            durationBadge?.progressIndicator.isHidden = true
        }
        durationLabel?.isHidden = true
    }

    private func elapsedDurationText(_ elapsed: Int) -> String {
        if elapsed < 60 { return "<1m" }
        if elapsed < 3_600 { return "\(elapsed / 60)m" }
        if elapsed < 86_400 { return "\(elapsed / 3_600)h" }
        return "\(elapsed / 86_400)d"
    }

    private func updateDurationBadgeColors() {
        guard let since = currentDurationSince,
              let badge = ThreadRowBadgeLayout.activityBadge(
                forElapsed: max(0, Int(Date().timeIntervalSince(since))),
                isBusy: isCurrentDurationBusy,
                isMainWorktree: isConfiguredAsMain
              ) else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let color: NSColor = switch badge.tone {
            case .yellow: .systemYellow
            case .orange: .systemOrange
            case .red: .systemRed
            }
            durationBadge?.layer?.borderColor = NSColor.clear.cgColor
            durationBadge?.layer?.borderWidth = 0
            durationBadge?.layer?.backgroundColor = NSColor.clear.cgColor
            let foregroundColor = BadgeForegroundStyle.color(
                tintColor: color,
                appearance: effectiveAppearance
            )
            durationBadge?.iconView.contentTintColor = foregroundColor
            durationBadge?.progressIndicator.setColor(foregroundColor)
        }
    }

    private func startDurationTimer() {
        guard durationTimer == nil else { return }
        durationTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self, let since = self.currentDurationSince else { return }
            self.refreshDurationText(since: since)
        }
    }

    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }

    override func removeFromSuperview() {
        stopDurationTimer()
        super.removeFromSuperview()
    }

    private func setDirtyDot(_ dot: NSImageView?, visible: Bool) {
        guard let dot else { return }
        if visible {
            dot.image = Self.cachedSymbolImage("circle.fill")
            dot.isHidden = false
            updateDirtyDotColors()
        } else {
            dot.image = nil
            dot.isHidden = true
        }
    }

    private func updateLeadingIconTint() {
        guard !isConfiguredAsMain else { return }
        if isRowVisuallySelected {
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            imageView?.contentTintColor = isDark ? .white : .labelColor
        } else if hasAllDead {
            imageView?.contentTintColor = .tertiaryLabelColor
        } else {
            if hasWaitingForInput {
                imageView?.contentTintColor = .systemOrange
            } else if hasUnreadCompletion {
                imageView?.contentTintColor = .systemGreen
            } else {
                imageView?.contentTintColor = configuredSectionColor ?? NSColor.appPrimary
            }
        }
    }

    private func updateMainTextColorForSelection() {
        let isEmphasized = backgroundStyle == .emphasized
        if isConfiguredAsMain {
            textField?.textColor = isEmphasized ? .white : .labelColor
        }
    }

    private func updateMainIconTintForSelection() {
        guard isConfiguredAsMain else { return }
        let tintColor = textField?.textColor ?? .labelColor
        imageView?.contentTintColor = tintColor
        inlineMainIconView?.contentTintColor = tintColor
    }

    private var isRowVisuallySelected: Bool {
        if backgroundStyle == .emphasized {
            return true
        }
        return (superview as? NSTableRowView)?.isSelected ?? false
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateLeadingIconTint()
        updateMainIconTintForSelection()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateMainTextColorForSelection()
        updateMainIconTintForSelection()
        updateTopBorderBadgeColors()
        updateAppearanceSensitiveColors()
    }

    private func updateAppearanceSensitiveColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // Keep-alive badge: systemCyan is illegible on white
        keepAliveBadge?.iconView.contentTintColor = isDark ? .systemCyan : .systemTeal
        updateDirtyDotColors()
    }

    private func updateDirtyDotColors() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let dirtyColor = NSColor.systemOrange.withAlphaComponent(isDark ? 0.7 : 1.0)
        primaryDirtyDot?.contentTintColor = dirtyColor
        secondaryDirtyDot?.contentTintColor = dirtyColor
    }

    private func statusDescriptions(for thread: MagentThread) -> [String] {
        var statuses: [String] = []
        if thread.isDirty {
            statuses.append("Dirty")
        }

        if thread.isSidebarHidden {
            statuses.append("Hidden")
        }

        if thread.isRateLimitExpiredAndResumable {
            statuses.append("Ready to resume")
        } else if thread.isBlockedByRateLimit {
            if let detail = thread.rateLimitLiftDescription, !detail.isEmpty {
                statuses.append("Rate limited (\(detail))")
            } else {
                statuses.append("Rate limited")
            }
        } else if thread.hasWaitingForInput {
            statuses.append("Waiting for input")
        } else if thread.isAnyBusy {
            statuses.append(thread.hasMagentBusy && !thread.hasAgentBusy ? "Setting up" : "Agent busy")
        } else if thread.hasUnreadAgentCompletion {
            statuses.append("Agent completed")
        }

        if thread.isKeepAlive {
            statuses.append("Keep Alive")
        }

        if thread.showArchiveSuggestion {
            statuses.append("Ready to archive")
        }

        return statuses
    }

    private func buildDetailedTooltip(
        description: String?,
        branchName: String,
        worktreeName: String,
        prLabel: String?,
        statuses: [String]
    ) -> String? {
        let trimmedDescription = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBranch = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorktree = worktreeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPR = prLabel?.trimmingCharacters(in: .whitespacesAndNewlines)

        var sections: [String] = []

        if let trimmedDescription, !trimmedDescription.isEmpty {
            sections.append(trimmedDescription)
        }

        var detailLines: [String] = []
        if !trimmedBranch.isEmpty {
            detailLines.append("Branch: \(trimmedBranch)")
        }
        if !trimmedWorktree.isEmpty {
            detailLines.append("Worktree: \(trimmedWorktree)")
        }
        if let trimmedPR, !trimmedPR.isEmpty {
            detailLines.append("PR: \(trimmedPR)")
        }
        if !detailLines.isEmpty {
            sections.append(detailLines.joined(separator: "\n"))
        }

        if !statuses.isEmpty {
            sections.append("Status: \(statuses.joined(separator: ", "))")
        }

        guard !sections.isEmpty else { return nil }
        return sections.joined(separator: "\n\n")
    }

    private func rateLimitTooltip(for thread: MagentThread) -> String {
        if let detail = thread.rateLimitLiftDescription, !detail.isEmpty {
            return "Rate limit reached. \(detail)"
        }
        return "Rate limit reached"
    }

    private func mainStatusDescriptions(
        isDirty: Bool,
        isRateLimitExpiredAndResumable: Bool,
        rateLimitTooltip: String?,
        isBlockedByRateLimit: Bool,
        isWaitingForInput: Bool,
        isBusy: Bool,
        isUnreadCompletion: Bool
    ) -> [String] {
        var statuses: [String] = []
        if isDirty {
            statuses.append("Dirty")
        }

        if isRateLimitExpiredAndResumable {
            statuses.append("Ready to resume")
        } else if isBlockedByRateLimit {
            let rateLimitDetail = rateLimitTooltip?
                .replacingOccurrences(of: "Rate limit reached. ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let rateLimitDetail, !rateLimitDetail.isEmpty, rateLimitDetail != "Rate limit reached" {
                statuses.append("Rate limited (\(rateLimitDetail))")
            } else {
                statuses.append("Rate limited")
            }
        } else if isWaitingForInput {
            statuses.append("Waiting for input")
        } else if isBusy {
            statuses.append("Agent busy")
        } else if isUnreadCompletion {
            statuses.append("Agent completed")
        }

        return statuses
    }

    @objc private func archiveButtonClicked() {
        onArchive?()
    }
}
