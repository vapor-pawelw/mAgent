import AppKit

@MainActor
enum PrimaryTintStyler {
    static func tintToolbarButtons(_ buttons: [NSButton], color: NSColor) {
        buttons.forEach { $0.contentTintColor = color }
    }

    static func stylePrimaryAction(_ button: NSButton, color: NSColor) {
        button.contentTintColor = color
        (button.cell as? NSButtonCell)?.backgroundColor = color
    }

    static func tintSettingsControls(in rootView: NSView, color: NSColor) {
        for view in [rootView] + rootView.descendants {
            guard let button = view as? NSButton, !button.hasDestructiveAction else { continue }

            if button.keyEquivalent == "\r" {
                stylePrimaryAction(button, color: color)
                continue
            }

            switch button.bezelStyle {
            case .regularSquare, .rounded:
                button.contentTintColor = color
            default:
                break
            }
        }
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
