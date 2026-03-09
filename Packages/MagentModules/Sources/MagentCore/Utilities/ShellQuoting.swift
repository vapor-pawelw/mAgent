import Foundation

/// Single-quote shell escaping — wraps the string in single quotes,
/// escaping any embedded single quotes via the `'\''` idiom.
public nonisolated func shellQuote(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
