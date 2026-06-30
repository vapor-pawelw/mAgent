import Foundation

@MainActor
enum DevSessionLog {
    enum Category: String {
        case app
        case sidebar
        case navigation
        case popout
    }

    #if DEBUG
    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let sessionFileURL: URL = {
        let timestamp = Self.fileTimestamp(Date())
        return URL(fileURLWithPath: "/tmp/magent-debug-\(ProcessInfo.processInfo.processIdentifier)-\(timestamp).log")
    }()

    private static let currentFileURL = URL(fileURLWithPath: "/tmp/magent-debug-current.log")
    private static var didWriteHeader = false

    static var currentLogPath: String {
        sessionFileURL.path
    }

    static func log(_ category: Category, _ message: @autoclosure () -> String) {
        write(category: category.rawValue, message: message())
    }

    static func log(
        _ category: Category,
        _ message: String,
        fields: @autoclosure () -> [String: Any?]
    ) {
        let renderedFields = fields()
            .compactMap { key, value -> String? in
                guard let value else { return nil }
                return "\(key)=\(render(value))"
            }
            .sorted()
            .joined(separator: " ")
        let fullMessage = renderedFields.isEmpty ? message : "\(message) \(renderedFields)"
        write(category: category.rawValue, message: fullMessage)
    }

    private static func write(category: String, message: String) {
        if !didWriteHeader {
            didWriteHeader = true
            try? FileManager.default.removeItem(at: currentFileURL)
            let header = "=== Magent debug session pid=\(ProcessInfo.processInfo.processIdentifier) startedAt=\(dateFormatter.string(from: Date())) ===\n"
            append(header)
        }

        let line = "[\(dateFormatter.string(from: Date()))] [\(category)] \(message)\n"
        append(line)
    }

    private static func append(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        append(data, to: sessionFileURL)
        append(data, to: currentFileURL)
    }

    private static func append(_ data: Data, to url: URL) {
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: url.path, contents: data)
        }
    }

    private static func fileTimestamp(_ date: Date) -> String {
        dateFormatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: ".", with: "-")
    }

    private static func render(_ value: Any) -> String {
        switch value {
        case let uuid as UUID:
            return uuid.uuidString
        case let string as String:
            return string.replacingOccurrences(of: "\n", with: "\\n")
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return String(describing: value).replacingOccurrences(of: "\n", with: "\\n")
        }
    }
    #else
    static var currentLogPath: String { "" }
    static func log(_ category: Category, _ message: @autoclosure () -> String) {}
    static func log(
        _ category: Category,
        _ message: String,
        fields: @autoclosure () -> [String: Any?]
    ) {}
    #endif
}
