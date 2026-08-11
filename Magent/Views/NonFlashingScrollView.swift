import AppKit

/// `NSScrollView` subclass that suppresses overlay-scroller reveals that are
/// not driven by direct user interaction with this scroll view.
///
/// The sidebar and changes panel reload frequently in response to background
/// state (session-monitor polling, busy/idle transitions, rate-limit changes,
/// git-state refresh, etc.). Every `reloadData` re-tiles the scroll view and
/// re-issues `reflectScrolledClipView` to preserve scroll position, both of
/// which can flash overlay scrollers in. When the user is focused in another
/// app, seeing scrollers flicker in our background window is visually noisy
/// and unrelated to any intent of theirs.
///
/// Strategy:
/// - Treat scroller visibility as explicit policy: show only for a short window
///   after a local `scrollWheel` event, otherwise hide.
/// - Suppress AppKit reveal paths (`flashScrollers`, `reflectScrolledClipView`)
///   unless that interaction window is active.
/// - This prevents hover/focus/state-churn flashes (including Universal Control
///   pointer transitions) while keeping normal scroll feedback during real input.
class NonFlashingScrollView: NSScrollView {
    private let interactionWindowSeconds: TimeInterval = 0.8
    private var lastUserScrollAt: Date?
    private var hideWorkItem: DispatchWorkItem?
    private var isApplyingInternalScrollerState = false
    private var preferredHasVerticalScroller = true
    private var preferredHasHorizontalScroller = false

    override var hasVerticalScroller: Bool {
        didSet {
            guard !isApplyingInternalScrollerState else { return }
            preferredHasVerticalScroller = hasVerticalScroller
            applyScrollerVisibilityPolicy()
        }
    }

    override var hasHorizontalScroller: Bool {
        didSet {
            guard !isApplyingInternalScrollerState else { return }
            preferredHasHorizontalScroller = hasHorizontalScroller
            applyScrollerVisibilityPolicy()
        }
    }

    override func scrollWheel(with event: NSEvent) {
        noteUserScrollInteraction()
        super.scrollWheel(with: event)
    }

    func noteUserScrollInteraction() {
        lastUserScrollAt = Date()
        applyScrollerVisibilityPolicy()
        scheduleAutoHide()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyScrollerVisibilityPolicy()
    }

    override func flashScrollers() {
        guard shouldRevealScrollers else { return }
        super.flashScrollers()
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        // Always reflect clip-view changes so NSScrollView can keep document tiling
        // and geometry in sync during programmatic scroll/restoration paths.
        // Scroller visibility is still controlled by applyScrollerVisibilityPolicy().
        applyScrollerVisibilityPolicy()
    }

    private var shouldRevealScrollers: Bool {
        guard let lastUserScrollAt else { return false }
        return Date().timeIntervalSince(lastUserScrollAt) <= interactionWindowSeconds
    }

    private func scheduleAutoHide() {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyScrollerVisibilityPolicy()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + interactionWindowSeconds, execute: work)
    }

    private func applyScrollerVisibilityPolicy() {
        let shouldShow = shouldRevealScrollers
        setScrollers(
            vertical: preferredHasVerticalScroller && shouldShow,
            horizontal: preferredHasHorizontalScroller && shouldShow
        )
    }

    private func setScrollers(vertical: Bool, horizontal: Bool) {
        isApplyingInternalScrollerState = true
        hasVerticalScroller = vertical
        hasHorizontalScroller = horizontal
        isApplyingInternalScrollerState = false
    }
}

struct DiscreteScrollSmoothing {
    static let pointsPerNotch: CGFloat = 44
    static let responseTime: TimeInterval = 0.06

    static func destination(
        currentDestination: CGFloat?,
        currentOrigin: CGFloat,
        scrollingDeltaY: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) -> CGFloat {
        let startingPoint = currentDestination ?? currentOrigin
        let direction: CGFloat = scrollingDeltaY > 0 ? 1 : -1
        let proposed = startingPoint - direction * pointsPerNotch
        return clampedDestination(proposed, allowedRange: allowedRange)
    }

    static func clampedDestination(
        _ destination: CGFloat,
        allowedRange: ClosedRange<CGFloat>
    ) -> CGFloat {
        min(max(destination, allowedRange.lowerBound), allowedRange.upperBound)
    }

    static func nextOrigin(
        currentOrigin: CGFloat,
        destination: CGFloat,
        elapsed: TimeInterval
    ) -> CGFloat {
        guard elapsed > 0 else { return currentOrigin }
        let progress = 1 - exp(-elapsed / responseTime)
        return currentOrigin + (destination - currentOrigin) * progress
    }

    static func shouldStop(
        appliedOrigin: CGFloat,
        destination: CGFloat,
        consecutiveStalledTicks: Int,
        elapsedSinceStart: TimeInterval
    ) -> Bool {
        abs(appliedOrigin - destination) <= 0.25
            || consecutiveStalledTicks >= 3
            || elapsedSinceStart >= 1
    }
}

