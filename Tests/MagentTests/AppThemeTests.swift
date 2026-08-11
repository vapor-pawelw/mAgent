import AppKit
import Testing

@Suite("App primary color", .serialized)
struct AppThemeTests {
    @MainActor
    @Test("Toolbar and primary action buttons use the configured primary color")
    func actionButtonsUseConfiguredPrimaryColor() throws {
        let primaryColor = NSColor(srgbRed: 0.14, green: 0.41, blue: 0.67, alpha: 1)
        let toolbarButton = NSButton()
        let primaryButton = NSButton(title: "Continue", target: nil, action: nil)

        PrimaryTintStyler.tintToolbarButtons([toolbarButton], color: primaryColor)
        PrimaryTintStyler.stylePrimaryAction(primaryButton, color: primaryColor)

        #expect(try rgb(toolbarButton.contentTintColor) == rgb(primaryColor))
        #expect(toolbarButton.symbolConfiguration != nil)
        #expect(try rgb((primaryButton.cell as? NSButtonCell)?.backgroundColor) == rgb(primaryColor))
        #expect(try rgb(primaryButton.bezelColor) == rgb(primaryColor))
    }

    @MainActor
    @Test("Settings tint selection controls and actions without recoloring destructive actions")
    func settingsControlsRespectSemanticActions() throws {
        let primaryColor = NSColor(srgbRed: 0.36, green: 0.25, blue: 0.82, alpha: 1)
        let root = NSView()
        let checkbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
        let action = NSButton(title: "Refresh", target: nil, action: nil)
        action.bezelStyle = .rounded
        let destructive = NSButton(title: "Remove", target: nil, action: nil)
        destructive.bezelStyle = .rounded
        destructive.hasDestructiveAction = true
        destructive.contentTintColor = .systemRed
        [checkbox, action, destructive].forEach { root.addSubview($0) }

        PrimaryTintStyler.tintSettingsControls(in: root, color: primaryColor)

        #expect(try rgb(checkbox.contentTintColor) == rgb(primaryColor))
        #expect(try rgb(action.contentTintColor) == rgb(primaryColor))
        #expect(try rgb(action.bezelColor) == rgb(primaryColor))
        #expect(try rgb(destructive.contentTintColor) == rgb(.systemRed))
    }

    @MainActor
    @Test("Primary slider uses the configured tint without changing its value range")
    func primarySliderUsesConfiguredTint() throws {
        let primaryColor = NSColor(srgbRed: 0.36, green: 0.25, blue: 0.82, alpha: 1)
        let slider = PrimaryTintSlider(value: 17, minValue: 10, maxValue: 24, target: nil, action: nil)

        slider.primaryTintColor = primaryColor

        #expect(try rgb(slider.primaryTintColor) == rgb(primaryColor))
        #expect(slider.minValue == 10)
        #expect(slider.maxValue == 24)
        #expect(slider.doubleValue == 17)
    }

    @MainActor
    private func rgb(_ color: NSColor?) throws -> [CGFloat] {
        let converted = try #require(color?.usingColorSpace(.sRGB))
        return [converted.redComponent, converted.greenComponent, converted.blueComponent]
    }
}
