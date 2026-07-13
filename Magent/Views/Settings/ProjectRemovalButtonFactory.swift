import AppKit

enum ProjectRemovalButtonFactory {
    static func make(target: AnyObject?, action: Selector) -> NSButton {
        let button = NSButton(title: "Remove Project…", target: target, action: action)
        button.bezelStyle = .rounded
        button.hasDestructiveAction = true
        return button
    }
}
