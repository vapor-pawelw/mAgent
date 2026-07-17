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
    var isPinned: Bool
    var isTitleManuallySet: Bool
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

private final class ChatAttachmentDropOverlayView: NSView {
    private let messageLabel = NSTextField(labelWithString: String(localized: .ThreadStrings.chatAttachmentDropOverlayTitle))
    private let dashLayer = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.addSublayer(dashLayer)
        alphaValue = 0

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .appPrimary
        addSubview(messageLabel)

        NSLayoutConstraint.activate([
            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func layout() {
        super.layout()
        dashLayer.frame = bounds
        dashLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 5, dy: 5),
            cornerWidth: 9,
            cornerHeight: 9,
            transform: nil
        )
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func updateAppearance() {
        messageLabel.textColor = .appPrimary
        effectiveAppearance.performAsCurrentDrawingAppearance {
            dashLayer.strokeColor = NSColor.appPrimary.withAlphaComponent(0.9).cgColor
            dashLayer.fillColor = NSColor.appPrimary.withAlphaComponent(0.10).cgColor
            dashLayer.lineWidth = 1.5
            dashLayer.lineDashPattern = [8, 5]
        }
    }
}

private final class ChatSurfaceDropView: NSView {
    var canAcceptDrop: ((NSPasteboard) -> Bool)?
    var onPerformDrop: ((NSPasteboard) -> Bool)?
    var onAppearanceChanged: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL, .png, .tiff])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackgroundColor()
        onAppearanceChanged?()
    }

    func updateBackgroundColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor(resource: .appBackground).cgColor
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        (canAcceptDrop?(sender.draggingPasteboard) ?? false) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        (canAcceptDrop?(sender.draggingPasteboard) ?? false) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canAcceptDrop?(sender.draggingPasteboard) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onPerformDrop?(sender.draggingPasteboard) ?? false
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
        onOpen: (() -> Void)? = nil,
        onRemove: (() -> Void)? = nil
    ) {
        self.attachmentID = attachmentID
        self.onRemove = onRemove
        self.onOpen = onOpen
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
        if onRemove != nil {
            removeButton.translatesAutoresizingMaskIntoConstraints = false
            removeButton.title = ""
            removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: removeAccessibilityLabel)
            removeButton.imagePosition = .imageOnly
            removeButton.isBordered = false
            removeButton.contentTintColor = .tertiaryLabelColor
            removeButton.target = self
            removeButton.action = #selector(removeTapped)
            addSubview(removeButton)
        }

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

        ])

        if onRemove != nil {
            NSLayoutConstraint.activate([
                removeButton.widthAnchor.constraint(equalToConstant: 16),
                removeButton.heightAnchor.constraint(equalToConstant: 16),
                removeButton.topAnchor.constraint(equalTo: topAnchor, constant: 2),
                removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            ])
        }

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

    private let onRemove: (() -> Void)?
    private let onOpen: (() -> Void)?

    override func resetCursorRects() {
        super.resetCursorRects()
        if onOpen != nil {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if let onOpen {
            onOpen()
            return
        }
        super.mouseDown(with: event)
    }

    @objc private func removeTapped() {
        onRemove?()
    }
}

private final class ChatImagePreviewOverlayView: NSView {
    private let image: NSImage
    private let imageView = NSImageView()
    private let zoomBadge = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private let zoomInButton = NSButton()
    private let zoomOutButton = NSButton()
    private let controlsStack = NSStackView()
    private var zoomScale: CGFloat = 1
    private var panOffset: CGPoint = .zero
    private var dragStartPoint: CGPoint?
    private var dragStartPanOffset: CGPoint = .zero
    var onClose: (() -> Void)?

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor

        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.masksToBounds = true
        addSubview(imageView)

        configureButton(
            closeButton,
            symbolName: "xmark",
            accessibilityDescription: String(localized: .ThreadStrings.chatAttachmentPreviewClose),
            action: #selector(closeTapped)
        )
        configureButton(
            zoomOutButton,
            symbolName: "minus.magnifyingglass",
            accessibilityDescription: String(localized: .ThreadStrings.chatAttachmentPreviewZoomOut),
            action: #selector(zoomOutTapped)
        )
        configureButton(
            zoomInButton,
            symbolName: "plus.magnifyingglass",
            accessibilityDescription: String(localized: .ThreadStrings.chatAttachmentPreviewZoomIn),
            action: #selector(zoomInTapped)
        )

        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 8
        controlsStack.addArrangedSubview(zoomOutButton)
        controlsStack.addArrangedSubview(zoomInButton)
        controlsStack.addArrangedSubview(closeButton)
        addSubview(controlsStack)

