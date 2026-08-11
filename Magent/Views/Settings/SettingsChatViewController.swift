import Cocoa
import MagentCore

private final class ChatThemePreviewView: NSView {
    private let userBubble = NSView()
    private let userLabel = NSTextField(wrappingLabelWithString: "")
    private let assistantLabel = NSTextField(wrappingLabelWithString: "")
    private let statusBubble = NSView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let contrastStack = NSStackView()
    private var previewAppearance: ChatAppearance?
    private var previewFontSize: CGFloat = NSFont.systemFontSize

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        layer?.borderWidth = 1

        let content = NSStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        addSubview(content)

        userBubble.translatesAutoresizingMaskIntoConstraints = false
        userBubble.wantsLayer = true
        userBubble.layer?.cornerRadius = 12
        userBubble.layer?.masksToBounds = true
        userBubble.addSubview(userLabel)
        userLabel.translatesAutoresizingMaskIntoConstraints = false
        userLabel.stringValue = String(localized: .SettingsStrings.settingsChatPreviewUserMessage)

        let userRow = NSStackView()
        userRow.orientation = .horizontal
        userRow.alignment = .centerY
        let userSpacer = NSView()
        userSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        userSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        userRow.addArrangedSubview(userSpacer)
        userRow.addArrangedSubview(userBubble)
        content.addArrangedSubview(userRow)

        assistantLabel.stringValue = String(localized: .SettingsStrings.settingsChatPreviewAssistantMessage)
        content.addArrangedSubview(assistantLabel)

        statusBubble.translatesAutoresizingMaskIntoConstraints = false
        statusBubble.wantsLayer = true
        statusBubble.layer?.cornerRadius = 9
        statusBubble.layer?.masksToBounds = true
        statusBubble.addSubview(statusLabel)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.stringValue = String(localized: .ThreadStrings.chatComposerWorkingHint)
        content.addArrangedSubview(statusBubble)

        let separator = NSBox()
        separator.boxType = .separator
        content.addArrangedSubview(separator)

        contrastStack.orientation = .vertical
        contrastStack.alignment = .leading
        contrastStack.spacing = 4
        content.addArrangedSubview(contrastStack)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),

            userRow.widthAnchor.constraint(equalTo: content.widthAnchor),
            userBubble.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, multiplier: 0.72),
            userLabel.topAnchor.constraint(equalTo: userBubble.topAnchor, constant: 8),
            userLabel.leadingAnchor.constraint(equalTo: userBubble.leadingAnchor, constant: 10),
            userLabel.trailingAnchor.constraint(equalTo: userBubble.trailingAnchor, constant: -10),
            userLabel.bottomAnchor.constraint(equalTo: userBubble.bottomAnchor, constant: -8),

            assistantLabel.widthAnchor.constraint(lessThanOrEqualTo: content.widthAnchor, multiplier: 0.82),

            statusLabel.topAnchor.constraint(equalTo: statusBubble.topAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: statusBubble.leadingAnchor, constant: 9),
            statusLabel.trailingAnchor.constraint(equalTo: statusBubble.trailingAnchor, constant: -9),
            statusLabel.bottomAnchor.constraint(equalTo: statusBubble.bottomAnchor, constant: -6),

            separator.widthAnchor.constraint(equalTo: content.widthAnchor),
            contrastStack.widthAnchor.constraint(equalTo: content.widthAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if let previewAppearance {
            update(appearance: previewAppearance, fontSize: previewFontSize)
        } else {
            updateSurfaceAppearance()
        }
    }

    func update(appearance: ChatAppearance, fontSize: CGFloat) {
        previewAppearance = appearance
        previewFontSize = fontSize
        let font = NSFont.systemFont(ofSize: fontSize)
        userLabel.font = font
        userLabel.textColor = appearance.userTextColor
        assistantLabel.font = font
        assistantLabel.textColor = appearance.agentTextColor
        statusLabel.font = .systemFont(ofSize: max(11, fontSize - 1), weight: .medium)
        statusLabel.textColor = appearance.agentTextColor

        effectiveAppearance.performAsCurrentDrawingAppearance {
            userBubble.layer?.backgroundColor = appearance.userBubbleColor.cgColor
            statusBubble.layer?.backgroundColor = appearance.agentBubbleColor.cgColor
        }
        updateSurfaceAppearance()
        updateContrastLabels(appearance: appearance)
    }

    private func updateSurfaceAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        }
    }

    private func updateContrastLabels(appearance: ChatAppearance) {
        contrastStack.arrangedSubviews.forEach {
            contrastStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        var backgroundColor = NSColor(resource: .appBackground)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            backgroundColor = NSColor(resource: .appBackground)
        }
        let checks: [(name: String, foreground: NSColor, background: NSColor)] = [
            (
                String(localized: .SettingsStrings.settingsChatUserBubbleColor),
                appearance.userTextColor,
                appearance.userBubbleColor
            ),
            (
                String(localized: .SettingsStrings.settingsChatAgentTextColor),
                appearance.agentTextColor,
                backgroundColor
            ),
            (
                String(localized: .SettingsStrings.settingsChatAgentBubbleColor),
                appearance.agentTextColor,
                appearance.agentBubbleColor
            ),
        ]
        for (name, foreground, background) in checks {
            let ratio = Self.contrastRatio(foreground: foreground, background: background)
            let accessible = ratio >= ChatColorContrastPolicy.minimumAccessibleRatio
            let result = accessible
                ? String(localized: .SettingsStrings.settingsChatContrastAccessible)
                : String(localized: .SettingsStrings.settingsChatContrastLow)
            let label = NSTextField(
                labelWithString: "\(accessible ? "✓" : "⚠") \(name) · \(result) · \(String(format: "%.1f:1", ratio))"
            )
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = accessible ? .systemGreen : .systemOrange
            label.lineBreakMode = .byTruncatingTail
            contrastStack.addArrangedSubview(label)
        }
    }

    private static func contrastRatio(foreground: NSColor, background: NSColor) -> Double {
        guard let foregroundRGB = foreground.usingColorSpace(.sRGB),
              let backgroundRGB = background.usingColorSpace(.sRGB) else {
            return 1
        }
        return ChatColorContrastPolicy.contrastRatio(
            foregroundRed: Double(foregroundRGB.redComponent),
            foregroundGreen: Double(foregroundRGB.greenComponent),
            foregroundBlue: Double(foregroundRGB.blueComponent),
            backgroundRed: Double(backgroundRGB.redComponent),
            backgroundGreen: Double(backgroundRGB.greenComponent),
            backgroundBlue: Double(backgroundRGB.blueComponent)
        )
    }
}

