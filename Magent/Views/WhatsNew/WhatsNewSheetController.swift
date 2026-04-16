import Cocoa
import MagentCore

/// Modal sheet that presents a `WhatsNewEntry`'s pages over the main window.
///
/// Handles the pager UI (dots + prev/next) for multi-page entries and hides it
/// entirely for single-page entries. Dismissal (via the "Got it" button OR the
/// titlebar close button) invokes `onDismiss`, which is where the service
/// records the entry version as "seen".
final class WhatsNewSheetController: NSWindowController {

    private let entry: WhatsNewEntry
    private let onDismiss: () -> Void

    private var currentIndex = 0
    private weak var parentWindow: NSWindow?

    private let pageContainer = NSView()
    private var pageContainerTopConstraint: NSLayoutConstraint?
    private var pageContainerBottomConstraint: NSLayoutConstraint?
    private var dotViews: [NSView] = []
    private let dotsStack = NSStackView()
    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let pagerRow = NSStackView()

    private var hasCalledDismiss = false

    static func present(
        entry: WhatsNewEntry,
        over parentWindow: NSWindow,
        onDismiss: @escaping () -> Void
    ) {
        let controller = WhatsNewSheetController(entry: entry, onDismiss: onDismiss)
        guard let sheetWindow = controller.window else { return }
        controller.parentWindow = parentWindow
        parentWindow.beginSheet(sheetWindow) { _ in
            controller.invokeDismissOnce()
        }
    }

    private init(entry: WhatsNewEntry, onDismiss: @escaping () -> Void) {
        precondition(!entry.pages.isEmpty, "WhatsNewEntry must contain at least one page")
        self.entry = entry
        self.onDismiss = onDismiss

        // Sheets dismiss via the explicit "Got it" button only; no titlebar
        // close (clicking it bypasses `endSheet` and leaves the parent window
        // attached to a closed sheet).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "What's New"
        window.isReleasedWhenClosed = false

        super.init(window: window)

        buildContentView()
        renderCurrentPage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    // MARK: - View construction

    private func buildContentView() {
        guard let window, let contentView = window.contentView else { return }

        let titleLabel = NSTextField(labelWithString: "What's New")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        pageContainer.translatesAutoresizingMaskIntoConstraints = false

        // Pager row: ◀  • ○ ○  ▶
        prevButton.isBordered = false
        prevButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous page")
        prevButton.imagePosition = .imageOnly
        prevButton.target = self
        prevButton.action = #selector(prevTapped)
        prevButton.contentTintColor = .secondaryLabelColor
        prevButton.setContentHuggingPriority(.required, for: .horizontal)

        nextButton.isBordered = false
        nextButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next page")
        nextButton.imagePosition = .imageOnly
        nextButton.target = self
        nextButton.action = #selector(nextTapped)
        nextButton.contentTintColor = .secondaryLabelColor
        nextButton.setContentHuggingPriority(.required, for: .horizontal)

        dotsStack.orientation = .horizontal
        dotsStack.spacing = 8
        dotsStack.alignment = .centerY

        pagerRow.orientation = .horizontal
        pagerRow.spacing = 18
        pagerRow.alignment = .centerY
        pagerRow.distribution = .equalCentering
        pagerRow.addArrangedSubview(prevButton)
        pagerRow.addArrangedSubview(dotsStack)
        pagerRow.addArrangedSubview(nextButton)
        pagerRow.translatesAutoresizingMaskIntoConstraints = false

        // Got it button (primary action)
        let gotItButton = NSButton(title: "Got it", target: self, action: #selector(gotItTapped))
        gotItButton.bezelStyle = .rounded
        gotItButton.keyEquivalent = "\r"
        gotItButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(titleLabel)
        contentView.addSubview(pageContainer)
        contentView.addSubview(pagerRow)
        contentView.addSubview(gotItButton)

        let pagerVisible = entry.pages.count > 1

        let topConstraint = pageContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16)
        let bottomConstraint: NSLayoutConstraint
        if pagerVisible {
            bottomConstraint = pageContainer.bottomAnchor.constraint(equalTo: pagerRow.topAnchor, constant: -12)
        } else {
            bottomConstraint = pageContainer.bottomAnchor.constraint(equalTo: gotItButton.topAnchor, constant: -16)
        }
        pageContainerTopConstraint = topConstraint
        pageContainerBottomConstraint = bottomConstraint

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            pageContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            pageContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            topConstraint,
            bottomConstraint,

            pagerRow.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            pagerRow.bottomAnchor.constraint(equalTo: gotItButton.topAnchor, constant: -14),

            gotItButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            gotItButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            gotItButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
        ])

