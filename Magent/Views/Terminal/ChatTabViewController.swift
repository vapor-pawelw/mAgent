import Cocoa
import MagentCore

struct ChatTabEntry {
    let identifier: String
    var agentType: AgentType
    var title: String
    var messages: [PersistedChatMessage]
    var draftInput: String
    var conversationSessionID: String?
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

private final class ChatMessageBubbleView: NSView {
    private let container = NSView()
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")

    init(message: PersistedChatMessage, appearance: ChatAppearance) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true
        addSubview(container)

        textLabel.stringValue = message.text
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping

        timestampLabel.stringValue = Self.timestampFormatter.string(from: message.createdAt)
        timestampLabel.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        timestampLabel.textColor = .secondaryLabelColor

        switch message.role {
        case .user:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = appearance.userBubbleColor.cgColor
            }
            textLabel.textColor = appearance.userTextColor
            timestampLabel.alignment = .right
        case .assistant:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = appearance.agentBubbleColor.cgColor
            }
            textLabel.textColor = appearance.agentTextColor
            timestampLabel.alignment = .left
        }

        let textStack = NSStackView()
        textStack.translatesAutoresizingMaskIntoConstraints = false
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 0
        textStack.addArrangedSubview(textLabel)
        container.addSubview(textStack)

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
            textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),

            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
}