/// Sidebar-only smoother. Its direction mapping assumes NSOutlineView's flipped coordinates.
final class SmoothDiscreteScrollView: NonFlashingScrollView {
    private var destinationY: CGFloat?
    private var animationTimer: Timer?
    private var animationStartedAt: TimeInterval?
    private var previousTickTime: TimeInterval?
    private var lastAppliedOriginY: CGFloat?
    private var consecutiveStalledTicks = 0
    private var isDiscreteScrollAnimationActive = false

    override func scrollWheel(with event: NSEvent) {
        guard !event.hasPreciseScrollingDeltas,
              abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX),
              event.scrollingDeltaY != 0,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            stopDiscreteScrollAnimation()
            super.scrollWheel(with: event)
            return
        }

        noteUserScrollInteraction()

        let clipView = contentView
        let currentOriginY = clipView.bounds.origin.y
        let allowedRange = verticalScrollRange(for: clipView)
        destinationY = DiscreteScrollSmoothing.destination(
            currentDestination: destinationY,
            currentOrigin: currentOriginY,
            scrollingDeltaY: event.scrollingDeltaY,
            allowedRange: allowedRange
        )
        animationStartedAt = ProcessInfo.processInfo.systemUptime
        consecutiveStalledTicks = 0
        lastAppliedOriginY = currentOriginY
        startDiscreteScrollAnimationIfNeeded()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            stopDiscreteScrollAnimation()
        }
        super.viewWillMove(toWindow: newWindow)
    }

    private func verticalScrollRange(for clipView: NSClipView) -> ClosedRange<CGFloat> {
        var proposedBounds = clipView.bounds
        proposedBounds.origin.y = -1_000_000_000
        let minimum = clipView.constrainBoundsRect(proposedBounds).origin.y
        proposedBounds.origin.y = 1_000_000_000
        let maximum = clipView.constrainBoundsRect(proposedBounds).origin.y
        return min(minimum, maximum)...max(minimum, maximum)
    }

    private func startDiscreteScrollAnimationIfNeeded() {
        guard !isDiscreteScrollAnimationActive else { return }
        isDiscreteScrollAnimationActive = true
        previousTickTime = ProcessInfo.processInfo.systemUptime
        scheduleNextDiscreteScrollTick()
    }

    private func scheduleNextDiscreteScrollTick() {
        animationTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: false) { [weak self] _ in
            // This timer is installed only on the main run loop, matching NSView isolation.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.advanceDiscreteScrollAnimation()
                if self.isDiscreteScrollAnimationActive {
                    self.scheduleNextDiscreteScrollTick()
                }
            }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceDiscreteScrollAnimation() {
        guard let requestedDestinationY = destinationY else {
            stopDiscreteScrollAnimation()
            return
        }

        let clipView = contentView
        let allowedRange = verticalScrollRange(for: clipView)
        let destinationY = DiscreteScrollSmoothing.clampedDestination(
            requestedDestinationY,
            allowedRange: allowedRange
        )
        self.destinationY = destinationY
        let currentOriginY = clipView.bounds.origin.y
        if let lastAppliedOriginY, abs(currentOriginY - lastAppliedOriginY) > 0.5 {
            stopDiscreteScrollAnimation()
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(max(now - (previousTickTime ?? now), 0), 1.0 / 30.0)
        let elapsedSinceStart = now - (animationStartedAt ?? now)
        previousTickTime = now

        let remaining = destinationY - currentOriginY
        let nextOriginY: CGFloat
        if abs(remaining) <= 0.25 {
            nextOriginY = destinationY
        } else {
            nextOriginY = DiscreteScrollSmoothing.nextOrigin(
                currentOrigin: currentOriginY,
                destination: destinationY,
                elapsed: elapsed
            )
        }

        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: nextOriginY))
        reflectScrolledClipView(clipView)
        let appliedOriginY = clipView.bounds.origin.y
        let movement = abs(appliedOriginY - currentOriginY)
        if movement < 0.01, abs(appliedOriginY - destinationY) > 0.25 {
            consecutiveStalledTicks += 1
        } else {
            consecutiveStalledTicks = 0
        }
        lastAppliedOriginY = appliedOriginY

        if DiscreteScrollSmoothing.shouldStop(
            appliedOrigin: appliedOriginY,
            destination: destinationY,
            consecutiveStalledTicks: consecutiveStalledTicks,
            elapsedSinceStart: elapsedSinceStart
        ) {
            stopDiscreteScrollAnimation()
        }
    }

    private func stopDiscreteScrollAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        destinationY = nil
        animationStartedAt = nil
        previousTickTime = nil
        lastAppliedOriginY = nil
        consecutiveStalledTicks = 0
        isDiscreteScrollAnimationActive = false
    }
}
