import AppKit
import MagentCore

@MainActor
enum AppTheme {
    private(set) static var primaryColor = NSColor(resource: .primaryBrand)

    static func apply(_ settings: AppSettings) {
        primaryColor = NSColor(hex: settings.effectivePrimaryColorHex)
            ?? NSColor(resource: .primaryBrand)
    }
}

extension NSColor {
    @MainActor
    static var appPrimary: NSColor {
        AppTheme.primaryColor
    }
}
