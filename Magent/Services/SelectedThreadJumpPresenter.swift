import Foundation
import MagentCore

enum SelectedThreadJumpPresenter {
    static func title(for thread: MagentThread) -> String {
        if thread.isMain {
            return "Main worktree"
        }

        let description = thread.taskDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !description.isEmpty {
            return description
        }

        let worktreeName = (thread.worktreePath as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !worktreeName.isEmpty {
            return worktreeName
        }

        return "Thread"
    }
}
