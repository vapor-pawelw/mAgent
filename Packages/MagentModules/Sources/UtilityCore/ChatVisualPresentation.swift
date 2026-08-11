import Foundation

public enum ChatContentLayoutPolicy {
    public static let maximumRailWidth = 920.0
    public static let minimumHorizontalInset = 14.0

    public static func railWidth(for containerWidth: Double) -> Double {
        let availableWidth = max(0, containerWidth - (minimumHorizontalInset * 2))
        return min(maximumRailWidth, availableWidth)
    }
}

public struct ChatComposerPresentation: Equatable, Sendable {
    public enum PrimaryAction: Equatable, Sendable {
        case disabled
        case send
        case steer
    }

    public let primaryAction: PrimaryAction
    public let isRunning: Bool
    public let queuedPromptCount: Int

    public init(
        hasDraftText: Bool,
        attachmentCount: Int,
        isRunning: Bool,
        queuedPromptCount: Int
    ) {
        let hasSubmission = hasDraftText || attachmentCount > 0
        if !hasSubmission {
            primaryAction = .disabled
        } else if isRunning {
            primaryAction = .steer
        } else {
            primaryAction = .send
        }
        self.isRunning = isRunning
        self.queuedPromptCount = max(0, queuedPromptCount)
    }
}

public enum ChatColorContrastPolicy {
    public static let minimumAccessibleRatio = 4.5

    public static func contrastRatio(
        foregroundRed: Double,
        foregroundGreen: Double,
        foregroundBlue: Double,
        backgroundRed: Double,
        backgroundGreen: Double,
        backgroundBlue: Double
    ) -> Double {
        let foreground = relativeLuminance(
            red: foregroundRed,
            green: foregroundGreen,
            blue: foregroundBlue
        )
        let background = relativeLuminance(
            red: backgroundRed,
            green: backgroundGreen,
            blue: backgroundBlue
        )
        return (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
    }

    public static func meetsAccessibleContrast(
        foregroundRed: Double,
        foregroundGreen: Double,
        foregroundBlue: Double,
        backgroundRed: Double,
        backgroundGreen: Double,
        backgroundBlue: Double
    ) -> Bool {
        contrastRatio(
            foregroundRed: foregroundRed,
            foregroundGreen: foregroundGreen,
            foregroundBlue: foregroundBlue,
            backgroundRed: backgroundRed,
            backgroundGreen: backgroundGreen,
            backgroundBlue: backgroundBlue
        ) >= minimumAccessibleRatio
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        let channels = [red, green, blue].map { component -> Double in
            let clamped = min(max(component, 0), 1)
            return clamped <= 0.04045
                ? clamped / 12.92
                : pow((clamped + 0.055) / 1.055, 2.4)
        }
        return (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
    }
}
