import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import LegacyComponents
import ComponentFlow

public final class SliderComponent: Component {
    public final class Discrete: Equatable {
        public let valueCount: Int
        public let value: Int
        public let minValue: Int?
        public let markPositions: Bool
        public let valueUpdated: (Int) -> Void
        
        public init(valueCount: Int, value: Int, minValue: Int? = nil, markPositions: Bool, valueUpdated: @escaping (Int) -> Void) {
            self.valueCount = valueCount
            self.value = value
            self.minValue = minValue
            self.markPositions = markPositions
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Discrete, rhs: Discrete) -> Bool {
            if lhs.valueCount != rhs.valueCount { return false }
            if lhs.value != rhs.value { return false }
            if lhs.minValue != rhs.minValue { return false }
            if lhs.markPositions != rhs.markPositions { return false }
            return true
        }
    }
    
    public final class Continuous: Equatable {
        public let value: CGFloat
        public let minValue: CGFloat?
        public let valueUpdated: (CGFloat) -> Void
        
        public init(value: CGFloat, minValue: CGFloat? = nil, valueUpdated: @escaping (CGFloat) -> Void) {
            self.value = value
            self.minValue = minValue
            self.valueUpdated = valueUpdated
        }
        
        public static func ==(lhs: Continuous, rhs: Continuous) -> Bool {
            if lhs.value != rhs.value { return false }
            if lhs.minValue != rhs.minValue { return false }
            return true
        }
    }
    
    public enum Content: Equatable {
        case discrete(Discrete)
        case continuous(Continuous)
    }
    
    public let content: Content
    public let useNative: Bool
    public let trackBackgroundColor: UIColor
    public let trackForegroundColor: UIColor
    public let minTrackForegroundColor: UIColor?
    public let knobSize: CGFloat?
    public let knobColor: UIColor?
    public let isTrackingUpdated: ((Bool) -> Void)?
    
    public init(
        content: Content,
        useNative: Bool = false,
        trackBackgroundColor: UIColor,
        trackForegroundColor: UIColor,
        minTrackForegroundColor: UIColor? = nil,
        knobSize: CGFloat? = nil,
        knobColor: UIColor? = nil,
        isTrackingUpdated: ((Bool) -> Void)? = nil
    ) {
        self.content = content
        self.useNative = useNative
        self.trackBackgroundColor = trackBackgroundColor
        self.trackForegroundColor = trackForegroundColor
        self.minTrackForegroundColor = minTrackForegroundColor
        self.knobSize = knobSize
        self.knobColor = knobColor
        self.isTrackingUpdated = isTrackingUpdated
    }
    
    public static func ==(lhs: SliderComponent, rhs: SliderComponent) -> Bool {
        if lhs.content != rhs.content { return false }
        if lhs.useNative != rhs.useNative { return false }
        if lhs.trackBackgroundColor != rhs.trackBackgroundColor { return false }
        if lhs.trackForegroundColor != rhs.trackForegroundColor { return false }
        if lhs.minTrackForegroundColor != rhs.minTrackForegroundColor { return false }
        if lhs.knobSize != rhs.knobSize { return false }
        if lhs.knobColor != rhs.knobColor { return false }
        return true
    }
    
    public final class View: UIView {
        private var nativeSliderView: UISlider?
        private var sliderView: TGPhotoEditorSliderView?
        
        private var component: SliderComponent?
        private weak var state: EmptyComponentState?
        
        private let feedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        
        public var hitTestTarget: UIView? {
            if #available(iOS 26.0, *) {
                return self.nativeSliderView
            } else {
                return self.sliderView
            }
        }
        
