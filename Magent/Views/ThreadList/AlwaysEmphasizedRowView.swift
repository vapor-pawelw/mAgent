import Cocoa
import MagentCore

private final class SignEmojiBadgeView: NSView {
    var capsuleFill: NSColor = .clear { didSet { needsDisplay = true } }

    private var fillOverlayLayer: CALayer?
    private let emojiLabel: NSTextField

    override var wantsUpdateLayer: Bool { true }

    override init(frame frameRect: NSRect) {
        emojiLabel = NSTextField(labelWithString: "")
        emojiLabel.translatesAutoresizingMaskIntoConstraints = false
        emojiLabel.alignment = .center
        emojiLabel.backgroundColor = .clear
        emojiLabel.isBordered = false
        emojiLabel.isEditable = false
        super.init(frame: frameRect)
        addSubview(emojiLabel)
        NSLayoutConstraint.activate([
            emojiLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emojiLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(emoji: String, font: NSFont, textColor: NSColor) {
        emojiLabel.stringValue = emoji
        emojiLabel.font = font
        emojiLabel.textColor = textColor
    }

    func updateTextColor(_ color: NSColor) {
        emojiLabel.textColor = color
    }

    override func updateLayer() {
        guard let layer else { return }
        let overlay: CALayer
        if let existing = fillOverlayLayer {
            overlay = existing
        } else {
            let new = CALayer()
            layer.addSublayer(new)
            fillOverlayLayer = new
            overlay = new
        }
        overlay.frame = layer.bounds
        overlay.cornerRadius = layer.cornerRadius
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
            overlay.backgroundColor = self.capsuleFill.cgColor
        }
    }

    override func layout() {
        super.layout()
        fillOverlayLayer?.frame = layer?.bounds ?? .zero
    }
}

private final class ArchivingRowOverlayView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor
        }
    }
}

final class AlwaysEmphasizedRowView: NSTableRowView {
    private static let busyOpacitySweepAnimationKey = "busy-row-opacity-sweep"
    private static let busyBorderRotationAnimationKey = "busy-border-rotation"
    private static let busyMaskOverscanLeft: CGFloat = 96
    private static let busyMaskOverscanRight: CGFloat = 48
    static let capsuleLeadingInset: CGFloat = 12
    static let capsuleTrailingInset: CGFloat = 12
    static let capsuleVerticalInset: CGFloat = 10
    static let capsuleBorderWidth: CGFloat = 2
    /// Half the border width — the inset from capsule rect to the border's inner edge.
    static let capsuleBorderInset: CGFloat = capsuleBorderWidth / 2
    private static let capsuleCornerRadius: CGFloat = 8
    /// Horizontal content padding from capsule inner edge (inside the border).
    static let capsuleContentHPadding: CGFloat = 12
    /// Vertical content padding from capsule inner edge (inside the border).
    static let capsuleContentVPadding: CGFloat = 12
    /// X/Y offset from the row's top-leading corner for the sign emoji badge/label center.
    /// Must be ≥ badge radius (10) + glow blur (6) + margin (2) = 18 so the glow
    /// stays within the row's bounds and doesn't bleed into adjacent rows or outside the leading edge.
    private static let signEmojiBadgeCenter: CGFloat = 18
    private var busyOpacityMaskLayer: CAGradientLayer?
    private weak var maskedContentView: NSView?
    private var archivingOverlay: ArchivingRowOverlayView?
    private var signEmojiTintColor: NSColor?
    private var signEmojiBadge: SignEmojiBadgeView?
    /// Container layer for the rotating conic gradient border.
    private var busyBorderContainer: CALayer?

    /// Single shared animation start time so all busy threads rotate and
    /// shimmer in phase. Set once when any thread first becomes busy;
    /// never reset (the epoch is meaningless, only the phase matters).
    private static var sharedAnimationEpoch: CFTimeInterval = 0

    /// Legacy property — kept so the data source assignment compiles but
    /// no longer drives per-thread phase tracking.
    var busyBorderPhaseKey: AnyHashable?

    /// Subtle highlight shown while the context menu for this (unselected) row is open.
    var showsContextMenuHighlight = false {
        didSet { needsDisplay = true }
    }
    var showsRateLimitHighlight = false {
        didSet { needsDisplay = true; updateSignEmojiBadge() }
    }
    var showsCompletionHighlight = false {
        didSet { needsDisplay = true; updateSignEmojiBadge() }
    }
    var showsWaitingHighlight = false {
        didSet { needsDisplay = true; updateSignEmojiBadge() }
    }
    var showsSubtleBottomSeparator = false {
        didSet { needsDisplay = true }
    }
    var showsBusyShimmer = false {
        didSet {
            guard showsBusyShimmer != oldValue else { return }
            updateBusyShimmerAnimation()
        }
    }
    var showsArchivingOverlay = false {
        didSet { updateArchivingOverlay() }
    }

