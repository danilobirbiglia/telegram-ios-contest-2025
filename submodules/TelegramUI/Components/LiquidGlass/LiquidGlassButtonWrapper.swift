import Foundation
import UIKit
import AsyncDisplayKit
import Display

// MARK: - Liquid Glass Button Wrapper

/// A wrapper that adds Liquid Glass effects to any button
/// Can be used to enhance existing Telegram buttons without modifying their core implementation
public final class LiquidGlassButtonWrapper: UIView {
    
    // MARK: - Properties
    
    /// The wrapped content view (button)
    public let contentView: UIView
    
    /// Glass background layers
    private let blurView: UIVisualEffectView
    private let highlightLayer: CAGradientLayer
    private let borderLayer: CAShapeLayer
    private var glowLayer: CALayer?
    
    /// Configuration
    public var cornerRadius: CGFloat = 20 {
        didSet { updateCornerRadius() }
    }
    
    public var isCircular: Bool = true {
        didSet { updateCornerRadius() }
    }
    
    public var animationConfig: LiquidGlassAnimations.AnimationConfig = .button
    
    /// State
    private var isPressed: Bool = false
    private var isRecording: Bool = false
    
    // MARK: - Initialization
    
    public init(contentView: UIView, isCircular: Bool = true) {
        self.contentView = contentView
        self.isCircular = isCircular
        
        // Create blur effect
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        self.blurView = UIVisualEffectView(effect: blurEffect)
        
        // Create highlight gradient (top shine)
        self.highlightLayer = CAGradientLayer()
        self.highlightLayer.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        self.highlightLayer.locations = [0.0, 0.3, 1.0]
        self.highlightLayer.startPoint = CGPoint(x: 0.5, y: 0)
        self.highlightLayer.endPoint = CGPoint(x: 0.5, y: 1)
        
        // Create border
        self.borderLayer = CAShapeLayer()
        self.borderLayer.fillColor = nil
        self.borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        self.borderLayer.lineWidth = 0.5
        
        super.init(frame: .zero)
        
        setupViews()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Setup
    
    private func setupViews() {
        // Add blur background
        addSubview(blurView)
        blurView.layer.addSublayer(highlightLayer)
        blurView.layer.addSublayer(borderLayer)
        
        // Add content on top
        addSubview(contentView)
        
        // Initial setup
        clipsToBounds = false
    }
    
    private func setupGestures() {
        // Add touch handling
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0
        longPressGesture.cancelsTouchesInView = false
        addGestureRecognizer(longPressGesture)
    }
    
    // MARK: - Layout
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        let radius = isCircular ? bounds.height / 2 : cornerRadius
        
        // Layout blur view
        blurView.frame = bounds
        blurView.layer.cornerRadius = radius
        blurView.clipsToBounds = true
        
        // Layout highlight
        highlightLayer.frame = bounds
        let highlightMask = CAShapeLayer()
        highlightMask.path = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
        highlightLayer.mask = highlightMask
        
        // Layout border
        borderLayer.frame = bounds
        borderLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
            cornerRadius: radius
        ).cgPath
        
        // Layout content
        contentView.frame = bounds
    }
    
    private func updateCornerRadius() {
        setNeedsLayout()
    }
    
    // MARK: - Touch Handling
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard !isPressed else { return }
            isPressed = true
            animateTouchDown()
            
        case .ended, .cancelled:
            guard isPressed else { return }
            isPressed = false
            animateTouchUp()
            
        default:
            break
        }
    }
    
    // MARK: - Animations
    
    private func animateTouchDown() {
        LiquidGlassAnimations.shared.animateTouchDown(
            view: self,
            config: animationConfig,
            highlightLayer: highlightLayer
        )
    }
    
    private func animateTouchUp() {
        LiquidGlassAnimations.shared.animateTouchUp(
            view: self,
            config: animationConfig,
            highlightLayer: highlightLayer
        )
    }
    
    /// Trigger a tap bounce animation
    public func animateTapBounce() {
        LiquidGlassAnimations.shared.animateTapBounce(layer: layer, config: animationConfig)
    }
    
    /// Start recording state (adds glow pulse)
    public func startRecordingState(color: UIColor = .red) {
        guard !isRecording else { return }
        isRecording = true
        glowLayer = LiquidGlassAnimations.shared.startGlowPulse(layer: layer, color: color)
    }
    
    /// Stop recording state
    public func stopRecordingState(animated: Bool = true) {
        guard isRecording, let glowLayer = glowLayer else { return }
        isRecording = false
        LiquidGlassAnimations.shared.stopGlowPulse(glowLayer: glowLayer, animated: animated)
        self.glowLayer = nil
    }
}

// MARK: - ASDisplayNode Extension for Liquid Glass

/// Extension to easily add Liquid Glass effects to ASDisplayNode-based buttons
public extension ASDisplayNode {
    
