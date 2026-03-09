import Cocoa
import MagentCore

extension ThreadDetailViewController {

    // Minimum lines scrolled from the bottom before the FAB appears.
    // This prevents the button from flashing on minor incidental scrolls near live output.
    private static let scrollFABThreshold: UInt64 = 12
    private static let scrollFABRefreshDelayNanoseconds: UInt64 = 120_000_000

    // MARK: - Setup

    // MARK: - Scroll Overlay (bottom-right draggable pill)

    func bringScrollOverlaysToFront() {
        if scrollOverlay.superview === terminalContainer {
            terminalContainer.addSubview(scrollOverlay, positioned: .above, relativeTo: nil)
        }
        if floatingScrollToBottomButton.superview === terminalContainer {
            terminalContainer.addSubview(floatingScrollToBottomButton, positioned: .above, relativeTo: nil)
        }
    }

    func setupScrollOverlay() {
        let overlay = scrollOverlay
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.onScrollUp       = { [weak self] in self?.scrollTerminalPageUpTapped() }
        overlay.onScrollDown     = { [weak self] in self?.scrollTerminalPageDownTapped() }
        overlay.onScrollToBottom = { [weak self] in self?.scrollTerminalToBottomTapped() }

        terminalContainer.addSubview(overlay)

        let trailing = overlay.trailingAnchor.constraint(equalTo: terminalContainer.trailingAnchor, constant: -16)
        let bottom   = overlay.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor, constant: -32)
        scrollOverlayTrailingConstraint = trailing
        scrollOverlayBottomConstraint   = bottom
        NSLayoutConstraint.activate([trailing, bottom])

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handleScrollOverlayPan(_:)))
        overlay.addGestureRecognizer(pan)
    }

    @objc func handleScrollOverlayPan(_ gesture: NSPanGestureRecognizer) {
        guard let trailing = scrollOverlayTrailingConstraint,
              let bottom   = scrollOverlayBottomConstraint else { return }

        switch gesture.state {
        case .began:
            // Store current offsets as positive distances from the edges.
            scrollOverlayDragStartTrailing = -trailing.constant
            scrollOverlayDragStartBottom   = -bottom.constant

        case .changed:
            let t = gesture.translation(in: view)
            // Positive x → moved right → trailing offset decreases (overlay moves right).
            let newTrailing = scrollOverlayDragStartTrailing - t.x
            // Positive y → moved up (AppKit coords) → bottom offset increases.
            let newBottom   = scrollOverlayDragStartBottom + t.y

            let size = scrollOverlay.frame.size
            trailing.constant = -min(max(8, newTrailing), terminalContainer.bounds.width  - size.width  - 8)
            bottom.constant   = -min(max(8, newBottom),   terminalContainer.bounds.height - size.height - 8)

        default:
            break
        }
    }

    func setupScrollFAB() {
        let btn = floatingScrollToBottomButton
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        btn.alphaValue = 0
        btn.setButtonType(.momentaryPushIn)
        btn.isBordered = false
        btn.focusRingType = .none
        btn.title = " Przewin w dol"
        btn.image = NSImage(systemSymbolName: "arrow.down.to.line", accessibilityDescription: nil)
        btn.imagePosition = .imageLeading
        btn.imageScaling = .scaleProportionallyDown
        btn.font = .systemFont(ofSize: 12, weight: .semibold)
        btn.contentTintColor = NSColor.labelColor
        btn.toolTip = "Przewin do live output"
        btn.target = self
        btn.action = #selector(floatingScrollToBottomTapped)
        btn.imageHugsTitle = true

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowBlurRadius = 6
        btn.wantsLayer = true
        btn.shadow = shadow
        btn.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
        btn.layer?.cornerRadius = 18
        btn.layer?.borderWidth = 1
        btn.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor

        terminalContainer.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.leadingAnchor.constraint(equalTo: terminalContainer.leadingAnchor, constant: 18),
            btn.bottomAnchor.constraint(equalTo: terminalContainer.bottomAnchor, constant: -18),
        ])
    }

    // MARK: - Show / Hide

    func setScrollFABVisible(_ visible: Bool) {
        if visible && floatingScrollToBottomButton.isHidden {
            floatingScrollToBottomButton.alphaValue = 0
            floatingScrollToBottomButton.isHidden = false
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.floatingScrollToBottomButton.animator().alphaValue = 1
            }
        } else if !visible && !floatingScrollToBottomButton.isHidden {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                self.floatingScrollToBottomButton.animator().alphaValue = 0
            }, completionHandler: {
                Task { @MainActor [weak self] in
                    self?.floatingScrollToBottomButton.isHidden = true
                }
            })
        }
    }

    func scheduleScrollFABVisibilityRefresh() {
        scrollFABRefreshTask?.cancel()

        guard let sessionName = currentSessionName() else {
            setScrollFABVisible(false)
            return
        }

        scrollFABRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.scrollFABRefreshDelayNanoseconds)
            guard !Task.isCancelled else { return }

            let linesFromBottom = await TmuxService.shared.scrollPosition(sessionName: sessionName) ?? 0
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard self.currentSessionName() == sessionName else { return }
                self.setScrollFABVisible(linesFromBottom >= Self.scrollFABThreshold)
            }
        }
    }

    // MARK: - Scrollbar Notification

    @objc func handleScrollbarUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let surfaceAddr = userInfo["surfaceAddr"] as? Int,
              let total = userInfo["total"] as? UInt64,
              let offset = userInfo["offset"] as? UInt64,
              let len = userInfo["len"] as? UInt64 else { return }

        // Only react to updates from the currently visible terminal.
        guard currentTabIndex < terminalViews.count,
              let surface = terminalViews[currentTabIndex].surface,
              Int(bitPattern: surface) == surfaceAddr else { return }

        let linesFromBottom = (total > offset + len) ? (total - offset - len) : 0
        setScrollFABVisible(linesFromBottom >= Self.scrollFABThreshold)
    }

    // MARK: - Action

    @objc func floatingScrollToBottomTapped() {
        // Hide immediately for instant feedback.
        setScrollFABVisible(false)
        scrollFABRefreshTask?.cancel()

        // Scroll ghostty's own scrollback to the bottom.
        if currentTabIndex < terminalViews.count {
            terminalViews[currentTabIndex].bindingAction("scroll_to_bottom")
        }

        // Also cancel tmux copy-mode in case scroll overlay page-up was used.
        scrollTerminalToBottomTapped()
        scheduleScrollFABVisibilityRefresh()
    }
}
