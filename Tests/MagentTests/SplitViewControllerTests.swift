import AppKit
import Testing

@Suite("Split view sidebar sizing")
struct SplitViewControllerTests {
    @Test("Sidebar width range supports a compact minimum on small screens")
    func sidebarSupportsCompactWidth() {
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: NSViewController())
        SidebarWidthRange.configure(sidebarItem)

        #expect(sidebarItem.minimumThickness == 154)
        #expect(sidebarItem.maximumThickness == 420)
        #expect(SidebarWidthRange.clamp(100) == 154)
        #expect(SidebarWidthRange.clamp(180) == 180)
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
}
