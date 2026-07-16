import AppKit
import Testing

@Suite("Status-row badge interaction")
struct RightClickMenuViewTests {
    @MainActor
    @Test("Left click forwards to row selection without requesting the context menu")
    func leftClickPassesThrough() throws {
        let view = RightClickMenuView()
        let responder = MouseDownRecordingResponder()
        view.nextResponder = responder
        var menuRequestCount = 0
        view.contextualMenuProvider = {
            menuRequestCount += 1
            return NSMenu()
        }
        let event = try #require(Self.mouseEvent(type: .leftMouseDown))

        view.mouseDown(with: event)

        #expect(responder.mouseDownCount == 1)
        #expect(menuRequestCount == 0)
    }

    @MainActor
    @Test("Context-menu lookup returns the badge-specific menu")
    func rightClickUsesContextMenu() throws {
        let view = RightClickMenuView()
        let expectedMenu = NSMenu()
        expectedMenu.addItem(withTitle: "Context", action: nil, keyEquivalent: "")
        view.contextualMenuProvider = { expectedMenu }
        let event = try #require(Self.mouseEvent(type: .rightMouseDown))

        #expect(view.menu(for: event) === expectedMenu)
    }

    @MainActor
    @Test("Control-click uses the contextual menu instead of selecting the row")
    func controlClickUsesContextMenu() throws {
        let view = ContextMenuRecordingView()
        let responder = MouseDownRecordingResponder()
        view.nextResponder = responder
        let expectedMenu = NSMenu()
        view.contextualMenuProvider = { expectedMenu }
        let event = try #require(Self.mouseEvent(type: .leftMouseDown, modifierFlags: .control))

        view.mouseDown(with: event)

        #expect(view.presentedMenu === expectedMenu)
        #expect(responder.mouseDownCount == 0)
    }

    @MainActor
    @Test("Nested badge content resolves to the full badge hit target")
    func nestedContentUsesBadgeHitTarget() {
        let view = RightClickMenuView(frame: NSRect(x: 0, y: 0, width: 80, height: 20))
        let nestedContent = NSView(frame: NSRect(x: 10, y: 4, width: 60, height: 12))
        view.addSubview(nestedContent)

        #expect(view.hitTest(NSPoint(x: 40, y: 10)) === view)
        #expect(view.hitTest(NSPoint(x: 4, y: 10)) === view)
        #expect(view.hitTest(NSPoint(x: 84, y: 10)) == nil)
    }

    private static func mouseEvent(
        type: NSEvent.EventType,
        modifierFlags: NSEvent.ModifierFlags = []
    ) -> NSEvent? {
        NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        )
    }
}

private final class MouseDownRecordingResponder: NSResponder {
    private(set) var mouseDownCount = 0

    override func mouseDown(with event: NSEvent) {
        mouseDownCount += 1
    }
}

private final class ContextMenuRecordingView: RightClickMenuView {
    private(set) var presentedMenu: NSMenu?

    override func popUpContextMenu(_ menu: NSMenu, with event: NSEvent) {
        presentedMenu = menu
    }
}