final class ChatTabViewController: NSViewController, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let chatIdentifier: String
    private(set) var agentType: AgentType
    private(set) var messages: [PersistedChatMessage]

    var onSubmit: ((String) -> Void)?
    var onDraftChanged: ((String) -> Void)?

    private let scrollView = NSScrollView()
    private let messagesStack = NSStackView()
    private let inputTextView = NSTextView()
    private let sendButton = NSButton()
    private let scrollToBottomButton = NSButton()
    private let slashAutocompleteContainer = NSView()
    private let slashAutocompleteScrollView = NSScrollView()
    private let slashAutocompleteTableView = NSTableView()
    private var inputScrollView: NSScrollView?
    private var inputHeightConstraint: NSLayoutConstraint?
    private var slashAutocompleteHeightConstraint: NSLayoutConstraint?
    private var filteredSlashCommands: [SlashCommandAutocompleteItem] = []
    private var chatAppearance: ChatAppearance
    private let initialDraftInput: String

    private let slashAutocompleteRowHeight: CGFloat = 46
    private let slashAutocompleteMaxVisibleRows = 7
    private static let slashAutocompleteCellIdentifier = NSUserInterfaceItemIdentifier("slash-autocomplete-cell")

    init(identifier: String, agentType: AgentType, messages: [PersistedChatMessage], draftInput: String) {
        self.chatIdentifier = identifier
        self.agentType = agentType
        self.messages = messages
        self.chatAppearance = ChatAppearance.resolve(from: PersistenceService.shared.loadSettings())
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
        reloadMessages()
        updateComposerHeight()
        updateScrollToBottomButtonVisibility()
        updateSlashAutocompleteAppearance()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .magentSettingsDidChange,
            object: nil
        )
    }

    func update(agentType: AgentType, messages: [PersistedChatMessage], draftInput: String? = nil) {
        self.agentType = agentType
        self.messages = messages
        if let draftInput, inputTextView.string != draftInput {
            inputTextView.string = draftInput
            updateComposerHeight()
        }
        reloadMessages()
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

        let headerLabel = NSTextField(labelWithString: "\(agentType.displayName) Chat")
        headerLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        headerLabel.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(headerLabel)

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
        inputTextView.font = .systemFont(ofSize: 13)
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
        sendButton.toolTip = "Return sends. Command+Return inserts newline."
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
        scrollToBottomButton.title = "Scroll to bottom"
        scrollToBottomButton.bezelStyle = .rounded
        scrollToBottomButton.target = self
        scrollToBottomButton.action = #selector(scrollToBottomTapped)
        view.addSubview(scrollToBottomButton)

        NSLayoutConstraint.activate([
            scrollToBottomButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            scrollToBottomButton.bottomAnchor.constraint(equalTo: composerContainer.topAnchor, constant: -8),
        ])

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollBoundsChanged),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
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

        NSLayoutConstraint.activate([
            slashAutocompleteScrollView.leadingAnchor.constraint(equalTo: slashAutocompleteContainer.leadingAnchor),
            slashAutocompleteScrollView.trailingAnchor.constraint(equalTo: slashAutocompleteContainer.trailingAnchor),
            slashAutocompleteScrollView.topAnchor.constraint(equalTo: slashAutocompleteContainer.topAnchor),
            slashAutocompleteScrollView.bottomAnchor.constraint(equalTo: slashAutocompleteContainer.bottomAnchor),

            slashAutocompleteContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            slashAutocompleteContainer.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -86),
            slashAutocompleteContainer.bottomAnchor.constraint(equalTo: composerContainer.topAnchor, constant: -8),
        ])
    }

    private func updateSlashAutocompleteAppearance() {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            slashAutocompleteContainer.layer?.backgroundColor = NSColor(resource: .surface).cgColor
            slashAutocompleteContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func reloadMessages(shouldScrollToBottom: Bool = true) {
        chatAppearance = ChatAppearance.resolve(from: PersistenceService.shared.loadSettings())
        for subview in messagesStack.arrangedSubviews {
            messagesStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for message in messages {
            let bubble = ChatMessageBubbleView(message: message, appearance: chatAppearance)
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
        let clip = scrollView.contentView
        let maxY = max(0, scrollView.documentView?.bounds.height ?? 0 - clip.bounds.height)
        let target = NSPoint(x: 0, y: maxY)
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
    }

    private func updateScrollToBottomButtonVisibility() {
        let clip = scrollView.contentView
        let maxY = max(0, (scrollView.documentView?.bounds.height ?? 0) - clip.bounds.height)
        scrollToBottomButton.isHidden = maxY - clip.bounds.origin.y < 24
    }

    private var slashCommands: [SlashCommandAutocompleteItem] {
        [
            SlashCommandAutocompleteItem(command: "/login", detail: String(localized: .ThreadStrings.chatSlashCommandLoginDescription), insertionText: "/login "),
            SlashCommandAutocompleteItem(command: "/logout", detail: String(localized: .ThreadStrings.chatSlashCommandLogoutDescription), insertionText: "/logout "),
            SlashCommandAutocompleteItem(command: "/model", detail: String(localized: .ThreadStrings.chatSlashCommandModelDescription), insertionText: "/model "),
            SlashCommandAutocompleteItem(command: "/scoped-models", detail: String(localized: .ThreadStrings.chatSlashCommandScopedModelsDescription), insertionText: "/scoped-models "),
            SlashCommandAutocompleteItem(command: "/settings", detail: String(localized: .ThreadStrings.chatSlashCommandSettingsDescription), insertionText: "/settings "),
            SlashCommandAutocompleteItem(command: "/resume", detail: String(localized: .ThreadStrings.chatSlashCommandResumeDescription), insertionText: "/resume "),
            SlashCommandAutocompleteItem(command: "/new", detail: String(localized: .ThreadStrings.chatSlashCommandNewDescription), insertionText: "/new "),
            SlashCommandAutocompleteItem(command: "/name", detail: String(localized: .ThreadStrings.chatSlashCommandNameDescription), insertionText: "/name "),
            SlashCommandAutocompleteItem(command: "/session", detail: String(localized: .ThreadStrings.chatSlashCommandSessionDescription), insertionText: "/session "),
            SlashCommandAutocompleteItem(command: "/tree", detail: String(localized: .ThreadStrings.chatSlashCommandTreeDescription), insertionText: "/tree "),
            SlashCommandAutocompleteItem(command: "/fork", detail: String(localized: .ThreadStrings.chatSlashCommandForkDescription), insertionText: "/fork "),
            SlashCommandAutocompleteItem(command: "/clone", detail: String(localized: .ThreadStrings.chatSlashCommandCloneDescription), insertionText: "/clone "),
            SlashCommandAutocompleteItem(command: "/compact", detail: String(localized: .ThreadStrings.chatSlashCommandCompactDescription), insertionText: "/compact "),
            SlashCommandAutocompleteItem(command: "/copy", detail: String(localized: .ThreadStrings.chatSlashCommandCopyDescription), insertionText: "/copy "),
            SlashCommandAutocompleteItem(command: "/export", detail: String(localized: .ThreadStrings.chatSlashCommandExportDescription), insertionText: "/export "),
            SlashCommandAutocompleteItem(command: "/share", detail: String(localized: .ThreadStrings.chatSlashCommandShareDescription), insertionText: "/share "),
            SlashCommandAutocompleteItem(command: "/reload", detail: String(localized: .ThreadStrings.chatSlashCommandReloadDescription), insertionText: "/reload "),
            SlashCommandAutocompleteItem(command: "/hotkeys", detail: String(localized: .ThreadStrings.chatSlashCommandHotkeysDescription), insertionText: "/hotkeys "),
            SlashCommandAutocompleteItem(command: "/changelog", detail: String(localized: .ThreadStrings.chatSlashCommandChangelogDescription), insertionText: "/changelog "),
            SlashCommandAutocompleteItem(command: "/quit", detail: String(localized: .ThreadStrings.chatSlashCommandQuitDescription), insertionText: "/quit "),
        ]
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
        let visibleRows = min(filteredSlashCommands.count, slashAutocompleteMaxVisibleRows)
        slashAutocompleteHeightConstraint?.constant = CGFloat(visibleRows) * slashAutocompleteRowHeight
        slashAutocompleteContainer.isHidden = false

        let selectedRow = slashAutocompleteTableView.selectedRow
        if selectedRow < 0 || !filteredSlashCommands.indices.contains(selectedRow) {
            slashAutocompleteTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            slashAutocompleteTableView.scrollRowToVisible(0)
        }
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
            if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
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
    }
}
