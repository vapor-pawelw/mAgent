public enum TabDisplayOrderSessionRenamer {
    public static func rekeyingTerminalSession(
        in displayOrder: [String],
        from oldSessionName: String,
        to newSessionName: String
    ) -> [String] {
        let oldIdentifier = "terminal:\(oldSessionName)"
        let newIdentifier = "terminal:\(newSessionName)"
        return displayOrder.map { $0 == oldIdentifier ? newIdentifier : $0 }
    }
}
