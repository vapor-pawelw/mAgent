import MagentCore

enum ProjectSettingsSelectionResolver {
    static func project(at selectedRow: Int, in projects: [Project]) -> Project? {
        guard projects.indices.contains(selectedRow) else { return nil }
        return projects[selectedRow]
    }
}
