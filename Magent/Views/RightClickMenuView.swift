import AppKit

class RightClickMenuView: NSView {
    var contextualMenuProvider: (() -> NSMenu?)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Nested labels and stacks must not fragment the badge's contextual-menu hit area.
        guard super.hitTest(point) != nil else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = menu(for: event) {
            popUpContextMenu(menu, with: event)
            return
        }
        nextResponder?.mouseDown(with: event)
    }

    func popUpContextMenu(_ menu: NSMenu, with event: NSEvent) {
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextualMenuProvider?() ?? super.menu(for: event)
    }
}