final class SettingsChatViewController: NSViewController {

    private let persistence = PersistenceService.shared
    private var settings: AppSettings!
    private var contentScrollView: NSScrollView!
    private var didInitialScrollToTop = false

    private let userBubbleColorWell = NSColorWell()
    private let userTextColorWell = NSColorWell()
    private let agentBubbleColorWell = NSColorWell()
    private let agentTextColorWell = NSColorWell()
    private let chatFontSizeSlider = PrimaryTintSlider(value: AppSettings.defaultChatFontSize, minValue: AppSettings.minChatFontSize, maxValue: AppSettings.maxChatFontSize, target: nil, action: nil)
    private let chatFontSizeValueLabel = NSTextField(labelWithString: "")
    private let themePreviewView = ChatThemePreviewView()

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

        let (previewCard, previewSection) = createSectionCard(
            title: String(localized: .SettingsStrings.settingsChatPreviewTitle)
        )
        stackView.addArrangedSubview(previewCard)

        let (textSizeCard, textSizeSection) = createSectionCard(
            title: String(localized: .SettingsStrings.settingsChatTextSizeTitle),
            description: String(localized: .SettingsStrings.settingsChatTextSizeDescription)
        )
        stackView.addArrangedSubview(textSizeCard)

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

        previewSection.addArrangedSubview(themePreviewView)
        themePreviewView.widthAnchor.constraint(equalTo: previewSection.widthAnchor).isActive = true

        configureChatFontSizeSlider()
        let textSizeRow = labeledSliderRow(
            label: String(localized: .SettingsStrings.settingsChatTextSizeLabel),
            slider: chatFontSizeSlider,
            valueLabel: chatFontSizeValueLabel
        )
        textSizeSection.addArrangedSubview(textSizeRow)

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
            previewCard.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            textSizeCard.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -40),
            resetDescription.widthAnchor.constraint(equalTo: colorsSection.widthAnchor),
        ])

        refreshControls()
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

    private func configureChatFontSizeSlider() {
        chatFontSizeSlider.target = self
        chatFontSizeSlider.action = #selector(chatFontSizeChanged)
        chatFontSizeSlider.controlSize = .small
        chatFontSizeSlider.numberOfTickMarks = Int((AppSettings.maxChatFontSize - AppSettings.minChatFontSize) + 1)
        chatFontSizeSlider.allowsTickMarkValuesOnly = true

        chatFontSizeValueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        chatFontSizeValueLabel.textColor = NSColor(resource: .textSecondary)
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

    private func labeledSliderRow(label: String, slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8

        let titleLabel = NSTextField(labelWithString: label)
        titleLabel.font = .systemFont(ofSize: 12)
        row.addArrangedSubview(titleLabel)

        slider.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(slider)
        NSLayoutConstraint.activate([
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])

        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(valueLabel)
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
        refreshControls()
    }

    private func refreshControls() {
        settings = persistence.loadSettings()
        let appearance = ChatAppearance.resolve(from: settings)
        userBubbleColorWell.color = appearance.userBubbleColor
        userTextColorWell.color = appearance.userTextColor
        agentBubbleColorWell.color = appearance.agentBubbleColor
        agentTextColorWell.color = appearance.agentTextColor
        chatFontSizeSlider.doubleValue = settings.chatFontSize
        chatFontSizeValueLabel.stringValue = formattedChatFontSizeLabel(settings.chatFontSize)
        themePreviewView.update(appearance: appearance, fontSize: CGFloat(settings.chatFontSize))
    }

    private func formattedChatFontSizeLabel(_ size: Double) -> String {
        let roundedSize = Int(size.rounded())
        let value = NumberFormatter.localizedString(from: NSNumber(value: roundedSize), number: .none)
        return String(localized: .SettingsStrings.settingsChatTextSizeValueFormat(value))
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

    @objc private func chatFontSizeChanged() {
        let clamped = min(
            max(chatFontSizeSlider.doubleValue, AppSettings.minChatFontSize),
            AppSettings.maxChatFontSize
        ).rounded()
        chatFontSizeSlider.doubleValue = clamped
        saveSettingsAndNotify { settings in
            settings.chatFontSize = clamped
        }
    }
}