    /// Wrap this node's view in a Liquid Glass button wrapper
    func wrapInLiquidGlass(isCircular: Bool = true) -> LiquidGlassButtonWrapper {
        return LiquidGlassButtonWrapper(contentView: self.view, isCircular: isCircular)
    }
    
    /// Add Liquid Glass touch animations to this node
    func addLiquidGlassAnimations(
        config: LiquidGlassAnimations.AnimationConfig = .button,
        highlightLayer: CAGradientLayer? = nil
    ) {
        // Create highlight layer if not provided
        let highlight = highlightLayer ?? createHighlightLayer()
        
        // Store reference
        objc_setAssociatedObject(self, &AssociatedKeys.highlightLayer, highlight, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        // Add highlight to layer
        if highlightLayer == nil {
            self.layer.addSublayer(highlight)
        }
        
        // Add touch tracking
        let gestureRecognizer = LiquidGlassTouchRecognizer(target: self, action: nil)
        gestureRecognizer.liquidGlassConfig = config
        gestureRecognizer.highlightLayer = highlight
        gestureRecognizer.targetNode = self
        self.view.addGestureRecognizer(gestureRecognizer)
    }
    
    private func createHighlightLayer() -> CAGradientLayer {
        let highlight = CAGradientLayer()
        highlight.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        highlight.locations = [0.0, 0.3, 1.0]
        highlight.startPoint = CGPoint(x: 0.5, y: 0)
        highlight.endPoint = CGPoint(x: 0.5, y: 1)
        highlight.frame = self.bounds
        return highlight
    }
}

// MARK: - Associated Keys

private enum AssociatedKeys {
    static var highlightLayer: UInt8 = 0
}

// MARK: - Liquid Glass Touch Recognizer

private class LiquidGlassTouchRecognizer: UIGestureRecognizer {
    
    var liquidGlassConfig: LiquidGlassAnimations.AnimationConfig = .button
    weak var highlightLayer: CAGradientLayer?
    weak var targetNode: ASDisplayNode?
    
    private var isPressed = false
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        guard !isPressed, let targetNode = targetNode else { return }
        isPressed = true
        
        LiquidGlassAnimations.shared.animateTouchDown(
            view: targetNode.view,
            config: liquidGlassConfig,
            highlightLayer: highlightLayer
        )
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        
        guard isPressed, let targetNode = targetNode else { return }
        isPressed = false
        
        LiquidGlassAnimations.shared.animateTouchUp(
            view: targetNode.view,
            config: liquidGlassConfig,
            highlightLayer: highlightLayer
        )
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        
        guard isPressed, let targetNode = targetNode else { return }
        isPressed = false
        
        LiquidGlassAnimations.shared.animateTouchUp(
            view: targetNode.view,
            config: liquidGlassConfig,
            highlightLayer: highlightLayer
        )
    }
}

// MARK: - HighlightTrackingButtonNode Extension

/// Extension specifically for Telegram's HighlightTrackingButtonNode
public extension HighlightTrackingButtonNode {
    
    /// Enable Liquid Glass animations on this button
    func enableLiquidGlassAnimations(config: LiquidGlassAnimations.AnimationConfig = .button) {
        // Store the original callback if it exists
        let originalCallback: ((Bool) -> Void)? = self.highligthedChanged
        
        self.highligthedChanged = { [weak self] highlighted in
            guard let self = self else { return }
            
            if highlighted {
                // Use Liquid Glass touch down animation
                self.view.liquidGlassTouchDown(config: config)
            } else {
                // Use Liquid Glass touch up animation
                self.view.liquidGlassTouchUp(config: config)
            }
            
            // Also call original callback if present
            originalCallback?(highlighted)
        }
    }
}

// MARK: - GlassBackgroundView Extension (if it exists in the codebase)

/// This extension adds Liquid Glass animations to the existing GlassBackgroundView
/// You may need to adjust based on the actual GlassBackgroundView implementation
/*
public extension GlassBackgroundView {
    
    /// Enable Liquid Glass touch animations
    func enableLiquidGlassAnimations(config: LiquidGlassAnimations.AnimationConfig = .button) {
        // Add touch gesture
        let gesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLiquidGlassTouch(_:)))
        gesture.minimumPressDuration = 0
        gesture.cancelsTouchesInView = false
        self.addGestureRecognizer(gesture)
        
        // Store config
        objc_setAssociatedObject(self, &LiquidGlassAssociatedKeys.config, config, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    @objc private func handleLiquidGlassTouch(_ gesture: UILongPressGestureRecognizer) {
        let config = objc_getAssociatedObject(self, &LiquidGlassAssociatedKeys.config) as? LiquidGlassAnimations.AnimationConfig ?? .button
        
        switch gesture.state {
        case .began:
            self.liquidGlassTouchDown(config: config)
        case .ended, .cancelled:
            self.liquidGlassTouchUp(config: config)
        default:
            break
        }
    }
}

private struct LiquidGlassAssociatedKeys {
    static var config = "liquidGlassConfig"
}
*/
