import Cocoa
import AVFoundation
import MagentCore
import UniformTypeIdentifiers

struct ChatTabEntry {
    let identifier: String
    var agentType: AgentType
    var title: String
    var messages: [PersistedChatMessage]
    var draftInput: String
    var draftAttachments: [PersistedChatAttachment]
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
    var onControlC: (() -> Bool)?
    var onPasteImageFromClipboard: (() -> Bool)?
    var onAttachmentDropHoverChanged: ((Bool) -> Void)?
    var canAcceptAttachmentDrop: ((NSPasteboard) -> Bool)?
    var onAttachmentDrop: ((NSPasteboard) -> Bool)?

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown,
           modifiers == .control,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           onControlC?() == true {
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
           event.charactersIgnoringModifiers?.lowercased() == "c",
           onControlC?() == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func paste(_ sender: Any?) {
        if onPasteImageFromClipboard?() == true {
            return
        }
        super.paste(sender)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptAttachmentDrop?(sender.draggingPasteboard) == true else {
            onAttachmentDropHoverChanged?(false)
            return super.draggingEntered(sender)
        }
        onAttachmentDropHoverChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptAttachmentDrop?(sender.draggingPasteboard) == true else {
            onAttachmentDropHoverChanged?(false)
            return super.draggingUpdated(sender)
        }
        onAttachmentDropHoverChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onAttachmentDropHoverChanged?(false)
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if canAcceptAttachmentDrop?(sender.draggingPasteboard) == true {
            return true
        }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canAcceptAttachmentDrop?(sender.draggingPasteboard) == true else {
            onAttachmentDropHoverChanged?(false)
            return super.performDragOperation(sender)
        }
        let accepted = onAttachmentDrop?(sender.draggingPasteboard) ?? false
        onAttachmentDropHoverChanged?(false)
        return accepted
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onAttachmentDropHoverChanged?(false)
        super.concludeDragOperation(sender)
    }
}

private final class ChatAttachmentDropTargetView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    var canAcceptDrop: ((NSPasteboard) -> Bool)?
    var onPerformDrop: ((NSPasteboard) -> Bool)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = canAcceptDrop?(sender.draggingPasteboard) ?? false
        onHoverChanged?(accepts)
        return accepts ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepts = canAcceptDrop?(sender.draggingPasteboard) ?? false
        onHoverChanged?(accepts)
        return accepts ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onHoverChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAcceptDrop?(sender.draggingPasteboard) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let accepted = onPerformDrop?(sender.draggingPasteboard) ?? false
        onHoverChanged?(false)
        return accepted
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        onHoverChanged?(false)
    }
}

private final class ChatAttachmentChipView: NSView {
    let attachmentID: UUID

    init(
        attachmentID: UUID,
        previewImage: NSImage,
        filename: String,
        kindBadge: String?,
        removeAccessibilityLabel: String,
        onRemove: @escaping () -> Void
    ) {
        self.attachmentID = attachmentID
        self.onRemove = onRemove
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            layer?.backgroundColor = NSColor(resource: .surface).cgColor
        }

        let preview = NSImageView()
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.image = previewImage
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 7
        preview.layer?.masksToBounds = true
        addSubview(preview)

        let nameLabel = NSTextField(labelWithString: filename)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .systemFont(ofSize: 10, weight: .medium)
        nameLabel.textColor = .secondaryLabelColor
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.alignment = .center
        addSubview(nameLabel)

