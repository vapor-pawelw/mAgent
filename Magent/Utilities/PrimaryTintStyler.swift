import AppKit

@MainActor
enum PrimaryTintStyler {
    static func tintToolbarButtons(_ buttons: [NSButton], color: NSColor) {
        let symbolConfiguration = NSImage.SymbolConfiguration(paletteColors: [color])
        buttons.forEach {
            $0.contentTintColor = color
            $0.symbolConfiguration = symbolConfiguration
            $0.needsDisplay = true
        }
    }

    static func stylePrimaryAction(_ button: NSButton, color: NSColor) {
        button.contentTintColor = color
        button.bezelColor = color
        (button.cell as? NSButtonCell)?.backgroundColor = color
        button.needsDisplay = true
    }

    static func tintSettingsControls(in rootView: NSView, color: NSColor) {
        for view in [rootView] + rootView.descendants {
            if let slider = view as? PrimaryTintSlider {
                slider.primaryTintColor = color
                continue
            }

            guard let button = view as? NSButton, !button.hasDestructiveAction else { continue }

            if button.keyEquivalent == "\r" {
                stylePrimaryAction(button, color: color)
                continue
            }

            switch button.bezelStyle {
            case .regularSquare, .rounded:
                if button.bezelStyle == .rounded {
                    stylePrimaryAction(button, color: color)
                } else {
                    button.contentTintColor = color
                }
            default:
                break
            }
        }
    }
}

final class PrimaryTintSlider: NSSlider {
    init(value: Double, minValue: Double, maxValue: Double, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        cell = PrimaryTintSliderCell()
        self.minValue = minValue
        self.maxValue = maxValue
        doubleValue = value
        self.target = target
        self.action = action
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        cell = PrimaryTintSliderCell()
    }

    var primaryTintColor: NSColor {
        get { (cell as? PrimaryTintSliderCell)?.primaryTintColor ?? .controlAccentColor }
        set {
            (cell as? PrimaryTintSliderCell)?.primaryTintColor = newValue
            needsDisplay = true
        }
    }
}

final class PrimaryTintSliderCell: NSSliderCell {
    var primaryTintColor = NSColor.controlAccentColor

    override func drawBar(inside rect: NSRect, flipped: Bool) {
        guard let slider = controlView as? NSSlider else {
            super.drawBar(inside: rect, flipped: flipped)
            return
        }

        let range = maxValue - minValue
        let fraction = range > 0 ? min(max((doubleValue - minValue) / range, 0), 1) : 0
        let trackThickness = min(4, slider.isVertical ? rect.width : rect.height)
        let trackRect: NSRect
        if slider.isVertical {
            trackRect = NSRect(
                x: rect.midX - trackThickness / 2,
                y: rect.minY,
                width: trackThickness,
                height: rect.height
            )
        } else {
            trackRect = NSRect(
                x: rect.minX,
                y: rect.midY - trackThickness / 2,
                width: rect.width,
                height: trackThickness
            )
        }

        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSBezierPath(
            roundedRect: trackRect,
            xRadius: trackThickness / 2,
            yRadius: trackThickness / 2
        ).fill()

        var fillRect = trackRect
        if slider.isVertical {
            fillRect.size.height *= fraction
        } else {
            fillRect.size.width *= fraction
            if slider.userInterfaceLayoutDirection == .rightToLeft {
                fillRect.origin.x = trackRect.maxX - fillRect.width
            }
        }

        primaryTintColor.setFill()
        NSBezierPath(
            roundedRect: fillRect,
            xRadius: trackThickness / 2,
            yRadius: trackThickness / 2
        ).fill()
    }
}

private extension NSView {
    var descendants: [NSView] {
        subviews + subviews.flatMap(\.descendants)
    }
}
