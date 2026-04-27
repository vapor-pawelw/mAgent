import Cocoa
import MagentCore

final class SettingsChatViewController: NSViewController {

    private let persistence = PersistenceService.shared
    private var settings: AppSettings!
    private var contentScrollView: NSScrollView!
    private var didInitialScrollToTop = false

    private let userBubbleColorWell = NSColorWell()
    private let userTextColorWell = NSColorWell()
    private let agentBubbleColorWell = NSColorWell()
    private let agentTextColorWell = NSColorWell()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 640))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        settings = persistence.loadSettings()

        contentScrollView = NSScrollView()
        contentScrollView.hasVerticalScroller = true
        contentScrollView.autohidesScrollers = true
        contentScrollView.drawsBackground = false
        contentScrollView.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let (colorsCard, colorsSection) = createSectionCard(
            title: String(localized: .SettingsStrings.settingsChatColorsTitle),
            description: String(localized: .SettingsStrings.settingsChatColorsDescription)
        )
        stackView.addArrangedSubview(colorsCard)

        configureColorWell(userBubbleColorWell, action: #selector(userBubbleColorChanged))
        configureColorWell(userTextColorWell, action: #selector(userTextColorChanged))
        configureColorWell(agentBubbleColorWell, action: #selector(agentBubbleColorChanged))
        configureColorWell(agentTextColorWell, action: #selector(agentTextColorChanged))

        let userBubbleRow = labeledColorRow(
            label: String(localized: .SettingsStrings.settingsChatUserBubbleColor),
            colorWell: userBubbleColorWell
        )
        colorsSection.addArrangedSubview(userBubbleRow)

        let userTextRow = labeledColorRow(
            label: String(localized: .SettingsStrings.settingsChatUserTextColor),
            colorWell: userTextColorWell
        )
        colorsSection.addArrangedSubview(userTextRow)

        let agentBubbleRow = labeledColorRow(
            label: String(localized: .SettingsStrings.settingsChatAgentBubbleColor),
            colorWell: agentBubbleColorWell
        )
        colorsSection.addArrangedSubview(agentBubbleRow)

        let agentTextRow = labeledColorRow(
            label: String(localized: .SettingsStrings.settingsChatAgentTextColor),
            colorWell: agentTextColorWell
        )
        colorsSection.addArrangedSubview(agentTextRow)

        let resetButton = NSButton(
            title: String(localized: .SettingsStrings.settingsChatResetColors),
            target: self,
            action: #selector(resetColorsTapped)
        )
        resetButton.bezelStyle = .rounded
        resetButton.controlSize = .small
        colorsSection.addArrangedSubview(resetButton)

        let resetDescription = NSTextField(
            wrappingLabelWithString: String(localized: .SettingsStrings.settingsChatResetColorsDescription)
        )
        resetDescription.font = .systemFont(ofSize: 11)
        resetDescription.textColor = NSColor(resource: .textSecondary)
        colorsSection.addArrangedSubview(resetDescription)

        let documentView = FlippedDocumentView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        contentScrollView.documentView = documentView

        view.addSubview(contentScrollView)

        NSLayoutConstraint.activate([
            contentScrollView.topAnchor.constraint(equalTo: view.topAnchor),
            contentScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),

            documentView.widthAnchor.constraint(equalTo: contentScrollView.widthAnchor),
            colorsCard.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            resetDescription.widthAnchor.constraint(equalTo: colorsSection.widthAnchor),
        ])

        refreshColorControls()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if !didInitialScrollToTop {
            scrollToTop()
            didInitialScrollToTop = true
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        if !didInitialScrollToTop, view.window != nil {
            scrollToTop()
            didInitialScrollToTop = true
        }
    }

    private func scrollToTop() {
        guard let clipView = contentScrollView?.contentView as NSClipView? else { return }
        clipView.scroll(to: NSPoint(x: 0, y: 0))
        contentScrollView.reflectScrolledClipView(clipView)
    }

    private func configureColorWell(_ colorWell: NSColorWell, action: Selector) {
        colorWell.target = self
        colorWell.action = action
    }

    private func labeledColorRow(label: String, colorWell: NSColorWell) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .systemFont(ofSize: 12)
        row.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(spacer)

        row.addArrangedSubview(colorWell)
        return row
    }

    private func createSectionCard(title: String, description: String? = nil) -> (container: NSView, content: NSStackView) {
        let container = SettingsSectionCardView()

        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        content.addArrangedSubview(titleLabel)

        if let description, !description.isEmpty {
            let descriptionLabel = NSTextField(wrappingLabelWithString: description)
            descriptionLabel.font = .systemFont(ofSize: 11)
            descriptionLabel.textColor = NSColor(resource: .textSecondary)
            content.addArrangedSubview(descriptionLabel)
            content.setCustomSpacing(12, after: descriptionLabel)
            NSLayoutConstraint.activate([
                descriptionLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            ])
        }

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return (container, content)
    }

    private func saveSettingsAndNotify(_ mutate: (inout AppSettings) -> Void) {
        settings = persistence.loadSettings()
        mutate(&settings)
        try? persistence.saveSettings(settings)
        NotificationCenter.default.post(name: .magentSettingsDidChange, object: nil)
        refreshColorControls()
    }

    private func refreshColorControls() {
        settings = persistence.loadSettings()
        let appearance = ChatAppearance.resolve(from: settings)
        userBubbleColorWell.color = appearance.userBubbleColor
        userTextColorWell.color = appearance.userTextColor
        agentBubbleColorWell.color = appearance.agentBubbleColor
        agentTextColorWell.color = appearance.agentTextColor
    }

    @objc private func userBubbleColorChanged() {
        saveSettingsAndNotify { settings in
            settings.chatUserBubbleColorHex = userBubbleColorWell.color.hexString
        }
    }

    @objc private func userTextColorChanged() {
        saveSettingsAndNotify { settings in
            settings.chatUserTextColorHex = userTextColorWell.color.hexString
        }
    }

    @objc private func agentBubbleColorChanged() {
        saveSettingsAndNotify { settings in
            settings.chatAssistantBubbleColorHex = agentBubbleColorWell.color.hexString
        }
    }

    @objc private func agentTextColorChanged() {
        saveSettingsAndNotify { settings in
            settings.chatAssistantTextColorHex = agentTextColorWell.color.hexString
        }
    }

    @objc private func resetColorsTapped() {
        saveSettingsAndNotify { settings in
            settings.chatUserBubbleColorHex = nil
            settings.chatUserTextColorHex = nil
            settings.chatAssistantBubbleColorHex = nil
            settings.chatAssistantTextColorHex = nil
        }
    }
}
