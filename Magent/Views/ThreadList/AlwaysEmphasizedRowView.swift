import Cocoa
import MagentCore

private final class ArchivingRowOverlayView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            self.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82).cgColor
        }
    }
}

final class AlwaysEmphasizedRowView: NSTableRowView {
    private static let busyBorderRotationAnimationKey = "busy-border-rotation"
    static let capsuleLeadingInset = ThreadCapsuleSectionMarkerStyle.capsuleLeadingInset
    static let capsuleTrailingInset = ThreadCapsuleSectionMarkerStyle.capsuleTrailingInset
    static let capsuleVerticalInset = ThreadCapsuleSectionMarkerStyle.capsuleVerticalInset
    static let capsuleBorderWidth: CGFloat = 2
    /// Half the border width — the inset from capsule rect to the border's inner edge.
    static let capsuleBorderInset: CGFloat = capsuleBorderWidth / 2
    private static let capsuleCornerRadius = ThreadCapsuleSectionMarkerStyle.capsuleCornerRadius
    /// Horizontal content padding from capsule inner edge (inside the border).
    static let capsuleContentHPadding: CGFloat = 12
    /// Vertical content padding from capsule inner edge (inside the border).
    static let capsuleContentVPadding: CGFloat = 12
    private var archivingOverlay: ArchivingRowOverlayView?
    /// Container layer for the rotating conic gradient border.
    private var busyBorderContainer: CALayer?

