import Foundation
import UIKit
import Display
import AsyncDisplayKit
import ComponentFlow
import TelegramPresentationData

public final class SwitchComponent: Component {
    public typealias EnvironmentType = Empty
    
    let tintColor: UIColor?
    let value: Bool
    let valueUpdated: (Bool) -> Void
    
    public init(
        tintColor: UIColor? = nil,
        value: Bool,
        valueUpdated: @escaping (Bool) -> Void
    ) {
        self.tintColor = tintColor
        self.value = value
        self.valueUpdated = valueUpdated
    }
    
    public static func ==(lhs: SwitchComponent, rhs: SwitchComponent) -> Bool {
        if lhs.tintColor != rhs.tintColor {
            return false
        }
        if lhs.value != rhs.value {
            return false
        }
        return true
    }
    
    private final class LiquidGlassSwitchView: UIControl {
        
        private let switchWidth: CGFloat = 51.0
        private let switchHeight: CGFloat = 31.0
        private let knobPadding: CGFloat = 2.0
        private var knobSize: CGFloat { switchHeight - (knobPadding * 2) }
        
        private var _isOn: Bool = false
        var isOn: Bool {
            get { return _isOn }
            set {
                guard _isOn != newValue else { return }
                _isOn = newValue
                animateStateChange()
            }
        }
        
        var onTintColor: UIColor = UIColor(red: 52/255, green: 199/255, blue: 89/255, alpha: 1.0) {
            didSet { updateTrackColor(animated: false) }
        }
        
        private let trackContainerView = UIView()
        private let blurEffectView: UIVisualEffectView
        private let trackColorView = UIView()
        private let glassHighlightLayer = CAGradientLayer()
        private let trackBorderLayer = CAShapeLayer()
        private let knobContainerView = UIView()
        private let knobShadowLayer = CALayer()
        private let knobBaseLayer = CALayer()
        private let knobHighlightLayer = CAGradientLayer()
        private let knobBorderLayer = CAShapeLayer()
        
        private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        
        override init(frame: CGRect) {
            let blurEffect = UIBlurEffect(style: .systemThinMaterial)
            self.blurEffectView = UIVisualEffectView(effect: blurEffect)
            
            super.init(frame: CGRect(x: 0, y: 0, width: switchWidth, height: switchHeight))
            setupUI()
        }
        
        required init?(coder: NSCoder) {
            let blurEffect = UIBlurEffect(style: .systemThinMaterial)
            self.blurEffectView = UIVisualEffectView(effect: blurEffect)
            super.init(coder: coder)
            setupUI()
        }
        
        private func setupUI() {
            backgroundColor = .clear
            
            let cornerRadius = switchHeight / 2
            
            trackContainerView.frame = bounds
            trackContainerView.layer.cornerRadius = cornerRadius
            trackContainerView.clipsToBounds = true
            addSubview(trackContainerView)
            
            blurEffectView.frame = trackContainerView.bounds
            blurEffectView.layer.cornerRadius = cornerRadius
            blurEffectView.clipsToBounds = true
            blurEffectView.alpha = 0.7
            trackContainerView.addSubview(blurEffectView)
            
            trackColorView.frame = trackContainerView.bounds
            trackColorView.backgroundColor = UIColor(white: 0.5, alpha: 0.3)
            trackContainerView.addSubview(trackColorView)
            
            glassHighlightLayer.frame = CGRect(x: 0, y: 0, width: switchWidth, height: switchHeight * 0.45)
            glassHighlightLayer.colors = [
                UIColor.white.withAlphaComponent(0.35).cgColor,
                UIColor.white.withAlphaComponent(0.0).cgColor
            ]
            glassHighlightLayer.startPoint = CGPoint(x: 0.5, y: 0)
            glassHighlightLayer.endPoint = CGPoint(x: 0.5, y: 1)
            trackContainerView.layer.addSublayer(glassHighlightLayer)
            
            trackBorderLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerRadius: cornerRadius).cgPath
            trackBorderLayer.fillColor = nil
            trackBorderLayer.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
            trackBorderLayer.lineWidth = 0.5
            trackContainerView.layer.addSublayer(trackBorderLayer)
            
            let knobFrame = CGRect(x: knobPadding, y: knobPadding, width: knobSize, height: knobSize)
            let knobCornerRadius = knobSize / 2
            
            knobContainerView.frame = knobFrame
            addSubview(knobContainerView)
            