        override public init(frame: CGRect) {
            super.init(frame: frame)
            feedbackGenerator.prepare()
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func cancelGestures() {
            if let sliderView = self.sliderView, let gestureRecognizers = sliderView.gestureRecognizers {
                for gestureRecognizer in gestureRecognizers {
                    gestureRecognizer.isEnabled = false
                    gestureRecognizer.isEnabled = true
                }
            }
        }
        
        func update(component: SliderComponent, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
            self.component = component
            self.state = state
            
            let size = CGSize(width: availableSize.width, height: 44.0)
            
            if #available(iOS 26.0, *) {
                if let sliderView = self.sliderView {
                    sliderView.removeFromSuperview()
                    self.sliderView = nil
                }
                
                let sliderView: UISlider
                if let current = self.nativeSliderView {
                    sliderView = current
                } else {
                    sliderView = UISlider()
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    sliderView.layer.allowsGroupOpacity = true
                    
                    self.addSubview(sliderView)
                    self.nativeSliderView = sliderView
                    
                    switch component.content {
                    case let .continuous(continuous):
                        sliderView.minimumValue = Float(continuous.minValue ?? 0.0)
                        sliderView.maximumValue = 1.0
                    case let .discrete(discrete):
                        sliderView.minimumValue = 0.0
                        sliderView.maximumValue = Float(discrete.valueCount - 1)
                    }
                }
                
                switch component.content {
                case let .continuous(continuous):
                    sliderView.value = Float(continuous.value)
                case let .discrete(discrete):
                    sliderView.value = Float(discrete.value)
                }
                
                sliderView.minimumTrackTintColor = component.trackForegroundColor
                sliderView.maximumTrackTintColor = component.trackBackgroundColor
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
                
            } else {
                if let nativeSlider = self.nativeSliderView {
                    nativeSlider.removeFromSuperview()
                    self.nativeSliderView = nil
                }
                
                var internalIsTrackingUpdated: ((Bool) -> Void)?
                if let isTrackingUpdated = component.isTrackingUpdated {
                    internalIsTrackingUpdated = { [weak self] isTracking in
                        self?.feedbackGenerator.impactOccurred()
                        isTrackingUpdated(isTracking)
                    }
                }
                
                let sliderView: TGPhotoEditorSliderView
                if let current = self.sliderView {
                    sliderView = current
                } else {
                    sliderView = TGPhotoEditorSliderView()
                    sliderView.enablePanHandling = true
                    sliderView.lineSize = 4.0
                    sliderView.trackCornerRadius = 2.0
                    sliderView.dotSize = 5.0
                    sliderView.minimumValue = 0.0
                    sliderView.startValue = 0.0
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    
                    switch component.content {
                    case let .discrete(discrete):
                        sliderView.maximumValue = CGFloat(discrete.valueCount - 1)
                        sliderView.positionsCount = discrete.valueCount
                        sliderView.useLinesForPositions = true
                        sliderView.markPositions = discrete.markPositions
                    case .continuous:
                        sliderView.maximumValue = 1.0
                    }
                    
                    sliderView.backgroundColor = nil
                    sliderView.isOpaque = false
                    sliderView.backColor = component.trackBackgroundColor
                    sliderView.startColor = component.trackBackgroundColor
                    sliderView.trackColor = component.trackForegroundColor
                    
                    let actualKnobSize = component.knobSize ?? 28.0
                    sliderView.knobImage = self.generateLiquidGlassKnobImage(
                        size: actualKnobSize,
                        color: component.knobColor ?? .white
                    )
                    
                    sliderView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: size)
                    sliderView.hitTestEdgeInsets = UIEdgeInsets(top: -sliderView.frame.minX, left: 0.0, bottom: 0.0, right: -sliderView.frame.minX)
                    
                    sliderView.disablesInteractiveTransitionGestureRecognizer = true
                    sliderView.addTarget(self, action: #selector(self.sliderValueChanged), for: .valueChanged)
                    sliderView.layer.allowsGroupOpacity = true
                    self.sliderView = sliderView
                    self.addSubview(sliderView)
                }
                
                sliderView.lowerBoundTrackColor = component.minTrackForegroundColor
                
                switch component.content {
                case let .discrete(discrete):
                    sliderView.value = CGFloat(discrete.value)
                    if let minValue = discrete.minValue {
                        sliderView.lowerBoundValue = CGFloat(minValue)
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                case let .continuous(continuous):
                    sliderView.value = continuous.value
                    if let minValue = continuous.minValue {
                        sliderView.lowerBoundValue = minValue
                    } else {
                        sliderView.lowerBoundValue = 0.0
                    }
                }
                
                sliderView.interactionBegan = {
                    internalIsTrackingUpdated?(true)
                }
                sliderView.interactionEnded = {
                    internalIsTrackingUpdated?(false)
                }
                
                transition.setFrame(view: sliderView, frame: CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: availableSize.width, height: 44.0)))
                sliderView.hitTestEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 0.0)
            }
            
            return size
        }
        
        private func generateLiquidGlassKnobImage(size: CGFloat, color: UIColor) -> UIImage {
            let imageSize = CGSize(width: 44.0, height: 44.0)
            let knobRect = CGRect(
                x: (imageSize.width - size) / 2,
                y: (imageSize.height - size) / 2,
                width: size,
                height: size
            )
            
            return UIGraphicsImageRenderer(size: imageSize).image { ctx in
                let context = ctx.cgContext
                context.clear(CGRect(origin: .zero, size: imageSize))
                
                context.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: UIColor(white: 0, alpha: 0.25).cgColor)
                context.setFillColor(color.cgColor)
                context.fillEllipse(in: knobRect)
                
                context.setShadow(offset: .zero, blur: 0, color: nil)
                
                context.saveGState()
                context.addEllipse(in: knobRect)
                context.clip()
                
                let highlightRect = CGRect(x: knobRect.minX, y: knobRect.minY, width: knobRect.width, height: knobRect.height * 0.45)
                let colors = [
                    UIColor.white.withAlphaComponent(0.7).cgColor,
                    UIColor.white.withAlphaComponent(0.0).cgColor
                ]
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: highlightRect.midX, y: highlightRect.minY),
                    end: CGPoint(x: highlightRect.midX, y: highlightRect.maxY),
                    options: []
                )
                context.restoreGState()
                
                context.setStrokeColor(UIColor(white: 0, alpha: 0.08).cgColor)
                context.setLineWidth(0.5)
                context.strokeEllipse(in: knobRect.insetBy(dx: 0.25, dy: 0.25))
            }
        }
        
        @objc private func sliderValueChanged() {
            guard let component = self.component else { return }
            
            let floatValue: CGFloat
            if #available(iOS 26.0, *) {
                if let nativeSliderView = self.nativeSliderView {
                    floatValue = CGFloat(nativeSliderView.value)
                } else {
                    return
                }
            } else {
                if let sliderView = self.sliderView {
                    floatValue = sliderView.value
                } else {
                    return
                }
            }
            
            switch component.content {
            case let .discrete(discrete):
                discrete.valueUpdated(Int(floatValue))
            case let .continuous(continuous):
                continuous.valueUpdated(floatValue)
            }
        }
    }

    public func makeView() -> View {
        return View(frame: CGRect())
    }
    
    public func update(view: View, availableSize: CGSize, state: EmptyComponentState, environment: Environment<Empty>, transition: ComponentTransition) -> CGSize {
        return view.update(component: self, availableSize: availableSize, state: state, environment: environment, transition: transition)
    }
}
