import Foundation
import UIKit
import AsyncDisplayKit


private final class SwitchNodeViewLayer: CALayer {
    override func setNeedsDisplay() {
    }
}

private final class LiquidGlassSwitchView: UIControl {
    
    private let switchWidth: CGFloat = 61.0
    private let switchHeight: CGFloat = 31.0
    private let knobPadding: CGFloat = 2.0
    private var knobDiameter: CGFloat { switchHeight - (knobPadding * 2) }
    private let liquidOverflow: CGFloat = 10.0
    
    private var _isOn: Bool = false
    var isOn: Bool {
        get { return _isOn }
        set {
            guard _isOn != newValue else { return }
            _isOn = newValue
            animateStateChange()
        }
    }
    
    var onTintColor: UIColor = UIColor(rgb: 0x34c759) {
        didSet { updateColors(animated: false) }
    }
    
    var offTintColor: UIColor = UIColor(white: 0.90, alpha: 1.0) {
        didSet { updateColors(animated: false) }
    }
    
    var knobColor: UIColor = .white {
        didSet {
            knobView.backgroundColor = knobColor
        }
    }
    
    private let trackView = UIView()
    private let trackBorder = UIView()
    private let knobView = UIView()
    private let knobHighlight = CAGradientLayer()
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
    private var isAnimating = false
    
    override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: switchWidth, height: switchHeight)))
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        backgroundColor = .clear
        clipsToBounds = false
        
        trackView.frame = bounds
        trackView.backgroundColor = offTintColor
        trackView.layer.cornerRadius = switchHeight / 2
        trackView.clipsToBounds = false
        trackView.isUserInteractionEnabled = false
        addSubview(trackView)
        
        let borderInset: CGFloat = 1.5
        trackBorder.frame = CGRect(x: borderInset, y: borderInset,
                                   width: switchWidth - borderInset * 2,
                                   height: switchHeight - borderInset * 2)
        trackBorder.backgroundColor = .clear
        trackBorder.layer.cornerRadius = (switchHeight - borderInset * 2) / 2
        trackBorder.layer.borderWidth = 1.5
        trackBorder.layer.borderColor = UIColor.clear.cgColor
        trackBorder.isUserInteractionEnabled = false
        addSubview(trackBorder)
        
        knobView.frame = CGRect(x: knobPadding, y: knobPadding, width: knobDiameter, height: knobDiameter)
        knobView.backgroundColor = knobColor
        knobView.layer.cornerRadius = knobDiameter / 2
        knobView.isUserInteractionEnabled = false
        
        knobView.layer.shadowColor = UIColor.black.cgColor
        knobView.layer.shadowOffset = CGSize(width: 0, height: 2)
        knobView.layer.shadowRadius = 2.5
        knobView.layer.shadowOpacity = 0.15
        
        addSubview(knobView)
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(panGesture)
        
        feedbackGenerator.prepare()
    }
    
    override var intrinsicContentSize: CGSize {
        return CGSize(width: switchWidth, height: switchHeight)
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        return CGSize(width: switchWidth, height: switchHeight)
    }
    
    private func updateColors(animated: Bool) {
        let duration = animated ? 0.25 : 0.0
        UIView.animate(withDuration: duration) {
            self.trackView.backgroundColor = self.isOn ? self.onTintColor : self.offTintColor
            self.trackBorder.layer.borderColor = self.isOn ? self.onTintColor.cgColor : UIColor.clear.cgColor
        }
    }
    
    private func animateStateChange() {
        guard !isAnimating else { return }
        isAnimating = true
        
        feedbackGenerator.impactOccurred()
        
        let offX = knobPadding
        let onX = switchWidth - knobDiameter - knobPadding
        let startX = knobView.frame.origin.x
        let targetX = isOn ? onX : offX
        
        let stretchedWidth = knobDiameter + liquidOverflow
        
        updateColors(animated: true)
        
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut], animations: {
            var frame = self.knobView.frame
            frame.size.width = stretchedWidth
            
            if self.isOn {
                frame.origin.x = startX
            } else {
                frame.origin.x = startX - self.liquidOverflow
            }
            
            self.knobView.frame = frame
            self.knobView.layer.cornerRadius = self.knobDiameter / 2
        }) { _ in
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveLinear], animations: {
                var frame = self.knobView.frame
                if self.isOn {
                    frame.origin.x = targetX - self.liquidOverflow + self.knobPadding
                } else {
                    frame.origin.x = targetX - self.liquidOverflow / 2
                }
                self.knobView.frame = frame
            }) { _ in
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0.8, options: [], animations: {
                    self.knobView.frame = CGRect(x: targetX, y: self.knobPadding, width: self.knobDiameter, height: self.knobDiameter)
                    self.knobView.layer.cornerRadius = self.knobDiameter / 2
                }) { _ in
                    self.isAnimating = false
                }
            }
        }
    }
    
    func setOn(_ on: Bool, animated: Bool) {
        guard _isOn != on else { return }
        _isOn = on
        
        if animated {
            animateStateChange()
        } else {
            let targetX = isOn ? (switchWidth - knobDiameter - knobPadding) : knobPadding
            knobView.frame = CGRect(x: targetX, y: knobPadding, width: knobDiameter, height: knobDiameter)
            knobView.layer.cornerRadius = knobDiameter / 2
            updateColors(animated: false)
        }
    }
    
    @objc private func handleTap() {
        isOn = !isOn
        sendActions(for: .valueChanged)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        if gesture.state == .ended {
            handleTap()
        }
    }
}

