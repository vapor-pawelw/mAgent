import AppKit
import Testing

@Suite
struct ProjectRemovalButtonFactoryTests {
    @Test
    func buttonPresentsAndInvokesDestructiveProjectRemovalAction() {
        let target = ProjectRemovalButtonTarget()
        let button = ProjectRemovalButtonFactory.make(
            target: target,
            action: #selector(ProjectRemovalButtonTarget.removeProject)
        )

        #expect(button.title == "Remove Project…")
        #expect(button.hasDestructiveAction)

        button.performClick(nil)

        #expect(target.didRequestRemoval)
    }
}

private final class ProjectRemovalButtonTarget: NSObject {
    var didRequestRemoval = false

    @objc func removeProject() {
        didRequestRemoval = true
    }
}
