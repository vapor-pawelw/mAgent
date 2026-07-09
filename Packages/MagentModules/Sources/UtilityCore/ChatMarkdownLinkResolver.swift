import Foundation

public struct ChatMarkdownFileLocation: Equatable {
    public let url: URL
    public let line: Int?
    public let column: Int?

    public init(url: URL, line: Int?, column: Int?) {
        self.url = url
        self.line = line
        self.column = column
    }
}

public enum ChatMarkdownLinkTarget: Equatable {
    case web(URL)
    case localFile(ChatMarkdownFileLocation)
    case diffFile(String)
}

public enum ChatMarkdownLinkResolver {
    private static let trailingLineColumnRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #":(\d+)(?::(\d+))?$"#)
    }()

    private static let lineColumnFragmentRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^[Ll](\d+)(?:[Cc](\d+))?$"#)
    }()

    public static func resolve(_ rawTarget: String, workingDirectory: String?) -> ChatMarkdownLinkTarget? {
        let trimmed = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let components = URLComponents(string: trimmed),
           components.scheme?.lowercased() == "magent-diff",
           components.host == "file",
           let path = components.queryItems?.first(where: { $0.name == "path" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            return .diffFile(path)
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return .web(url)
        }

        guard let fileLocation = resolveLocalFileLocation(from: trimmed, workingDirectory: workingDirectory) else {
            return nil
        }
        return .localFile(fileLocation)
    }

    private static func resolveLocalFileLocation(from rawTarget: String, workingDirectory: String?) -> ChatMarkdownFileLocation? {
        if rawTarget.lowercased().hasPrefix("file://"),
           let parsedURL = URL(string: rawTarget),
           parsedURL.isFileURL {
            let (strippedPath, trailingLine, trailingColumn) = stripTrailingLineColumn(from: parsedURL.path)
            guard !strippedPath.isEmpty else { return nil }
            let fragmentLocation = parseLineColumnFragment(parsedURL.fragment)
            return ChatMarkdownFileLocation(
                url: URL(fileURLWithPath: strippedPath).standardizedFileURL,
                line: trailingLine ?? fragmentLocation.line,
                column: trailingColumn ?? fragmentLocation.column
            )
        }

        let components = rawTarget.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let pathPart = String(components.first ?? "")
        let fragmentPart = components.count > 1 ? String(components[1]) : nil

        let (strippedPath, trailingLine, trailingColumn) = stripTrailingLineColumn(from: pathPart)
        guard !strippedPath.isEmpty else { return nil }

        let expandedPath = NSString(string: strippedPath).expandingTildeInPath
        let normalizedURL: URL
        if expandedPath.hasPrefix("/") {
            normalizedURL = URL(fileURLWithPath: expandedPath).standardizedFileURL
        } else {
            guard let workingDirectory, !workingDirectory.isEmpty else { return nil }
            let baseURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            normalizedURL = baseURL.appendingPathComponent(expandedPath).standardizedFileURL
        }

        let fragmentLocation = parseLineColumnFragment(fragmentPart)
        return ChatMarkdownFileLocation(
            url: normalizedURL,
            line: trailingLine ?? fragmentLocation.line,
            column: trailingColumn ?? fragmentLocation.column
        )
    }

    private static func stripTrailingLineColumn(from path: String) -> (path: String, line: Int?, column: Int?) {
        let nsPath = path as NSString
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        guard let match = trailingLineColumnRegex.firstMatch(in: path, options: [], range: range) else {
            return (path, nil, nil)
        }

        let pathRange = match.range(at: 0)
        let lineRange = match.range(at: 1)
        let columnRange = match.range(at: 2)

        let strippedPath = nsPath.replacingCharacters(in: pathRange, with: "")
        let lineValue: Int? = lineRange.location != NSNotFound
            ? Int(nsPath.substring(with: lineRange))
            : nil
        let columnValue: Int? = columnRange.location != NSNotFound
            ? Int(nsPath.substring(with: columnRange))
            : nil
        return (strippedPath, lineValue, columnValue)
    }

    private static func parseLineColumnFragment(_ fragment: String?) -> (line: Int?, column: Int?) {
        guard let fragment, !fragment.isEmpty else { return (nil, nil) }

        let nsFragment = fragment as NSString
        let range = NSRange(location: 0, length: nsFragment.length)
        guard let match = lineColumnFragmentRegex.firstMatch(in: fragment, options: [], range: range) else {
            return (nil, nil)
        }

        let lineRange = match.range(at: 1)
        let columnRange = match.range(at: 2)
        let lineValue: Int? = lineRange.location != NSNotFound
            ? Int(nsFragment.substring(with: lineRange))
            : nil
        let columnValue: Int? = columnRange.location != NSNotFound
            ? Int(nsFragment.substring(with: columnRange))
            : nil
        return (lineValue, columnValue)
    }
}
