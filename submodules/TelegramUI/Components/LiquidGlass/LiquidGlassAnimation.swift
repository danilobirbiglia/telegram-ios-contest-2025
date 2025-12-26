import Foundation
import UIKit

// MARK: - Liquid Glass Animation Protocol

/// Protocol for views that support Liquid Glass animations
public protocol LiquidGlassAnimatable: AnyObject {
    var liquidGlassLayer: CALayer { get }
    var liquidGlassHighlightLayer: CAGradientLayer? { get }
    var liquidGlassBorderLayer: CAShapeLayer? { get }
}

// MARK: - Liquid Glass Animation Controller

/// Centralized controller for Liquid Glass animations
/// Provides consistent iOS 26-style animations across all glass elements
public final class LiquidGlassAnimations {
    
    // MARK: - Singleton
    
    public static let shared = LiquidGlassAnimations()
    
    private init() {}
    
    // MARK: - Animation Configuration
    
    public struct AnimationConfig {
        // Tap animation - iOS 26 style
        public var tapScaleDown: CGFloat = 0.92
        public var tapDuration: TimeInterval = 0.1
        public var tapSpringDamping: CGFloat = 0.8
        
        // Bounce back animation - iOS 26 uses ~20% bounce
        public var bounceDuration: TimeInterval = 0.5
        public var bounceSpringDamping: CGFloat = 0.6  // Lower = more bounce
        public var bounceSpringVelocity: CGFloat = 0.0
        public var bounceOvershoot: CGFloat = 1.08  // Scale overshoots to 108%
        
        // Highlight animation
        public var highlightOpacityPressed: Float = 0.5
        public var highlightOpacityNormal: Float = 1.0
        
        // Stretch animation (for transitions)
        public var stretchDuration: TimeInterval = 0.4
        public var stretchSquishY: CGFloat = 0.94
        
        public static let `default` = AnimationConfig()
        
        /// iOS 26 style button animation
        public static let button = AnimationConfig(
            tapScaleDown: 0.92,
            tapDuration: 0.1,
            tapSpringDamping: 0.8,
            bounceDuration: 0.5,
            bounceSpringDamping: 0.6,
            bounceSpringVelocity: 0.0,
            bounceOvershoot: 1.08,
            highlightOpacityPressed: 0.5,
            highlightOpacityNormal: 1.0,
            stretchDuration: 0.4,
            stretchSquishY: 0.94
        )
        
        /// iOS 26 style tab bar pill animation
        public static let tabBar = AnimationConfig(
            tapScaleDown: 0.94,
            tapDuration: 0.12,
            tapSpringDamping: 0.75,
            bounceDuration: 0.55,
            bounceSpringDamping: 0.55,
            bounceSpringVelocity: 0.0,
            bounceOvershoot: 1.06,
            highlightOpacityPressed: 0.6,
            highlightOpacityNormal: 1.0,
            stretchDuration: 0.45,
            stretchSquishY: 0.92
        )
        
        /// Subtle animation for smaller elements
        public static let subtle = AnimationConfig(
            tapScaleDown: 0.95,
            tapDuration: 0.08,
            tapSpringDamping: 0.85,
            bounceDuration: 0.4,
            bounceSpringDamping: 0.7,
            bounceSpringVelocity: 0.0,
            bounceOvershoot: 1.04,
            highlightOpacityPressed: 0.6,
            highlightOpacityNormal: 1.0,
            stretchDuration: 0.35,
            stretchSquishY: 0.96
        )
    }
    
    // MARK: - Touch Down Animation
    
    /// Animate touch down (press) state
    public func animateTouchDown(
        view: UIView,
        config: AnimationConfig = .default,
        highlightLayer: CAGradientLayer? = nil
    ) {
        UIView.animate(
            withDuration: config.tapDuration,
            delay: 0,
            usingSpringWithDamping: config.tapSpringDamping,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                view.transform = CGAffineTransform(scaleX: config.tapScaleDown, y: config.tapScaleDown)
            }
        )
        
        if let highlightLayer = highlightLayer {
            CATransaction.begin()
            CATransaction.setAnimationDuration(config.tapDuration)
            highlightLayer.opacity = config.highlightOpacityPressed
            CATransaction.commit()
        }
        
