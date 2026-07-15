import AppKit
import Testing

@Suite("Split view sidebar sizing")
struct SplitViewControllerTests {
    @Test("Sidebar width range supports a compact minimum on small screens")
    func sidebarSupportsCompactWidth() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSViewController())
        SidebarWidthRange.configure(sidebarItem)

        #expect(sidebarItem.minimumThickness == 200)
        #expect(sidebarItem.maximumThickness == 420)
        #expect(SidebarWidthRange.clamp(100) == 200)
        #expect(SidebarWidthRange.clamp(220) == 220)
        #expect(SidebarWidthRange.clamp(500) == 420)
    }

    @Test("Thread selection clicks are not treated as divider drags")
    func threadSelectionClickDoesNotResizeSidebar() {
        var intent = SidebarDividerResizeIntent()
        let isDividerInteraction = intent.recognizes(
            .leftMouseDown,
            pointerX: 120,
            dividerX: 280,
            dividerThickness: 1
        )

        #expect(!isDividerInteraction)
    }

    @Test("A layout shift cannot turn a content interaction into a divider drag")
    func dividerDragMustBeginWithMouseDown() {
        var intent = SidebarDividerResizeIntent()
        let beganInContent = intent.recognizes(
            .leftMouseDown,
            pointerX: 120,
            dividerX: 280,
            dividerThickness: 1
        )
        let layoutMovedDividerUnderPointer = intent.recognizes(
            .leftMouseDragged,
            pointerX: 120,
            dividerX: 120,
            dividerThickness: 1
        )
        let endedOverDivider = intent.recognizes(
            .leftMouseUp,
            pointerX: 120,
            dividerX: 120,
            dividerThickness: 1
        )

        #expect(!beganInContent)
        #expect(!layoutMovedDividerUnderPointer)
        #expect(!endedOverDivider)
        #expect(!intent.isDragging)
    }

    @Test("Pointer interactions on the divider are treated as sidebar resizing")
    func dividerPointerEventsResizeSidebar() {
        var intent = SidebarDividerResizeIntent()
        for eventType in [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            let isDividerInteraction = intent.recognizes(
                eventType,
                pointerX: 282,
                dividerX: 280,
                dividerThickness: 1
            )

            #expect(isDividerInteraction)
        }
    }

    @Test("An active divider drag remains a resize when the divider reaches its width limit")
    func clampedDividerDragRemainsResize() {
        var intent = SidebarDividerResizeIntent()
        let beganOnDivider = intent.recognizes(
            .leftMouseDown,
            pointerX: 280,
            dividerX: 280,
            dividerThickness: 1
        )
        let continuedPastLimit = intent.recognizes(
            .leftMouseDragged,
            pointerX: 500,
            dividerX: 420,
            dividerThickness: 1
        )
        let endedPastLimit = intent.recognizes(
            .leftMouseUp,
            pointerX: 500,
            dividerX: 420,
            dividerThickness: 1
        )

        #expect(beganOnDivider)
        #expect(continuedPastLimit)
        #expect(endedPastLimit)
        #expect(!intent.isDragging)
    }

    @Test("A missed mouse-up is recovered from the physical button state")
    func releasedPrimaryButtonClearsStaleDrag() {
        var intent = SidebarDividerResizeIntent()
        _ = intent.recognizes(
            .leftMouseDown,
            pointerX: 280,
            dividerX: 280,
            dividerThickness: 1
        )

        intent.reconcilePrimaryButtonState(isPressed: false)

        #expect(!intent.isDragging)
    }

    @Test("Automatic layout keeps the preferred sidebar position")
    func automaticLayoutKeepsPreferredPosition() {
        let position = SidebarSplitPositionPolicy.position(
            proposed: 320,
            preferred: 280,
            enforced: nil,
            allowsMovement: false
        )

        #expect(position == 280)
    }

    @Test("A real divider drag or collapse can move the divider")
    func explicitSidebarInteractionAllowsMovement() {
        let position = SidebarSplitPositionPolicy.position(
            proposed: 320,
            preferred: 280,
            enforced: nil,
            allowsMovement: true
        )

        #expect(position == 320)
    }

    @Test("Content-swap enforcement takes precedence over active interaction")
    func contentSwapEnforcementTakesPrecedence() {
        let position = SidebarSplitPositionPolicy.position(
            proposed: 320,
            preferred: 280,
            enforced: 260,
            allowsMovement: true
        )

        #expect(position == 260)
    }
}
