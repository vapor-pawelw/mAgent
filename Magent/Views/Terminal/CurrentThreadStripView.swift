import AppKit
import MagentCore

final class CurrentThreadStripView: NSView {
    private enum Layout {
        static let height: CGFloat = 28
        static let cornerRadius: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let horizontalPadding: CGFloat = 10
        static let iconSize: CGFloat = 15
        static let dirtyDotSize: CGFloat = 7
        static let labelSpacing: CGFloat = 6
        static let metadataSpacing: CGFloat = 4
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let dirtyDot = NSView()
    private let metadataLabel = NSTextField(labelWithString: "")
    private let separatorLabel = NSTextField(labelWithString: "·")
    private let contentStack = NSStackView()

    private var currentThread: MagentThread?
    private var sectionColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Layout.height)
    }

    func configure(with thread: MagentThread, sectionColor: NSColor?) {
        currentThread = thread
        self.sectionColor = sectionColor

        iconView.image = NSImage(
            systemSymbolName: thread.isMain ? "house.fill" : thread.threadIcon.symbolName,
            accessibilityDescription: thread.isMain ? nil : thread.threadIcon.accessibilityDescription
        ) ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)

        let summary = Self.summary(for: thread)
        titleLabel.stringValue = summary.title
        metadataLabel.stringValue = summary.metadata
        metadataLabel.isHidden = summary.metadata.isEmpty
        separatorLabel.isHidden = summary.metadata.isEmpty
        dirtyDot.isHidden = !thread.isDirty
        toolTip = summary.tooltip

        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius
        layer?.borderWidth = Layout.borderWidth

        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        dirtyDot.translatesAutoresizingMaskIntoConstraints = false
        dirtyDot.wantsLayer = true
        dirtyDot.layer?.cornerRadius = Layout.dirtyDotSize / 2
        dirtyDot.setContentHuggingPriority(.required, for: .horizontal)
        dirtyDot.setContentCompressionResistancePriority(.required, for: .horizontal)

        separatorLabel.translatesAutoresizingMaskIntoConstraints = false
        separatorLabel.font = .systemFont(ofSize: 11)
        separatorLabel.setContentHuggingPriority(.required, for: .horizontal)
        separatorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .systemFont(ofSize: 11)
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1
        metadataLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        metadataLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .horizontal
        contentStack.alignment = .centerY
        contentStack.spacing = Layout.labelSpacing
        contentStack.detachesHiddenViews = true
        contentStack.setContentHuggingPriority(.defaultLow, for: .horizontal)
        contentStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        contentStack.addArrangedSubview(iconView)
        contentStack.addArrangedSubview(titleLabel)
        contentStack.addArrangedSubview(dirtyDot)
        contentStack.addArrangedSubview(separatorLabel)
        contentStack.addArrangedSubview(metadataLabel)
        contentStack.setCustomSpacing(Layout.metadataSpacing, after: dirtyDot)
        contentStack.setCustomSpacing(Layout.metadataSpacing, after: separatorLabel)

        addSubview(contentStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Layout.height),

            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.horizontalPadding),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.horizontalPadding),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.widthAnchor.constraint(equalToConstant: Layout.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Layout.iconSize),

            dirtyDot.widthAnchor.constraint(equalToConstant: Layout.dirtyDotSize),
            dirtyDot.heightAnchor.constraint(equalToConstant: Layout.dirtyDotSize),
        ])

        updateAppearance()
    }

    private func updateAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.62).cgColor
            layer?.borderColor = Self.borderColor(for: currentThread, sectionColor: sectionColor, appearance: effectiveAppearance).cgColor
            iconView.contentTintColor = sectionColor ?? NSColor.secondaryLabelColor
            titleLabel.textColor = NSColor.labelColor
            metadataLabel.textColor = NSColor.secondaryLabelColor
            separatorLabel.textColor = NSColor.tertiaryLabelColor
            dirtyDot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        }
    }

    private static func borderColor(for thread: MagentThread?, sectionColor: NSColor?, appearance: NSAppearance) -> NSColor {
        if let thread {
            if thread.isBlockedByRateLimit {
                return thread.isRateLimitPropagatedOnly
                    ? NSColor.systemOrange.withAlphaComponent(0.5)
                    : NSColor.systemRed.withAlphaComponent(0.5)
            }
            if thread.hasWaitingForInput {
                return NSColor.systemOrange.withAlphaComponent(0.5)
            }
            if thread.isAnyBusy || thread.hasUnreadAgentCompletion {
                return NSColor.systemGreen.withAlphaComponent(0.5)
            }
        }

        if let sectionColor {
            return sectionColor.withAlphaComponent(0.28)
        }

        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)
    }

    private static func summary(for thread: MagentThread) -> (title: String, metadata: String, tooltip: String) {
        if thread.isMain {
            let branch = thread.currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            let mainWorktree = String(localized: .ThreadStrings.threadInfoMainWorktree)
            let resolvedBranch = branch.isEmpty ? mainWorktree : branch
            return (
                title: mainWorktree,
                metadata: resolvedBranch,
                tooltip: [
                    mainWorktree,
                    String(localized: .ThreadStrings.threadInfoBranchTooltip(resolvedBranch)),
                ].joined(separator: "\n")
            )
        }

        let worktreeName = (thread.worktreePath as NSString).lastPathComponent
        let branch = thread.currentBranch.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBranch = branch.isEmpty ? thread.name : branch
        let description = thread.taskDescription?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (description?.isEmpty == false) ? description! : resolvedBranch

        var metadataParts: [String] = []
        if title != resolvedBranch {
            metadataParts.append(resolvedBranch)
        }
        if worktreeName != resolvedBranch {
            metadataParts.append(worktreeName)
        }

        let metadata = metadataParts.joined(separator: "  ·  ")
        let tooltipParts = [
            title,
            String(localized: .ThreadStrings.threadInfoBranchTooltip(resolvedBranch)),
            String(localized: .ThreadStrings.threadInfoWorktreeTooltip(worktreeName)),
        ]
        return (title: title, metadata: metadata, tooltip: tooltipParts.joined(separator: "\n"))
    }
}