        if pagerVisible {
            buildDots(count: entry.pages.count)
        } else {
            pagerRow.isHidden = true
            prevButton.isHidden = true
            nextButton.isHidden = true
        }
    }

    private func buildDots(count: Int) {
        dotViews.removeAll()
        for view in dotsStack.arrangedSubviews {
            dotsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for _ in 0..<count {
            let dot = NSView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.wantsLayer = true
            dot.layer?.cornerRadius = 3
            NSLayoutConstraint.activate([
                dot.widthAnchor.constraint(equalToConstant: 6),
                dot.heightAnchor.constraint(equalToConstant: 6),
            ])
            dotsStack.addArrangedSubview(dot)
            dotViews.append(dot)
        }
    }

    // MARK: - Page rendering

    private func renderCurrentPage() {
        // Clear previous page content.
        for subview in pageContainer.subviews {
            subview.removeFromSuperview()
        }

        let page = entry.pages[currentIndex]
        let pageView = makePageView(for: page)
        pageView.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(pageView)
        NSLayoutConstraint.activate([
            pageView.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            pageView.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            pageView.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            pageView.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
        ])

        updateDotAppearance()
        prevButton.isEnabled = currentIndex > 0
        nextButton.isEnabled = currentIndex < entry.pages.count - 1
    }

    private func makePageView(for page: WhatsNewPage) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.distribution = .fill

        if let assetName = page.imageAssetName,
           let image = NSImage(named: assetName) {
            let imageView = NSImageView()
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.imageAlignment = .alignCenter
            imageView.translatesAutoresizingMaskIntoConstraints = false
            // Override NSImageView's giant intrinsic content size (driven by
            // `image.size`) so a huge screenshot doesn't blow the sheet out to
            // the screen's full width — with low hug/compression on both axes
            // auto-layout is free to size the view from our explicit
            // width/aspect constraints below.
            imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
            imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
            stack.addArrangedSubview(imageView)

            // Width: at most the stack's width (required), preferring to fill
            // it (high but breakable if the aspect ratio would push height
            // over the max).
            NSLayoutConstraint.activate([
                imageView.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
                imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 340),
            ])
            let fillWidth = imageView.widthAnchor.constraint(equalTo: stack.widthAnchor)
            fillWidth.priority = .defaultHigh
            fillWidth.isActive = true

            if image.size.width > 0, image.size.height > 0 {
                let ratio = image.size.height / image.size.width
                imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: ratio).isActive = true
            }
        }

        let titleLabel = NSTextField(labelWithString: page.title)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        titleLabel.preferredMaxLayoutWidth = 480
        stack.addArrangedSubview(titleLabel)

        let bodyLabel = NSTextField(wrappingLabelWithString: page.body)
        bodyLabel.alignment = .center
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.preferredMaxLayoutWidth = 480
        stack.addArrangedSubview(bodyLabel)

        return stack
    }

    private func updateDotAppearance() {
        let active = NSColor.labelColor
        let inactive = NSColor.tertiaryLabelColor
        for (index, dot) in dotViews.enumerated() {
            dot.layer?.backgroundColor = (index == currentIndex ? active : inactive).cgColor
        }
    }

    // MARK: - Actions

    @objc private func prevTapped() {
        guard currentIndex > 0 else { return }
        currentIndex -= 1
        renderCurrentPage()
    }

    @objc private func nextTapped() {
        guard currentIndex < entry.pages.count - 1 else { return }
        currentIndex += 1
        renderCurrentPage()
    }

    @objc private func gotItTapped() {
        closeSheet()
    }

    private func closeSheet() {
        guard let window else { return }
        if let parentWindow {
            parentWindow.endSheet(window)
        } else {
            window.close()
            invokeDismissOnce()
        }
    }

    private func invokeDismissOnce() {
        guard !hasCalledDismiss else { return }
        hasCalledDismiss = true
        onDismiss()
    }
}