open class SwitchNode: ASDisplayNode {
    public var valueUpdated: ((Bool) -> Void)?
    
    public var frameColor = UIColor(rgb: 0xe0e0e0) {
        didSet {
            if self.isNodeLoaded {
                if #available(iOS 26.0, *) {
                    (self.view as? UISwitch)?.tintColor = self.frameColor
                } else {
                    (self.view as? LiquidGlassSwitchView)?.offTintColor = self.frameColor
                }
            }
        }
    }
    
    public var handleColor = UIColor(rgb: 0xffffff) {
        didSet {
            if self.isNodeLoaded {
                if #available(iOS 26.0, *) {
                    (self.view as? UISwitch)?.thumbTintColor = self.handleColor
                } else {
                    (self.view as? LiquidGlassSwitchView)?.knobColor = self.handleColor
                }
            }
        }
    }
    
    public var contentColor = UIColor(rgb: 0x42d451) {
        didSet {
            if self.isNodeLoaded {
                if #available(iOS 26.0, *) {
                    (self.view as? UISwitch)?.onTintColor = self.contentColor
                } else {
                    (self.view as? LiquidGlassSwitchView)?.onTintColor = self.contentColor
                }
            }
        }
    }
    
    private var _isOn: Bool = false
    public var isOn: Bool {
        get { return self._isOn }
        set {
            if newValue != self._isOn {
                self._isOn = newValue
                if self.isNodeLoaded {
                    if #available(iOS 26.0, *) {
                        (self.view as? UISwitch)?.setOn(newValue, animated: false)
                    } else {
                        (self.view as? LiquidGlassSwitchView)?.setOn(newValue, animated: false)
                    }
                }
            }
        }
    }
    
    override public init() {
        super.init()
        self.setViewBlock {
            if #available(iOS 26.0, *) {
                return UISwitch()
            } else {
                return LiquidGlassSwitchView()
            }
        }
    }
    
    override open func didLoad() {
        super.didLoad()
        self.view.isAccessibilityElement = false
        
        if #available(iOS 26.0, *) {
            let switchView = self.view as! UISwitch
            switchView.tintColor = self.frameColor
            switchView.onTintColor = self.contentColor
            switchView.thumbTintColor = self.handleColor
            switchView.setOn(self._isOn, animated: false)
            switchView.addTarget(self, action: #selector(switchValueChanged(_:)), for: .valueChanged)
        } else {
            let switchView = self.view as! LiquidGlassSwitchView
            switchView.offTintColor = self.frameColor
            switchView.onTintColor = self.contentColor
            switchView.knobColor = self.handleColor
            switchView.setOn(self._isOn, animated: false)
            switchView.addTarget(self, action: #selector(customSwitchValueChanged(_:)), for: .valueChanged)
        }
    }
    
    public func setOn(_ value: Bool, animated: Bool) {
        self._isOn = value
        if self.isNodeLoaded {
            if #available(iOS 26.0, *) {
                (self.view as? UISwitch)?.setOn(value, animated: animated)
            } else {
                (self.view as? LiquidGlassSwitchView)?.setOn(value, animated: animated)
            }
        }
    }
    
    override open func calculateSizeThatFits(_ constrainedSize: CGSize) -> CGSize {
        return CGSize(width: 51.0, height: 31.0)
    }
    
    @objc private func switchValueChanged(_ sender: UISwitch) {
        self._isOn = sender.isOn
        self.valueUpdated?(sender.isOn)
    }
    
    @objc private func customSwitchValueChanged(_ sender: AnyObject) {
        if let switchView = sender as? LiquidGlassSwitchView {
            self._isOn = switchView.isOn
            self.valueUpdated?(switchView.isOn)
        }
    }
}