        zoomBadge.translatesAutoresizingMaskIntoConstraints = false
        zoomBadge.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        zoomBadge.textColor = .white
        zoomBadge.alignment = .center
        zoomBadge.wantsLayer = true
        zoomBadge.layer?.cornerRadius = 8
        zoomBadge.layer?.masksToBounds = true
        zoomBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.62).cgColor
        zoomBadge.isHidden = true
        addSubview(zoomBadge)

        NSLayoutConstraint.activate([
            controlsStack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            controlsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            zoomBadge.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 8),
            zoomBadge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            zoomBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 54),
            zoomBadge.heightAnchor.constraint(equalToConstant: 24),
        ])

        updateZoomControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        layoutImage()
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        guard bounds.contains(localPoint) else { return nil }
        for view in [closeButton, zoomInButton, zoomOutButton] {
            let buttonPoint = view.convert(localPoint, from: self)
            if view.bounds.contains(buttonPoint) {
                return view
            }
        }
        return self
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if imageView.frame.width > 0, imageView.frame.height > 0 {
            addCursorRect(imageView.frame, cursor: canPan ? .openHand : .pointingHand)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onClose?()
            return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard delta != 0 else {
            super.scrollWheel(with: event)
            return
        }
        setZoomScale(zoomScale * (delta > 0 ? 1.08 : 0.92))
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !zoomBadge.isHidden, zoomBadge.frame.contains(point) {
            setZoomScale(1)
            return
        }
        guard imageView.frame.contains(point) else {
            onClose?()
            return
        }
        guard canPan else { return }
        NSCursor.closedHand.set()
        dragStartPoint = point
        dragStartPanOffset = panOffset
    }

    override func mouseDragged(with event: NSEvent) {
        guard canPan, let dragStartPoint else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        panOffset = CGPoint(
            x: dragStartPanOffset.x + point.x - dragStartPoint.x,
            y: dragStartPanOffset.y + point.y - dragStartPoint.y
        )
        clampPanOffset()
        layoutImage()
    }

    override func mouseUp(with event: NSEvent) {
        dragStartPoint = nil
        if canPan {
            NSCursor.openHand.set()
        }
    }

    private var canPan: Bool {
        displayedImageSize.width > bounds.width || displayedImageSize.height > bounds.height
    }

    private var defaultImageScale: CGFloat {
        let imageSize = normalizedImageSize
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return 1
        }
        return min((bounds.width * 0.5) / imageSize.width, (bounds.height * 0.5) / imageSize.height)
    }

    private var displayedImageSize: CGSize {
        let imageSize = normalizedImageSize
        let scale = defaultImageScale * zoomScale
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    private var normalizedImageSize: CGSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return CGSize(width: 1, height: 1) }
        return size
    }

    private func configureButton(
        _ button: NSButton,
        symbolName: String,
        accessibilityDescription: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityDescription)
        button.imagePosition = .imageOnly
        button.bezelStyle = .rounded
        button.contentTintColor = .white
        button.target = self
        button.action = action
        button.toolTip = accessibilityDescription
        button.widthAnchor.constraint(equalToConstant: 32).isActive = true
        button.heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    private func layoutImage() {
        clampPanOffset()
        let size = displayedImageSize
        imageView.frame = CGRect(
            x: bounds.midX - size.width / 2 + panOffset.x,
            y: bounds.midY - size.height / 2 + panOffset.y,
            width: size.width,
            height: size.height
        )
    }

    private func setZoomScale(_ newScale: CGFloat) {
        zoomScale = min(max(newScale, 0.25), 6)
        if abs(zoomScale - 1) < 0.01 {
            zoomScale = 1
            panOffset = .zero
        }
        clampPanOffset()
        layoutImage()
        updateZoomControls()
        window?.invalidateCursorRects(for: self)
    }

    private func clampPanOffset() {
        let size = displayedImageSize
        let maxX = max(0, (size.width - bounds.width) / 2)
        let maxY = max(0, (size.height - bounds.height) / 2)
        panOffset.x = min(max(panOffset.x, -maxX), maxX)
        panOffset.y = min(max(panOffset.y, -maxY), maxY)
    }

    private func updateZoomControls() {
        let percent = Int((zoomScale * 100).rounded())
        zoomBadge.stringValue = "\(percent)%"
        zoomBadge.isHidden = zoomScale == 1
        zoomOutButton.isEnabled = zoomScale > 0.25
        zoomInButton.isEnabled = zoomScale < 6
    }

    @objc private func closeTapped() {
        onClose?()
    }

    @objc private func zoomInTapped() {
        setZoomScale(zoomScale * 1.25)
    }

    @objc private func zoomOutTapped() {
        setZoomScale(zoomScale / 1.25)
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
    private let contentStack = NSStackView()
    private let messageTextView = ChatMessageTextView()
    private let toolHeaderStack = NSStackView()
    private let toolKindImageView = NSImageView()
    private let toolDisclosureButton = NSButton(title: "", target: nil, action: nil)
    private let loadingProgressIndicator = NSProgressIndicator()
    private let loadingStatusLabel = NSTextField(labelWithString: "")
    private let createdAt: Date
    private let onOpenLink: ((String) -> Void)?
    private let onOpenAttachment: ((PersistedChatAttachment) -> Void)?
    private let isQueuedSubmissionPending: Bool
    private let rendersAsSeparator: Bool
    private var bubbleHeightConstraint: NSLayoutConstraint?
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private let isLoadingIndicatorBubble: Bool
    private let isUnboxedAssistant: Bool
    private var maxBubbleWidth: CGFloat { isUnboxedAssistant ? 760 : 560 }
    private let minBubbleWidth: CGFloat = 44
    private var bubbleHorizontalPadding: CGFloat { isUnboxedAssistant ? 0 : 24 }
    private var bubbleVerticalPadding: CGFloat { isUnboxedAssistant ? 8 : 20 }
    private var messageAttachmentStripHeight: CGFloat = 0
    private var messageTextHidden = false
    private var toolPresentation: ChatToolTranscriptPresentation?
    private var statusPresentation: ChatMessageStatusPresentation?
    private var toolExpanded = false
    private var toolDisclosureFontSize: CGFloat = 12
    private var toolDisclosureTextColor: NSColor = .labelColor
    private let loadingPlaceholderText: String

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
        onOpenLink: ((String) -> Void)? = nil,
        onOpenAttachment: ((PersistedChatAttachment) -> Void)? = nil
    ) {
        self.createdAt = message.createdAt
        self.onOpenLink = onOpenLink
        self.onOpenAttachment = onOpenAttachment
        self.isQueuedSubmissionPending = queuedSubmissionPending
        self.rendersAsSeparator = message.role == .system
        self.isLoadingIndicatorBubble = message.role == .assistant && Self.isThinkingPlaceholderText(message.text)
        self.loadingPlaceholderText = message.text
        let displayPlan = ChatMessageDisplayPlanner.plan(for: message)
        switch displayPlan.kind {
        case .message:
            break
        case .tool(let presentation):
            self.toolPresentation = presentation
        case .status(let presentation):
            self.statusPresentation = presentation
        }
        self.isUnboxedAssistant = displayPlan.role == .assistant && self.statusPresentation == nil
        self.toolExpanded = self.toolPresentation?.isExpandedByDefault ?? false
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let displayRole = displayPlan.role
        if rendersAsSeparator {
            configureSeparatorMessage(text: message.text, fontSize: fontSize)
            return
        }

        container.translatesAutoresizingMaskIntoConstraints = false
        container.wantsLayer = true
        container.layer?.cornerRadius = isUnboxedAssistant ? 0 : 14
        container.layer?.masksToBounds = true
        addSubview(container)

        let exactTimestampTooltip = Self.exactTimestampTooltip(message.createdAt)
        let metadataText = Self.hoverMetadataText(
            modelLabel: Self.resolvedModelLabel(for: message.modelId, agentType: agentType),
            reasoningLevel: message.reasoningLevel
        )
        let metadataTooltip = ChatTimestampPresentation.metadataTooltip(
            exactText: exactTimestampTooltip,
            metadataText: metadataText
        )
        toolTip = metadataTooltip
        container.toolTip = metadataTooltip

        let baseTextColor: NSColor
        let codeColor: NSColor
        switch displayRole {
        case .user:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = appearance.userBubbleColor.cgColor
            }
            baseTextColor = appearance.userTextColor
            codeColor = appearance.userTextColor.withAlphaComponent(0.75)
            if isQueuedSubmissionPending {
                container.alphaValue = 0.65
            }
        case .system:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                container.layer?.backgroundColor = NSColor.appPrimary.withAlphaComponent(0.10).cgColor
                container.layer?.borderWidth = 1
                container.layer?.borderColor = NSColor.appPrimary.withAlphaComponent(0.22).cgColor
            }
            baseTextColor = NSColor(resource: .textSecondary)
            codeColor = baseTextColor
        case .assistant:
            effectiveAppearance.performAsCurrentDrawingAppearance {
                let bubbleColor = isUnboxedAssistant
                    ? NSColor.clear
                    : (isLoadingIndicatorBubble ? NSColor(resource: .appBackground) : appearance.agentBubbleColor)
                container.layer?.backgroundColor = bubbleColor.cgColor
            }
            if statusPresentation?.kind == .cancellation {
                baseTextColor = NSColor(calibratedRed: 0.62, green: 0.12, blue: 0.12, alpha: 1.0)
                codeColor = baseTextColor.withAlphaComponent(0.85)
            } else if statusPresentation?.kind == .approvalRequired {
                baseTextColor = NSColor(resource: .primaryBrand)
                codeColor = NSColor(resource: .textSecondary)
            } else if statusPresentation?.kind == .error {
                baseTextColor = NSColor(calibratedRed: 0.62, green: 0.12, blue: 0.12, alpha: 1.0)
                codeColor = baseTextColor.withAlphaComponent(0.85)
            } else {
                baseTextColor = appearance.agentTextColor
                codeColor = NSColor(resource: .textSecondary)
            }
        }

        if isLoadingIndicatorBubble {
            let loadingStack = NSStackView()
            loadingStack.translatesAutoresizingMaskIntoConstraints = false
            loadingStack.orientation = .horizontal
            loadingStack.alignment = .centerY
            loadingStack.spacing = 7

            loadingProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
            loadingProgressIndicator.style = .spinning
            loadingProgressIndicator.controlSize = .small
            loadingProgressIndicator.isIndeterminate = true
            loadingProgressIndicator.toolTip = metadataTooltip
            loadingProgressIndicator.startAnimation(nil)
            loadingStack.addArrangedSubview(loadingProgressIndicator)

            loadingStatusLabel.translatesAutoresizingMaskIntoConstraints = false
            loadingStatusLabel.font = .systemFont(ofSize: fontSize, weight: .regular)
            loadingStatusLabel.textColor = baseTextColor.withAlphaComponent(0.6)
            loadingStatusLabel.lineBreakMode = .byTruncatingTail
            loadingStatusLabel.toolTip = metadataTooltip
            loadingStatusLabel.stringValue = Self.loadingStatusText(
                placeholderText: loadingPlaceholderText,
                startedAt: createdAt
            )
            loadingStack.addArrangedSubview(loadingStatusLabel)
            container.addSubview(loadingStack)
            NSLayoutConstraint.activate([
                loadingStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                loadingStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                loadingStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                loadingStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            ])
        } else {
            contentStack.translatesAutoresizingMaskIntoConstraints = false
            contentStack.orientation = .vertical
            contentStack.alignment = .leading
            contentStack.spacing = 8
            container.addSubview(contentStack)

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
            messageTextView.toolTip = metadataTooltip
            messageTextView.linkTextAttributes = [
                .foregroundColor: NSColor.appPrimary,
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
            ]
            let queuedSuffix = Self.queuedSubmissionSuffix
            let renderedMessageText: String
            if let toolPresentation {
                renderedMessageText = toolPresentation.body
            } else if let statusPresentation {
                renderedMessageText = Self.statusMessageText(statusPresentation)
            } else if ChatTranscriptDisplayCompactor.isActivitySummary(message) {
                renderedMessageText = ChatTranscriptDisplayCompactor.plainText(fromActivitySummary: message.text)
            } else if displayRole == .user, isQueuedSubmissionPending {
                renderedMessageText = "\(message.text)\(queuedSuffix)"
            } else {
                renderedMessageText = message.text
            }
            messageTextHidden = renderedMessageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (toolPresentation != nil && !toolExpanded)
            let attributedMessage = NSMutableAttributedString(
                attributedString: Self.styledMarkdownText(
                    toolPresentation?.title == "Activity"
                        ? ChatTranscriptDisplayCompactor.plainText(fromActivitySummary: renderedMessageText)
                        : renderedMessageText,
                    baseColor: baseTextColor,
                    codeColor: codeColor,
                    linkColor: NSColor.appPrimary,
                    baseFontSize: fontSize
                )
            )
            if let toolPresentation, toolPresentation.title == "Activity" {
                Self.applyActivitySummaryStyle(
                    to: attributedMessage,
                    rawText: toolPresentation.body,
                    baseColor: baseTextColor,
                    baseFontSize: fontSize
                )
            } else if toolPresentation != nil {
                Self.applyToolTranscriptStyle(to: attributedMessage, baseColor: baseTextColor, baseFontSize: fontSize)
                Self.applyDiffLineHighlights(to: attributedMessage, baseFontSize: fontSize)
            }
            if toolPresentation == nil, ChatTranscriptDisplayCompactor.isActivitySummary(message) {
                Self.applyActivitySummaryStyle(
                    to: attributedMessage,
                    rawText: message.text,
                    baseColor: baseTextColor,
                    baseFontSize: fontSize
                )
            }
            if displayRole == .user, isQueuedSubmissionPending {
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

            if let toolPresentation {
                configureToolDisclosureButton(presentation: toolPresentation, fontSize: fontSize, textColor: baseTextColor)
                toolDisclosureButton.toolTip = metadataTooltip
                toolKindImageView.toolTip = metadataTooltip
                contentStack.addArrangedSubview(toolHeaderStack)
                toolHeaderStack.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
            }

            messageTextView.translatesAutoresizingMaskIntoConstraints = false
            messageTextView.isHidden = messageTextHidden
            contentStack.addArrangedSubview(messageTextView)

            if !message.attachments.isEmpty {
                let attachmentScrollView = Self.makeAttachmentStrip(
                    attachments: message.attachments,
                    removeAccessibilityLabel: String(localized: .CommonStrings.commonClose),
                    onOpenAttachment: onOpenAttachment
                )
                contentStack.addArrangedSubview(attachmentScrollView)
                messageAttachmentStripHeight = 106
            }
        }

        let bubbleRow = NSStackView()
        bubbleRow.translatesAutoresizingMaskIntoConstraints = false
        bubbleRow.orientation = .horizontal
        bubbleRow.alignment = .centerY
        bubbleRow.spacing = 8

        let bubbleSpacer = NSView()
        bubbleSpacer.translatesAutoresizingMaskIntoConstraints = false
        bubbleSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bubbleSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        switch displayRole {
        case .user:
            bubbleRow.addArrangedSubview(bubbleSpacer)
            bubbleRow.addArrangedSubview(container)
        case .assistant:
            bubbleRow.addArrangedSubview(container)
            bubbleRow.addArrangedSubview(bubbleSpacer)
        case .system:
            bubbleRow.addArrangedSubview(bubbleSpacer)
            bubbleRow.addArrangedSubview(container)
            let trailingSpacer = NSView()
            trailingSpacer.translatesAutoresizingMaskIntoConstraints = false
            trailingSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            trailingSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            bubbleRow.addArrangedSubview(trailingSpacer)
        }

        addSubview(bubbleRow)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(lessThanOrEqualToConstant: maxBubbleWidth),

            bubbleRow.topAnchor.constraint(equalTo: topAnchor),
            bubbleRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            bubbleRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            bubbleRow.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        if !isLoadingIndicatorBubble {
            bubbleHeightConstraint = container.heightAnchor.constraint(equalToConstant: 20)
            bubbleHeightConstraint?.isActive = true
            bubbleWidthConstraint = container.widthAnchor.constraint(equalToConstant: maxBubbleWidth)
            bubbleWidthConstraint?.priority = .defaultHigh
            bubbleWidthConstraint?.isActive = true
            let horizontalInset: CGFloat = isUnboxedAssistant ? 0 : 12
            let verticalInset: CGFloat = isUnboxedAssistant ? 4 : 10
            NSLayoutConstraint.activate([
                contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
                contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset),
                contentStack.topAnchor.constraint(equalTo: container.topAnchor, constant: verticalInset),
                contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -verticalInset),
                messageTextView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        guard !rendersAsSeparator else { return }
        if !isLoadingIndicatorBubble {
            updateBubbleLayout()
        }
    }

    func scheduleMeasuredLayoutRefresh() {
        guard !isLoadingIndicatorBubble, !rendersAsSeparator else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshMeasuredLayout()
        }
    }

    private func refreshMeasuredLayout() {
        guard !isLoadingIndicatorBubble, !rendersAsSeparator else { return }
        if let layoutManager = messageTextView.layoutManager,
           let textStorage = messageTextView.textStorage {
            layoutManager.invalidateLayout(
                forCharacterRange: NSRange(location: 0, length: textStorage.length),
                actualCharacterRange: nil
            )
        }
        needsLayout = true
        layoutSubtreeIfNeeded()
        updateBubbleLayout()
        superview?.needsLayout = true
        superview?.layoutSubtreeIfNeeded()
    }

    func clearSelection() {
        guard !isLoadingIndicatorBubble, !rendersAsSeparator else { return }
        messageTextView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func refreshRelativeTimestamp(now: Date = Date()) {
        guard !rendersAsSeparator else { return }
        if isLoadingIndicatorBubble {
            let statusText = Self.loadingStatusText(
                placeholderText: loadingPlaceholderText,
                startedAt: createdAt,
                now: now
            )
            guard loadingStatusLabel.stringValue != statusText else { return }

            loadingStatusLabel.stringValue = statusText
            loadingStatusLabel.invalidateIntrinsicContentSize()

            // Loading rows do not use `updateBubbleLayout()`, so force an Auto Layout
            // pass after the elapsed-time label changes.
            needsUpdateConstraints = true
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }


    private func configureSeparatorMessage(text: String, fontSize: CGFloat) {
        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        addSubview(row)

        let leadingLine = makeSeparatorLine()
        let trailingLine = makeSeparatorLine()
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: max(11, fontSize - 1), weight: .medium)
        label.textColor = NSColor(resource: .textSecondary)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)

        row.addArrangedSubview(leadingLine)
        row.addArrangedSubview(label)
        row.addArrangedSubview(trailingLine)

        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            leadingLine.heightAnchor.constraint(equalToConstant: 1),
            trailingLine.heightAnchor.constraint(equalToConstant: 1),
            leadingLine.widthAnchor.constraint(equalTo: trailingLine.widthAnchor),
            leadingLine.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            trailingLine.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
        ])
    }

    private func makeSeparatorLine() -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        effectiveAppearance.performAsCurrentDrawingAppearance {
            line.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.65).cgColor
        }
        return line
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
        let measuredToolHeaderWidth = toolPresentation == nil ? 0 : ceil(toolDisclosureButton.intrinsicContentSize.width)
        let targetBubbleWidth = min(
            maxBubbleWidth,
            max(minBubbleWidth, ceil(max(measuredLineWidth, measuredToolHeaderWidth) + bubbleHorizontalPadding))
        )
        if abs(bubbleWidthConstraint.constant - targetBubbleWidth) > 0.5 {
            bubbleWidthConstraint.constant = targetBubbleWidth
        }

        let targetTextWidth = max(1, targetBubbleWidth - bubbleHorizontalPadding)
        if abs(textContainer.containerSize.width - targetTextWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: targetTextWidth, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: textContainer)
        }

        let textHeight = messageTextHidden ? 0 : ceil(layoutManager.usedRect(for: textContainer).height)
        let toolHeaderHeight = toolPresentation == nil ? 0 : ceil(toolDisclosureButton.intrinsicContentSize.height)
        let visibleBlocks = [toolHeaderHeight, textHeight, messageAttachmentStripHeight].filter { $0 > 0 }
        let contentSpacing = CGFloat(max(0, visibleBlocks.count - 1)) * contentStack.spacing
        bubbleHeightConstraint?.constant = max(
            20,
            toolHeaderHeight + textHeight + messageAttachmentStripHeight + contentSpacing + bubbleVerticalPadding
        )
    }

    private static func makeAttachmentStrip(
        attachments: [PersistedChatAttachment],
        removeAccessibilityLabel: String,
        onOpenAttachment: ((PersistedChatAttachment) -> Void)?
    ) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        documentView.addSubview(stack)
        scrollView.documentView = documentView

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: documentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: documentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: documentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
            documentView.heightAnchor.constraint(equalTo: stack.heightAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 106),
        ])

        for attachment in attachments {
            let fileURL = URL(fileURLWithPath: attachment.filePath)
            let chip = ChatAttachmentChipView(
                attachmentID: attachment.id,
                previewImage: previewImage(for: attachment, fileURL: fileURL),
                filename: fileURL.lastPathComponent,
                kindBadge: kindBadgeText(for: attachment.kind),
                removeAccessibilityLabel: removeAccessibilityLabel,
                onOpen: attachment.kind == .image ? {
                    onOpenAttachment?(attachment)
                } : nil,
                onRemove: nil
            )
            stack.addArrangedSubview(chip)
        }

        return scrollView
    }

    private static func previewImage(for attachment: PersistedChatAttachment, fileURL: URL) -> NSImage {
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

    private static func videoThumbnail(for fileURL: URL) -> NSImage? {
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

    private static func kindBadgeText(for kind: PersistedChatAttachmentKind) -> String? {
        switch kind {
        case .image:
            return "IMG"
        case .video:
            return "VID"
        case .file:
            return "FILE"
        }
    }

    @objc private func toggleToolExpanded() {
        guard toolPresentation != nil else { return }
        toolExpanded.toggle()
        messageTextHidden = !toolExpanded
        messageTextView.isHidden = messageTextHidden
        refreshToolDisclosureTitle()
        needsLayout = true
        updateBubbleLayout()
    }

    private func configureToolDisclosureButton(presentation: ChatToolTranscriptPresentation, fontSize: CGFloat, textColor: NSColor) {
        toolDisclosureFontSize = fontSize
        toolDisclosureTextColor = textColor
        toolHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        toolHeaderStack.orientation = .horizontal
        toolHeaderStack.alignment = .firstBaseline
        toolHeaderStack.spacing = 7

        let iconConfig = NSImage.SymbolConfiguration(pointSize: max(11, fontSize - 1), weight: .medium)
        toolKindImageView.translatesAutoresizingMaskIntoConstraints = false
        toolKindImageView.image = NSImage(
            systemSymbolName: Self.toolSymbolName(for: presentation),
            accessibilityDescription: presentation.title
        )?.withSymbolConfiguration(iconConfig)
        toolKindImageView.contentTintColor = textColor.withAlphaComponent(0.68)
        toolKindImageView.setContentHuggingPriority(.required, for: .horizontal)
        toolHeaderStack.addArrangedSubview(toolKindImageView)

        toolDisclosureButton.translatesAutoresizingMaskIntoConstraints = false
        toolDisclosureButton.isBordered = false
        toolDisclosureButton.alignment = .left
        toolDisclosureButton.font = .systemFont(ofSize: max(11, fontSize - 1), weight: .medium)
        toolDisclosureButton.contentTintColor = textColor.withAlphaComponent(0.85)
        toolDisclosureButton.lineBreakMode = .byWordWrapping
        toolDisclosureButton.cell?.wraps = true
        toolDisclosureButton.cell?.lineBreakMode = .byWordWrapping
        toolDisclosureButton.target = self
        toolDisclosureButton.action = #selector(toggleToolExpanded)
        toolDisclosureButton.setButtonType(.momentaryChange)
        toolDisclosureButton.toolTip = "Click to expand tool details"
        toolDisclosureButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        toolDisclosureButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        toolHeaderStack.addArrangedSubview(toolDisclosureButton)
        refreshToolDisclosureTitle()
    }

    private func refreshToolDisclosureTitle() {
        guard let toolPresentation else { return }
        let title = NSMutableAttributedString()
        let baseFontSize = max(11, toolDisclosureFontSize - 1)
        title.append(NSAttributedString(
            string: toolPresentation.title,
            attributes: [
                .font: NSFont.systemFont(ofSize: baseFontSize, weight: .semibold),
                .foregroundColor: toolDisclosureTextColor,
            ]
        ))
        let trimmedDetail = toolPresentation.detail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail = trimmedDetail, !detail.isEmpty {
            title.append(NSAttributedString(
                string: "\n\(detail)",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: max(10, baseFontSize - 1), weight: .regular),
                    .foregroundColor: toolDisclosureTextColor.withAlphaComponent(0.72),
                ]
            ))
        }
        toolDisclosureButton.attributedTitle = title
        let chevronName = toolExpanded ? "chevron.down" : "chevron.right"
        toolDisclosureButton.image = NSImage(
            systemSymbolName: chevronName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        toolDisclosureButton.imagePosition = .imageLeading
        toolDisclosureButton.contentTintColor = toolDisclosureTextColor.withAlphaComponent(0.72)
    }

    private static func toolSymbolName(for presentation: ChatToolTranscriptPresentation) -> String {
        if presentation.title == "Activity" { return "bolt.horizontal.circle" }
        let title = presentation.title.lowercased()
        if title.contains("patch") || title.contains("edit") { return "pencil.and.outline" }
        if title.contains("read") { return "doc.text.magnifyingglass" }
        if title.contains("command") { return presentation.kind == .result ? "terminal.fill" : "terminal" }
        switch presentation.kind {
        case .call: return "hammer"
        case .output: return "text.alignleft"
        case .result: return "checkmark.circle"
        }
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

    private static func applyDiffLineHighlights(to attributed: NSMutableAttributedString, baseFontSize: CGFloat) {
        let full = attributed.string as NSString
        let addedColor = NSColor.systemGreen.withAlphaComponent(0.18)
        let removedColor = NSColor.systemRed.withAlphaComponent(0.18)
        let headerColor = NSColor.systemBlue.withAlphaComponent(0.12)
        let patchHeaderColor = NSColor.systemPurple.withAlphaComponent(0.12)
        full.enumerateSubstrings(in: NSRange(location: 0, length: full.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            guard range.length > 0 else { return }
            let line = full.substring(with: range)
            let color: NSColor?
            if line.hasPrefix("+") && !line.hasPrefix("+++") { color = addedColor }
            else if line.hasPrefix("-") && !line.hasPrefix("---") { color = removedColor }
            else if line.hasPrefix("@@") || line.hasPrefix("diff --git") { color = headerColor }
            else if line.hasPrefix("*** ") || line.hasPrefix("@@") { color = patchHeaderColor }
            else { color = nil }
            if let color { attributed.addAttribute(.backgroundColor, value: color, range: range) }
        }
    }

    private static func applyToolTranscriptStyle(
        to attributed: NSMutableAttributedString,
        baseColor: NSColor,
        baseFontSize: CGFloat
    ) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return }

        let monoFont = NSFont.monospacedSystemFont(ofSize: max(11, baseFontSize - 1), weight: .regular)
        attributed.addAttributes(
            [
                .font: monoFont,
                .foregroundColor: baseColor.withAlphaComponent(0.92),
            ],
            range: fullRange
        )

        let sectionFont = NSFont.systemFont(ofSize: max(11, baseFontSize - 1), weight: .semibold)
        let sectionColor = NSColor.appPrimary
        let full = attributed.string as NSString
        full.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            guard range.length > 0 else { return }
            let line = full.substring(with: range)
            if ["Command", "Working directory", "Options", "Arguments", "Status", "Output", "Patch"].contains(line) {
                attributed.addAttributes(
                    [
                        .font: sectionFont,
                        .foregroundColor: sectionColor,
                    ],
                    range: range
                )
            }
        }
    }

    private static func applyActivitySummaryStyle(
        to attributed: NSMutableAttributedString,
        rawText: String,
        baseColor: NSColor,
        baseFontSize: CGFloat
    ) {
        let fullRange = NSRange(location: 0, length: attributed.length)
        guard fullRange.length > 0 else { return }

        attributed.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: baseFontSize, weight: .regular),
                .foregroundColor: baseColor.withAlphaComponent(0.9),
            ],
            range: fullRange
        )

        let headlineRange = (attributed.string as NSString).range(of: "Activity")
        if headlineRange.location != NSNotFound {
            attributed.addAttributes(
                [
                    .font: NSFont.systemFont(ofSize: baseFontSize, weight: .semibold),
                    .foregroundColor: baseColor,
                ],
                range: headlineRange
            )
        }

        let insertions = ChatTranscriptDisplayCompactor.activitySummarySymbolInsertions(
            rawText: rawText,
            renderedText: attributed.string
        )
        for insertion in insertions.reversed() {
            let attachment = NSTextAttachment()
            let symbolConfiguration = NSImage.SymbolConfiguration(
                paletteColors: [baseColor.withAlphaComponent(0.62)]
            )
            let image = NSImage(systemSymbolName: insertion.symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfiguration)
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -2, width: baseFontSize, height: baseFontSize)
            let iconString = NSMutableAttributedString(attachment: attachment)
            iconString.append(NSAttributedString(string: " "))
            guard insertion.utf16Offset <= attributed.length else { continue }
            attributed.insert(iconString, at: insertion.utf16Offset)
        }
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

    private static func loadingStatusText(
        placeholderText: String,
        startedAt: Date,
        now: Date = Date()
    ) -> String {
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let verb = placeholderText.trimmingCharacters(in: .whitespacesAndNewlines) == ChatBusyStateRecovery.continuedWorkPlaceholderText
            ? "Still working"
            : "Working"
        return "\(verb) (\(formattedElapsedDuration(elapsed)) • esc to interrupt)"
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

    private static func statusMessageText(_ status: ChatMessageStatusPresentation) -> String {
        guard let detail = status.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !detail.isEmpty else {
            return status.title
        }
        return "\(status.title)\n\(detail)"
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
    private let inputTextView = ChatInputTextView()
    private let attachButton = NSButton()
    private let sendButton = NSButton()
    private let scrollToBottomButton = NSButton()
    private let rootDropView = ChatSurfaceDropView()
    private let composerContainerView = NSView()
    private let attachmentDropOverlayView = ChatAttachmentDropOverlayView()
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
    private var renderedDisplayMessages: [PersistedChatMessage] = []
    private var messageRenderGeneration = UUID()
    private var postMessageLayoutUpdateScheduled = false
    private var pendingPostMessageScrollToBottom = false
    private weak var mediaPreviewOverlayView: ChatImagePreviewOverlayView?
    private let initialDraftInput: String

    private let slashAutocompleteRowHeight: CGFloat = 46
    private let slashAutocompleteVisibleRowsLimit = 5
    private let slashAutocompleteVerticalPadding: CGFloat = 6
    private static let slashAutocompleteCellIdentifier = NSUserInterfaceItemIdentifier("slash-autocomplete-cell")
    private static let progressiveFullReloadThreshold = 60
    private static let progressiveFullReloadBatchSize = 20

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
        rootDropView.wantsLayer = true
        rootDropView.updateBackgroundColor()
        rootDropView.onAppearanceChanged = { [weak self] in
            self?.updateComposerAppearance()
            self?.updateSlashAutocompleteAppearance()
            self?.updateScrollToBottomButtonAppearance()
        }
        view = rootDropView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureSurfaceDropTarget()
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

    private func configureSurfaceDropTarget() {
        rootDropView.canAcceptDrop = { [weak self] pasteboard in
            self?.canReadAttachments(from: pasteboard) ?? false
        }
        rootDropView.onPerformDrop = { [weak self] pasteboard in
            self?.handleAttachmentDrop(from: pasteboard) ?? false
        }
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
        messagesStack.spacing = 12

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

        let composerContainer = composerContainerView
        composerContainer.translatesAutoresizingMaskIntoConstraints = false
        composerContainer.wantsLayer = true
        composerContainer.layer?.cornerRadius = 12
        composerContainer.layer?.borderWidth = 1
        composerContainer.layer?.masksToBounds = true
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
            composerContentStack.topAnchor.constraint(equalTo: composerContainer.topAnchor, constant: 6),
            composerContentStack.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor, constant: -6),
        ])

        composerContainer.addSubview(attachmentDropOverlayView)
        let attachmentsDocumentView = NSView()
        attachmentsDocumentView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsScrollView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsScrollView.hasVerticalScroller = false
        attachmentsScrollView.hasHorizontalScroller = true
        attachmentsScrollView.autohidesScrollers = true
        attachmentsScrollView.drawsBackground = false
        attachmentsScrollView.borderType = .noBorder
        attachmentsScrollView.documentView = attachmentsDocumentView
        attachmentsStackView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsStackView.orientation = .horizontal
        attachmentsStackView.alignment = .centerY
        attachmentsStackView.spacing = 8
        attachmentsDocumentView.addSubview(attachmentsStackView)
        NSLayoutConstraint.activate([
            attachmentDropOverlayView.leadingAnchor.constraint(equalTo: composerContainer.leadingAnchor),
            attachmentDropOverlayView.trailingAnchor.constraint(equalTo: composerContainer.trailingAnchor),
            attachmentDropOverlayView.topAnchor.constraint(equalTo: composerContainer.topAnchor),
            attachmentDropOverlayView.bottomAnchor.constraint(equalTo: composerContainer.bottomAnchor),
            attachmentsStackView.leadingAnchor.constraint(equalTo: attachmentsDocumentView.leadingAnchor),
            attachmentsStackView.trailingAnchor.constraint(equalTo: attachmentsDocumentView.trailingAnchor),
            attachmentsStackView.topAnchor.constraint(equalTo: attachmentsDocumentView.topAnchor),
            attachmentsStackView.bottomAnchor.constraint(equalTo: attachmentsDocumentView.bottomAnchor),
            attachmentsDocumentView.heightAnchor.constraint(equalTo: attachmentsStackView.heightAnchor),
        ])

        attachmentsHeightConstraint = attachmentsScrollView.heightAnchor.constraint(equalToConstant: 0)
        attachmentsHeightConstraint?.isActive = true
        attachmentsScrollView.isHidden = true
        composerContentStack.addArrangedSubview(attachmentsScrollView)
        attachmentsScrollView.widthAnchor.constraint(equalTo: composerContentStack.widthAnchor).isActive = true

        let inputScroll = NSScrollView()
        inputScroll.translatesAutoresizingMaskIntoConstraints = false
        inputScroll.drawsBackground = false
        inputScroll.borderType = .noBorder
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.scrollerStyle = .legacy

        inputTextView.isRichText = false
        inputTextView.drawsBackground = false
        inputTextView.isEditable = true
        inputTextView.isSelectable = true
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
        inputTextView.setAccessibilityIdentifier("chat-composer-input")
        inputTextView.onControlC = { [weak self] in
            self?.handleComposerControlC() ?? false
        }
        inputTextView.onPasteImageFromClipboard = { [weak self] in
            self?.handlePasteImageFromClipboard() ?? false
        }
        inputTextView.registerForDraggedTypes([.fileURL, .png, .tiff])
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
        composerContentStack.addArrangedSubview(inputScroll)
        inputScroll.widthAnchor.constraint(equalTo: composerContentStack.widthAnchor).isActive = true

        attachButton.translatesAutoresizingMaskIntoConstraints = false
        attachButton.title = ""
        attachButton.image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attach")
        attachButton.imagePosition = .imageOnly
        attachButton.isBordered = false
        attachButton.controlSize = .regular
        attachButton.contentTintColor = .secondaryLabelColor
        attachButton.target = self
        attachButton.action = #selector(attachFilesTapped)

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = ""
        let sendIconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        sendButton.image = NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send")?
            .withSymbolConfiguration(sendIconConfig)
        sendButton.imagePosition = .imageOnly
        sendButton.isBordered = false
        sendButton.controlSize = .large
        sendButton.contentTintColor = .appPrimary
        sendButton.target = self
        sendButton.action = #selector(sendTapped)
        sendButton.toolTip = "Return sends. Shift+Return inserts newline. Esc or Ctrl+C cancels running request."

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
        updateComposerAppearance()
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

        setupModelReasoningRow(parentStack: composerContentStack)
    }

    private func setupModelReasoningRow(parentStack: NSStackView) {
        modelReasoningRow.translatesAutoresizingMaskIntoConstraints = false
        modelReasoningRow.orientation = .horizontal
        modelReasoningRow.alignment = .centerY
        modelReasoningRow.spacing = 6
        parentStack.addArrangedSubview(modelReasoningRow)

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

        modelReasoningRow.addArrangedSubview(attachButton)
        modelReasoningRow.addArrangedSubview(modelPicker)
        modelReasoningRow.addArrangedSubview(reasoningPicker)
        modelReasoningRow.addArrangedSubview(spacer)
        modelReasoningRow.addArrangedSubview(sendButton)

        let preferredModelWidth = modelPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 180)
        preferredModelWidth.priority = .defaultHigh
        let preferredReasoningWidth = reasoningPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 116)
        preferredReasoningWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            modelReasoningRow.widthAnchor.constraint(equalTo: parentStack.widthAnchor),
            preferredModelWidth,
            preferredReasoningWidth,
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

    private func updateComposerAppearance() {
        composerContainerView.effectiveAppearance.performAsCurrentDrawingAppearance {
            composerContainerView.layer?.backgroundColor = NSColor(resource: .surface)
                .withAlphaComponent(0.82)
                .cgColor
            composerContainerView.layer?.borderColor = NSColor.separatorColor
                .withAlphaComponent(0.55)
                .cgColor
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
            reasoningPicker.addItem(withTitle: AgentReasoningLevelPresentation.pickerTitle(for: level, agentType: agentType))
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

        if clickedView.isDescendant(of: inputTextView)
            || (inputScrollView.map { clickedView.isDescendant(of: $0) } ?? false) {
            view.window?.makeFirstResponder(inputTextView)
            return
        }

        guard shouldClearSelection(for: clickedView) else { return }
        clearSelectionState()
    }

    private func shouldClearSelection(for clickedView: NSView) -> Bool {
        if clickedView.isDescendant(of: composerContainerView) {
            return false
        }
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
    }

    private func makeMessageBubble(for message: PersistedChatMessage) -> ChatMessageBubbleView {
        let bubble = ChatMessageBubbleView(
            message: message,
            agentType: agentType,
            appearance: chatAppearance,
            fontSize: chatFontSize,
            queuedSubmissionPending: pendingQueuedUserMessageIDs.contains(message.id),
            onOpenLink: onOpenMarkdownLink,
            onOpenAttachment: { [weak self] attachment in
                self?.openAttachmentPreview(attachment)
            }
        )
        return bubble
    }

    private func pinMessageBubbleWidth(_ bubble: ChatMessageBubbleView) {
        // Activate only after insertion so both anchors share a common ancestor.
        bubble.widthAnchor.constraint(equalTo: messagesStack.widthAnchor).isActive = true
        bubble.scheduleMeasuredLayoutRefresh()
    }

    private func removeAllRenderedBubbles() {
        for subview in messagesStack.arrangedSubviews {
            messagesStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
    }

    private func appendRenderedBubbles(
        from snapshot: [PersistedChatMessage],
        in range: Range<Int>
    ) {
        for index in range where snapshot.indices.contains(index) {
            let bubble = makeMessageBubble(for: snapshot[index])
            messagesStack.addArrangedSubview(bubble)
            pinMessageBubbleWidth(bubble)
        }
    }

    private func applyIncrementalMessageRenderPlan(
        _ plan: ChatMessageRenderPlan,
        displayMessages: [PersistedChatMessage]
    ) {
        guard case .incremental(let removeTailCount, let appendRange, let changedIndices) = plan else { return }

        if removeTailCount > 0 {
            for _ in 0..<removeTailCount {
                guard let last = messagesStack.arrangedSubviews.last else { break }
                messagesStack.removeArrangedSubview(last)
                last.removeFromSuperview()
            }
        }

        for index in changedIndices {
            guard displayMessages.indices.contains(index) else { continue }
            guard messagesStack.arrangedSubviews.indices.contains(index) else { continue }
            let old = messagesStack.arrangedSubviews[index]
            messagesStack.removeArrangedSubview(old)
            old.removeFromSuperview()
            let bubble = makeMessageBubble(for: displayMessages[index])
            messagesStack.insertArrangedSubview(bubble, at: index)
            pinMessageBubbleWidth(bubble)
        }

        if !appendRange.isEmpty {
            for index in appendRange where displayMessages.indices.contains(index) {
                let bubble = makeMessageBubble(for: displayMessages[index])
                messagesStack.addArrangedSubview(bubble)
                pinMessageBubbleWidth(bubble)
            }
        }
    }

    private func reloadMessages(
        shouldScrollToBottom: Bool = true,
        forceFullReload: Bool = false
    ) {
        let shouldAutoScroll = shouldScrollToBottom && isNearBottomForAutoScroll()
        messageRenderGeneration = UUID()
        let renderGeneration = messageRenderGeneration
        let settings = PersistenceService.shared.loadSettings()
        chatAppearance = ChatAppearance.resolve(from: settings)
        chatFontSize = Self.resolvedChatFontSize(from: settings)
        inputTextView.font = .systemFont(ofSize: chatFontSize)
        updateComposerHeight()

        let displayMessages = ChatTranscriptDisplayCompactor.compactedMessages(messages)
        let plan = ChatMessageRenderPlanner.plan(previous: renderedDisplayMessages, next: displayMessages)
        let shouldFullReload: Bool = {
            switch plan {
            case .fullReload:
                return true
            case .incremental:
                return forceFullReload
            }
        }()

        if shouldFullReload && displayMessages.count > Self.progressiveFullReloadThreshold {
            let snapshot = displayMessages
            removeAllRenderedBubbles()
            renderedDisplayMessages = []
            renderMessageBubblesProgressively(
                snapshot: snapshot,
                nextIndex: 0,
                generation: renderGeneration,
                shouldScrollToBottom: shouldAutoScroll
            )
            return
        }

        switch plan {
        case .fullReload:
            removeAllRenderedBubbles()
            appendRenderedBubbles(from: displayMessages, in: displayMessages.indices)
        case .incremental:
            if forceFullReload {
                removeAllRenderedBubbles()
                appendRenderedBubbles(from: displayMessages, in: displayMessages.indices)
            } else {
                applyIncrementalMessageRenderPlan(plan, displayMessages: displayMessages)
            }
        }
        renderedDisplayMessages = displayMessages
        refreshVisibleRelativeTimestamps()

        schedulePostMessageLayoutUpdate(shouldScrollToBottom: shouldAutoScroll)
    }

    private func renderMessageBubblesProgressively(
        snapshot: [PersistedChatMessage],
        nextIndex: Int,
        generation: UUID,
        shouldScrollToBottom: Bool
    ) {
        guard messageRenderGeneration == generation else { return }

        let batchEnd = min(snapshot.count, nextIndex + Self.progressiveFullReloadBatchSize)
        appendRenderedBubbles(from: snapshot, in: nextIndex..<batchEnd)

        if batchEnd < snapshot.count {
            DispatchQueue.main.async { [weak self] in
                self?.renderMessageBubblesProgressively(
                    snapshot: snapshot,
                    nextIndex: batchEnd,
                    generation: generation,
                    shouldScrollToBottom: shouldScrollToBottom
                )
            }
            return
        }

        renderedDisplayMessages = snapshot
        refreshVisibleRelativeTimestamps()

        schedulePostMessageLayoutUpdate(shouldScrollToBottom: shouldScrollToBottom, generation: generation)
    }

    private func isNearBottomForAutoScroll() -> Bool {
        guard isViewLoaded, scrollView.documentView != nil else { return true }
        return distanceFromBottom(for: scrollView.contentView) < 80
    }

    private func schedulePostMessageLayoutUpdate(
        shouldScrollToBottom: Bool,
        generation: UUID? = nil
    ) {
        pendingPostMessageScrollToBottom = pendingPostMessageScrollToBottom || shouldScrollToBottom
        guard !postMessageLayoutUpdateScheduled else { return }
        postMessageLayoutUpdateScheduled = true

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.postMessageLayoutUpdateScheduled = false
            if let generation, self.messageRenderGeneration != generation {
                self.pendingPostMessageScrollToBottom = false
                return
            }
            let shouldScroll = self.pendingPostMessageScrollToBottom
            self.pendingPostMessageScrollToBottom = false
            if shouldScroll {
                self.scrollToBottom(animated: false)
            } else {
                self.updateScrollToBottomButtonVisibility()
            }
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
            slashCommand("/fast", detail: String(localized: .ThreadStrings.chatSlashCommandFastDescription)),
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
        attachmentDropOverlayView.updateAppearance()
        attachmentDropOverlayView.alphaValue = isHovering ? 1 : 0
    }

    private func canReadAttachments(from pasteboard: NSPasteboard) -> Bool {
        if let fileURLs = pastedFileURLs(from: pasteboard), !fileURLs.isEmpty {
            return true
        }
        return pastedImages(from: pasteboard).isEmpty == false
    }

    private func handleAttachmentDrop(from pasteboard: NSPasteboard) -> Bool {
        let fileURLs = pastedFileURLs(from: pasteboard) ?? []
        let pasteboardImages = pastedImages(from: pasteboard)
        let plan = ChatAttachmentDropPlanner.plan(
            fileURLs: fileURLs,
            hasPasteboardImages: !pasteboardImages.isEmpty
        )

        var attachmentURLs = plan.fileURLs
        if plan.shouldImportPasteboardImages {
            let pastedImageURLs = pasteboardImages.compactMap { image in
                writeImageToTemporaryAttachmentFile(image)
            }
            attachmentURLs.append(contentsOf: pastedImageURLs)
        }

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

    private func openAttachmentPreview(_ attachment: PersistedChatAttachment) {
        guard attachment.kind == .image else { return }
        let fileURL = URL(fileURLWithPath: attachment.filePath)
        guard let image = NSImage(contentsOf: fileURL) else { return }
        guard let hostView = view.window?.contentView ?? view.superview else { return }

        mediaPreviewOverlayView?.removeFromSuperview()
        let overlay = ChatImagePreviewOverlayView(image: image)
        overlay.onClose = { [weak self, weak overlay] in
            overlay?.removeFromSuperview()
            if self?.mediaPreviewOverlayView === overlay {
                self?.mediaPreviewOverlayView = nil
            }
        }
        hostView.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: hostView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: hostView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: hostView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
        ])
        mediaPreviewOverlayView = overlay
        view.window?.makeFirstResponder(overlay)
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
                removeAccessibilityLabel: closeLabel,
                onOpen: attachment.kind == .image ? { [weak self] in
                    self?.openAttachmentPreview(attachment)
                } : nil,
                onRemove: { [weak self] in
                    self?.removeDraftAttachment(id: attachment.id)
                }
            )
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

        syncInputTextViewFrameToScrollView()
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

    private func syncInputTextViewFrameToScrollView() {
        guard let inputScrollView else { return }
        let clipSize = inputScrollView.contentView.bounds.size
        guard clipSize.width.isFinite, clipSize.height.isFinite, clipSize.width > 0 else { return }

        let targetHeight = max(inputTextView.frame.height, clipSize.height, minComposerHeight)
        let targetFrame = NSRect(x: 0, y: 0, width: clipSize.width, height: targetHeight)
        if abs(inputTextView.frame.width - targetFrame.width) > 0.5
            || abs(inputTextView.frame.height - targetFrame.height) > 0.5 {
            inputTextView.frame = targetFrame
            inputTextView.textContainer?.containerSize = NSSize(
                width: targetFrame.width,
                height: CGFloat.greatestFiniteMagnitude
            )
            inputTextView.textContainer?.widthTracksTextView = true
            inputTextView.invalidateTextContainerOrigin()
            inputTextView.window?.invalidateCursorRects(for: inputTextView)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        syncInputTextViewFrameToScrollView()
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
        sendButton.contentTintColor = .appPrimary
        reloadMessages(shouldScrollToBottom: false, forceFullReload: true)
        updateSlashAutocompleteAppearance()
        updateScrollToBottomButtonAppearance()
        updateComposerAppearance()
        setAttachmentDropHoverActive(false)
        reloadAttachmentChips()
        configureModelReasoningPickers()
    }

    private static func resolvedChatFontSize(from settings: AppSettings) -> CGFloat {
        CGFloat(min(max(settings.chatFontSize, AppSettings.minChatFontSize), AppSettings.maxChatFontSize))
    }
}
