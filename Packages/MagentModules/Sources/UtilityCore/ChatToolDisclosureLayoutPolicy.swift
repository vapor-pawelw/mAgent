import Foundation

public enum ChatToolDisclosureLayoutPolicy {
    public static func targetWidth(
        isActivitySummary: Bool,
        maximumWidth: Double,
        minimumWidth: Double,
        measuredLineWidth: Double,
        measuredHeaderWidth: Double,
        horizontalPadding: Double
    ) -> Double {
        if isActivitySummary {
            return maximumWidth
        }

        return min(
            maximumWidth,
            max(
                minimumWidth,
                ceil(max(measuredLineWidth, measuredHeaderWidth) + horizontalPadding)
            )
        )
    }

    public static func headerTitle(title: String, detail: String?) -> String {
        let trimmedDetail = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedDetail.isEmpty else { return title }
        return "\(title)  ·  \(trimmedDetail)"
    }
}
