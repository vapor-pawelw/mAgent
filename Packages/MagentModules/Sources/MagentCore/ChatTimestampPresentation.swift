import Foundation

public enum ChatTimestampPresentation {
    public static func metadataTooltip(
        exactText: String,
        metadataText: String?
    ) -> String {
        if let metadataText = metadataText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !metadataText.isEmpty {
            return "\(exactText)\n\(metadataText)"
        }
        return exactText
    }
}
