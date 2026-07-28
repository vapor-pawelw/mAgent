import AppKit

final class DiffPanelHeaderActionStack: NSStackView {
    let refreshButton = NSButton()
    let infoButton = NSButton()

    var showsInfoButton: Bool {
        get { !infoButton.isHidden }
        set { infoButton.isHidden = !newValue }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        orientation = .horizontal
        spacing = 6
        alignment = .centerY
        detachesHiddenViews = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        translatesAutoresizingMaskIntoConstraints = false
        addArrangedSubview(refreshButton)
        addArrangedSubview(infoButton)
        showsInfoButton = false
    }
}
