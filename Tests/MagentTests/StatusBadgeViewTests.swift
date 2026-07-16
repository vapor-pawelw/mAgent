import AppKit
import Testing

@Suite("PR and Jira status badges")
struct StatusBadgeViewTests {
    @Test("Semantic badge colors use a ten-percent background tint")
    func backgroundTintOpacity() {
        #expect(StatusBadgeView.Style.backgroundOpacity == 0.10)
    }

    @Test("Dark appearance strongly brightens badge labels while preserving their hue")
    func darkAppearanceForeground() throws {
        let appearance = try #require(NSAppearance(named: .darkAqua))
        let tint = NSColor(srgbRed: 0.75, green: 0.20, blue: 0.12, alpha: 1)

        let foreground = try #require(
            BadgeForegroundStyle.color(tintColor: tint, appearance: appearance)
                .usingColorSpace(.sRGB)
        )

        #expect(foreground.redComponent > tint.redComponent)
        #expect(foreground.greenComponent >= 0.59)
        #expect(foreground.blueComponent > tint.blueComponent)
        #expect(foreground.redComponent > foreground.greenComponent)
        #expect(foreground.greenComponent > foreground.blueComponent)
    }

    @Test("Light appearance strongly darkens badge labels while preserving their hue")
    func lightAppearanceForeground() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        let tint = NSColor(srgbRed: 0.12, green: 0.48, blue: 0.82, alpha: 1)

        let foreground = try #require(
            BadgeForegroundStyle.color(tintColor: tint, appearance: appearance)
                .usingColorSpace(.sRGB)
        )

        #expect(foreground.redComponent < tint.redComponent)
        #expect(foreground.greenComponent < tint.greenComponent)
        #expect(foreground.blueComponent <= 0.44)
        #expect(foreground.blueComponent > foreground.greenComponent)
        #expect(foreground.greenComponent > foreground.redComponent)
    }

    @Test("Light appearance gives yellow activity labels a single contrast adjustment")
    func lightAppearanceYellowActivityForeground() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        var resolvedTint: NSColor?
        appearance.performAsCurrentDrawingAppearance {
            resolvedTint = NSColor.systemYellow.usingColorSpace(.sRGB)
        }
        let tint = try #require(resolvedTint)

        let foreground = try #require(
            BadgeForegroundStyle.color(tintColor: .systemYellow, appearance: appearance)
                .usingColorSpace(.sRGB)
        )

        #expect(foreground.redComponent < tint.redComponent)
        #expect(foreground.greenComponent <= 0.43)
        #expect(foreground.redComponent > foreground.greenComponent)
        #expect(foreground.greenComponent > foreground.blueComponent)
    }
}
