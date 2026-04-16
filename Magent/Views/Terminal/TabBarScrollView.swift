import Cocoa

/// Horizontal-only scroll view that hosts the tab bar stack. Configured for a
/// chrome-less look: no border, transparent background, overlay scrollers that
/// auto-hide. Vertical-only scroll events (traditional mouse wheel) are
/// translated into horizontal panning so users without a horizontal scroll
/// surface can still navigate overflowing tabs without reaching for the arrow
/// buttons. Trackpad swipes that already carry horizontal delta pass through
/// unchanged.
final class TabBarScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        drawsBackground = false
        borderType = .noBorder
        // No visible scroller at any time — overflow is communicated via the
        // flanking arrow buttons. Scrolling still works via wheel/trackpad and
        // programmatic clip-view animation.
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        usesPredominantAxisScrolling = true
        automaticallyAdjustsContentInsets = false
        contentInsets = .init(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func scrollWheel(with event: NSEvent) {
        // Only translate purely vertical scroll events (traditional mouse wheel).
        // Trackpad / Magic Mouse swipes carry horizontal delta — pass through so
        // their natural horizontal pan still works.
        if abs(event.scrollingDeltaX) < 0.01, abs(event.scrollingDeltaY) > 0.01 {
            if let horizontalEvent = event.withHorizontalDelta() {
                super.scrollWheel(with: horizontalEvent)
                return
            }
        }
        super.scrollWheel(with: event)
    }
}

private extension NSEvent {
    /// Returns a copy of this scroll event with the Y delta swapped onto the X
    /// axis. Falls back to nil if CGEvent conversion fails; callers should
    /// forward the original event in that case.
    func withHorizontalDelta() -> NSEvent? {
        guard let cgCopy = cgEvent?.copy() else { return nil }
        let deltaY = cgCopy.getDoubleValueField(.scrollWheelEventDeltaAxis1)
        let pointDeltaY = cgCopy.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)
        let fixedPtDeltaY = cgCopy.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        cgCopy.setDoubleValueField(.scrollWheelEventDeltaAxis1, value: 0)
        cgCopy.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        cgCopy.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        cgCopy.setDoubleValueField(.scrollWheelEventDeltaAxis2, value: deltaY)
        cgCopy.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: pointDeltaY)
        cgCopy.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: fixedPtDeltaY)
        return NSEvent(cgEvent: cgCopy)
    }
}
