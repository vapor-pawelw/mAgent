import AppKit

struct AgentLaunchPromptTextCommandActions {
    let submit: () -> Void
    let cancel: () -> Void
    let selectNextField: () -> Void
    let selectPreviousField: () -> Void
    let undo: () -> Void
    let redo: () -> Void
}

enum AgentLaunchPromptTextCommand: Equatable {
    case submit
    case cancel
    case selectNextField
    case selectPreviousField
    case undo
    case redo

    init?(selector: Selector) {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            self = .submit
        case #selector(NSResponder.cancelOperation(_:)):
            self = .cancel
        case #selector(NSResponder.insertTab(_:)):
            self = .selectNextField
        case #selector(NSResponder.insertBacktab(_:)):
            self = .selectPreviousField
        case Selector(("undo:")):
            self = .undo
        case Selector(("redo:")):
            self = .redo
        default:
            return nil
        }
    }

    func perform(
        isShiftReturn: Bool,
        actions: AgentLaunchPromptTextCommandActions
    ) -> Bool {
        switch self {
        case .submit:
            guard !isShiftReturn else { return false }
            actions.submit()
        case .cancel:
            actions.cancel()
        case .selectNextField:
            actions.selectNextField()
        case .selectPreviousField:
            actions.selectPreviousField()
        case .undo:
            actions.undo()
        case .redo:
            actions.redo()
        }
        return true
    }
}
