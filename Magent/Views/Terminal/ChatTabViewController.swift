import Cocoa
import MagentCore

struct ChatTabEntry {
    let identifier: String
    var agentType: AgentType
    var title: String
    var messages: [PersistedChatMessage]
    var viewController: ChatTabViewController?
}

private final class ChatMessageBubbleView: NSView {
    private let container = NSView()
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let timestampLabel = NSTextField(labelWithString: "")

    init(message: PersistedChatMessage) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        addSubview(container)

        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        container.addSubview(stack)

        textLabel.stringValue = message.text
        textLabel.font = .systemFont(ofSize: 13)
        textLabel.maximumNumberOfLines = 0
        textLabel.lineBreakMode = .byWordWrapping

        timestampLabel.stringValue = Self.timestampFormatter.string(from: message.createdAt)
        timestampLabel.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        timestampLabel.textColor = .secondaryLabelColor

        switch message.role {
        case .user:
            container.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            textLabel.textColor = .white
            timestampLabel.textColor = NSColor.white.withAlphaComponent(0.8)
        case .assistant:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = NSColor(resource: .surface).cgColor
            }
            textLabel.textColor = .labelColor
        }

        container.layer?.cornerRadius = 14
        container.layer?.masksToBounds = true

        stack.addArrangedSubview(textLabel)
        stack.addArrangedSubview(timestampLabel)

        let leadingAnchorTarget: NSLayoutXAxisAnchor
        let trailingAnchorTarget: NSLayoutXAxisAnchor
        switch message.role {
        case .user:
            leadingAnchorTarget = centerXAnchor
            trailingAnchorTarget = trailingAnchor
        case .assistant:
            leadingAnchorTarget = leadingAnchor
            trailingAnchorTarget = centerXAnchor
        }

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchorTarget),
            container.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchorTarget),
            container.topAnchor.constraint(equalTo: topAnchor),
            container.bottomAnchor.constraint(equalTo: bottomAnchor),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 560),

            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

final class ChatTabViewController: NSViewController, NSTextViewDelegate {
    let identifier: String
    private(set) var agentType: AgentType
    private(set) var messages: [PersistedChatMessage]

    var onSubmit: ((String) -> Void)?

    private let scrollView = NSScrollView()
    private let messagesStack = NSStackView()
    private let inputTextView = NSTextView()
    private let sendButton = NSButton()
    private let scrollToBottomButton = NSButton()

    init(identifier: String, agentType: AgentType, messages: [PersistedChatMessage]) {
        self.identifier = identifier
        self.agentType = agentType
        self.messages = messages
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
        updateScrollToBottomButtonVisibility()
    }

    func update(agentType: AgentType, messages: [PersistedChatMessage]) {
        self.agentType = agentType
        self.messages = messages
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
        composerStack.alignment = .bottom
        composerStack.spacing = 8
        composerContainer.addSubview(composerStack)

        NSLayoutConstraint.activate([
            composerStack.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor),
            composerStack.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor),
            composerStack.topAnchor.constraint(equalTo: composerContainer.topAnchor),
            composerStack.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor),
        ])

        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.drawsBackground = false
        inputScroll.borderType = .bezelBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.scrollerStyle = .overlay

        inputTextView.isRichText = false
        inputTextView.font = .systemFont(ofSize: 13)
        inputTextView.isAutomaticDashSubstitutionEnabled = false
        inputTextView.isAutomaticQuoteSubstitutionEnabled = false
        inputTextView.isAutomaticTextReplacementEnabled = false
        inputTextView.isHorizontallyResizable = false
        inputTextView.isVerticallyResizable = true
        inputTextView.textContainerInset = NSSize(width: 6, height: 6)
        inputTextView.delegate = self
        inputTextView.string = ""
        inputScroll.documentView = inputTextView

        composerStack.addArrangedSubview(inputScroll)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = "Send"
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        composerStack.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            inputScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            inputScroll.heightAnchor.constraint(lessThanOrEqualToConstant: 120),
            sendButton.widthAnchor.constraint(equalToConstant: 64),
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

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func reloadMessages() {
        for subview in messagesStack.arrangedSubviews {
            messagesStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for message in messages {
            let bubble = ChatMessageBubbleView(message: message)
            messagesStack.addArrangedSubview(bubble)
        }

        DispatchQueue.main.async { [weak self] in
            self?.scrollToBottom(animated: false)
            self?.updateScrollToBottomButtonVisibility()
        }
    }

    @objc private func sendTapped() {
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            NSSound.beep()
            return
        }
        inputTextView.string = ""
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
}