            knobShadowLayer.frame = CGRect(origin: .zero, size: knobFrame.size)
            knobShadowLayer.backgroundColor = UIColor.white.cgColor
            knobShadowLayer.cornerRadius = knobCornerRadius
            knobShadowLayer.shadowColor = UIColor.black.cgColor
            knobShadowLayer.shadowOffset = CGSize(width: 0, height: 3)
            knobShadowLayer.shadowRadius = 6
            knobShadowLayer.shadowOpacity = 0.25
            knobContainerView.layer.addSublayer(knobShadowLayer)
            
            knobBaseLayer.frame = CGRect(origin: .zero, size: knobFrame.size)
            knobBaseLayer.backgroundColor = UIColor.white.cgColor
            knobBaseLayer.cornerRadius = knobCornerRadius
            knobBaseLayer.masksToBounds = true
            knobContainerView.layer.addSublayer(knobBaseLayer)
            
            knobHighlightLayer.frame = CGRect(x: 0, y: 0, width: knobSize, height: knobSize * 0.5)
            knobHighlightLayer.colors = [
                UIColor.white.withAlphaComponent(0.9).cgColor,
                UIColor.white.withAlphaComponent(0.3).cgColor
            ]
            knobHighlightLayer.startPoint = CGPoint(x: 0.5, y: 0)
            knobHighlightLayer.endPoint = CGPoint(x: 0.5, y: 1)
            knobHighlightLayer.cornerRadius = knobCornerRadius
            knobBaseLayer.addSublayer(knobHighlightLayer)
            
