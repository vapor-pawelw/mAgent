import Foundation

/// Manages compatibility symlinks left by worktree rename operations.
enum SymlinkManager {

    /// Removes broken symlinks from the given directory.
    /// Rename operations leave symlinks (old-name → actual-worktree-dir) that become
    /// stale once the worktree is archived/removed.
    static func cleanupBrokenSymlinks(in directory: String) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: directory) else { return }
        for entry in entries {
            let fullPath = (directory as NSString).appendingPathComponent(entry)
            let url = URL(fileURLWithPath: fullPath)
            guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
                  values.isSymbolicLink == true else { continue }
            if !fm.fileExists(atPath: fullPath) {
                try? fm.removeItem(atPath: fullPath)
            }
        }
    }

    /// Removes broken symlinks from all projects' worktrees base directories.
    static func cleanupAll(settings: AppSettings) {
        for project in settings.projects {
            cleanupBrokenSymlinks(in: project.resolvedWorktreesBasePath())
        }
    }

    /// Creates a symlink from `oldPath` to `newPath` for backward compatibility.
    /// Replaces any existing symlink at `oldPath`; no-ops if a real file/dir exists there.
    static func createCompatibilitySymlink(from oldPath: String, to newPath: String) {
        let fileManager = FileManager.default
        let oldURL = URL(fileURLWithPath: oldPath)

        if let values = try? oldURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            try? fileManager.removeItem(atPath: oldPath)
        }

        guard !fileManager.fileExists(atPath: oldPath) else { return }
        try? fileManager.createSymbolicLink(atPath: oldPath, withDestinationPath: newPath)
    }
}