        // Haptic feedback
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
    }
    
    /// Animate touch up (release) state with iOS 26 style bounce
    public func animateTouchUp(
        view: UIView,
        config: AnimationConfig = .default,
        highlightLayer: CAGradientLayer? = nil
    ) {
        // iOS 26 style: scale up with overshoot then settle
        // Using keyframe animation for precise control
        UIView.animateKeyframes(
            withDuration: config.bounceDuration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .calculationModeCubic],
            animations: {
                // Phase 1: Quick scale up with overshoot (0% - 40%)
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.4) {
                    view.transform = CGAffineTransform(scaleX: config.bounceOvershoot, y: config.bounceOvershoot)
                }
                // Phase 2: Settle back to normal (40% - 100%)
                UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.6) {
                    view.transform = .identity
                }
            }
        )
        
        if let highlightLayer = highlightLayer {
            CATransaction.begin()
            CATransaction.setAnimationDuration(config.bounceDuration * 0.4)
            highlightLayer.opacity = config.highlightOpacityNormal
            CATransaction.commit()
        }
    }
    
    // MARK: - Tap Bounce Animation
    
    /// Quick tap bounce animation (iOS 26 style: scale down → overshoot → settle)
    public func animateTapBounce(
        layer: CALayer,
        config: AnimationConfig = .default
    ) {
        let animation = CAKeyframeAnimation(keyPath: "transform.scale")
        animation.values = [
            1.0,                        // Start
            config.tapScaleDown,        // Press down
            config.bounceOvershoot,     // Overshoot
            0.98,                       // Slight undershoot
            1.0                         // Settle
        ]
        animation.keyTimes = [0, 0.2, 0.5, 0.75, 1.0]
        animation.duration = config.bounceDuration
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),                              // Down
            CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1),          // Overshoot (spring-like)
            CAMediaTimingFunction(name: .easeInEaseOut),                        // Undershoot
            CAMediaTimingFunction(name: .easeOut)                               // Settle
        ]
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "liquidGlassTapBounce")
    }
    
    // MARK: - Icon Morph Animation
    
    /// Animate icon morphing (e.g., mic -> send button)
    public func animateIconMorph(
        iconView: UIView,
        newImage: UIImage?,
        imageView: UIImageView? = nil,
        completion: (() -> Void)? = nil
    ) {
        // Phase 1: Fade out + scale down
        UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseOut], animations: {
            iconView.alpha = 0
            iconView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        }) { _ in
            // Change icon
            if let imageView = imageView ?? iconView as? UIImageView {
                imageView.image = newImage
            }
            
            iconView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            
            // Phase 2: Fade in + scale up with bounce
            UIView.animate(
                withDuration: 0.3,
                delay: 0,
                usingSpringWithDamping: 0.5,
                initialSpringVelocity: 0.8,
                options: [],
                animations: {
                    iconView.alpha = 1
                    iconView.transform = .identity
                },
                completion: { _ in
                    completion?()
                }
            )
        }
    }
    
    // MARK: - Stretch Transition Animation
    
    /// Animate stretch transition (for pill moving between positions)
    public func animateStretchTransition(
        layer: CALayer,
        from startFrame: CGRect,
        to endFrame: CGRect,
        config: AnimationConfig = .default,
        completion: (() -> Void)? = nil
    ) {
        let distance = abs(endFrame.midX - startFrame.midX)
        let isLongDistance = distance > 100
        
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        
        // Position animation with spring
        let positionAnimation = CASpringAnimation(keyPath: "position")
        positionAnimation.fromValue = CGPoint(x: startFrame.midX, y: startFrame.midY)
        positionAnimation.toValue = CGPoint(x: endFrame.midX, y: endFrame.midY)
        positionAnimation.damping = isLongDistance ? 12 : 15
        positionAnimation.stiffness = isLongDistance ? 180 : 220
        positionAnimation.mass = 1.0
        positionAnimation.initialVelocity = 0
        
        // Width stretch animation
        let widthAnimation = CAKeyframeAnimation(keyPath: "bounds.size.width")
        let maxStretch = startFrame.width + distance * 0.3
        widthAnimation.values = [startFrame.width, maxStretch, endFrame.width * 0.95, endFrame.width]
        widthAnimation.keyTimes = [0, 0.3, 0.7, 1.0]
        widthAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1),
            CAMediaTimingFunction(name: .easeOut)
        ]
        
        // Height squish animation (subtle vertical compression during stretch)
        let heightAnimation = CAKeyframeAnimation(keyPath: "bounds.size.height")
        heightAnimation.values = [
            startFrame.height,
            startFrame.height * config.stretchSquishY,
            endFrame.height * 1.02,
            endFrame.height
        ]
        heightAnimation.keyTimes = [0, 0.3, 0.7, 1.0]
        heightAnimation.timingFunctions = widthAnimation.timingFunctions
        
        // Group all animations
        let group = CAAnimationGroup()
        group.animations = [positionAnimation, widthAnimation, heightAnimation]
        group.duration = config.stretchDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        
        layer.add(group, forKey: "liquidGlassStretch")
        
        // Set final values
        layer.position = CGPoint(x: endFrame.midX, y: endFrame.midY)
        layer.bounds = CGRect(origin: .zero, size: endFrame.size)
        
        CATransaction.commit()
    }
    
    // MARK: - Arc Path Animation (for floating pill effect)
    
    /// Animate along an arc path (for pill floating between distant tabs)
    public func animateAlongArc(
        layer: CALayer,
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        arcHeight: CGFloat = 20,
        duration: TimeInterval = 0.4,
        completion: (() -> Void)? = nil
    ) {
        let path = UIBezierPath()
        path.move(to: startPoint)
        
        // Calculate control point for arc
        let midX = (startPoint.x + endPoint.x) / 2
        let controlPoint = CGPoint(x: midX, y: min(startPoint.y, endPoint.y) - arcHeight)
        
        path.addQuadCurve(to: endPoint, controlPoint: controlPoint)
        
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        
        let pathAnimation = CAKeyframeAnimation(keyPath: "position")
        pathAnimation.path = path.cgPath
        pathAnimation.duration = duration
        pathAnimation.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
        pathAnimation.fillMode = .forwards
        pathAnimation.isRemovedOnCompletion = false
        
        layer.add(pathAnimation, forKey: "liquidGlassArcPath")
        layer.position = endPoint
        
        CATransaction.commit()
    }
    
    // MARK: - Ripple Effect
    
    /// Create a subtle ripple effect on tap
    public func createRippleEffect(
        in layer: CALayer,
        at point: CGPoint,
        color: UIColor = .white,
        maxRadius: CGFloat? = nil
    ) {
        let rippleLayer = CAShapeLayer()
        let radius = maxRadius ?? max(layer.bounds.width, layer.bounds.height)
        
        rippleLayer.frame = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        rippleLayer.path = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 10, height: 10)).cgPath
        rippleLayer.fillColor = color.withAlphaComponent(0.3).cgColor
        
        layer.addSublayer(rippleLayer)
        
        // Scale animation
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        scaleAnimation.fromValue = 1
        scaleAnimation.toValue = radius / 5
        
        // Fade animation
        let fadeAnimation = CABasicAnimation(keyPath: "opacity")
        fadeAnimation.fromValue = 0.3
        fadeAnimation.toValue = 0
        
        let group = CAAnimationGroup()
        group.animations = [scaleAnimation, fadeAnimation]
        group.duration = 0.4
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            rippleLayer.removeFromSuperlayer()
        }
        rippleLayer.add(group, forKey: "ripple")
        CATransaction.commit()
    }
    
    // MARK: - Glow Pulse Effect
    
    /// Add a subtle glow pulse (for recording state, etc.)
    public func startGlowPulse(
        layer: CALayer,
        color: UIColor = .red,
        intensity: CGFloat = 0.8
    ) -> CALayer {
        let glowLayer = CALayer()
        glowLayer.frame = layer.bounds.insetBy(dx: -4, dy: -4)
        glowLayer.backgroundColor = UIColor.clear.cgColor
        glowLayer.cornerRadius = glowLayer.bounds.height / 2
        glowLayer.shadowColor = color.cgColor
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = 8
        glowLayer.shadowOpacity = Float(intensity)
        
        layer.insertSublayer(glowLayer, at: 0)
        
        let pulseAnimation = CABasicAnimation(keyPath: "shadowOpacity")
        pulseAnimation.fromValue = intensity
        pulseAnimation.toValue = intensity * 0.3
        pulseAnimation.duration = 0.8
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        glowLayer.add(pulseAnimation, forKey: "glowPulse")
        
        return glowLayer
    }
    
    /// Stop glow pulse effect
    public func stopGlowPulse(glowLayer: CALayer, animated: Bool = true) {
        if animated {
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                glowLayer.removeFromSuperlayer()
            }
            let fadeAnimation = CABasicAnimation(keyPath: "opacity")
            fadeAnimation.fromValue = glowLayer.opacity
            fadeAnimation.toValue = 0
            fadeAnimation.duration = 0.2
            fadeAnimation.fillMode = .forwards
            fadeAnimation.isRemovedOnCompletion = false
            glowLayer.add(fadeAnimation, forKey: "fadeOut")
            CATransaction.commit()
        } else {
            glowLayer.removeFromSuperlayer()
        }
    }
}

