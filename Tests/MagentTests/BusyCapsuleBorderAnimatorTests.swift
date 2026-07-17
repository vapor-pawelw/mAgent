import AppKit
import Testing

@Suite("Busy capsule border")
struct BusyCapsuleBorderAnimatorTests {
    @MainActor
    @Test("Active state renders a rotating conic border with the requested geometry")
    func activeStateRendersAnimatedBorder() throws {
        let host = CALayer()
        let animator = BusyCapsuleBorderAnimator(hostLayer: host)
        let bounds = CGRect(x: 0, y: 0, width: 120, height: 28)
        let borderRect = bounds.insetBy(dx: 1, dy: 1)
        let appearance = try #require(NSAppearance(named: .aqua))

        animator.update(
            isActive: true,
            canAnimate: true,
            bounds: bounds,
            borderRect: borderRect,
            cornerRadius: 6,
            borderWidth: 2,
            isSelected: false,
            appearance: appearance
        )

        let container = try #require(host.sublayers?.first)
        let gradient = try #require(container.sublayers?.first as? CAGradientLayer)
        let mask = try #require(container.mask as? CAShapeLayer)

        #expect(animator.isVisible)
        #expect(gradient.type == .conic)
        #expect(gradient.animationKeys()?.isEmpty == false)
        #expect(mask.frame == bounds)
        #expect(mask.lineWidth == 2)
        #expect(mask.path?.boundingBoxOfPath == borderRect)
    }

    @MainActor
    @Test("Inactive and reduced-motion states remove the animated border")
    func inactiveStateRemovesAnimatedBorder() throws {
        let host = CALayer()
        let animator = BusyCapsuleBorderAnimator(hostLayer: host)
        let appearance = try #require(NSAppearance(named: .aqua))

        animator.update(
            isActive: true,
            canAnimate: true,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 28),
            borderRect: CGRect(x: 1, y: 1, width: 98, height: 26),
            cornerRadius: 6,
            borderWidth: 2,
            isSelected: false,
            appearance: appearance
        )
        animator.update(
            isActive: true,
            canAnimate: false,
            bounds: .zero,
            borderRect: .zero,
            cornerRadius: 0,
            borderWidth: 0,
            isSelected: false,
            appearance: appearance
        )

        #expect(!animator.isVisible)
        #expect(host.sublayers?.isEmpty != false)
    }
}
