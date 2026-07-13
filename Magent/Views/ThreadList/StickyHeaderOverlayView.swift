import Cocoa

/// Floating overlay that pins project and section headers at the top of the sidebar
/// scroll view so the user always knows which project/section the visible threads
/// belong to. Positioned above the scroll view in the view hierarchy.
final class StickyHeaderOverlayView: NSView {

    // MARK: - Layout constants (match outline view cell layout)

    static let projectRowHeight: CGFloat = ThreadListViewController.projectHeaderRowHeight
    static let sectionRowHeight: CGFloat = 28
    private static let leadingInset: CGFloat = SectionHeaderStripStyle.contentLeadingInset
    private static let trailingInset: CGFloat = SectionHeaderStripStyle.contentTrailingInset
    private static let topInset: CGFloat = 6
    private static let fadeHeight: CGFloat = 28

    // MARK: - Subviews

    private let headerBlurView = NSVisualEffectView()
    private let fadeBlurView = NSVisualEffectView()
    private var lastFadeMaskSize: NSSize = .zero
    private var lastFadeMaskScale: CGFloat = 0

    private let projectContainer = NSView()
    private let projectNameLabel = NSTextField(labelWithString: "")
    private let projectPinIcon = NSImageView()
    private let projectAddButton = NSButton()

    private let sectionContainer = SectionHeaderStripView()
    private let sectionNameLabel = NSTextField(labelWithString: "")

    private let fadeSpacerView = NSView()

    private var sectionTopToProject: NSLayoutConstraint!
    private var sectionTopToSuperview: NSLayoutConstraint!
    private var fadeTopToProject: NSLayoutConstraint!
    private var fadeTopToSection: NSLayoutConstraint!

    // MARK: - State

    struct HeaderState: Equatable {
        var projectId: UUID?
        var projectName: String?
        var projectIsPinned: Bool = false
        var sectionName: String?
        var sectionColor: NSColor?

        static let hidden = HeaderState()
    }

    private var currentState = HeaderState.hidden

    /// Called when the user clicks the sticky project header.
    var onProjectClicked: (() -> Void)?
    /// Called when the user clicks the sticky section header.
    var onSectionClicked: (() -> Void)?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setup() {
        wantsLayer = true

        for blurView in [headerBlurView, fadeBlurView] {
            blurView.translatesAutoresizingMaskIntoConstraints = false
            blurView.blendingMode = .withinWindow
            blurView.material = .popover
            blurView.state = .active
            addSubview(blurView)
        }

        // Project header row
        projectContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(projectContainer)

        projectNameLabel.font = .systemFont(ofSize: 20, weight: .bold)
        projectNameLabel.textColor = .labelColor
        projectNameLabel.lineBreakMode = .byTruncatingTail
        projectNameLabel.translatesAutoresizingMaskIntoConstraints = false
        projectContainer.addSubview(projectNameLabel)

        projectPinIcon.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
        projectPinIcon.contentTintColor = NSColor(resource: .primaryBrand)
        projectPinIcon.translatesAutoresizingMaskIntoConstraints = false
        projectPinIcon.isHidden = true
        projectContainer.addSubview(projectPinIcon)

        projectAddButton.identifier = ThreadListViewController.projectAddButtonIdentifier
        projectAddButton.translatesAutoresizingMaskIntoConstraints = false
        projectAddButton.isBordered = false
        projectAddButton.imagePosition = .imageOnly
        projectAddButton.focusRingType = .none
        projectAddButton.setButtonType(.momentaryChange)
        projectAddButton.sendAction(on: [.leftMouseUp])
        let plusImage = NSImage(
            systemSymbolName: "plus",
            accessibilityDescription: "Add Thread"
        )?.withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        projectAddButton.image = plusImage ?? NSImage(systemSymbolName: "plus", accessibilityDescription: "Add Thread")
        projectAddButton.contentTintColor = .controlAccentColor
        projectContainer.addSubview(projectAddButton)

        // Section header row
        sectionContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sectionContainer)

        sectionNameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        sectionNameLabel.textColor = NSColor(resource: .textSecondary)
        sectionNameLabel.lineBreakMode = .byTruncatingTail
        sectionNameLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionContainer.addSubview(sectionNameLabel)

        fadeSpacerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fadeSpacerView)

        // Constraints
        sectionTopToProject = sectionContainer.topAnchor.constraint(
            equalTo: projectContainer.bottomAnchor
        )
        sectionTopToSuperview = sectionContainer.topAnchor.constraint(
            equalTo: topAnchor,
            constant: Self.topInset
        )

        fadeTopToProject = fadeSpacerView.topAnchor.constraint(
            equalTo: projectContainer.bottomAnchor
        )
        fadeTopToSection = fadeSpacerView.topAnchor.constraint(
            equalTo: sectionContainer.bottomAnchor
        )

        NSLayoutConstraint.activate([
            headerBlurView.topAnchor.constraint(equalTo: topAnchor),
            headerBlurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerBlurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerBlurView.bottomAnchor.constraint(equalTo: fadeSpacerView.topAnchor),

            fadeBlurView.topAnchor.constraint(equalTo: fadeSpacerView.topAnchor),
            fadeBlurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fadeBlurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeBlurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            projectContainer.topAnchor.constraint(equalTo: topAnchor, constant: Self.topInset),
            projectContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            projectContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            projectContainer.heightAnchor.constraint(equalToConstant: Self.projectRowHeight),

            projectNameLabel.centerYAnchor.constraint(equalTo: projectContainer.centerYAnchor, constant: -1),
            projectNameLabel.leadingAnchor.constraint(
                equalTo: projectContainer.leadingAnchor,
                constant: Self.leadingInset
            ),
            projectNameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: projectPinIcon.leadingAnchor,
                constant: -6
            ),

            projectPinIcon.centerYAnchor.constraint(equalTo: projectNameLabel.centerYAnchor),
            projectPinIcon.widthAnchor.constraint(equalToConstant: 10),
            projectPinIcon.heightAnchor.constraint(equalToConstant: 10),
            projectPinIcon.trailingAnchor.constraint(
                lessThanOrEqualTo: projectAddButton.leadingAnchor,
                constant: -6
            ),

            projectAddButton.centerYAnchor.constraint(equalTo: projectNameLabel.centerYAnchor),
            projectAddButton.widthAnchor.constraint(equalToConstant: ThreadListViewController.projectHeaderActionButtonSize),
            projectAddButton.heightAnchor.constraint(equalToConstant: ThreadListViewController.projectHeaderActionButtonSize),
            projectAddButton.trailingAnchor.constraint(
                equalTo: projectContainer.trailingAnchor,
                constant: -ThreadListViewController.projectAddButtonTrailingInset
            ),

            sectionTopToProject,

            sectionContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            sectionContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            sectionContainer.heightAnchor.constraint(equalToConstant: Self.sectionRowHeight),

            sectionNameLabel.leadingAnchor.constraint(
                equalTo: sectionContainer.leadingAnchor,
                constant: Self.leadingInset
            ),
            sectionNameLabel.centerYAnchor.constraint(equalTo: sectionContainer.centerYAnchor),
            sectionNameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: sectionContainer.trailingAnchor,
                constant: -Self.trailingInset
            ),

            fadeSpacerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            fadeSpacerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            fadeSpacerView.heightAnchor.constraint(equalToConstant: Self.fadeHeight),
            fadeSpacerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        isHidden = true
    }

    // MARK: - Update

    @discardableResult
    func update(state: HeaderState) -> Bool {
        guard state != currentState else { return false }
        currentState = state

        let showProject = state.projectName != nil
        let showSection = state.sectionName != nil

        if !showProject && !showSection {
            isHidden = true
            projectContainer.isHidden = true
            sectionContainer.isHidden = true
            return true
        }

        isHidden = false

        // Project row
        projectContainer.isHidden = !showProject
        if showProject {
            projectNameLabel.stringValue = state.projectName ?? ""
            projectPinIcon.isHidden = !state.projectIsPinned
            projectAddButton.objectValue = state.projectId?.uuidString
            projectAddButton.isHidden = state.projectId == nil
        }

        // Section row
        sectionContainer.isHidden = !showSection
        if showSection {
            sectionNameLabel.stringValue = state.sectionName ?? ""
            if let color = state.sectionColor {
                sectionContainer.sectionColor = color
            }
        }

        // Adjust section top constraint
        sectionTopToProject.isActive = showProject && showSection
        sectionTopToSuperview.isActive = !showProject && showSection

        // Fade anchors below the last visible header row
        fadeTopToSection.isActive = showSection
        fadeTopToProject.isActive = !showSection && showProject

        updateBackdropMask()
        invalidateIntrinsicContentSize()
        return true
    }

    func configureProjectAddButton(
        projectId: UUID?,
        target: AnyObject?,
        action: Selector,
        toolTip: String?,
        menu: NSMenu?,
        isEnabled: Bool
    ) {
        projectAddButton.objectValue = projectId?.uuidString
        projectAddButton.isHidden = projectId == nil
        projectAddButton.target = target
        projectAddButton.action = action
        projectAddButton.toolTip = toolTip
        projectAddButton.menu = menu
        projectAddButton.isEnabled = isEnabled
    }

    func setProjectAddButtonEnabled(_ isEnabled: Bool) {
        projectAddButton.isEnabled = isEnabled
    }

    override var intrinsicContentSize: NSSize {
        var h: CGFloat = 0
        if !projectContainer.isHidden { h += Self.projectRowHeight }
        if !sectionContainer.isHidden { h += Self.sectionRowHeight }
        if h > 0 { h += Self.topInset + Self.fadeHeight }
        return NSSize(width: NSView.noIntrinsicMetric, height: h)
    }

    private func updateBackdropMask() {
        let size = fadeBlurView.bounds.size
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        guard size.width > 0, size.height > 0 else {
            fadeBlurView.maskImage = nil
            return
        }
        guard size != lastFadeMaskSize || scale != lastFadeMaskScale else { return }

        fadeBlurView.maskImage = makeFadeMaskImage(size: size, scale: scale)
        lastFadeMaskSize = size
        lastFadeMaskScale = scale
    }

    private func makeFadeMaskImage(size: NSSize, scale: CGFloat) -> NSImage {
        let pixelWidth = max(1, Int(ceil(size.width * scale)))
        let pixelHeight = max(1, Int(ceil(size.height * scale)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        )

        guard let context else {
            let image = NSImage(size: size)
            image.lockFocus()
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
            image.unlockFocus()
            return image
        }

        let stops = StickyHeaderBackdropMask.gradientStops(
            totalHeight: size.height,
            rampHeight: size.height
        )
        let locations: [CGFloat] = stops.map(\.location)
        let components: [CGFloat] = stops.flatMap { [$0.opacity, $0.opacity, $0.opacity, $0.opacity] }
        let gradient = CGGradient(
            colorSpace: colorSpace,
            colorComponents: components,
            locations: locations,
            count: stops.count
        )

        if let gradient {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: CGFloat(pixelHeight)),
                options: []
            )
        }

        guard let cgImage = context.makeImage() else { return NSImage(size: size) }
        let image = NSImage(cgImage: cgImage, size: size)
        image.cacheMode = .never
        return image
    }

    override func layout() {
        super.layout()
        updateBackdropMask()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if !isHidden { updateBackdropMask() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if !isHidden { updateBackdropMask() }
    }

    // MARK: - Click Handling

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let buttonPoint = projectAddButton.convert(point, from: self)
        if let hitView = projectAddButton.hitTest(buttonPoint) {
            return hitView
        }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !sectionContainer.isHidden, sectionContainer.frame.contains(point) {
            onSectionClicked?()
        } else if !projectContainer.isHidden, projectContainer.frame.contains(point) {
            onProjectClicked?()
        }
        // Don't call super — absorb the click so it doesn't pass through
    }
}
