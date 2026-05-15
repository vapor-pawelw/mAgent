import Foundation
import MagentCore

enum RateLimitFingerprinting {
    static let version = "v2"
    static let maxLegacyFingerprintLength = 512

    static func legacyFingerprint(from focusText: String, fallback: String?) -> String {
        let normalizedFocus = normalizedText(focusText)
        if !normalizedFocus.isEmpty {
            return String(normalizedFocus.prefix(maxLegacyFingerprintLength))
        }
        let normalizedFallback = fallback.map(normalizedText)
        if let normalizedFallback, !normalizedFallback.isEmpty {
            return String(normalizedFallback.prefix(maxLegacyFingerprintLength))
        }
        return "__empty_rate_limit_fingerprint__"
    }

    static func structuredFingerprint(
        resetAt: Date,
        agent: AgentType,
        detectorMode: String,
        focusText: String,
        hasRelativeReset: Bool
    ) -> String {
        let indicatorClass = rateLimitIndicatorClass(from: focusText)
        if hasRelativeReset {
            return [
                version,
                agent.rawValue,
                detectorMode,
                indicatorClass,
                "relative",
                stableHashHex(normalizedText(focusText)),
            ].joined(separator: "|")
        }

        let resetMinuteBucket = Int(resetAt.timeIntervalSince1970) / 60
        return [
            version,
            agent.rawValue,
            detectorMode,
            indicatorClass,
            String(resetMinuteBucket),
        ].joined(separator: "|")
    }

    static func rateLimitIndicatorClass(from focusText: String) -> String {
        let normalized = normalizedText(focusText)
        if normalized.contains("you've hit your limit") || normalized.contains("hit your limit") {
            return "hit_limit"
        }
        if normalized.contains("hit your usage limit") || normalized.contains("usage limit") {
            return "usage_limit"
        }
        if normalized.contains("too many requests") {
            return "too_many_requests"
        }
        if normalized.contains("quota exceeded") {
            return "quota_exceeded"
        }
        if normalized.contains("retry after") || normalized.contains("try again") {
            return "retry_after"
        }
        if normalized.contains("rate limit") || normalized.contains("rate limited") {
            return "rate_limit"
        }
        return "generic_limit"
    }

    static func stableHashHex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        let prime: UInt64 = 0x100000001b3
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return String(hash, radix: 16)
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
