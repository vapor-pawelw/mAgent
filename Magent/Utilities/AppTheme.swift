import AppKit
import MagentCore

@MainActor
enum AppTheme {
    private(set) static var primaryColor = NSColor(resource: .primaryBrand)

    static func apply(_ settings: AppSettings) {
        primaryColor = NSColor(hex: settings.effectivePrimaryColorHex)
            ?? NSColor(resource: .primaryBrand)
    }

    static func tintToolbarButtons(_ buttons: [NSButton]) {
        PrimaryTintStyler.tintToolbarButtons(buttons, color: primaryColor)
    }

    static func stylePrimaryAction(_ button: NSButton) {
        PrimaryTintStyler.stylePrimaryAction(button, color: primaryColor)
    }

    static func tintSettingsControls(in rootView: NSView) {
        PrimaryTintStyler.tintSettingsControls(in: rootView, color: primaryColor)
        invalidatePrimarySelectionRows(in: rootView)
    }

    private static func invalidatePrimarySelectionRows(in view: NSView) {
        if view is PrimarySelectionTableRowView {
            view.needsDisplay = true
        }
        view.subviews.forEach(invalidatePrimarySelectionRows)
    }
}

final class PrimarySelectionTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            let opacity: CGFloat = isEmphasized ? 0.30 : 0.18
            NSColor.appPrimary.withAlphaComponent(opacity).setFill()
            NSBezierPath(
                roundedRect: bounds.insetBy(dx: 3, dy: 1),
                xRadius: 5,
                yRadius: 5
            ).fill()
        }
    }
}

extension NSColor {
    @MainActor
    static var appPrimary: NSColor {
        AppTheme.primaryColor
    }
}