    /// Single shared animation start time so all busy threads rotate in phase.
    /// Set once when any thread first becomes busy;
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
        didSet { needsDisplay = true }
    }
    var showsCompletionHighlight = false {
        didSet { needsDisplay = true }
    }
    var showsWaitingHighlight = false {
        didSet { needsDisplay = true }
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
    var showsPopoutTint = false {
        didSet { needsDisplay = true }
    }
    var sectionMarkerColor: NSColor? {
        didSet { needsDisplay = true }
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
            // In light mode our selection is a pale tint, not a dark bg — push .normal
            // so AppKit doesn't auto-invert adaptive colors (labelColor etc.) to white.
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let style: NSView.BackgroundStyle = (isSelected && isDark) ? .emphasized : .normal
            for case let cell as NSTableCellView in subviews {
                cell.backgroundStyle = style
            }
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
        layoutBusyBorderLayers()
    }

    // MARK: - Capsule Style

    /// Resolved fill and border colors for the current row state.
    /// Single source of truth for capsule drawing.
    private struct CapsuleStyle {
        let fill: NSColor
        let border: NSColor
    }

    private var currentCapsuleBorderWidth: CGFloat {
        (isSelected || showsPopoutTint) ? Self.capsuleBorderWidth : 1
    }

    private var currentCapsuleVisualState: ThreadRowCapsuleVisualState {
        ThreadRowCapsuleVisualState.resolve(
            isSelected: isSelected,
            showsRateLimitHighlight: showsRateLimitHighlight,
            showsWaitingHighlight: showsWaitingHighlight,
            showsCompletionHighlight: showsCompletionHighlight,
            showsPopoutTint: showsPopoutTint
        )
    }

    private var currentCapsuleStyle: CapsuleStyle {
        switch currentCapsuleVisualState {
        case .selected:
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let fillColor = isDark
                ? NSColor.appPrimary.withAlphaComponent(0.1)
                : NSColor.appPrimary.withAlphaComponent(0.2)
            return CapsuleStyle(
                fill: fillColor,
                border: .appPrimary
            )
        case .rateLimited:
            return CapsuleStyle(
                fill: NSColor.systemRed.withAlphaComponent(0.06),
                border: NSColor.systemRed.withAlphaComponent(0.5)
            )
        case .waiting:
            return CapsuleStyle(
                fill: NSColor.systemOrange.withAlphaComponent(0.06),
                border: NSColor.systemOrange.withAlphaComponent(0.5)
            )
        case .completed:
            return CapsuleStyle(
                fill: NSColor.systemGreen.withAlphaComponent(0.06),
                border: NSColor.systemGreen.withAlphaComponent(0.5)
            )
        case .poppedOut:
            return CapsuleStyle(
                fill: NSColor.systemPurple.withAlphaComponent(0.12),
                border: NSColor.systemPurple.withAlphaComponent(0.7)
            )
        case .idle:
            let fillColor = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.035)
                : NSColor.black.withAlphaComponent(0.03)
            return CapsuleStyle(fill: fillColor, border: .clear)
        }
    }

    private func drawCapsuleBorderAndFill(_ style: CapsuleStyle) {
        let borderWidth = currentCapsuleBorderWidth
        let fillPath = NSBezierPath(
            roundedRect: capsuleRect,
            xRadius: Self.capsuleCornerRadius,
            yRadius: Self.capsuleCornerRadius
        )
        style.fill.setFill()
        fillPath.fill()
        drawSectionMarker(in: fillPath)

        let insetRect = capsuleRect.insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let borderPath = NSBezierPath(
            roundedRect: insetRect,
            xRadius: Self.capsuleCornerRadius,
            yRadius: Self.capsuleCornerRadius
        )
        borderPath.lineWidth = borderWidth
        style.border.setStroke()
        borderPath.stroke()
    }

    private func drawSectionMarker(in capsulePath: NSBezierPath) {
        guard let sectionMarkerColor else { return }
        let vertices = ThreadCapsuleSectionMarkerStyle.vertices(
            in: capsuleRect,
            isFlipped: isFlipped
        )
        guard let firstVertex = vertices.first else { return }

        let markerPath = NSBezierPath()
        markerPath.move(to: firstVertex)
        vertices.dropFirst().forEach { markerPath.line(to: $0) }
        markerPath.close()

        NSGraphicsContext.saveGraphicsState()
        capsulePath.addClip()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ThreadCapsuleSectionMarkerStyle.color(
                sectionColor: sectionMarkerColor,
                isSelected: isSelected
            ).setFill()
            markerPath.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        // Selection drawing is done here (not in drawSelection) so we can use
        // selectionHighlightStyle = .none on the outline view to fully suppress
        // AppKit's own selection rect (which adds an unwanted border on right-click).
        let style = currentCapsuleStyle
        if isSelected || showsRateLimitHighlight || showsWaitingHighlight || showsCompletionHighlight || showsPopoutTint {
            drawCapsuleBorderAndFill(style)
        } else {
            // Normal: subtle fill with context-menu emphasis when needed.
            let fillPath = NSBezierPath(
                roundedRect: capsuleRect,
                xRadius: Self.capsuleCornerRadius,
                yRadius: Self.capsuleCornerRadius
            )
            // Brighten fill slightly when the context menu is open for this row.
            let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let fillColor: NSColor
            if showsContextMenuHighlight {
                fillColor = isDark
                    ? NSColor.white.withAlphaComponent(0.1)
                    : NSColor.black.withAlphaComponent(0.06)
            } else {
                fillColor = style.fill
            }
            fillColor.setFill()
            fillPath.fill()
            drawSectionMarker(in: fillPath)

            if busyBorderContainer == nil, showsContextMenuHighlight {
                let insetRect = capsuleRect.insetBy(dx: 0.5, dy: 0.5)
                let borderPath = NSBezierPath(
                    roundedRect: insetRect,
                    xRadius: Self.capsuleCornerRadius,
                    yRadius: Self.capsuleCornerRadius
                )
                borderPath.lineWidth = 1
                let borderColor = isDark
                    ? NSColor.white.withAlphaComponent(0.3)
                    : NSColor.black.withAlphaComponent(0.15)
                borderColor.setStroke()
                borderPath.stroke()
            }
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
        if showsBusyShimmer {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                stopBusyBorderAnimation()
                return
            }
            startBusyBorderAnimation()
        } else {
            stopBusyBorderAnimation()
        }
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
        let borderWidth = currentCapsuleBorderWidth

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
            let accentColor = NSColor.appPrimary
            var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
            accentColor.usingColorSpace(.sRGB)?.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)
            brightColor = NSColor(hue: hue, saturation: max(sat * 0.7, 0.3), brightness: min(bri * 1.1, 1.0), alpha: 0.8)
            // Keep unselected busy rows consistent with idle rows: only the moving arc draws a border.
            dimColor = .clear
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
        if let shapeMask = container.mask as? CAShapeLayer {
            shapeMask.lineWidth = currentCapsuleBorderWidth
        }
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
            shapeMask.lineWidth = currentCapsuleBorderWidth
        }
        CATransaction.commit()
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

final class SectionHeaderStripView: NSView {}

final class SectionHeaderRowView: NSTableRowView {
    override var isEmphasized: Bool {
        get { true }
        set {}
    }

    override func drawBackground(in dirtyRect: NSRect) {}
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

/// Cell view for `SidebarGroupSeparator` rows. Preserves breathing room between
/// pinned, normal, and hidden thread groups without drawing a visual divider.
final class SidebarGroupSeparatorCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
