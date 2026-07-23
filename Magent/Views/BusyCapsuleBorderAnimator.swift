import AppKit

@MainActor
final class BusyCapsuleBorderAnimator {
    private static let rotationAnimationKey = "busy-capsule-border-rotation"
    private static var sharedAnimationEpoch: CFTimeInterval = 0

    private weak var hostLayer: CALayer?
    private var containerLayer: CALayer?

    init(hostLayer: CALayer) {
        self.hostLayer = hostLayer
    }

    var isVisible: Bool {
        containerLayer != nil
    }

    func update(
        isActive: Bool,
        canAnimate: Bool,
        bounds: CGRect,
        borderRect: CGRect,
        cornerRadius: CGFloat,
        borderWidth: CGFloat,
        isSelected: Bool,
        appearance: NSAppearance,
        accentColor: NSColor = .controlAccentColor,
        zPosition: CGFloat = 0
    ) {
        guard isActive, canAnimate else {
            stop()
            return
        }

        if containerLayer == nil {
            start(
                bounds: bounds,
                borderRect: borderRect,
                cornerRadius: cornerRadius,
                borderWidth: borderWidth,
                isSelected: isSelected,
                appearance: appearance,
                accentColor: accentColor,
                zPosition: zPosition
            )
        } else {
            layout(
                bounds: bounds,
                borderRect: borderRect,
                cornerRadius: cornerRadius,
                borderWidth: borderWidth
            )
            updateColors(isSelected: isSelected, appearance: appearance, accentColor: accentColor)
            restoreAnimationIfNeeded()
        }
    }

    func stop() {
        containerLayer?.removeFromSuperlayer()
        containerLayer = nil
    }

    private func start(
        bounds: CGRect,
        borderRect: CGRect,
        cornerRadius: CGFloat,
        borderWidth: CGFloat,
        isSelected: Bool,
        appearance: NSAppearance,
        accentColor: NSColor,
        zPosition: CGFloat
    ) {
        guard let hostLayer else { return }

        let container = CALayer()
        container.frame = bounds
        container.zPosition = zPosition
        hostLayer.addSublayer(container)

        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.locations = [0.0, 0.08, 0.16, 0.5, 0.84, 0.92, 1.0]
        container.addSublayer(gradient)

        let mask = CAShapeLayer()
        mask.fillColor = nil
        mask.strokeColor = NSColor.white.cgColor
        container.mask = mask

        containerLayer = container
        layout(
            bounds: bounds,
            borderRect: borderRect,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth
        )
        updateColors(isSelected: isSelected, appearance: appearance, accentColor: accentColor)

        if Self.sharedAnimationEpoch == 0 {
            Self.sharedAnimationEpoch = CACurrentMediaTime()
        }
        gradient.add(makeRotationAnimation(), forKey: Self.rotationAnimationKey)
    }

    private func layout(
        bounds: CGRect,
        borderRect: CGRect,
        cornerRadius: CGFloat,
        borderWidth: CGFloat
    ) {
        guard let containerLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.frame = bounds

        if let gradient = containerLayer.sublayers?.first as? CAGradientLayer {
            let diagonal = sqrt(borderRect.width * borderRect.width + borderRect.height * borderRect.height)
            gradient.frame = CGRect(
                x: borderRect.midX - diagonal / 2,
                y: borderRect.midY - diagonal / 2,
                width: diagonal,
                height: diagonal
            )
        }
        if let mask = containerLayer.mask as? CAShapeLayer {
            mask.frame = containerLayer.bounds
            mask.path = CGPath(
                roundedRect: borderRect,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            mask.lineWidth = borderWidth
        }
        CATransaction.commit()
    }

    private func updateColors(isSelected: Bool, appearance: NSAppearance, accentColor: NSColor) {
        guard let gradient = containerLayer?.sublayers?.first as? CAGradientLayer else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        appearance.performAsCurrentDrawingAppearance {
            let brightColor: NSColor
            let dimColor: NSColor
            if isSelected {
                brightColor = NSColor.white.withAlphaComponent(0.9)
                dimColor = NSColor.white.withAlphaComponent(0.25)
            } else {
                var hue: CGFloat = 0
                var saturation: CGFloat = 0
                var brightness: CGFloat = 0
                var alpha: CGFloat = 0
                accentColor.usingColorSpace(.sRGB)?.getHue(
                    &hue,
                    saturation: &saturation,
                    brightness: &brightness,
                    alpha: &alpha
                )
                brightColor = NSColor(
                    hue: hue,
                    saturation: max(saturation * 0.7, 0.3),
                    brightness: min(brightness * 1.1, 1.0),
                    alpha: 0.8
                )
                dimColor = .clear
            }
            gradient.colors = [
                brightColor.cgColor,
                brightColor.withAlphaComponent(isSelected ? 0.5 : 0.4).cgColor,
                dimColor.cgColor,
                dimColor.cgColor,
                dimColor.cgColor,
                brightColor.withAlphaComponent(isSelected ? 0.5 : 0.4).cgColor,
                brightColor.cgColor,
            ]
        }
        CATransaction.commit()
    }

    private func restoreAnimationIfNeeded() {
        guard let gradient = containerLayer?.sublayers?.first as? CAGradientLayer,
              gradient.animation(forKey: Self.rotationAnimationKey) == nil else { return }
        gradient.add(makeRotationAnimation(), forKey: Self.rotationAnimationKey)
    }

    private func makeRotationAnimation() -> CABasicAnimation {
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0.0
        rotation.toValue = CGFloat.pi * 2
        rotation.duration = 3.0
        rotation.repeatCount = .infinity
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotation.beginTime = Self.sharedAnimationEpoch
        return rotation
    }
}
