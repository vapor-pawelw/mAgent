import Cocoa
import MagentCore

struct ChatTabEntry {
    let identifier: String
    var agentType: AgentType
    var title: String
    var messages: [PersistedChatMessage]
    var draftInput: String
    var conversationSessionID: String?
    var modelId: String?
    var reasoningLevel: String?
    var viewController: ChatTabViewController?
}

private struct SlashCommandAutocompleteItem {
    let command: String
    let detail: String
    let insertionText: String
}

private final class SlashCommandAutocompleteCellView: NSTableCellView {
    private let commandLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)

        commandLabel.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
        commandLabel.lineBreakMode = .byTruncatingTail
        commandLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stack.addArrangedSubview(commandLabel)
        stack.addArrangedSubview(detailLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: SlashCommandAutocompleteItem) {
        commandLabel.stringValue = item.command
        detailLabel.stringValue = item.detail
    }
}

private final class ChatInputTextView: NSTextView {
    var onCommandC: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           onCommandC?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class ChatMessageTextView: NSTextView {
    private var hoverTrackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .iBeam)
        addLinkCursorRects()
    }

    override func cursorUpdate(with event: NSEvent) {
        updateHoverCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoverCursor(for: event)
    }

    private func updateHoverCursor(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hasLink(at: point) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.iBeam.set()
        }
    }

    private func hasLink(at point: NSPoint) -> Bool {
        guard let layoutManager, let textContainer, let textStorage else { return false }

        var containerPoint = point
        containerPoint.x -= textContainerInset.width
        containerPoint.y -= textContainerInset.height

        guard containerPoint.x >= 0, containerPoint.y >= 0 else { return false }

        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRange = NSRange(location: glyphIndex, length: 1)
        let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard glyphRect.contains(containerPoint) else { return false }

        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return false }
        return textStorage.attribute(.link, at: charIndex, effectiveRange: nil) != nil
    }

    private func addLinkCursorRects() {
        guard let layoutManager, let textContainer, let textStorage else { return }
        layoutManager.ensureLayout(for: textContainer)
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: textContainer
            ) { [weak self] rect, _ in
                guard let self else { return }
                var adjusted = rect
                adjusted.origin.x += self.textContainerInset.width
                adjusted.origin.y += self.textContainerInset.height
                self.addCursorRect(adjusted, cursor: .pointingHand)
            }
        }
    }
}

private final class ChatMessageBubbleView: NSView, NSTextViewDelegate {
    private let container = NSView()
    private let messageTextView = ChatMessageTextView()
    private let timestampLabel = NSTextField(labelWithString: "")
    private let onOpenLink: ((String) -> Void)?
    private var bubbleHeightConstraint: NSLayoutConstraint?
    private let isLoadingIndicatorBubble: Bool
    private let loadingBubbleSide: CGFloat = 36
    private let loadingBubbleCornerRadius: CGFloat = 10

    private enum MarkdownToken {
        case text(String)
        case code(String)
        case link(label: String, target: String)
    }

    init(
        message: PersistedChatMessage,
        appearance: ChatAppearance,
        fontSize: CGFloat,
        onOpenLink: ((String) -> Void)? = nil
    ) {
        self.onOpenLink = onOpenLink
        self.isLoadingIndicatorBubble = message.role == .assistant && Self.isThinkingPlaceholderText(message.text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = isLoadingIndicatorBubble ? loadingBubbleCornerRadius : 14
        container.layer?.masksToBounds = true
        addSubview(container)

        timestampLabel.stringValue = Self.formattedTimestamp(message.createdAt)
        timestampLabel.font = .monospacedSystemFont(ofSize: max(9, fontSize - 4), weight: .regular)
        timestampLabel.textColor = .secondaryLabelColor
        timestampLabel.isSelectable = true
        timestampLabel.allowsEditingTextAttributes = false
        let exactTimestampTooltip = Self.exactTimestampTooltip(message.createdAt)
        toolTip = exactTimestampTooltip
        container.toolTip = exactTimestampTooltip
        messageTextView.toolTip = exactTimestampTooltip
        timestampLabel.toolTip = exactTimestampTooltip

        let baseTextColor: NSColor
        let codeColor: NSColor
        switch message.role {
        case .user:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = appearance.userBubbleColor.cgColor
            }
            baseTextColor = appearance.userTextColor
            codeColor = appearance.userTextColor.withAlphaComponent(0.75)
            timestampLabel.alignment = .right
        case .assistant:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = appearance.agentBubbleColor.cgColor
            }
            baseTextColor = appearance.agentTextColor
            codeColor = NSColor(resource: .textSecondary)
            timestampLabel.alignment = .left
        }

