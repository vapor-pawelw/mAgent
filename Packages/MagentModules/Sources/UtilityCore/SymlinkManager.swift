import Foundation
import ShellInfra
import MagentModels

/// Manages compatibility symlinks left by worktree rename operations.
public enum SymlinkManager {

    /// Removes broken symlinks from the given directory.
    /// Rename operations leave symlinks (old-name → actual-worktree-dir) that become
    /// stale once the worktree is archived/removed.
    public static func cleanupBrokenSymlinks(in directory: String) {
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
    public static func cleanupAll(settings: AppSettings) {
        for project in settings.projects {
            cleanupBrokenSymlinks(in: project.resolvedWorktreesBasePath())
        }
    }

    /// Creates a symlink from `oldPath` to `newPath` for backward compatibility.
    /// Replaces any existing symlink at `oldPath`; no-ops if a real file/dir exists there.
    public static func createCompatibilitySymlink(from oldPath: String, to newPath: String) {
        let fileManager = FileManager.default
        let oldURL = URL(fileURLWithPath: oldPath)

        if let values = try? oldURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            try? fileManager.removeItem(atPath: oldPath)
        }

        guard !fileManager.fileExists(atPath: oldPath) else { return }
        try? fileManager.createSymbolicLink(atPath: oldPath, withDestinationPath: newPath)
    }

    /// Ensures `<worktreesBasePath>/<branchName>` exists as a symlink to `worktreePath`.
    /// - Safety rules:
    ///   - no-op when `branchName` is empty or path-unsafe (contains path separators)
    ///   - no-op when a real file/directory already exists at the target alias path
    ///   - no-op when an existing symlink already resolves to the same destination
    ///   - replaces only broken symlinks at the alias path
    public static func ensureBranchSymlink(
        branchName: String,
        worktreePath: String,
        worktreesBasePath: String
    ) {
        let trimmed = branchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard (trimmed as NSString).lastPathComponent == trimmed else { return }

        let fm = FileManager.default
        let aliasPath = (worktreesBasePath as NSString).appendingPathComponent(trimmed)

        // If the worktree directory already has the branch name, no compatibility
        // alias is needed — the real directory path already matches.
        if URL(fileURLWithPath: aliasPath).resolvingSymlinksInPath().path
            == URL(fileURLWithPath: worktreePath).resolvingSymlinksInPath().path {
            return
        }

        let aliasURL = URL(fileURLWithPath: aliasPath)
        if let values = try? aliasURL.resourceValues(forKeys: [.isSymbolicLinkKey]),
           values.isSymbolicLink == true {
            if let destination = try? fm.destinationOfSymbolicLink(atPath: aliasPath) {
                let absoluteDestination = destination.hasPrefix("/")
                    ? destination
                    : (worktreesBasePath as NSString).appendingPathComponent(destination)
                let resolvedExisting = URL(fileURLWithPath: absoluteDestination).resolvingSymlinksInPath().path
                let resolvedTarget = URL(fileURLWithPath: worktreePath).resolvingSymlinksInPath().path
                if resolvedExisting == resolvedTarget {
                    return
                }
            }
            // Replace only broken symlinks. Live symlinks are assumed intentional.
            if !fm.fileExists(atPath: aliasPath) {
                try? fm.removeItem(atPath: aliasPath)
                try? fm.createSymbolicLink(atPath: aliasPath, withDestinationPath: worktreePath)
            }
            return
        }

        guard !fm.fileExists(atPath: aliasPath) else { return }
        try? fm.createSymbolicLink(atPath: aliasPath, withDestinationPath: worktreePath)
    }
}