    /// The inset rect used for the capsule border/background.
    private var capsuleRect: NSRect {
        NSRect(
            x: bounds.minX + Self.capsuleLeadingInset,
            y: bounds.minY + Self.capsuleVerticalInset,
            width: bounds.width - Self.capsuleLeadingInset - Self.capsuleTrailingInset,
            height: bounds.height - Self.capsuleVerticalInset * 2
        )
    }


    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        focusRingType = .none
    }

    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    // With selectionHighlightStyle = .none, AppKit no longer triggers redraws
    // or backgroundStyle changes on child views automatically. Force both so
    // drawBackground renders our capsule and cells update their tints.
    override var isSelected: Bool {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            // Push backgroundStyle to child cell views so they can react to
            // selection changes (icon tint, badge colors, text color).
            let style: NSView.BackgroundStyle = isSelected ? .emphasized : .normal
            for case let cell as NSTableCellView in subviews {
                cell.backgroundStyle = style
            }
            updateSignEmojiSelectionColor()
            updateBusyBorderSelectionColors()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateBusyShimmerAnimation()
        if window != nil, let spinner = archivingOverlay?.subviews.compactMap({ $0 as? NSStackView }).first?
            .views.first(where: { $0 is NSProgressIndicator }) as? NSProgressIndicator {
            spinner.startAnimation(nil)
        }
    }

    override func layout() {
        super.layout()
        if let busyOpacityMaskLayer,
           let maskedContentView,
           let contentLayer = maskedContentView.layer {
            busyOpacityMaskLayer.frame = busyMaskFrame(for: contentLayer.bounds)
        }
        layoutBusyBorderLayers()
    }

    // MARK: - Capsule Style

    /// Resolved fill and border colors for the current row state.
    /// Single source of truth consumed by both capsule drawing and the sign emoji badge.
    private struct CapsuleStyle {
        let fill: NSColor
        let border: NSColor
    }

    private var currentCapsuleStyle: CapsuleStyle {
        if isSelected {
            return CapsuleStyle(
                fill: NSColor.controlAccentColor.withAlphaComponent(0.1),
                border: .controlAccentColor
            )
        } else if showsRateLimitHighlight {
            return CapsuleStyle(
                fill: NSColor.systemRed.withAlphaComponent(0.06),
                border: NSColor.systemRed.withAlphaComponent(0.5)
            )
        } else if showsWaitingHighlight {
            return CapsuleStyle(
                fill: NSColor.systemOrange.withAlphaComponent(0.06),
                border: NSColor.systemOrange.withAlphaComponent(0.5)
            )
        } else if showsCompletionHighlight {
            return CapsuleStyle(
                fill: NSColor.systemGreen.withAlphaComponent(0.06),
                border: NSColor.systemGreen.withAlphaComponent(0.5)
            )
        } else {
            return CapsuleStyle(
                fill: NSColor.white.withAlphaComponent(0.05),
                border: NSColor.white.withAlphaComponent(0.12)
            )
        }
    }

    private func drawCapsuleBorderAndFill(_ style: CapsuleStyle) {
        let fillPath = NSBezierPath(
            roundedRect: capsuleRect,
            xRadius: Self.capsuleCornerRadius,
            yRadius: Self.capsuleCornerRadius
        )
        style.fill.setFill()
        fillPath.fill()

        let insetRect = capsuleRect.insetBy(dx: Self.capsuleBorderWidth / 2, dy: Self.capsuleBorderWidth / 2)
        let borderPath = NSBezierPath(
            roundedRect: insetRect,
            xRadius: Self.capsuleCornerRadius,
            yRadius: Self.capsuleCornerRadius
        )
        borderPath.lineWidth = Self.capsuleBorderWidth
        style.border.setStroke()
        borderPath.stroke()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Selection drawing is done here (not in drawSelection) so we can use
        // selectionHighlightStyle = .none on the outline view to fully suppress
        // AppKit's own selection rect (which adds an unwanted border on right-click).
        let style = currentCapsuleStyle
        if isSelected || showsRateLimitHighlight || showsWaitingHighlight || showsCompletionHighlight {
            drawCapsuleBorderAndFill(style)
        } else {
            // Normal: subtle fill + optional 1pt border (thinner than highlighted states).
            let fillPath = NSBezierPath(
                roundedRect: capsuleRect,
                xRadius: Self.capsuleCornerRadius,
                yRadius: Self.capsuleCornerRadius
            )
            // Brighten fill slightly when the context menu is open for this row.
            let fillColor = showsContextMenuHighlight
                ? NSColor.white.withAlphaComponent(0.1)
                : style.fill
            fillColor.setFill()
            fillPath.fill()

            // Skip static border when the animated busy border is active.
            if busyBorderContainer == nil {
                let insetRect = capsuleRect.insetBy(dx: 0.5, dy: 0.5)
                let borderPath = NSBezierPath(
                    roundedRect: insetRect,
                    xRadius: Self.capsuleCornerRadius,
                    yRadius: Self.capsuleCornerRadius
                )
                if showsContextMenuHighlight {
                    borderPath.lineWidth = Self.capsuleBorderWidth
                    NSColor.white.withAlphaComponent(0.3).setStroke()
                } else {
                    borderPath.lineWidth = 1
                    style.border.setStroke()
                }
                borderPath.stroke()
            }
        }

        // Draw glow around sign emoji badge using NSShadow — reliable in AppKit
        // draw-based rendering, unlike CALayer shadow which is clipped in layer-backed views.
        if signEmojiBadge?.isHidden == false {
            let badgeCenterX = Self.signEmojiBadgeCenter
            let badgeCenterY: CGFloat = isFlipped
                ? Self.signEmojiBadgeCenter
                : bounds.height - Self.signEmojiBadgeCenter
            let badgeRect = CGRect(
                x: badgeCenterX - 10, y: badgeCenterY - 10, width: 20, height: 20
            )
            NSGraphicsContext.current?.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowBlurRadius = 6
            glow.shadowOffset = .zero
            // Strip pre-baked alpha from border color so shadowColor alone controls intensity.
            glow.shadowColor = style.border.withAlphaComponent(0.5)
            glow.set()
            // Fill must be opaque for NSShadow to cast at full strength — alpha scales the
            // shadow intensity, so near-transparent fills produce near-invisible glows.
            // The badge subview renders on top and covers this fill entirely.
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        if showsSubtleBottomSeparator {
            let separatorY = isFlipped ? (bounds.maxY - 1) : bounds.minY
            let separatorRect = NSRect(
                x: bounds.minX + 8,
                y: separatorY,
                width: max(0, bounds.width - 16),
                height: 1
            )
            NSColor.separatorColor.withAlphaComponent(0.24).setFill()
            NSBezierPath(rect: separatorRect).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        // No-op: all capsule drawing is in drawBackground to allow
        // selectionHighlightStyle = .none without losing our custom highlight.
    }

    private func updateBusyShimmerAnimation() {
        guard let contentView = targetContentView(),
              let contentLayer = contentView.layer else {
            stopBusyShimmerAnimation()
            return
        }
        if showsBusyShimmer {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                stopBusyShimmerAnimation()
                stopBusyBorderAnimation()
                return
            }
            startBusyBorderAnimation()
            let maskLayer = ensureBusyOpacityMaskLayer()
            maskLayer.frame = busyMaskFrame(for: contentLayer.bounds)
            if contentLayer.mask !== maskLayer {
                contentLayer.mask = maskLayer
            }
            maskedContentView = contentView

            guard maskLayer.animation(forKey: Self.busyOpacitySweepAnimationKey) == nil else { return }

            // Keep the dip fully offscreen at cycle boundaries so leading icons
            // do not appear to blink/disappear when the animation loops.
            let startLocations: [NSNumber] = [-0.72, -0.56, -0.47, -0.38, -0.22]
            let endLocations: [NSNumber] = [1.22, 1.38, 1.47, 1.56, 1.72]
            maskLayer.locations = startLocations

            // Ensure the shared epoch exists so shimmer and border stay in phase.
            if Self.sharedAnimationEpoch == 0 {
                Self.sharedAnimationEpoch = CACurrentMediaTime()
            }

            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = startLocations
            animation.toValue = endLocations
            animation.duration = 2.6
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.beginTime = Self.sharedAnimationEpoch
            maskLayer.add(animation, forKey: Self.busyOpacitySweepAnimationKey)
        } else {
            stopBusyShimmerAnimation()
        }
    }

    private func stopBusyShimmerAnimation() {
        busyOpacityMaskLayer?.removeAnimation(forKey: Self.busyOpacitySweepAnimationKey)
        if let maskedContentView,
           let maskedLayer = maskedContentView.layer,
           maskedLayer.mask === busyOpacityMaskLayer {
            maskedLayer.mask = nil
        }
        maskedContentView = nil
        stopBusyBorderAnimation()
    }

    private func ensureBusyOpacityMaskLayer() -> CAGradientLayer {
        if let busyOpacityMaskLayer {
            return busyOpacityMaskLayer
        }
        let mask = CAGradientLayer()
        mask.startPoint = CGPoint(x: 0, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 0.5)
        mask.colors = [
            NSColor.white.withAlphaComponent(1.0).cgColor,
            NSColor.white.withAlphaComponent(1.0).cgColor,
            NSColor.white.withAlphaComponent(0.74).cgColor,
            NSColor.white.withAlphaComponent(1.0).cgColor,
            NSColor.white.withAlphaComponent(1.0).cgColor,
        ]
        busyOpacityMaskLayer = mask
        return mask
    }

    private func targetContentView() -> NSView? {
        if let maskedContentView, subviews.contains(maskedContentView) {
            return maskedContentView
        }
        if let cellView = subviews.first(where: { $0 is NSTableCellView }) {
            return cellView
        }
        return subviews.first
    }

    private func busyMaskFrame(for contentBounds: CGRect) -> CGRect {
        CGRect(
            x: -Self.busyMaskOverscanLeft,
            y: contentBounds.minY,
            width: contentBounds.width + Self.busyMaskOverscanLeft + Self.busyMaskOverscanRight,
            height: contentBounds.height
        )
    }

    // MARK: - Busy Border Animation

    private func makeBorderRotationAnimation() -> CABasicAnimation {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0.0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 3.0
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        // Pin to the original start time so CA computes the correct phase
        // even when the animation is re-added after being dropped.
        rotation.beginTime = Self.sharedAnimationEpoch
        return rotation
    }

    private func startBusyBorderAnimation() {
        guard window != nil else { return }
        if let existing = busyBorderContainer {
            // Re-add rotation if CA dropped it (e.g. view left and re-entered window).
            if let gradient = existing.sublayers?.first as? CAGradientLayer,
               gradient.animation(forKey: Self.busyBorderRotationAnimationKey) == nil {
                gradient.add(makeBorderRotationAnimation(), forKey: Self.busyBorderRotationAnimationKey)
            }
            return
        }

        let rect = capsuleRect
        let cornerRadius = Self.capsuleCornerRadius
        let borderWidth: CGFloat = Self.capsuleBorderWidth

        // Container sits behind content but above row background.
        let container = CALayer()
        container.frame = bounds
        container.zPosition = -1
        layer?.addSublayer(container)

        // The conic gradient that will rotate. Made larger than the capsule
        // so the gradient sweep looks smooth even at the corners.
        let gradientLayer = CAGradientLayer()
        gradientLayer.type = .conic
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)

        applyBorderGradientColors(gradientLayer, selected: isSelected)
        gradientLayer.locations = [0.0, 0.08, 0.16, 0.5, 0.84, 0.92, 1.0]

        // Expand gradient frame so rotation doesn't clip.
        let diagonal = sqrt(rect.width * rect.width + rect.height * rect.height)
        gradientLayer.frame = CGRect(
            x: rect.midX - diagonal / 2,
            y: rect.midY - diagonal / 2,
            width: diagonal,
            height: diagonal
        )
        container.addSublayer(gradientLayer)

        // Mask the gradient to just the capsule border stroke.
        let borderPath = CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        let shapeMask = CAShapeLayer()
        shapeMask.path = borderPath
        shapeMask.fillColor = nil
        shapeMask.strokeColor = NSColor.white.cgColor
        shapeMask.lineWidth = borderWidth
        container.mask = shapeMask

        // Record a shared epoch the first time any thread starts animating.
        // All threads use this same epoch so their rotations stay in phase.
        if Self.sharedAnimationEpoch == 0 {
            Self.sharedAnimationEpoch = CACurrentMediaTime()
        }
        gradientLayer.add(makeBorderRotationAnimation(), forKey: Self.busyBorderRotationAnimationKey)

        busyBorderContainer = container
    }

    /// Set the gradient colors based on selection state.
    private func applyBorderGradientColors(_ gradientLayer: CAGradientLayer, selected: Bool) {
        let brightColor: NSColor
        let dimColor: NSColor
        if selected {
            brightColor = NSColor.white.withAlphaComponent(0.9)
            dimColor = NSColor.white.withAlphaComponent(0.25)
        } else {
            let accentColor = NSColor.controlAccentColor
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            accentColor.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            brightColor = NSColor(hue: hue, saturation: max(sat * 0.7, 0.3), brightness: min(bri * 1.1, 1.0), alpha: 0.8)
            dimColor = NSColor.white.withAlphaComponent(0.12)
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            gradientLayer.colors = [
                brightColor.cgColor,
                brightColor.withAlphaComponent(selected ? 0.5 : 0.4).cgColor,
                dimColor.cgColor,
                dimColor.cgColor,
                dimColor.cgColor,
                brightColor.withAlphaComponent(selected ? 0.5 : 0.4).cgColor,
                brightColor.cgColor,
            ]
        }
    }

    private func updateBusyBorderSelectionColors() {
        guard let container = busyBorderContainer,
              let gradient = container.sublayers?.first as? CAGradientLayer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyBorderGradientColors(gradient, selected: isSelected)
        CATransaction.commit()
    }

    private func stopBusyBorderAnimation() {
        guard busyBorderContainer != nil else { return }
        busyBorderContainer?.removeFromSuperlayer()
        busyBorderContainer = nil
        // Don't reset sharedAnimationEpoch — other threads may still be
        // animating and new busy threads should join in phase.
    }

    private func layoutBusyBorderLayers() {
        guard let container = busyBorderContainer else { return }
        // Disable implicit animations so frame/path changes don't
        // create transactions that reset the running rotation.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.frame = bounds
        let rect = capsuleRect
        let cornerRadius = Self.capsuleCornerRadius

        if let gradientLayer = container.sublayers?.first as? CAGradientLayer {
            let diagonal = sqrt(rect.width * rect.width + rect.height * rect.height)
            gradientLayer.frame = CGRect(
                x: rect.midX - diagonal / 2,
                y: rect.midY - diagonal / 2,
                width: diagonal,
                height: diagonal
            )
        }
        if let shapeMask = container.mask as? CAShapeLayer {
            shapeMask.path = CGPath(
                roundedRect: rect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
        }
        CATransaction.commit()
    }

    // MARK: - Sign Emoji

    /// Configure the sign emoji displayed on the capsule's leading edge.
    func configureSignEmoji(_ emoji: String?, tintColor: NSColor?, isSelected: Bool) {
        signEmojiTintColor = tintColor
        guard let emoji, !emoji.isEmpty else {
            signEmojiBadge?.isHidden = true
            return
        }
        let fontSize: CGFloat = (emoji == "↑" || emoji == "↓") ? 14 : 11
        let textColor: NSColor = isSelected ? .white : (tintColor ?? .labelColor)

        let badge = ensureSignEmojiBadge()
        badge.configure(
            emoji: emoji,
            font: .systemFont(ofSize: fontSize, weight: .bold),
            textColor: textColor
        )
        badge.isHidden = false
        updateSignEmojiBadge()
    }

    private func updateSignEmojiSelectionColor() {
        guard let badge = signEmojiBadge, !badge.isHidden else { return }
        badge.updateTextColor(isSelected ? .white : (signEmojiTintColor ?? .labelColor))
        updateSignEmojiBadge()
    }

    /// Updates badge fill to mirror the capsule's current background color.
    private func updateSignEmojiBadge() {
        guard let badge = signEmojiBadge, !badge.isHidden else { return }
        badge.capsuleFill = currentCapsuleStyle.fill
        // Glow is drawn in drawBackground via NSShadow — trigger a redraw.
        needsDisplay = true
    }

    private func ensureSignEmojiBadge() -> SignEmojiBadgeView {
        if let badge = signEmojiBadge { return badge }
        let badge = SignEmojiBadgeView()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 10  // circle (half of 20pt size)
        badge.isHidden = true
        addSubview(badge)
        let size: CGFloat = 20
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: size),
            badge.heightAnchor.constraint(equalToConstant: size),
            badge.centerXAnchor.constraint(
                equalTo: leadingAnchor,
                constant: Self.signEmojiBadgeCenter
            ),
            badge.centerYAnchor.constraint(
                equalTo: topAnchor,
                constant: Self.signEmojiBadgeCenter
            ),
        ])
        signEmojiBadge = badge
        return badge
    }

    private func updateArchivingOverlay() {
        if showsArchivingOverlay {
            ensureArchivingOverlay()
        } else {
            archivingOverlay?.removeFromSuperview()
            archivingOverlay = nil
        }
    }

    private func ensureArchivingOverlay() {
        guard archivingOverlay == nil else { return }

        let overlay = ArchivingRowOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: "Archiving…")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false

        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
        ])

        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        archivingOverlay = overlay
    }
}

final class ProjectHeaderRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }
}

final class SidebarSpacerRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawBackground(in dirtyRect: NSRect) {
        super.drawBackground(in: dirtyRect)
    }
}

final class SidebarSpacerCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