        if isLoadingIndicatorBubble {
            let spinner = NSProgressIndicator()
            spinner.translatesAutoresizingMaskIntoConstraints = false
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.isDisplayedWhenStopped = false
            spinner.startAnimation(nil)
            container.addSubview(spinner)
            NSLayoutConstraint.activate([
                spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            configureLoadingBubbleBorderAnimation()
        } else {
            messageTextView.drawsBackground = false
            messageTextView.isEditable = false
            messageTextView.isSelectable = true
            messageTextView.isRichText = false
            messageTextView.importsGraphics = false
            messageTextView.usesFindPanel = false
            messageTextView.textContainerInset = .zero
            messageTextView.textContainer?.lineFragmentPadding = 0
            messageTextView.isHorizontallyResizable = false
            messageTextView.isVerticallyResizable = true
            messageTextView.textContainer?.widthTracksTextView = false
            messageTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
            messageTextView.delegate = self
            messageTextView.linkTextAttributes = [
                .foregroundColor: NSColor(resource: .primaryBrand),
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            ]
            messageTextView.textStorage?.setAttributedString(
                Self.styledMarkdownText(
                    message.text,
                    baseColor: baseTextColor,
                    codeColor: codeColor,
                    linkColor: NSColor(resource: .primaryBrand),
                    baseFontSize: fontSize
                )
            )

            messageTextView.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(messageTextView)
        }

        let timestampRow = NSStackView()
        timestampRow.translatesAutoresizingMaskIntoConstraints = false
        timestampRow.orientation = .horizontal
        timestampRow.alignment = .centerY
        timestampRow.spacing = 0

        let bubbleRow = NSStackView()
        bubbleRow.translatesAutoresizingMaskIntoConstraints = false
        bubbleRow.orientation = .horizontal
        bubbleRow.alignment = .centerY
        bubbleRow.spacing = 8

        let timestampSpacer = NSView()
        timestampSpacer.translatesAutoresizingMaskIntoConstraints = false
        timestampSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        timestampSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let bubbleSpacer = NSView()
        bubbleSpacer.translatesAutoresizingMaskIntoConstraints = false
        bubbleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bubbleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if message.role == .user {
            timestampRow.addArrangedSubview(timestampSpacer)
            timestampRow.addArrangedSubview(timestampLabel)
            bubbleRow.addArrangedSubview(bubbleSpacer)
            bubbleRow.addArrangedSubview(container)
        } else {
            timestampRow.addArrangedSubview(timestampLabel)
            timestampRow.addArrangedSubview(timestampSpacer)
            bubbleRow.addArrangedSubview(container)
            bubbleRow.addArrangedSubview(bubbleSpacer)
        }

        let outer = NSStackView()
        outer.translatesAutoresizingMaskIntoConstraints = false
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 4
        if message.role == .user {
            outer.addArrangedSubview(timestampRow)
            outer.addArrangedSubview(bubbleRow)
        } else {
            outer.addArrangedSubview(bubbleRow)
            outer.addArrangedSubview(timestampRow)
        }
        addSubview(outer)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 560),

            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if isLoadingIndicatorBubble {
            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: loadingBubbleSide),
                container.heightAnchor.constraint(equalToConstant: loadingBubbleSide),
            ])
        } else {
            bubbleHeightConstraint = container.heightAnchor.constraint(equalToConstant: 20)
            bubbleHeightConstraint?.isActive = true
            NSLayoutConstraint.activate([
                messageTextView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                messageTextView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                messageTextView.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
                messageTextView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard !isLoadingIndicatorBubble else { return }
        updateBubbleHeight()
    }

    func clearSelection() {
        guard !isLoadingIndicatorBubble else { return }
        messageTextView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        if let target = link as? String {
            onOpenLink?(target)
            return true
        }
        if let url = link as? URL {
            onOpenLink?(url.absoluteString)
            return true
        }
        return false
    }

    private func updateBubbleHeight() {
        guard let textContainer = messageTextView.textContainer,
              let layoutManager = messageTextView.layoutManager else { return }

        let availableWidth = max(1, messageTextView.bounds.width - (textContainer.lineFragmentPadding * 2))
        if abs(textContainer.containerSize.width - availableWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: availableWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        // 10pt top + 10pt bottom padding around text.
        bubbleHeightConstraint?.constant = max(20, textHeight + 20)
    }

    private func configureLoadingBubbleBorderAnimation() {
        guard let layer = container.layer else { return }
        layer.borderWidth = 1
        var baseBorderColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.35)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            baseBorderColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.35)
        }
        layer.borderColor = baseBorderColor.cgColor

        if layer.animation(forKey: "chatLoadingBorderPulse") == nil {
            let pulse = CABasicAnimation(keyPath: "borderColor")
            pulse.fromValue = baseBorderColor.cgColor
            pulse.toValue = NSColor(resource: .primaryBrand).withAlphaComponent(0.9).cgColor
            pulse.duration = 0.9
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(pulse, forKey: "chatLoadingBorderPulse")
        }
    }

    private static func styledMarkdownText(
        _ source: String,
        baseColor: NSColor,
        codeColor: NSColor,
        linkColor: NSColor,
        baseFontSize: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = NSFont.systemFont(ofSize: baseFontSize)
        let codeFont = NSFont.monospacedSystemFont(ofSize: max(11, baseFontSize - 1), weight: .regular)
        let linkFont = NSFont.systemFont(ofSize: baseFontSize, weight: .regular)

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor,
        ]
        let codeAttributes: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: codeColor,
        ]
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: linkFont,
            .foregroundColor: linkColor,
        ]

        for token in tokenizeMarkdown(source) {
            switch token {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .code(let text):
                result.append(NSAttributedString(string: text, attributes: codeAttributes))
            case .link(let label, let target):
                let display = label.isEmpty ? target : label
                let attrs = linkAttributes.merging([.link: target]) { current, _ in current }
                result.append(NSAttributedString(string: display, attributes: attrs))
            }
        }

        return result
    }

    private static func tokenizeMarkdown(_ source: String) -> [MarkdownToken] {
        guard !source.isEmpty else { return [.text("")] }

        var tokens: [MarkdownToken] = []
        var buffer = ""

        func flushText() {
            guard !buffer.isEmpty else { return }
            tokens.append(.text(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        var index = source.startIndex
        while index < source.endIndex {
            let character = source[index]

            if character == "`" {
                var delimiterCount = 0
                var delimiterIndex = index
                while delimiterIndex < source.endIndex, source[delimiterIndex] == "`" {
                    delimiterCount += 1
                    delimiterIndex = source.index(after: delimiterIndex)
                }

                let delimiter = String(repeating: "`", count: delimiterCount)
                if let closeRange = source[delimiterIndex...].range(of: delimiter) {
                    flushText()
                    let codeText = String(source[delimiterIndex..<closeRange.lowerBound])
                    tokens.append(.code(codeText))
                    index = closeRange.upperBound
                    continue
                }

                buffer.append(delimiter)
                index = delimiterIndex
                continue
            }

            if character == "[" {
                if let closeBracket = source[index...].firstIndex(of: "]") {
                    let afterBracket = source.index(after: closeBracket)
                    if afterBracket < source.endIndex, source[afterBracket] == "(",
                       let closeParen = source[source.index(after: afterBracket)...].firstIndex(of: ")") {
                        let labelStart = source.index(after: index)
                        let targetStart = source.index(after: afterBracket)
                        let label = String(source[labelStart..<closeBracket])
                        let target = String(source[targetStart..<closeParen])
                        flushText()
                        tokens.append(.link(label: label, target: target))
                        index = source.index(after: closeParen)
                        continue
                    }
                }
            }

            buffer.append(character)
            index = source.index(after: index)
        }

        flushText()
        return tokens
    }

    private static func formattedTimestamp(_ date: Date, now: Date = Date()) -> String {
        relativeTimestampFormatter.localizedString(for: date, relativeTo: now)
    }

    private static func exactTimestampTooltip(_ date: Date) -> String {
        exactTimestampFormatter.string(from: date)
    }

    private static let exactTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .full
        formatter.timeStyle = .long
        return formatter
    }()

    private static let relativeTimestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func isThinkingPlaceholderText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Thinking."
            || trimmed == "Thinking.."
            || trimmed == "Thinking..."
            || trimmed == "Thinking…"
    }
}

