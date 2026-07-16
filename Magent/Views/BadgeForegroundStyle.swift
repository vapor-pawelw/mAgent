import AppKit

enum BadgeForegroundStyle {
    static let darkLighteningFraction: CGFloat = 0.50
    static let lightDarkeningFraction: CGFloat = 0.55

    static func color(tintColor: NSColor, appearance: NSAppearance) -> NSColor {
        var foregroundColor = tintColor
        appearance.performAsCurrentDrawingAppearance {
            let resolvedTint = tintColor.usingColorSpace(.sRGB) ?? tintColor
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                foregroundColor = resolvedTint.blended(
                    withFraction: darkLighteningFraction,
                    of: .white
                ) ?? resolvedTint
            } else {
                foregroundColor = resolvedTint.blended(
                    withFraction: lightDarkeningFraction,
                    of: .black
                ) ?? resolvedTint
            }
        }
        return foregroundColor
    }
}