// MARK: - UIView Extension for Easy Access

public extension UIView {
    
    /// Animate touch down with Liquid Glass effect (iOS 26 style)
    func liquidGlassTouchDown(
        config: LiquidGlassAnimations.AnimationConfig = .button,
        highlightLayer: CAGradientLayer? = nil
    ) {
        LiquidGlassAnimations.shared.animateTouchDown(
            view: self,
            config: config,
            highlightLayer: highlightLayer
        )
    }
    
    /// Animate touch up with Liquid Glass bounce (iOS 26 style with overshoot)
    func liquidGlassTouchUp(
        config: LiquidGlassAnimations.AnimationConfig = .button,
        highlightLayer: CAGradientLayer? = nil
    ) {
        LiquidGlassAnimations.shared.animateTouchUp(
            view: self,
            config: config,
            highlightLayer: highlightLayer
        )
    }
    
    /// Add tap bounce animation (iOS 26 style)
    func liquidGlassTapBounce(config: LiquidGlassAnimations.AnimationConfig = .button) {
        LiquidGlassAnimations.shared.animateTapBounce(layer: self.layer, config: config)
    }
    
    /// Perform a complete tap animation (down + up with bounce)
    func liquidGlassPerformTap(
        config: LiquidGlassAnimations.AnimationConfig = .button,
        highlightLayer: CAGradientLayer? = nil,
        completion: (() -> Void)? = nil
    ) {
        // Touch down
        LiquidGlassAnimations.shared.animateTouchDown(
            view: self,
            config: config,
            highlightLayer: highlightLayer
        )
        
        // Touch up after brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + config.tapDuration) {
            LiquidGlassAnimations.shared.animateTouchUp(
                view: self,
                config: config,
                highlightLayer: highlightLayer
            )
            
            DispatchQueue.main.asyncAfter(deadline: .now() + config.bounceDuration) {
                completion?()
            }
        }
    }
}

// MARK: - CALayer Extension

public extension CALayer {
    
    /// Animate stretch transition
    func liquidGlassStretch(
        from startFrame: CGRect,
        to endFrame: CGRect,
        config: LiquidGlassAnimations.AnimationConfig = .tabBar,
        completion: (() -> Void)? = nil
    ) {
        LiquidGlassAnimations.shared.animateStretchTransition(
            layer: self,
            from: startFrame,
            to: endFrame,
            config: config,
            completion: completion
        )
    }
    
    /// Animate along arc path
    func liquidGlassArc(
        from startPoint: CGPoint,
        to endPoint: CGPoint,
        arcHeight: CGFloat = 20,
        duration: TimeInterval = 0.4,
        completion: (() -> Void)? = nil
    ) {
        LiquidGlassAnimations.shared.animateAlongArc(
            layer: self,
            from: startPoint,
            to: endPoint,
            arcHeight: arcHeight,
            duration: duration,
            completion: completion
        )
    }
}