final class ChatTabViewController: NSViewController, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let chatIdentifier: String
    private(set) var agentType: AgentType
    private(set) var messages: [PersistedChatMessage]
    private(set) var modelId: String?
    private(set) var reasoningLevel: String?

    var onSubmit: ((String) -> Void)?
    var onDraftChanged: ((String) -> Void)?
    var onCancelRunningCommand: (() -> Void)?
    var onOpenMarkdownLink: ((String) -> Void)?
    var onModelReasoningChanged: ((String?, String?) -> Void)?
    var isCommandRunning: (() -> Bool)?

    private let scrollView = NSScrollView()
    private let messagesStack = NSStackView()
    private let inputTextView = ChatInputTextView()
    private let sendButton = NSButton()
    private let scrollToBottomButton = NSButton()
    private let slashAutocompleteContainer = NSView()
    private let slashAutocompleteScrollView = NSScrollView()
    private let slashAutocompleteTableView = NSTableView()
    private let modelPicker = NSPopUpButton()
    private let reasoningPicker = NSPopUpButton()
    private let modelReasoningRow = NSStackView()
    private var inputScrollView: NSScrollView?
    private let backgroundClickGesture = NSClickGestureRecognizer()
    private var inputHeightConstraint: NSLayoutConstraint?
    private var slashAutocompleteHeightConstraint: NSLayoutConstraint?
    private var filteredSlashCommands: [SlashCommandAutocompleteItem] = []
    private var chatAppearance: ChatAppearance
    private var chatFontSize: CGFloat
    private let initialDraftInput: String

    private let slashAutocompleteRowHeight: CGFloat = 46
    private let slashAutocompleteVisibleRowsLimit = 5
    private let slashAutocompleteVerticalPadding: CGFloat = 6
    private static let slashAutocompleteCellIdentifier = NSUserInterfaceItemIdentifier("slash-autocomplete-cell")

    init(
        identifier: String,
        agentType: AgentType,
        messages: [PersistedChatMessage],
        draftInput: String,
        modelId: String? = nil,
        reasoningLevel: String? = nil
    ) {
        let settings = PersistenceService.shared.loadSettings()
        self.chatIdentifier = identifier
        self.agentType = agentType
        self.messages = messages
        self.modelId = modelId
        self.reasoningLevel = reasoningLevel
        self.chatAppearance = ChatAppearance.resolve(from: settings)
        self.chatFontSize = Self.resolvedChatFontSize(from: settings)
        self.initialDraftInput = draftInput
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = AppBackgroundView()
        root.wantsLayer = true
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        installBackgroundClickGesture()
        configureModelReasoningPickers()
        reloadMessages()
        updateComposerHeight()
        updateScrollToBottomButtonVisibility()
        updateSlashAutocompleteAppearance()
        updateScrollToBottomButtonAppearance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .magentSettingsDidChange,
            object: nil
        )
    }

    func update(
        agentType: AgentType,
        messages: [PersistedChatMessage],
        draftInput: String? = nil,
        modelId: String? = nil,
        reasoningLevel: String? = nil
    ) {
        let previousAgentType = self.agentType
        self.agentType = agentType
        self.messages = messages
        self.modelId = modelId
        self.reasoningLevel = reasoningLevel
        if let draftInput, inputTextView.string != draftInput {
            inputTextView.string = draftInput
            updateComposerHeight()
        }
        if previousAgentType != agentType {
            configureModelReasoningPickers()
        } else {
            syncModelReasoningSelection()
        }
        reloadMessages()
        updateSlashAutocompleteForCurrentInput()
    }

    func focusComposer() {
        view.window?.makeFirstResponder(inputTextView)
    }

    private func setupUI() {
        let rootStack = NSStackView()
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        rootStack.orientation = .vertical
        rootStack.spacing = 10
        view.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            rootStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            rootStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            rootStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        ])

        let messagesContainer = NSView()
        messagesContainer.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(messagesContainer)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true

        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        messagesStack.translatesAutoresizingMaskIntoConstraints = false
        messagesStack.orientation = .vertical
        messagesStack.alignment = .leading
        messagesStack.spacing = 8

        doc.addSubview(messagesStack)
        scrollView.documentView = doc
        messagesContainer.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: messagesContainer.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: messagesContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: messagesContainer.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: messagesContainer.bottomAnchor),
            messagesContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),

            doc.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            messagesStack.topAnchor.constraint(equalTo: doc.topAnchor),
            messagesStack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            messagesStack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            messagesStack.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
        ])

        let composerContainer = NSView()
        composerContainer.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(composerContainer)

        let composerStack = NSStackView()
        composerStack.translatesAutoresizingMaskIntoConstraints = false
        composerStack.orientation = .horizontal
        composerStack.alignment = .centerY
        composerStack.spacing = 8
        composerContainer.addSubview(composerStack)

        NSLayoutConstraint.activate([
            composerStack.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor),
            composerStack.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor),
            composerStack.topAnchor.constraint(equalTo: composerContainer.topAnchor),
            composerStack.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor),
        ])

        setupSlashAutocompleteUI(composerContainer: composerContainer)

        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.drawsBackground = false
        inputScroll.borderType = .bezelBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.scrollerStyle = .legacy

        inputTextView.isRichText = false
        inputTextView.font = .systemFont(ofSize: chatFontSize)
        inputTextView.isAutomaticDashSubstitutionEnabled = false
        inputTextView.isAutomaticQuoteSubstitutionEnabled = false
        inputTextView.isAutomaticTextReplacementEnabled = false
        inputTextView.isHorizontallyResizable = false
        inputTextView.isVerticallyResizable = true
        inputTextView.textContainerInset = NSSize(width: 6, height: 6)
        inputTextView.delegate = self
        inputTextView.string = initialDraftInput
        inputTextView.textContainer?.widthTracksTextView = true
        inputTextView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        inputTextView.onCommandC = { [weak self] in
            self?.handleComposerCommandC() ?? false
        }
        inputScroll.documentView = inputTextView

        inputScrollView = inputScroll
        composerStack.addArrangedSubview(inputScroll)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = ""
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")
        sendButton.imagePosition = .imageOnly
        sendButton.bezelStyle = .rounded
        sendButton.controlSize = .large
        sendButton.contentTintColor = .controlAccentColor
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.toolTip = "Return sends. Shift+Return inserts newline."
        composerStack.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            {
                let c = inputScroll.heightAnchor.constraint(equalToConstant: minComposerHeight)
                inputHeightConstraint = c
                return c
            }(),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
        ])

        scrollToBottomButton.translatesAutoresizingMaskIntoConstraints = false
        scrollToBottomButton.title = ""
        let scrollIconConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        scrollToBottomButton.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: "Scroll to bottom")?
            .withSymbolConfiguration(scrollIconConfig)
        scrollToBottomButton.imagePosition = .imageOnly
        scrollToBottomButton.isBordered = false
        scrollToBottomButton.toolTip = "Scroll to bottom"
        scrollToBottomButton.target = self
        scrollToBottomButton.action = #selector(scrollToBottomTapped)
        view.addSubview(scrollToBottomButton)

        NSLayoutConstraint.activate([
            scrollToBottomButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: composerContainer.topAnchor, constant: -10),
            scrollToBottomButton.widthAnchor.constraint(equalToConstant: 30),
            scrollToBottomButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        setupModelReasoningRow(rootStack: rootStack)
    }

    private func setupModelReasoningRow(rootStack: NSStackView) {
        modelReasoningRow.translatesAutoresizingMaskIntoConstraints = false
        modelReasoningRow.orientation = .horizontal
        modelReasoningRow.alignment = .centerY
        modelReasoningRow.spacing = 8
        rootStack.addArrangedSubview(modelReasoningRow)

        modelPicker.translatesAutoresizingMaskIntoConstraints = false
        modelPicker.controlSize = .small
        modelPicker.target = self
        modelPicker.action = #selector(modelPickerChanged)
        modelPicker.toolTip = String(localized: .ThreadStrings.chatSlashCommandModelDescription)

        reasoningPicker.translatesAutoresizingMaskIntoConstraints = false
        reasoningPicker.controlSize = .small
        reasoningPicker.target = self
        reasoningPicker.action = #selector(reasoningPickerChanged)
        reasoningPicker.toolTip = String(localized: .ThreadStrings.chatSlashCommandEffortDescription)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        modelReasoningRow.addArrangedSubview(modelPicker)
        modelReasoningRow.addArrangedSubview(reasoningPicker)
        modelReasoningRow.addArrangedSubview(spacer)

        NSLayoutConstraint.activate([
            modelReasoningRow.widthAnchor.constraint(equalTo: rootStack.widthAnchor),
            modelPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
            reasoningPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 116),
        ])
    }

    private func setupSlashAutocompleteUI(composerContainer: NSView) {
        slashAutocompleteContainer.translatesAutoresizingMaskIntoConstraints = false
        slashAutocompleteContainer.wantsLayer = true
        slashAutocompleteContainer.layer?.cornerRadius = 10
        slashAutocompleteContainer.layer?.masksToBounds = true
        slashAutocompleteContainer.layer?.borderWidth = 1
        slashAutocompleteContainer.isHidden = true
        updateSlashAutocompleteAppearance()

        slashAutocompleteScrollView.translatesAutoresizingMaskIntoConstraints = false
        slashAutocompleteScrollView.drawsBackground = false
        slashAutocompleteScrollView.borderType = .noBorder
        slashAutocompleteScrollView.hasVerticalScroller = true
        slashAutocompleteScrollView.autohidesScrollers = true
        slashAutocompleteScrollView.scrollerStyle = .overlay

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("slash-autocomplete-column"))
        column.resizingMask = .autoresizingMask
        slashAutocompleteTableView.addTableColumn(column)
        slashAutocompleteTableView.headerView = nil
        slashAutocompleteTableView.usesAlternatingRowBackgroundColors = false
        slashAutocompleteTableView.selectionHighlightStyle = .regular
        slashAutocompleteTableView.focusRingType = .none
        slashAutocompleteTableView.intercellSpacing = NSSize(width: 0, height: 0)
        slashAutocompleteTableView.rowHeight = slashAutocompleteRowHeight
        slashAutocompleteTableView.delegate = self
        slashAutocompleteTableView.dataSource = self
        slashAutocompleteTableView.target = self
        slashAutocompleteTableView.action = #selector(slashAutocompleteRowClicked)
        slashAutocompleteTableView.doubleAction = #selector(slashAutocompleteRowClicked)
        slashAutocompleteTableView.allowsEmptySelection = false

        slashAutocompleteScrollView.documentView = slashAutocompleteTableView
        slashAutocompleteContainer.addSubview(slashAutocompleteScrollView)
        view.addSubview(slashAutocompleteContainer)

        slashAutocompleteHeightConstraint = slashAutocompleteContainer.heightAnchor.constraint(equalToConstant: 0)
        slashAutocompleteHeightConstraint?.isActive = true

        let preferredAutocompleteWidth = slashAutocompleteContainer.widthAnchor.constraint(equalToConstant: 360)
        preferredAutocompleteWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            slashAutocompleteScrollView.leadingAnchor.constraint(equalTo: slashAutocompleteContainer.leadingAnchor),
            slashAutocompleteScrollView.trailingAnchor.constraint(equalTo: slashAutocompleteContainer.trailingAnchor),
            slashAutocompleteScrollView.topAnchor.constraint(
                equalTo: slashAutocompleteContainer.topAnchor,
                constant: slashAutocompleteVerticalPadding
            ),
            slashAutocompleteScrollView.bottomAnchor.constraint(
                equalTo: slashAutocompleteContainer.bottomAnchor,
                constant: -slashAutocompleteVerticalPadding
            ),

            slashAutocompleteContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            slashAutocompleteContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),
            slashAutocompleteContainer.bottomAnchor.constraint(equalTo: composerContainer.topAnchor, constant: -8),
            preferredAutocompleteWidth,
        ])
    }

    private func updateSlashAutocompleteAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            slashAutocompleteContainer.layer?.backgroundColor = NSColor(resource: .surface).cgColor
            slashAutocompleteContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }
    }

    private func updateScrollToBottomButtonAppearance() {
        scrollToBottomButton.wantsLayer = true
        scrollToBottomButton.layer?.cornerRadius = 15
        scrollToBottomButton.layer?.borderWidth = 0
        scrollToBottomButton.layer?.masksToBounds = true
        scrollToBottomButton.alphaValue = TerminalScrollToBottomPillButton.restingAlpha

        let appearance = view.effectiveAppearance
        appearance.performAsCurrentDrawingAppearance {
            scrollToBottomButton.layer?.backgroundColor = TerminalOverlayStyle.backgroundColor(for: appearance).cgColor
            scrollToBottomButton.contentTintColor = TerminalOverlayStyle.contentTintColor(for: appearance)
        }
    }

    private var selectedModelIdFromPicker: String? {
        modelPicker.selectedItem?.representedObject as? String
    }

    private var selectedReasoningLevelFromPicker: String? {
        reasoningPicker.selectedItem?.representedObject as? String
    }

    private func configureModelReasoningPickers() {
        modelPicker.removeAllItems()
        reasoningPicker.removeAllItems()

        guard agentType != .custom,
              let agentConfig = AgentModelsService.shared.config(for: agentType),
              !agentConfig.models.isEmpty else {
            modelReasoningRow.isHidden = true
            modelId = nil
            reasoningLevel = nil
            return
        }

        modelReasoningRow.isHidden = false
        for model in agentConfig.models {
            modelPicker.addItem(withTitle: model.label)
            modelPicker.lastItem?.representedObject = model.id as NSString
        }
        syncModelReasoningSelection(using: agentConfig)
    }

    private func syncModelReasoningSelection(using agentConfig: AgentModelConfig? = nil) {
        guard let agentConfig = agentConfig ?? AgentModelsService.shared.config(for: agentType) else { return }
        guard modelPicker.numberOfItems > 0 else { return }

        let preferredModelId = AgentModelsService.shared.validatedModelId(modelId, for: agentType)
            ?? AgentModelsService.shared.validatedModelId(AgentLastSelectionStore.lastModel(for: agentType), for: agentType)
            ?? (modelPicker.itemArray.first?.representedObject as? String)

        if let preferredModelId,
           let modelIndex = modelPicker.itemArray.firstIndex(where: { ($0.representedObject as? String) == preferredModelId }) {
            modelPicker.selectItem(at: modelIndex)
        } else {
            modelPicker.selectItem(at: 0)
        }

        repopulateReasoningPicker(agentConfig: agentConfig, preferredLevel: reasoningLevel)
        commitModelReasoningSelection(notify: false)
    }

    private func repopulateReasoningPicker(agentConfig: AgentModelConfig, preferredLevel: String? = nil) {
        let selectedModelId = selectedModelIdFromPicker
        reasoningPicker.removeAllItems()
        for level in agentConfig.effectiveReasoningLevels(for: selectedModelId) {
            reasoningPicker.addItem(withTitle: level.capitalized)
            reasoningPicker.lastItem?.representedObject = level as NSString
        }

        let fallbackLevel = AgentModelsService.shared.validatedReasoningLevel(
            AgentLastSelectionStore.lastReasoning(for: agentType, modelId: selectedModelId),
            for: agentType,
            modelId: selectedModelId
        )
        let resolvedPreferred = AgentModelsService.shared.validatedReasoningLevel(
            preferredLevel,
            for: agentType,
            modelId: selectedModelId
        ) ?? fallbackLevel

        if let resolvedPreferred,
           let reasoningIndex = reasoningPicker.itemArray.firstIndex(where: { ($0.representedObject as? String) == resolvedPreferred }) {
            reasoningPicker.selectItem(at: reasoningIndex)
        } else if reasoningPicker.numberOfItems > 0 {
            reasoningPicker.selectItem(at: 0)
        }
    }

    private func commitModelReasoningSelection(notify: Bool) {
        modelId = selectedModelIdFromPicker
        reasoningLevel = selectedReasoningLevelFromPicker

        if let modelId {
            AgentLastSelectionStore.saveModel(modelId, for: agentType)
        }
        if let reasoningLevel {
            AgentLastSelectionStore.saveReasoning(reasoningLevel, for: agentType, modelId: modelId)
        }
        if notify {
            onModelReasoningChanged?(modelId, reasoningLevel)
        }
    }

    @objc private func modelPickerChanged() {
        guard let agentConfig = AgentModelsService.shared.config(for: agentType) else { return }
        repopulateReasoningPicker(agentConfig: agentConfig)
        commitModelReasoningSelection(notify: true)
    }

    @objc private func reasoningPickerChanged() {
        commitModelReasoningSelection(notify: true)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func installBackgroundClickGesture() {
        backgroundClickGesture.target = self
        backgroundClickGesture.action = #selector(handleBackgroundClick(_:))
        backgroundClickGesture.buttonMask = 0x1
        backgroundClickGesture.delaysPrimaryMouseButtonEvents = false
        view.addGestureRecognizer(backgroundClickGesture)
    }

    @objc private func handleBackgroundClick(_ gesture: NSClickGestureRecognizer) {
        let locationInView = gesture.location(in: view)
        guard let clickedView = view.hitTest(locationInView) else { return }
        guard shouldClearSelection(for: clickedView) else { return }
        clearSelectionState()
    }

    private func shouldClearSelection(for clickedView: NSView) -> Bool {
        if clickedView.isDescendant(of: inputTextView) {
            return false
        }
        if let inputScrollView, clickedView.isDescendant(of: inputScrollView) {
            return false
        }
        if clickedView.isDescendant(of: slashAutocompleteContainer) {
            return false
        }
        if clickedView is NSButton || clickedView.isDescendant(of: sendButton) || clickedView.isDescendant(of: scrollToBottomButton) {
            return false
        }
        return true
    }

    private func clearSelectionState() {
        if !slashAutocompleteContainer.isHidden {
            hideSlashAutocomplete()
        } else {
            slashAutocompleteTableView.deselectAll(nil)
        }

        let currentSelection = inputTextView.selectedRange()
        if currentSelection.location != NSNotFound && currentSelection.length > 0 {
            let caretLocation = min(currentSelection.location, (inputTextView.string as NSString).length)
            inputTextView.setSelectedRange(NSRange(location: caretLocation, length: 0))
        }

        for case let bubble as ChatMessageBubbleView in messagesStack.arrangedSubviews {
            bubble.clearSelection()
        }

        _ = view.window?.makeFirstResponder(nil)
    }

    private func reloadMessages(shouldScrollToBottom: Bool = true) {
        let settings = PersistenceService.shared.loadSettings()
        chatAppearance = ChatAppearance.resolve(from: settings)
        chatFontSize = Self.resolvedChatFontSize(from: settings)
        inputTextView.font = .systemFont(ofSize: chatFontSize)
        updateComposerHeight()
        for subview in messagesStack.arrangedSubviews {
            messagesStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for message in messages {
            let bubble = ChatMessageBubbleView(
                message: message,
                appearance: chatAppearance,
                fontSize: chatFontSize,
                onOpenLink: onOpenMarkdownLink
            )
            messagesStack.addArrangedSubview(bubble)
            bubble.widthAnchor.constraint(equalTo: messagesStack.widthAnchor).isActive = true
        }

        DispatchQueue.main.async { [weak self] in
            if shouldScrollToBottom {
                self?.scrollToBottom(animated: false)
            }
            self?.updateScrollToBottomButtonVisibility()
        }
    }

    @objc private func sendTapped() {
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }
        hideSlashAutocomplete()
        inputTextView.string = ""
        onDraftChanged?("")
        updateComposerHeight()
        onSubmit?(text)
    }

    @objc private func scrollToBottomTapped() {
        scrollToBottom(animated: true)
    }

    @objc private func scrollBoundsChanged() {
        updateScrollToBottomButtonVisibility()
    }

    private func scrollToBottom(animated: Bool) {
        // Ensure Auto Layout has finalized message bubble heights before we compute maxY.
        view.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()

        let clip = scrollView.contentView
        let target = NSPoint(x: 0, y: bottomContentOffsetY(for: clip))
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.allowsImplicitAnimation = true
                clip.animator().setBoundsOrigin(target)
                scrollView.reflectScrolledClipView(clip)
            }
        } else {
            clip.setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(clip)
        }

        // A follow-up pass on the next run-loop keeps us pinned to the real bottom
        // when constraints settle after the initial scroll calculation.
        DispatchQueue.main.async { [weak self] in
            self?.snapToBottomIfNeeded()
        }
    }

    private func snapToBottomIfNeeded() {
        view.layoutSubtreeIfNeeded()
        scrollView.layoutSubtreeIfNeeded()
        scrollView.documentView?.layoutSubtreeIfNeeded()

        let clip = scrollView.contentView
        let epsilon: CGFloat = 1
        guard distanceFromBottom(for: clip) > epsilon else { return }
        clip.setBoundsOrigin(NSPoint(x: 0, y: bottomContentOffsetY(for: clip)))
        scrollView.reflectScrolledClipView(clip)
    }

    private func updateScrollToBottomButtonVisibility() {
        let clip = scrollView.contentView
        scrollToBottomButton.isHidden = distanceFromBottom(for: clip) < 24
    }

    private func bottomContentOffsetY(for clip: NSClipView) -> CGFloat {
        let maxY = max(0, (scrollView.documentView?.bounds.height ?? 0) - clip.bounds.height)
        let isFlipped = scrollView.documentView?.isFlipped ?? false
        return isFlipped ? maxY : 0
    }

    private func distanceFromBottom(for clip: NSClipView) -> CGFloat {
        let maxY = max(0, (scrollView.documentView?.bounds.height ?? 0) - clip.bounds.height)
        let isFlipped = scrollView.documentView?.isFlipped ?? false
        return isFlipped ? abs(maxY - clip.bounds.origin.y) : abs(clip.bounds.origin.y)
    }

    private var slashCommands: [SlashCommandAutocompleteItem] {
        switch agentType {
        case .codex:
            return codexSlashCommands
        case .claude:
            return claudeSlashCommands
        case .custom:
            return []
        }
    }

    private var codexSlashCommands: [SlashCommandAutocompleteItem] {
        [
            slashCommand("/help", detail: String(localized: .ThreadStrings.chatSlashCommandHelpDescription)),
            slashCommand("/clear", detail: String(localized: .ThreadStrings.chatSlashCommandClearDescription)),
            slashCommand("/model", detail: String(localized: .ThreadStrings.chatSlashCommandModelDescription)),
            slashCommand("/effort", detail: String(localized: .ThreadStrings.chatSlashCommandEffortDescription)),
        ]
    }

    private var claudeSlashCommands: [SlashCommandAutocompleteItem] {
        [
            slashCommand("/add-dir", detail: String(localized: .ThreadStrings.chatSlashCommandAddDirDescription)),
            slashCommand("/agents", detail: String(localized: .ThreadStrings.chatSlashCommandAgentsDescription)),
            slashCommand("/branch", detail: String(localized: .ThreadStrings.chatSlashCommandBranchDescription)),
            slashCommand("/clear", detail: String(localized: .ThreadStrings.chatSlashCommandClearDescription)),
            slashCommand("/compact", detail: String(localized: .ThreadStrings.chatSlashCommandCompactDescription)),
            slashCommand("/config", detail: String(localized: .ThreadStrings.chatSlashCommandConfigDescription)),
            slashCommand("/context", detail: String(localized: .ThreadStrings.chatSlashCommandContextDescription)),
            slashCommand("/continue", detail: String(localized: .ThreadStrings.chatSlashCommandContinueDescription)),
            slashCommand("/copy", detail: String(localized: .ThreadStrings.chatSlashCommandCopyDescription)),
            slashCommand("/cost", detail: String(localized: .ThreadStrings.chatSlashCommandCostDescription)),
            slashCommand("/diff", detail: String(localized: .ThreadStrings.chatSlashCommandDiffDescription)),
            slashCommand("/doctor", detail: String(localized: .ThreadStrings.chatSlashCommandDoctorDescription)),
            slashCommand("/effort", detail: String(localized: .ThreadStrings.chatSlashCommandEffortDescription)),
            slashCommand("/exit", detail: String(localized: .ThreadStrings.chatSlashCommandExitDescription)),
            slashCommand("/export", detail: String(localized: .ThreadStrings.chatSlashCommandExportDescription)),
            slashCommand("/fast", detail: String(localized: .ThreadStrings.chatSlashCommandFastDescription)),
            slashCommand("/feedback", detail: String(localized: .ThreadStrings.chatSlashCommandFeedbackDescription)),
            slashCommand("/fork", detail: String(localized: .ThreadStrings.chatSlashCommandForkDescription)),
            slashCommand("/help", detail: String(localized: .ThreadStrings.chatSlashCommandHelpDescription)),
            slashCommand("/hooks", detail: String(localized: .ThreadStrings.chatSlashCommandHooksDescription)),
            slashCommand("/ide", detail: String(localized: .ThreadStrings.chatSlashCommandIdeDescription)),
            slashCommand("/init", detail: String(localized: .ThreadStrings.chatSlashCommandInitDescription)),
            slashCommand("/login", detail: String(localized: .ThreadStrings.chatSlashCommandLoginDescription)),
            slashCommand("/logout", detail: String(localized: .ThreadStrings.chatSlashCommandLogoutDescription)),
            slashCommand("/mcp", detail: String(localized: .ThreadStrings.chatSlashCommandMcpDescription)),
            slashCommand("/memory", detail: String(localized: .ThreadStrings.chatSlashCommandMemoryDescription)),
            slashCommand("/model", detail: String(localized: .ThreadStrings.chatSlashCommandModelDescription)),
            slashCommand("/new", detail: String(localized: .ThreadStrings.chatSlashCommandNewDescription)),
            slashCommand("/permissions", detail: String(localized: .ThreadStrings.chatSlashCommandPermissionsDescription)),
            slashCommand("/plan", detail: String(localized: .ThreadStrings.chatSlashCommandPlanDescription)),
            slashCommand("/plugin", detail: String(localized: .ThreadStrings.chatSlashCommandPluginDescription)),
            slashCommand("/quit", detail: String(localized: .ThreadStrings.chatSlashCommandQuitDescription)),
            slashCommand("/rename", detail: String(localized: .ThreadStrings.chatSlashCommandRenameDescription)),
            slashCommand("/resume", detail: String(localized: .ThreadStrings.chatSlashCommandResumeDescription)),
            slashCommand("/review", detail: String(localized: .ThreadStrings.chatSlashCommandReviewDescription)),
            slashCommand("/rewind", detail: String(localized: .ThreadStrings.chatSlashCommandRewindDescription)),
            slashCommand("/sandbox", detail: String(localized: .ThreadStrings.chatSlashCommandSandboxDescription)),
            slashCommand("/security-review", detail: String(localized: .ThreadStrings.chatSlashCommandSecurityReviewDescription)),
            slashCommand("/settings", detail: String(localized: .ThreadStrings.chatSlashCommandSettingsDescription)),
            slashCommand("/skills", detail: String(localized: .ThreadStrings.chatSlashCommandSkillsDescription)),
            slashCommand("/status", detail: String(localized: .ThreadStrings.chatSlashCommandStatusDescription)),
            slashCommand("/statusline", detail: String(localized: .ThreadStrings.chatSlashCommandStatuslineDescription)),
            slashCommand("/tasks", detail: String(localized: .ThreadStrings.chatSlashCommandTasksDescription)),
            slashCommand("/terminal-setup", detail: String(localized: .ThreadStrings.chatSlashCommandTerminalSetupDescription)),
            slashCommand("/theme", detail: String(localized: .ThreadStrings.chatSlashCommandThemeDescription)),
            slashCommand("/tui", detail: String(localized: .ThreadStrings.chatSlashCommandTuiDescription)),
            slashCommand("/ultraplan", detail: String(localized: .ThreadStrings.chatSlashCommandUltraplanDescription)),
            slashCommand("/ultrareview", detail: String(localized: .ThreadStrings.chatSlashCommandUltrareviewDescription)),
            slashCommand("/usage", detail: String(localized: .ThreadStrings.chatSlashCommandUsageDescription)),
        ]
    }

    private func slashCommand(
        _ command: String,
        detail: String,
        insertionText: String? = nil
    ) -> SlashCommandAutocompleteItem {
        let insertion = insertionText ?? "\(command) "
        return SlashCommandAutocompleteItem(
            command: command,
            detail: detail,
            insertionText: insertion
        )
    }

    private func updateSlashAutocompleteForCurrentInput() {
        guard let activeRange = activeSlashTokenRange() else {
            hideSlashAutocomplete()
            return
        }
        let fullText = inputTextView.string as NSString
        let token = fullText.substring(with: activeRange)
        guard token.hasPrefix("/") else {
            hideSlashAutocomplete()
            return
        }
        let query = String(token.dropFirst()).lowercased()
        filteredSlashCommands = slashCommands.filter { item in
            query.isEmpty || item.command.lowercased().hasPrefix("/\(query)")
        }
        guard !filteredSlashCommands.isEmpty else {
            hideSlashAutocomplete()
            return
        }
        showSlashAutocomplete()
    }

    private func showSlashAutocomplete() {
        slashAutocompleteTableView.reloadData()
        let shouldScroll = filteredSlashCommands.count > slashAutocompleteVisibleRowsLimit
        let visibleRows = min(filteredSlashCommands.count, slashAutocompleteVisibleRowsLimit)
        let tableContentHeight = slashAutocompleteTableContentHeight(forVisibleRows: visibleRows)
        slashAutocompleteHeightConstraint?.constant = tableContentHeight + (slashAutocompleteVerticalPadding * 2)
        slashAutocompleteScrollView.hasVerticalScroller = shouldScroll
        slashAutocompleteScrollView.verticalScrollElasticity = shouldScroll ? .automatic : .none
        if !shouldScroll {
            let clip = slashAutocompleteScrollView.contentView
            clip.setBoundsOrigin(.zero)
            slashAutocompleteScrollView.reflectScrolledClipView(clip)
        }
        slashAutocompleteContainer.isHidden = false

        let selectedRow = slashAutocompleteTableView.selectedRow
        if selectedRow < 0 || !filteredSlashCommands.indices.contains(selectedRow) {
            slashAutocompleteTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            slashAutocompleteTableView.scrollRowToVisible(0)
        }
    }

    private func slashAutocompleteTableContentHeight(forVisibleRows visibleRows: Int) -> CGFloat {
        guard visibleRows > 0 else { return 0 }
        let lastVisibleRow = visibleRows - 1
        let rowMaxY = slashAutocompleteTableView.rect(ofRow: lastVisibleRow).maxY
        return ceil(rowMaxY + 1)
    }

    private func hideSlashAutocomplete() {
        filteredSlashCommands = []
        slashAutocompleteTableView.reloadData()
        slashAutocompleteTableView.deselectAll(nil)
        slashAutocompleteHeightConstraint?.constant = 0
        slashAutocompleteContainer.isHidden = true
    }

    private func activeSlashTokenRange() -> NSRange? {
        let fullText = inputTextView.string as NSString
        let selection = inputTextView.selectedRange()
        guard selection.location != NSNotFound else { return nil }
        guard selection.location <= fullText.length else { return nil }

        let whitespace = CharacterSet.whitespacesAndNewlines
        let caret = selection.location
        var start = caret
        while start > 0 {
            let previous = fullText.substring(with: NSRange(location: start - 1, length: 1))
            if previous.rangeOfCharacter(from: whitespace) != nil {
                break
            }
            start -= 1
        }

        var end = caret
        while end < fullText.length {
            let current = fullText.substring(with: NSRange(location: end, length: 1))
            if current.rangeOfCharacter(from: whitespace) != nil {
                break
            }
            end += 1
        }

        guard start < fullText.length else { return nil }
        guard fullText.substring(with: NSRange(location: start, length: 1)) == "/" else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private func moveSlashAutocompleteSelection(delta: Int) {
        guard !filteredSlashCommands.isEmpty else { return }
        let current = slashAutocompleteTableView.selectedRow >= 0 ? slashAutocompleteTableView.selectedRow : 0
        let next = max(0, min(filteredSlashCommands.count - 1, current + delta))
        slashAutocompleteTableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        slashAutocompleteTableView.scrollRowToVisible(next)
    }

    @objc private func slashAutocompleteRowClicked() {
        confirmSlashAutocompleteSelection()
    }

    private func confirmSlashAutocompleteSelection() {
        let row = slashAutocompleteTableView.selectedRow
        guard filteredSlashCommands.indices.contains(row) else { return }
        applySlashAutocomplete(filteredSlashCommands[row])
    }

    private func applySlashAutocomplete(_ item: SlashCommandAutocompleteItem) {
        guard let activeRange = activeSlashTokenRange() else {
            hideSlashAutocomplete()
            return
        }
        guard let textStorage = inputTextView.textStorage else { return }

        textStorage.replaceCharacters(in: activeRange, with: item.insertionText)
        let insertionLocation = activeRange.location + (item.insertionText as NSString).length
        inputTextView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
        onDraftChanged?(inputTextView.string)
        updateComposerHeight()
        hideSlashAutocomplete()
    }

    private func handleComposerCommandC() -> Bool {
        guard isCommandRunning?() == true else { return false }
        onCancelRunningCommand?()
        return true
    }

    private var composerLineHeight: CGFloat {
        let font = inputTextView.font ?? .systemFont(ofSize: 13)
        return font.ascender + abs(font.descender) + font.leading
    }

    private var minComposerHeight: CGFloat {
        max(34, ceil(composerLineHeight + (inputTextView.textContainerInset.height * 2) + 6))
    }

    private var maxComposerHeight: CGFloat {
        ceil((composerLineHeight * 5) + (inputTextView.textContainerInset.height * 2) + 6)
    }

    private func updateComposerHeight() {
        guard let constraint = inputHeightConstraint,
              let textContainer = inputTextView.textContainer,
              let layoutManager = inputTextView.layoutManager else { return }

        layoutManager.ensureLayout(for: textContainer)
        let usedHeight = layoutManager.usedRect(for: textContainer).height
        let desiredHeight = ceil(usedHeight + (inputTextView.textContainerInset.height * 2) + 6)
        let clamped = min(max(desiredHeight, minComposerHeight), maxComposerHeight)
        constraint.constant = clamped

        let needsScroller = desiredHeight > maxComposerHeight + 0.5
        inputScrollView?.hasVerticalScroller = needsScroller
        if needsScroller {
            inputTextView.scrollRangeToVisible(NSRange(location: inputTextView.string.utf16.count, length: 0))
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateComposerHeight()
        updateScrollToBottomButtonAppearance()
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === inputTextView else { return }
        onDraftChanged?(inputTextView.string)
        updateComposerHeight()
        updateSlashAutocompleteForCurrentInput()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard notification.object as? NSTextView === inputTextView else { return }
        updateSlashAutocompleteForCurrentInput()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard textView === inputTextView else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            guard !slashAutocompleteContainer.isHidden else { return false }
            hideSlashAutocomplete()
            return true
        }
        if commandSelector == #selector(NSResponder.moveUp(_:)) {
            guard !slashAutocompleteContainer.isHidden else { return false }
            moveSlashAutocompleteSelection(delta: -1)
            return true
        }
        if commandSelector == #selector(NSResponder.moveDown(_:)) {
            guard !slashAutocompleteContainer.isHidden else { return false }
            moveSlashAutocompleteSelection(delta: 1)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if !slashAutocompleteContainer.isHidden {
                confirmSlashAutocompleteSelection()
                return true
            }
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(self)
            } else {
                sendTapped()
            }
            return true
        }
        return false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard tableView == slashAutocompleteTableView else { return 0 }
        return filteredSlashCommands.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView == slashAutocompleteTableView else { return nil }
        guard filteredSlashCommands.indices.contains(row) else { return nil }

        let cell: SlashCommandAutocompleteCellView
        if let reused = tableView.makeView(withIdentifier: Self.slashAutocompleteCellIdentifier, owner: self) as? SlashCommandAutocompleteCellView {
            cell = reused
        } else {
            cell = SlashCommandAutocompleteCellView(frame: .zero)
            cell.identifier = Self.slashAutocompleteCellIdentifier
        }
        cell.configure(item: filteredSlashCommands[row])
        return cell
    }

    @objc private func settingsDidChange() {
        reloadMessages(shouldScrollToBottom: false)
        updateSlashAutocompleteAppearance()
        updateScrollToBottomButtonAppearance()
        configureModelReasoningPickers()
    }

    private static func resolvedChatFontSize(from settings: AppSettings) -> CGFloat {
        CGFloat(min(max(settings.chatFontSize, AppSettings.minChatFontSize), AppSettings.maxChatFontSize))
    }
}