            knobBorderLayer.path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: knobFrame.size).insetBy(dx: 0.25, dy: 0.25)).cgPath
            knobBorderLayer.fillColor = nil
            knobBorderLayer.strokeColor = UIColor.black.withAlphaComponent(0.08).cgColor
            knobBorderLayer.lineWidth = 0.5
            knobContainerView.layer.addSublayer(knobBorderLayer)
            
            let tapGesture = UITapGestureRecognizer(target: self, action: #selector(tapped))
            addGestureRecognizer(tapGesture)
            
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            addGestureRecognizer(panGesture)
            
            feedbackGenerator.prepare()
        }
        
        override var intrinsicContentSize: CGSize {
            return CGSize(width: switchWidth, height: switchHeight)
        }
        
        override func sizeThatFits(_ size: CGSize) -> CGSize {
            return CGSize(width: switchWidth, height: switchHeight)
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            
            let cornerRadius = switchHeight / 2
            trackContainerView.frame = bounds
            blurEffectView.frame = trackContainerView.bounds
            trackColorView.frame = trackContainerView.bounds
            glassHighlightLayer.frame = CGRect(x: 0, y: 0, width: switchWidth, height: switchHeight * 0.45)
            trackBorderLayer.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerRadius: cornerRadius).cgPath
        }
        
        private func updateTrackColor(animated: Bool) {
            let targetColor = isOn ? onTintColor.withAlphaComponent(0.85) : UIColor(white: 0.5, alpha: 0.3)
            let blurAlpha: CGFloat = isOn ? 0.4 : 0.7
            
            if animated {
                UIView.animate(withDuration: 0.25) {
                    self.trackColorView.backgroundColor = targetColor
                    self.blurEffectView.alpha = blurAlpha
                }
            } else {
                trackColorView.backgroundColor = targetColor
                blurEffectView.alpha = blurAlpha
            }
        }
        
        private func animateStateChange() {
            let targetX = isOn ? (switchWidth - knobSize - knobPadding) : knobPadding
            
            feedbackGenerator.impactOccurred()
            
            updateTrackColor(animated: true)
            
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.65,
                initialSpringVelocity: 0.3,
                options: [.allowUserInteraction],
                animations: {
                    self.knobContainerView.frame.origin.x = targetX
                },
                completion: nil
            )
        }
        
        func setOn(_ on: Bool, animated: Bool) {
            guard _isOn != on else { return }
            _isOn = on
            
            let targetX = isOn ? (switchWidth - knobSize - knobPadding) : knobPadding
            
            if animated {
                animateStateChange()
            } else {
                knobContainerView.frame.origin.x = targetX
                updateTrackColor(animated: false)
            }
        }
        
        @objc private func tapped() {
            UIView.animate(withDuration: 0.1, animations: {
                self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
            }) { _ in
                UIView.animate(
                    withDuration: 0.35,
                    delay: 0,
                    usingSpringWithDamping: 0.5,
                    initialSpringVelocity: 0.8,
                    options: [.allowUserInteraction],
                    animations: {
                        self.transform = .identity
                    },
                    completion: nil
                )
            }
            
            _isOn.toggle()
            animateStateChange()
            sendActions(for: .valueChanged)
        }
        
        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: self)
            let minX = knobPadding
            let maxX = switchWidth - knobSize - knobPadding
            
            switch gesture.state {
            case .began:
                feedbackGenerator.impactOccurred()
                UIView.animate(withDuration: 0.15) {
                    self.knobContainerView.transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
                }
                
            case .changed:
                var newX = knobContainerView.frame.origin.x + translation.x
                newX = max(minX, min(maxX, newX))
                knobContainerView.frame.origin.x = newX
                
                let progress = (newX - minX) / (maxX - minX)
                let offColor = UIColor(white: 0.5, alpha: 0.3)
                trackColorView.backgroundColor = interpolateColor(from: offColor, to: onTintColor.withAlphaComponent(0.85), progress: progress)
                blurEffectView.alpha = 0.7 - (progress * 0.3)
                
                gesture.setTranslation(.zero, in: self)
                
            case .ended, .cancelled:
                UIView.animate(
                    withDuration: 0.25,
                    delay: 0,
                    usingSpringWithDamping: 0.6,
                    initialSpringVelocity: 0.5,
                    options: [],
                    animations: {
                        self.knobContainerView.transform = .identity
                    },
                    completion: nil
                )
                
                let midX = (minX + maxX) / 2
                let newState = knobContainerView.frame.origin.x > midX
                
                if newState != _isOn {
                    _isOn = newState
                    animateStateChange()
                    sendActions(for: .valueChanged)
                } else {
                    let targetX = _isOn ? maxX : minX
                    UIView.animate(
                        withDuration: 0.25,
                        delay: 0,
                        usingSpringWithDamping: 0.7,
                        initialSpringVelocity: 0.5,
                        options: [],
                        animations: {
                            self.knobContainerView.frame.origin.x = targetX
                            self.updateTrackColor(animated: false)
                        },
                        completion: nil
                    )
                }
                
            default:
                break
            }
        }
        
        private func interpolateColor(from: UIColor, to: UIColor, progress: CGFloat) -> UIColor {
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            from.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            to.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            return UIColor(
                red: r1 + (r2 - r1) * progress,
                green: g1 + (g2 - g1) * progress,
                blue: b1 + (b2 - b1) * progress,
                alpha: a1 + (a2 - a1) * progress
            )
        }
    }
    
    public final class View: UIView {
        private var nativeSwitch: UISwitch?
        private var liquidGlassSwitch: LiquidGlassSwitchView?
        
        private var component: SwitchComponent?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            
            if #available(iOS 26.0, *) {
                let switchView = UISwitch()
                switchView.addTarget(self, action: #selector(nativeValueChanged(_:)), for: .valueChanged)
                addSubview(switchView)
                nativeSwitch = switchView
            } else {
                let switchView = LiquidGlassSwitchView()
                switchView.addTarget(self, action: #selector(liquidGlassValueChanged(_:)), for: .valueChanged)
                addSubview(switchView)
                liquidGlassSwitch = switchView
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc private func nativeValueChanged(_ sender: UISwitch) {
            component?.valueUpdated(sender.isOn)
        }
        
        @objc private func liquidGlassValueChanged(_ sender: LiquidGlassSwitchView) {
            component?.valueUpdated(sender.isOn)
        }
        
        func update(component: SwitchComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
            self.component = component
            
            if #available(iOS 26.0, *) {
                if let switchView = nativeSwitch {
                    if let tintColor = component.tintColor {
                        switchView.onTintColor = tintColor
                    }
                    switchView.setOn(component.value, animated: !transition.animation.isImmediate)
                    switchView.sizeToFit()
                    switchView.frame = CGRect(origin: .zero, size: switchView.frame.size)
                    return switchView.frame.size
                }
            } else {
                if let switchView = liquidGlassSwitch {
                    if let tintColor = component.tintColor {
                        switchView.onTintColor = tintColor
                    }
                    switchView.setOn(component.value, animated: !transition.animation.isImmediate)
                    let size = switchView.sizeThatFits(availableSize)
                    switchView.frame = CGRect(origin: .zero, size: size)
                    return size
                }
            }
            
            return CGSize(width: 51, height: 31)
        }
    }
    
    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<EnvironmentType>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
