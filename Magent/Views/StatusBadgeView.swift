import Cocoa
import MagentModels

/// A tiny rounded-rect pill displaying a status label with a colored background.
/// Used inline in sidebar rows and top-bar buttons to show PR/Jira status.
final class StatusBadgeView: RightClickMenuView {

    struct Style {
        static let backgroundOpacity: CGFloat = 0.10
        let tintColor: NSColor

        static let open = Style(tintColor: .systemGreen)
        static let draft = Style(tintColor: .secondaryLabelColor)
        static let merged = Style(tintColor: .systemPurple)
        static let approved = Style(tintColor: .systemGreen)
        static let changesRequested = Style(tintColor: .systemOrange)
        static let closed = Style(tintColor: .systemRed)

        static let jiraTodo = Style(tintColor: .secondaryLabelColor)
        static let jiraInProgress = Style(tintColor: .systemBlue)
        static let jiraDone = Style(tintColor: .systemGreen)

    }

    private let label = NSTextField(labelWithString: "")

    override var wantsUpdateLayer: Bool { true }

    private var badgeStyle = Style(tintColor: .clear)
    private var cornerRadius: CGFloat = 3

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        addSubview(label)

        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
    }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = self.badgeStyle.tintColor
                .withAlphaComponent(Style.backgroundOpacity)
                .cgColor
            self.layer?.cornerRadius = self.cornerRadius
            self.label.textColor = BadgeForegroundStyle.color(
                tintColor: self.badgeStyle.tintColor,
                appearance: self.effectiveAppearance
            )
        }
    }

    func configure(text: String, style: Style, fontSize: CGFloat) {
        label.stringValue = text
        label.font = .systemFont(ofSize: fontSize, weight: .medium)
        badgeStyle = style
        needsDisplay = true
    }

    // MARK: - PR Status

    static func prStyle(for pr: PullRequestInfo) -> Style {
        if pr.isMerged { return .merged }
        if pr.isClosed { return .closed }
        if pr.isDraft { return .draft }
        switch pr.reviewDecision {
        case .approved: return .approved
        case .changesRequested: return .changesRequested
        case .reviewRequired, nil: return .open
        }
    }

    // MARK: - Jira Status

    /// Returns the semantic Jira category tint, or nil for unknown categories.
    static func jiraCategoryTintColor(forKey categoryKey: String?) -> NSColor? {
        switch categoryKey {
        case "new": return Style.jiraTodo.tintColor
        case "indeterminate": return Style.jiraInProgress.tintColor
        case "done": return Style.jiraDone.tintColor
        default: return nil
        }
    }

    /// Maps the Jira `statusCategory.key` to a badge style.
    /// Falls back to keyword matching on the status name when category is unavailable.
    static func jiraStyle(forCategoryKey categoryKey: String?) -> Style {
        switch categoryKey {
        case "done": return .jiraDone
        case "indeterminate": return .jiraInProgress
        case "new": return .jiraTodo
        default: return .jiraTodo
        }
    }
}