        let removeButton = NSButton()
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.title = ""
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: removeAccessibilityLabel)
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        addSubview(removeButton)

        var kindLabel: NSTextField?
        if let kindBadge, !kindBadge.isEmpty {
            let badge = NSTextField(labelWithString: kindBadge)
            badge.translatesAutoresizingMaskIntoConstraints = false
            badge.font = .monospacedSystemFont(ofSize: 8, weight: .semibold)
            badge.textColor = .labelColor
            badge.backgroundColor = .clear
            badge.alignment = .center
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 5
            badge.layer?.masksToBounds = true
            effectiveAppearance.performAsCurrentDrawingAppearance {
                badge.layer?.backgroundColor = NSColor(resource: .appBackground).withAlphaComponent(0.92).cgColor
            }
            addSubview(badge)
            kindLabel = badge
        }

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 88),
            heightAnchor.constraint(equalToConstant: 104),

            preview.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            preview.heightAnchor.constraint(equalToConstant: 64),

            nameLabel.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 5),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),

            removeButton.widthAnchor.constraint(equalToConstant: 16),
            removeButton.heightAnchor.constraint(equalToConstant: 16),
            removeButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ])

        if let kindLabel {
            NSLayoutConstraint.activate([
                kindLabel.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 4),
                kindLabel.topAnchor.constraint(equalTo: preview.topAnchor, constant: 4),
                kindLabel.heightAnchor.constraint(equalToConstant: 14),
                kindLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 28),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private let onRemove: () -> Void

    @objc private func removeTapped() {
        onRemove()
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

private final class ChatTimestampLabel: NSTextField {
    var fullTimestampText: String = ""
    var onPrimaryClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.type == .leftMouseDown, event.clickCount == 1 {
            onPrimaryClick?()
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(
            title: String(localized: .ThreadStrings.chatTimestampCopyFullTimeAction),
            action: #selector(copyFullTimestamp(_:)),
            keyEquivalent: ""
        )
        copyItem.target = self
        copyItem.isEnabled = !fullTimestampText.isEmpty
        menu.addItem(copyItem)
        return menu
    }

    @objc private func copyFullTimestamp(_ sender: Any?) {
        guard !fullTimestampText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullTimestampText, forType: .string)
    }
}

private final class ChatMessageBubbleView: NSView, NSTextViewDelegate {
    private static let loadingBorderRotationAnimationKey = "chat-loading-border-rotation"
    private static var sharedLoadingBorderAnimationEpoch: CFTimeInterval = 0

    private let container = NSView()
    private let messageTextView = ChatMessageTextView()
    private let loadingStatusLabel = NSTextField(labelWithString: "")
    private let timestampLabel = ChatTimestampLabel(labelWithString: "")
    private let createdAt: Date
    private let sentModelLabel: String?
    private let sentReasoningLevel: String?
    private let onOpenLink: ((String) -> Void)?
    private let isQueuedSubmissionPending: Bool
    private var bubbleHeightConstraint: NSLayoutConstraint?
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private let isLoadingIndicatorBubble: Bool
    private let loadingBubbleCornerRadius: CGFloat = 10
    private let maxBubbleWidth: CGFloat = 560
    private let minBubbleWidth: CGFloat = 44
    private let bubbleHorizontalPadding: CGFloat = 24
    private let bubbleVerticalPadding: CGFloat = 20
    private var loadingBorderContainerLayer: CALayer?
    private var bubbleHoverTrackingArea: NSTrackingArea?
    private var isPointerHoveringBubble = false
    private var timestampDisplayMode: ChatTimestampDisplayMode = .relative

    private enum AssistantDisplayState {
        case normal
        case info
        case warning
        case error
        case cancelled
    }

    init(
        message: PersistedChatMessage,
        agentType: AgentType,
        appearance: ChatAppearance,
        fontSize: CGFloat,
        queuedSubmissionPending: Bool = false,
        onOpenLink: ((String) -> Void)? = nil
    ) {
        self.createdAt = message.createdAt
        self.sentModelLabel = Self.resolvedModelLabel(for: message.modelId, agentType: agentType)
        self.sentReasoningLevel = message.reasoningLevel
        self.onOpenLink = onOpenLink
        self.isQueuedSubmissionPending = queuedSubmissionPending
        self.isLoadingIndicatorBubble = message.role == .assistant && Self.isThinkingPlaceholderText(message.text)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = isLoadingIndicatorBubble ? loadingBubbleCornerRadius : 14
        container.layer?.masksToBounds = true
        addSubview(container)

        timestampLabel.stringValue = Self.formattedTimestamp(message.createdAt)
        timestampLabel.font = .systemFont(ofSize: max(8, fontSize - 6), weight: .regular)
        timestampLabel.textColor = .secondaryLabelColor
        timestampLabel.isSelectable = false
        timestampLabel.allowsEditingTextAttributes = false
        timestampLabel.isHidden = isLoadingIndicatorBubble
        timestampLabel.onPrimaryClick = { [weak self] in
            self?.toggleTimestampDisplayMode()
        }
        let exactTimestampTooltip = Self.exactTimestampTooltip(message.createdAt)
        timestampLabel.fullTimestampText = exactTimestampTooltip
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
            if isQueuedSubmissionPending {
                container.alphaValue = 0.65
            }
            timestampLabel.alignment = .right
        case .assistant:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                let bubbleColor = isLoadingIndicatorBubble ? NSColor(resource: .appBackground) : appearance.agentBubbleColor
                container.layer?.backgroundColor = bubbleColor.cgColor
            }
            let isCancelledMessage = Self.isCancelledPlaceholderText(message.text)
            if isCancelledMessage {
                baseTextColor = NSColor(calibratedRed: 0.62, green: 0.12, blue: 0.12, alpha: 1.0)
                codeColor = baseTextColor.withAlphaComponent(0.85)
            } else {
                baseTextColor = appearance.agentTextColor
                codeColor = NSColor(resource: .textSecondary)
            }
            timestampLabel.alignment = .left
        }

        if isLoadingIndicatorBubble {
            loadingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
            loadingStatusLabel.font = .systemFont(ofSize: fontSize, weight: .regular)
            loadingStatusLabel.textColor = baseTextColor.withAlphaComponent(0.6)
            loadingStatusLabel.lineBreakMode = .byTruncatingTail
            loadingStatusLabel.stringValue = Self.loadingStatusText(startedAt: createdAt)
            container.addSubview(loadingStatusLabel)
            NSLayoutConstraint.activate([
                loadingStatusLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
                loadingStatusLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
                loadingStatusLabel.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
                loadingStatusLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10),
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
            let queuedSuffix = Self.queuedSubmissionSuffix
            let renderedMessageText: String
            if message.role == .user, isQueuedSubmissionPending {
                renderedMessageText = "\(message.text)\(queuedSuffix)"
            } else {
                renderedMessageText = message.text
            }
            let attributedMessage = NSMutableAttributedString(
                attributedString: Self.styledMarkdownText(
                    renderedMessageText,
                    baseColor: baseTextColor,
                    codeColor: codeColor,
                    linkColor: NSColor(resource: .primaryBrand),
                    baseFontSize: fontSize
                )
            )
            if message.role == .user, isQueuedSubmissionPending {
                let suffixLength = (queuedSuffix as NSString).length
                if attributedMessage.length >= suffixLength {
                    let suffixRange = NSRange(location: attributedMessage.length - suffixLength, length: suffixLength)
                    let queuedInfoFont = NSFont.monospacedSystemFont(ofSize: max(11, fontSize - 1), weight: .medium)
                    attributedMessage.addAttributes(
                        [
                            .font: queuedInfoFont,
                            .foregroundColor: baseTextColor.withAlphaComponent(0.9),
                        ],
                        range: suffixRange
                    )
                }
            }
            messageTextView.textStorage?.setAttributedString(attributedMessage)

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
        outer.addArrangedSubview(bubbleRow)
        outer.addArrangedSubview(timestampRow)
        addSubview(outer)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth),

            outer.topAnchor.constraint(equalTo: topAnchor),
            outer.leadingAnchor.constraint(equalTo: leadingAnchor),
            outer.trailingAnchor.constraint(equalTo: trailingAnchor),
            outer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if !isLoadingIndicatorBubble {
            bubbleHeightConstraint = container.heightAnchor.constraint(equalToConstant: 20)
            bubbleHeightConstraint?.isActive = true
            bubbleWidthConstraint = container.widthAnchor.constraint(equalToConstant: maxBubbleWidth)
            bubbleWidthConstraint?.isActive = true
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard !isLoadingIndicatorBubble else { return }
        if let bubbleHoverTrackingArea {
            removeTrackingArea(bubbleHoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        bubbleHoverTrackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        guard !isLoadingIndicatorBubble else { return }
        isPointerHoveringBubble = true
        refreshTimestampPresentation()
    }

    override func mouseExited(with event: NSEvent) {
        guard !isLoadingIndicatorBubble else { return }
        isPointerHoveringBubble = false
        refreshTimestampPresentation()
    }

    override func layout() {
        super.layout()
        if isLoadingIndicatorBubble {
            layoutLoadingBorderAnimationLayer()
        } else {
            updateBubbleLayout()
        }
    }

    func clearSelection() {
        guard !isLoadingIndicatorBubble else { return }
        messageTextView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func refreshRelativeTimestamp(now: Date = Date()) {
        if isLoadingIndicatorBubble {
            let statusText = Self.loadingStatusText(startedAt: createdAt, now: now)
            guard loadingStatusLabel.stringValue != statusText else { return }

            loadingStatusLabel.stringValue = statusText
            loadingStatusLabel.invalidateIntrinsicContentSize()

            // Loading bubbles do not use `updateBubbleLayout()`, so force an Auto Layout
            // pass here before recomputing the animated border geometry.
            needsUpdateConstraints = true
            needsLayout = true
            layoutSubtreeIfNeeded()
            layoutLoadingBorderAnimationLayer()
        } else {
            refreshTimestampPresentation(now: now)
        }
    }

    private func refreshTimestampPresentation(now: Date = Date()) {
        let hoverText: String?
        if isPointerHoveringBubble {
            hoverText = Self.hoverMetadataText(modelLabel: sentModelLabel, reasoningLevel: sentReasoningLevel)
        } else {
            hoverText = nil
        }
        timestampLabel.stringValue = ChatTimestampPresentation.displayText(
            mode: timestampDisplayMode,
            relativeText: Self.formattedTimestamp(createdAt, now: now),
            exactText: Self.exactTimestampTooltip(createdAt),
            hoverText: hoverText
        )
    }

    private func toggleTimestampDisplayMode() {
        guard !isLoadingIndicatorBubble else { return }
        timestampDisplayMode.toggle()
        refreshTimestampPresentation()
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

    private func updateBubbleLayout() {
        guard let textContainer = messageTextView.textContainer,
              let layoutManager = messageTextView.layoutManager,
              let bubbleWidthConstraint else { return }

        let maxTextWidth = max(1, maxBubbleWidth - bubbleHorizontalPadding)
        if abs(textContainer.containerSize.width - maxTextWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)

        let measuredLineWidth = max(0, Self.maxLineWidth(in: layoutManager, textContainer: textContainer))
        let targetBubbleWidth = min(
            maxBubbleWidth,
            max(minBubbleWidth, ceil(measuredLineWidth + bubbleHorizontalPadding))
        )
        if abs(bubbleWidthConstraint.constant - targetBubbleWidth) > 0.5 {
            bubbleWidthConstraint.constant = targetBubbleWidth
        }

        let targetTextWidth = max(1, targetBubbleWidth - bubbleHorizontalPadding)
        if abs(textContainer.containerSize.width - targetTextWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: targetTextWidth, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
        }

        let textHeight = ceil(layoutManager.usedRect(for: textContainer).height)
        bubbleHeightConstraint?.constant = max(20, textHeight + bubbleVerticalPadding)
    }

    private static func maxLineWidth(in layoutManager: NSLayoutManager, textContainer: NSTextContainer) -> CGFloat {
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard glyphRange.length > 0 else { return 0 }
        var maxWidth: CGFloat = 0
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var effectiveRange = NSRange(location: 0, length: 0)
            let lineRect = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &effectiveRange,
                withoutAdditionalLayout: true
            )
            maxWidth = max(maxWidth, ceil(lineRect.width))
            guard effectiveRange.length > 0 else { break }
            glyphIndex = NSMaxRange(effectiveRange)
        }
        return maxWidth
    }

    private func configureLoadingBubbleBorderAnimation() {
        guard let layer = container.layer else { return }
        layer.borderWidth = 0
        layer.borderColor = NSColor.clear.cgColor

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.borderWidth = 1
                layer.borderColor = NSColor(resource: .primaryBrand).withAlphaComponent(0.35).cgColor
            }
            return
        }

        if let existing = loadingBorderContainerLayer {
            if let gradient = existing.sublayers?.first as? CAGradientLayer,
               gradient.animation(forKey: Self.loadingBorderRotationAnimationKey) == nil {
                gradient.add(makeLoadingBorderRotationAnimation(), forKey: Self.loadingBorderRotationAnimationKey)
            }
            return
        }

        let borderContainer = CALayer()
        borderContainer.frame = container.bounds
        borderContainer.zPosition = 1
        layer.addSublayer(borderContainer)

        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.locations = [0.0, 0.08, 0.16, 0.5, 0.84, 0.92, 1.0]
        applyLoadingBorderGradientColors(gradient)
        borderContainer.addSublayer(gradient)

        let borderMask = CAShapeLayer()
        borderMask.fillColor = nil
        borderMask.strokeColor = NSColor.white.cgColor
        borderMask.lineWidth = 1.5
        borderContainer.mask = borderMask

        if Self.sharedLoadingBorderAnimationEpoch == 0 {
            Self.sharedLoadingBorderAnimationEpoch = CACurrentMediaTime()
        }
        gradient.add(makeLoadingBorderRotationAnimation(), forKey: Self.loadingBorderRotationAnimationKey)

        loadingBorderContainerLayer = borderContainer
        layoutLoadingBorderAnimationLayer()
    }

    private func makeLoadingBorderRotationAnimation() -> CABasicAnimation {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0.0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 2.2
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotation.beginTime = Self.sharedLoadingBorderAnimationEpoch
        return rotation
    }

    private func applyLoadingBorderGradientColors(_ gradientLayer: CAGradientLayer) {
        let bright = NSColor(resource: .primaryBrand).withAlphaComponent(0.85)
        let mid = NSColor(resource: .primaryBrand).withAlphaComponent(0.45)
        let dim = NSColor(resource: .primaryBrand).withAlphaComponent(0.12)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            gradientLayer.colors = [
                bright.cgColor,
                mid.cgColor,
                dim.cgColor,
                dim.cgColor,
                dim.cgColor,
                mid.cgColor,
                bright.cgColor,
            ]
        }
    }

    private func layoutLoadingBorderAnimationLayer() {
        guard let borderContainer = loadingBorderContainerLayer else { return }
        guard !container.bounds.isEmpty else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        borderContainer.frame = container.bounds
        if let gradient = borderContainer.sublayers?.first as? CAGradientLayer {
            let rect = container.bounds
            let diagonal = sqrt(rect.width * rect.width + rect.height * rect.height)
            gradient.frame = CGRect(
                x: rect.midX - diagonal / 2,
                y: rect.midY - diagonal / 2,
                width: diagonal,
                height: diagonal
            )
        }

        if let borderMask = borderContainer.mask as? CAShapeLayer {
            let borderRect = container.bounds.insetBy(dx: 0.75, dy: 0.75)
            let cornerRadius = max(0, loadingBubbleCornerRadius - 0.75)
            borderMask.path = CGPath(
                roundedRect: borderRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        }

        CATransaction.commit()
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
        let boldAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: baseFontSize, weight: .bold),
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

        for token in ChatMarkdownTokenizer.tokenize(source) {
            switch token {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .bold(let text):
                result.append(NSAttributedString(string: text, attributes: boldAttributes))
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

    private static func formattedTimestamp(_ date: Date, now: Date = Date()) -> String {
        let age = now.timeIntervalSince(date)
        if age >= 0, age < 60 {
            return String(localized: .ThreadStrings.chatRelativeTimeLessThanMinuteAgo)
        }
        return relativeTimestampFormatter.localizedString(for: date, relativeTo: now)
    }

    private static func exactTimestampTooltip(_ date: Date) -> String {
        exactTimestampFormatter.string(from: date)
    }

    private static func hoverMetadataText(modelLabel: String?, reasoningLevel: String?) -> String? {
        let cleanModel = modelLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReasoning = reasoningLevel?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if let cleanModel, !cleanModel.isEmpty, let cleanReasoning, !cleanReasoning.isEmpty {
            return "\(cleanModel) · \(cleanReasoning)"
        }
        if let cleanModel, !cleanModel.isEmpty {
            return cleanModel
        }
        if let cleanReasoning, !cleanReasoning.isEmpty {
            return cleanReasoning
        }
        return nil
    }

    private static func resolvedModelLabel(for modelId: String?, agentType: AgentType) -> String? {
        guard let modelId, !modelId.isEmpty else { return nil }
        guard let config = AgentModelsService.shared.config(for: agentType) else { return modelId }
        return config.models.first(where: { $0.id == modelId })?.label ?? modelId
    }

    private static let exactTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateStyle = .long
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let relativeTimestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func loadingStatusText(startedAt: Date, now: Date = Date()) -> String {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        return "Working (\(formattedElapsedDuration(elapsed)) • esc to interrupt)"
    }

    private static func formattedElapsedDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m \(seconds)s"
        }
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    private static var queuedSubmissionSuffix: String {
        "\n\nQueued: will be submitted after current response."
    }

    private static func isThinkingPlaceholderText(_ text: String) -> Bool {
        ChatBusyStateRecovery.isAssistantLoadingPlaceholder(text)
    }

    private static func isCancelledPlaceholderText(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) == ChatBusyStateRecovery.cancelledPlaceholderText
    }
}

final class ChatTabViewController: NSViewController, NSTextViewDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let chatIdentifier: String
    private(set) var agentType: AgentType
    private(set) var messages: [PersistedChatMessage]
    private(set) var modelId: String?
    private(set) var reasoningLevel: String?

    var onSubmit: ((String, [PersistedChatAttachment]) -> Void)?
    var onDraftChanged: ((String) -> Void)?
    var onDraftAttachmentsChanged: (([PersistedChatAttachment]) -> Void)?
    var onCancelRunningCommand: (() -> Void)?
    var onOpenMarkdownLink: ((String) -> Void)?
    var onModelReasoningChanged: ((String?, String?) -> Void)?
    var isCommandRunning: (() -> Bool)?

    private let scrollView = NSScrollView()
    private let messagesStack = NSStackView()
    private let inputTextView = ChatInputTextView(frame: .zero, textContainer: nil)
    private let attachButton = NSButton()
    private let sendButton = NSButton()
    private let scrollToBottomButton = NSButton()
    private let attachmentDropTargetView = ChatAttachmentDropTargetView()
    private let attachmentsScrollView = NSScrollView()
    private let attachmentsStackView = NSStackView()
    private let slashAutocompleteContainer = NSView()
    private let slashAutocompleteScrollView = NSScrollView()
    private let slashAutocompleteTableView = NSTableView()
    private let modelPicker = NSPopUpButton()
    private let reasoningPicker = NSPopUpButton()
    private let modelReasoningRow = NSStackView()
    private var relativeTimestampTimer: Timer?
    private var inputScrollView: NSScrollView?
    private let backgroundClickGesture = NSClickGestureRecognizer()
    private var inputHeightConstraint: NSLayoutConstraint?
    private var attachmentsHeightConstraint: NSLayoutConstraint?
    private var slashAutocompleteHeightConstraint: NSLayoutConstraint?
    private var filteredSlashCommands: [SlashCommandAutocompleteItem] = []
    private var chatAppearance: ChatAppearance
    private var chatFontSize: CGFloat
    private var pendingQueuedUserMessageIDs: Set<UUID>
    private var draftAttachments: [PersistedChatAttachment]
    private var renderedMessages: [PersistedChatMessage] = []
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
        draftAttachments: [PersistedChatAttachment] = [],
        modelId: String? = nil,
        reasoningLevel: String? = nil,
        pendingQueuedUserMessageIDs: Set<UUID> = []
    ) {
        let settings = PersistenceService.shared.loadSettings()
        self.chatIdentifier = identifier
        self.agentType = agentType
        self.messages = messages
        self.modelId = modelId
        self.reasoningLevel = reasoningLevel
        self.chatAppearance = ChatAppearance.resolve(from: settings)
        self.chatFontSize = Self.resolvedChatFontSize(from: settings)
        self.pendingQueuedUserMessageIDs = pendingQueuedUserMessageIDs
        self.draftAttachments = draftAttachments
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
        reloadMessages(forceFullReload: true)
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
        draftAttachments: [PersistedChatAttachment]? = nil,
        modelId: String? = nil,
        reasoningLevel: String? = nil,
        pendingQueuedUserMessageIDs: Set<UUID>? = nil
    ) {
        let previousAgentType = self.agentType
        self.agentType = agentType
        self.messages = messages
        self.modelId = modelId
        self.reasoningLevel = reasoningLevel
        if let pendingQueuedUserMessageIDs {
            self.pendingQueuedUserMessageIDs = pendingQueuedUserMessageIDs
        }
        if let draftAttachments {
            self.draftAttachments = draftAttachments
            reloadAttachmentChips()
        }
        if let draftInput, inputTextView.string != draftInput {
            inputTextView.string = draftInput
            updateComposerHeight()
        }
        if previousAgentType != agentType {
            configureModelReasoningPickers()
        } else {
            syncModelReasoningSelection()
        }
        reloadMessages(forceFullReload: previousAgentType != agentType)
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
            rootStack.topAnchor.constraint(equalTo: view.topAnchor),
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

        let composerContainer = attachmentDropTargetView
        composerContainer.translatesAutoresizingMaskIntoConstraints = false
        composerContainer.wantsLayer = true
        composerContainer.layer?.cornerRadius = 10
        composerContainer.layer?.borderWidth = 1
        composerContainer.layer?.masksToBounds = true
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            composerContainer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
            composerContainer.layer?.backgroundColor = NSColor(resource: .surface).withAlphaComponent(0.36).cgColor
        }
        rootStack.addArrangedSubview(composerContainer)

        let composerContentStack = NSStackView()
        composerContentStack.translatesAutoresizingMaskIntoConstraints = false
        composerContentStack.orientation = .vertical
        composerContentStack.alignment = .leading
        composerContentStack.spacing = 6
        composerContainer.addSubview(composerContentStack)

        NSLayoutConstraint.activate([
            composerContentStack.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor, constant: 8),
            composerContentStack.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor, constant: -8),
            composerContentStack.topAnchor.constraint(equalTo: composerContainer.topAnchor, constant: 8),
            composerContentStack.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor, constant: -8),
        ])

        setupSlashAutocompleteUI(composerContainer: composerContainer)

        attachmentsScrollView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsScrollView.drawsBackground = false
        attachmentsScrollView.borderType = .noBorder
        attachmentsScrollView.hasVerticalScroller = false
        attachmentsScrollView.hasHorizontalScroller = true
        attachmentsScrollView.autohidesScrollers = true
        attachmentsScrollView.scrollerStyle = .overlay
        attachmentsScrollView.horizontalScrollElasticity = .allowed
        attachmentsScrollView.verticalScrollElasticity = .none

        let attachmentsDocumentView = NSView()
        attachmentsDocumentView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsStackView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsStackView.orientation = .horizontal
        attachmentsStackView.alignment = .centerY
        attachmentsStackView.spacing = 8
        attachmentsDocumentView.addSubview(attachmentsStackView)
        attachmentsScrollView.documentView = attachmentsDocumentView

        NSLayoutConstraint.activate([
            attachmentsStackView.topAnchor.constraint(equalTo: attachmentsDocumentView.topAnchor),
            attachmentsStackView.leadingAnchor.constraint(equalTo: attachmentsDocumentView.leadingAnchor),
            attachmentsStackView.trailingAnchor.constraint(equalTo: attachmentsDocumentView.trailingAnchor),
            attachmentsStackView.bottomAnchor.constraint(equalTo: attachmentsDocumentView.bottomAnchor),
            attachmentsDocumentView.heightAnchor.constraint(equalTo: attachmentsStackView.heightAnchor),
        ])

        attachmentsHeightConstraint = attachmentsScrollView.heightAnchor.constraint(equalToConstant: 0)
        attachmentsHeightConstraint?.isActive = true
        attachmentsScrollView.isHidden = true
        composerContentStack.addArrangedSubview(attachmentsScrollView)
        attachmentsScrollView.widthAnchor.constraint(equalTo: composerContentStack.widthAnchor).isActive = true

        let composerStack = NSStackView()
        composerStack.translatesAutoresizingMaskIntoConstraints = false
        composerStack.orientation = .horizontal
        composerStack.alignment = .centerY
        composerStack.spacing = 8
        composerContentStack.addArrangedSubview(composerStack)
        composerStack.widthAnchor.constraint(equalTo: composerContentStack.widthAnchor).isActive = true

        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.drawsBackground = false
        inputScroll.borderType = .noBorder
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
        inputTextView.onControlC = { [weak self] in
            self?.handleComposerControlC() ?? false
        }
        inputTextView.onPasteImageFromClipboard = { [weak self] in
            self?.handlePasteImageFromClipboard() ?? false
        }
        inputTextView.onAttachmentDropHoverChanged = { [weak self] isHovering in
            self?.setAttachmentDropHoverActive(isHovering)
        }
        inputTextView.canAcceptAttachmentDrop = { [weak self] pasteboard in
            self?.canReadAttachments(from: pasteboard) ?? false
        }
        inputTextView.onAttachmentDrop = { [weak self] pasteboard in
            self?.handleAttachmentDrop(from: pasteboard) ?? false
        }
        inputScroll.documentView = inputTextView

        inputScrollView = inputScroll
        composerStack.addArrangedSubview(inputScroll)

        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachButton.title = ""
        attachButton.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attach")
        attachButton.imagePosition = .imageOnly
        attachButton.bezelStyle = .rounded
        attachButton.controlSize = .regular
        attachButton.target = self
        attachButton.action = #selector(attachFilesTapped)
        composerStack.addArrangedSubview(attachButton)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = ""
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")
        sendButton.imagePosition = .imageOnly
        sendButton.bezelStyle = .rounded
        sendButton.controlSize = .large
        sendButton.contentTintColor = .controlAccentColor
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.toolTip = "Return sends. Shift+Return inserts newline. Esc or Ctrl+C cancels running request."
        composerStack.addArrangedSubview(sendButton)

        NSLayoutConstraint.activate([
            {
                let c = inputScroll.heightAnchor.constraint(equalToConstant: minComposerHeight)
                inputHeightConstraint = c
                return c
            }(),
            attachButton.widthAnchor.constraint(equalToConstant: 30),
            attachButton.heightAnchor.constraint(equalToConstant: 30),
            sendButton.widthAnchor.constraint(equalToConstant: 34),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
        ])

        attachmentDropTargetView.onHoverChanged = { [weak self] isHovering in
            self?.setAttachmentDropHoverActive(isHovering)
        }
        attachmentDropTargetView.canAcceptDrop = { [weak self] pasteboard in
            self?.canReadAttachments(from: pasteboard) ?? false
        }
        attachmentDropTargetView.onPerformDrop = { [weak self] pasteboard in
            self?.handleAttachmentDrop(from: pasteboard) ?? false
        }
        reloadAttachmentChips()

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

    func setRelativeTimeUpdatesEnabled(_ enabled: Bool) {
        if enabled {
            startRelativeTimestampUpdatesIfNeeded()
            refreshVisibleRelativeTimestamps()
        } else {
            stopRelativeTimestampUpdates()
        }
    }

    private func startRelativeTimestampUpdatesIfNeeded() {
        guard relativeTimestampTimer == nil else { return }
        relativeTimestampTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshVisibleRelativeTimestamps()
            }
        }
    }

    private func stopRelativeTimestampUpdates() {
        relativeTimestampTimer?.invalidate()
        relativeTimestampTimer = nil
    }

    private func refreshVisibleRelativeTimestamps() {
        let now = Date()
        for case let bubble as ChatMessageBubbleView in messagesStack.arrangedSubviews {
            bubble.refreshRelativeTimestamp(now: now)
        }
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
        if clickedView.isDescendant(of: attachmentsScrollView) {
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

    private func makeMessageBubble(for message: PersistedChatMessage) -> ChatMessageBubbleView {
        let bubble = ChatMessageBubbleView(
            message: message,
            agentType: agentType,
            appearance: chatAppearance,
            fontSize: chatFontSize,
            queuedSubmissionPending: pendingQueuedUserMessageIDs.contains(message.id),
            onOpenLink: onOpenMarkdownLink
        )
        return bubble
    }

    private func pinMessageBubbleWidth(_ bubble: ChatMessageBubbleView) {
        // Activate only after insertion so both anchors share a common ancestor.
        bubble.widthAnchor.constraint(equalTo: messagesStack.widthAnchor).isActive = true
    }

    private func removeAllRenderedBubbles() {
        for subview in messagesStack.arrangedSubviews {
            messagesStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }

    private func applyIncrementalMessageRenderPlan(_ plan: ChatMessageRenderPlan) {
        guard case .incremental(let removeTailCount, let appendRange, let changedIndices) = plan else { return }

        if removeTailCount > 0 {
            for _ in 0..<removeTailCount {
                guard let last = messagesStack.arrangedSubviews.last else { break }
                messagesStack.removeArrangedSubview(last)
                last.removeFromSuperview()
            }
        }

        for index in changedIndices {
            guard messages.indices.contains(index) else { continue }
            guard messagesStack.arrangedSubviews.indices.contains(index) else { continue }
            let old = messagesStack.arrangedSubviews[index]
            messagesStack.removeArrangedSubview(old)
            old.removeFromSuperview()
            let bubble = makeMessageBubble(for: messages[index])
            messagesStack.insertArrangedSubview(bubble, at: index)
            pinMessageBubbleWidth(bubble)
        }

        if !appendRange.isEmpty {
            for index in appendRange where messages.indices.contains(index) {
                let bubble = makeMessageBubble(for: messages[index])
                messagesStack.addArrangedSubview(bubble)
                pinMessageBubbleWidth(bubble)
            }
        }
    }

    private func reloadMessages(
        shouldScrollToBottom: Bool = true,
        forceFullReload: Bool = false
    ) {
        let settings = PersistenceService.shared.loadSettings()
        chatAppearance = ChatAppearance.resolve(from: settings)
        chatFontSize = Self.resolvedChatFontSize(from: settings)
        inputTextView.font = .systemFont(ofSize: chatFontSize)
        updateComposerHeight()

        let plan = ChatMessageRenderPlanner.plan(previous: renderedMessages, next: messages)
        switch plan {
        case .fullReload:
            removeAllRenderedBubbles()
            for message in messages {
                let bubble = makeMessageBubble(for: message)
                messagesStack.addArrangedSubview(bubble)
                pinMessageBubbleWidth(bubble)
            }
        case .incremental:
            if forceFullReload {
                removeAllRenderedBubbles()
                for message in messages {
                    let bubble = makeMessageBubble(for: message)
                    messagesStack.addArrangedSubview(bubble)
                    pinMessageBubbleWidth(bubble)
                }
            } else {
                applyIncrementalMessageRenderPlan(plan)
            }
        }
        renderedMessages = messages
        refreshVisibleRelativeTimestamps()

        DispatchQueue.main.async { [weak self] in
            if shouldScrollToBottom {
                self?.scrollToBottom(animated: false)
            }
            self?.updateScrollToBottomButtonVisibility()
        }
    }

    @objc private func sendTapped() {
        let text = inputTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = draftAttachments
        guard !text.isEmpty || !attachments.isEmpty else {
            NSSound.beep()
            return
        }
        hideSlashAutocomplete()
        inputTextView.string = ""
        onDraftChanged?("")
        draftAttachments = []
        onDraftAttachmentsChanged?([])
        reloadAttachmentChips()
        updateComposerHeight()
        onSubmit?(text, attachments)
    }

    @objc private func attachFilesTapped() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        let handleSelection: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK else { return }
            self?.appendDraftAttachments(from: panel.urls)
        }

        if let window = view.window {
            panel.beginSheetModal(for: window, completionHandler: handleSelection)
        } else {
            handleSelection(panel.runModal())
        }
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

    private func setAttachmentDropHoverActive(_ isHovering: Bool) {
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            if isHovering {
                attachmentDropTargetView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
                attachmentDropTargetView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor
            } else {
                attachmentDropTargetView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.25).cgColor
                attachmentDropTargetView.layer?.backgroundColor = NSColor(resource: .surface).withAlphaComponent(0.36).cgColor
            }
        }
    }

    private func canReadAttachments(from pasteboard: NSPasteboard) -> Bool {
        if let fileURLs = pastedFileURLs(from: pasteboard), !fileURLs.isEmpty {
            return true
        }
        return pastedImages(from: pasteboard).isEmpty == false
    }

    private func handleAttachmentDrop(from pasteboard: NSPasteboard) -> Bool {
        var attachmentURLs: [URL] = []
        if let fileURLs = pastedFileURLs(from: pasteboard), !fileURLs.isEmpty {
            attachmentURLs.append(contentsOf: fileURLs)
        }
        let pastedImageURLs = pastedImages(from: pasteboard).compactMap { image in
            writeImageToTemporaryAttachmentFile(image)
        }
        attachmentURLs.append(contentsOf: pastedImageURLs)

        guard !attachmentURLs.isEmpty else { return false }
        appendDraftAttachments(from: attachmentURLs)
        return true
    }

    private func handlePasteImageFromClipboard() -> Bool {
        let pastedImageURLs = pastedImages(from: .general).compactMap { image in
            writeImageToTemporaryAttachmentFile(image)
        }
        guard !pastedImageURLs.isEmpty else { return false }
        appendDraftAttachments(from: pastedImageURLs)
        return true
    }

    private func pastedFileURLs(from pasteboard: NSPasteboard) -> [URL]? {
        guard let rawURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] else {
            return nil
        }
        return rawURLs.map { $0 as URL }
    }

    private func pastedImages(from pasteboard: NSPasteboard) -> [NSImage] {
        (pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]) ?? []
    }

    private func writeImageToTemporaryAttachmentFile(_ image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("magent-chat-attachments", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true, attributes: nil)
            let url = tempDirectory.appendingPathComponent("paste-\(UUID().uuidString).png")
            try pngData.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func appendDraftAttachments(from fileURLs: [URL]) {
        var existingPaths = Set(draftAttachments.map { normalizeAttachmentPath($0.filePath) })
        var changed = false

        for url in fileURLs {
            let path = normalizeAttachmentPath(url.path)
            guard !path.isEmpty else { continue }
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard !existingPaths.contains(path) else { continue }

            let kind = attachmentKind(for: URL(fileURLWithPath: path))
            draftAttachments.append(
                PersistedChatAttachment(
                    filePath: path,
                    kind: kind
                )
            )
            existingPaths.insert(path)
            changed = true
        }

        guard changed else { return }
        onDraftAttachmentsChanged?(draftAttachments)
        reloadAttachmentChips()
    }

    private func removeDraftAttachment(id: UUID) {
        guard let index = draftAttachments.firstIndex(where: { $0.id == id }) else { return }
        draftAttachments.remove(at: index)
        onDraftAttachmentsChanged?(draftAttachments)
        reloadAttachmentChips()
    }

    private func reloadAttachmentChips() {
        for view in attachmentsStackView.arrangedSubviews {
            attachmentsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if draftAttachments.isEmpty {
            attachmentsScrollView.isHidden = true
            attachmentsHeightConstraint?.constant = 0
            return
        }

        let closeLabel = String(localized: .CommonStrings.commonClose)
        for attachment in draftAttachments {
            let url = URL(fileURLWithPath: attachment.filePath)
            let preview = previewImage(for: attachment, fileURL: url)
            let kindBadge = kindBadgeText(for: attachment.kind)
            let chip = ChatAttachmentChipView(
                attachmentID: attachment.id,
                previewImage: preview,
                filename: url.lastPathComponent,
                kindBadge: kindBadge,
                removeAccessibilityLabel: closeLabel
            ) { [weak self] in
                self?.removeDraftAttachment(id: attachment.id)
            }
            attachmentsStackView.addArrangedSubview(chip)
        }

        attachmentsScrollView.isHidden = false
        attachmentsHeightConstraint?.constant = 106
    }

    private func previewImage(for attachment: PersistedChatAttachment, fileURL: URL) -> NSImage {
        switch attachment.kind {
        case .image:
            if let image = NSImage(contentsOf: fileURL) {
                return image
            }
        case .video:
            if let thumbnail = videoThumbnail(for: fileURL) {
                return thumbnail
            }
        case .file:
            break
        }
        return NSWorkspace.shared.icon(forFile: fileURL.path)
    }

    private func videoThumbnail(for fileURL: URL) -> NSImage? {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        do {
            let frame = try generator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
        } catch {
            return nil
        }
    }

    private func attachmentKind(for fileURL: URL) -> PersistedChatAttachmentKind {
        let pathExtension = fileURL.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathExtension.isEmpty,
              let type = UTType(filenameExtension: pathExtension) else {
            return .file
        }
        if type.conforms(to: .image) {
            return .image
        }
        if type.conforms(to: .movie) || type.conforms(to: .video) {
            return .video
        }
        return .file
    }

    private func kindBadgeText(for kind: PersistedChatAttachmentKind) -> String? {
        switch kind {
        case .image:
            return "IMG"
        case .video:
            return "VID"
        case .file:
            return nil
        }
    }

    private func normalizeAttachmentPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func handleComposerControlC() -> Bool {
        guard isCommandRunning?() == true else { return false }
        onCancelRunningCommand?()
        return true
    }

    private func handleComposerEscape() -> Bool {
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
            if !slashAutocompleteContainer.isHidden {
                hideSlashAutocomplete()
                return true
            }
            return handleComposerEscape()
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
        reloadMessages(shouldScrollToBottom: false, forceFullReload: true)
        updateSlashAutocompleteAppearance()
        updateScrollToBottomButtonAppearance()
        setAttachmentDropHoverActive(false)
        reloadAttachmentChips()
        configureModelReasoningPickers()
    }

    private static func resolvedChatFontSize(from settings: AppSettings) -> CGFloat {
        CGFloat(min(max(settings.chatFontSize, AppSettings.minChatFontSize), AppSettings.maxChatFontSize))
    }
}
