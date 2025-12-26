import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ContextUI
import ChatPresentationInterfaceState
import ChatMessageBackground
import ChatControllerInteraction
import AccountContext
import ChatTextInputMediaRecordingButton
import ChatSendButtonRadialStatusNode
import ChatSendMessageActionUI
import ComponentFlow
import AnimatedCountLabelNode
import GlassBackgroundComponent
import ComponentDisplayAdapters
import StarsParticleEffect


private enum LiquidGlassAnimations {
    
    struct AnimationConfig {
        let tapScaleDown: CGFloat
        let bounceOvershoot: CGFloat
        let tapDuration: TimeInterval
        let bounceDuration: TimeInterval
        let tapSpringDamping: CGFloat
        let bounceSpringDamping: CGFloat
        let bounceSpringVelocity: CGFloat
        let highlightOpacityPressed: Float
        let highlightOpacityNormal: Float
        
        static let button = AnimationConfig(
            tapScaleDown: 0.92,
            bounceOvershoot: 1.08,
            tapDuration: 0.12,
            bounceDuration: 0.5,
            tapSpringDamping: 0.6,
            bounceSpringDamping: 0.6,
            bounceSpringVelocity: 0.8,
            highlightOpacityPressed: 0.5,
            highlightOpacityNormal: 1.0
        )
        
        static let tabBar = AnimationConfig(
            tapScaleDown: 0.95,
            bounceOvershoot: 1.05,
            tapDuration: 0.1,
            bounceDuration: 0.45,
            tapSpringDamping: 0.65,
            bounceSpringDamping: 0.65,
            bounceSpringVelocity: 0.6,
            highlightOpacityPressed: 0.6,
            highlightOpacityNormal: 1.0
        )
        
        static let subtle = AnimationConfig(
            tapScaleDown: 0.96,
            bounceOvershoot: 1.03,
            tapDuration: 0.08,
            bounceDuration: 0.35,
            tapSpringDamping: 0.7,
            bounceSpringDamping: 0.7,
            bounceSpringVelocity: 0.5,
            highlightOpacityPressed: 0.7,
            highlightOpacityNormal: 1.0
        )
    }
}

private final class EffectBadgeView: UIView {
    private let context: AccountContext
    private var currentEffectId: Int64?
    
    private let backgroundView: UIImageView
    
    private var theme: PresentationTheme?
    
    private var effect: AvailableMessageEffects.MessageEffect?
    private var effectIcon: ComponentView<Empty>?
    
    private let effectDisposable = MetaDisposable()
    
    init(context: AccountContext) {
        self.context = context
        self.backgroundView = UIImageView()
        
        super.init(frame: CGRect())
        
        self.isUserInteractionEnabled = false
        
        self.addSubview(self.backgroundView)
    }
    
    required init(coder: NSCoder) {
        preconditionFailure()
    }
    
    deinit {
        self.effectDisposable.dispose()
    }
    
    func update(size: CGSize, theme: PresentationTheme, effectId: Int64) {
        if self.theme !== theme {
            self.theme = theme
            self.backgroundView.image = generateFilledCircleImage(diameter: size.width, color: theme.list.plainBackgroundColor, strokeColor: nil, strokeWidth: nil, backgroundColor: nil)
            self.backgroundView.layer.shadowPath = UIBezierPath(ovalIn: CGRect(origin: CGPoint(), size: size)).cgPath
            self.backgroundView.layer.shadowColor = UIColor(white: 0.0, alpha: 1.0).cgColor
            self.backgroundView.layer.shadowOpacity = 0.14
            self.backgroundView.layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
            self.backgroundView.layer.shadowRadius = 1.0
        }
        
        self.backgroundView.frame = CGRect(origin: CGPoint(), size: size)
        
        if self.currentEffectId != effectId {
            self.currentEffectId = effectId
            
            let messageEffect = self.context.engine.stickers.availableMessageEffects()
            |> take(1)
            |> map { availableMessageEffects -> AvailableMessageEffects.MessageEffect? in
                guard let availableMessageEffects else {
                    return nil
                }
                for messageEffect in availableMessageEffects.messageEffects {
                    if messageEffect.id == effectId || messageEffect.effectSticker.fileId.id == effectId {
                        return messageEffect
                    }
                }
                return nil
            }
            
            self.effectDisposable.set((messageEffect |> deliverOnMainQueue).start(next: { [weak self] effect in
                guard let self, let effect else {
                    return
                }
                self.effect = effect
                self.updateIcon()
            }))
        }
    }
    
    private func updateIcon() {
        guard let effect else {
            return
        }
        
        let effectIcon: ComponentView<Empty>
        if let current = self.effectIcon {
            effectIcon = current
        } else {
            effectIcon = ComponentView()
            self.effectIcon = effectIcon
        }
        let effectIconContent: ChatSendMessageScreenEffectIcon.Content
        if let staticIcon = effect.staticIcon {
            effectIconContent = .file(staticIcon._parse())
        } else {
            effectIconContent = .text(effect.emoticon)
        }
        let effectIconSize = effectIcon.update(
            transition: .immediate,
            component: AnyComponent(ChatSendMessageScreenEffectIcon(
                context: self.context,
                content: effectIconContent
            )),
            environment: {},
            containerSize: CGSize(width: 8.0, height: 8.0)
        )
        
        let size = CGSize(width: 16.0, height: 16.0)
        if let effectIconView = effectIcon.view {
            if effectIconView.superview == nil {
                self.addSubview(effectIconView)
            }
            effectIconView.frame = CGRect(origin: CGPoint(x: floor((size.width - effectIconSize.width) * 0.5), y: floor((size.height - effectIconSize.height) * 0.5)), size: effectIconSize)
        }
    }
}

public final class ChatTextInputActionButtonsNode: ASDisplayNode, ChatSendMessageActionSheetControllerSourceSendButtonNode {
    private let context: AccountContext
    private let presentationContext: ChatPresentationContext?
    private let strings: PresentationStrings
    
    
    public let micButtonBackgroundView: GlassBackgroundView
    public let micButtonTintMaskView: UIImageView
    public let micButton: ChatTextInputMediaRecordingButton
    
    private let micButtonHighlightLayer: CAGradientLayer
    private var micButtonGlowLayer: CALayer?
    
    
    public let sendContainerNode: ASDisplayNode
    public let sendButtonBackgroundView: UIImageView
    private var sendButtonBackgroundEffectLayer: StarsParticleEffectLayer?
    public let sendButton: HighlightTrackingButtonNode
    public var sendButtonRadialStatusNode: ChatSendButtonRadialStatusNode?
    public var sendButtonHasApplyIcon = false
    public var animatingSendButton = false
    
    private let sendButtonHighlightLayer: CAGradientLayer
    
    public let textNode: ImmediateAnimatedCountLabelNode
    
    
    public let expandMediaInputButton: HighlightTrackingButton
    private let expandMediaInputButtonBackgroundView: GlassBackgroundView
    private let expandMediaInputButtonIcon: GlassBackgroundView.ContentImageView
    
    private let expandButtonHighlightLayer: CAGradientLayer
    
    private var effectBadgeView: EffectBadgeView?
    
    public var sendButtonLongPressed: ((ASDisplayNode, ContextGesture) -> Void)?
    
    private var gestureRecognizer: ContextGesture?
    public var sendButtonLongPressEnabled = false {
        didSet {
            self.gestureRecognizer?.isEnabled = self.sendButtonLongPressEnabled
        }
    }
    
    private var micButtonPointerInteraction: PointerInteraction?
    private var sendButtonPointerInteraction: PointerInteraction?
    
    let maskContentView: UIView
    
    private var validLayout: CGSize?
    
    public var customSendColor: UIColor?
    public var isSendDisabled: Bool = false
    
    
    public init(context: AccountContext, presentationInterfaceState: ChatPresentationInterfaceState, presentationContext: ChatPresentationContext?, presentController: @escaping (ViewController) -> Void) {
        self.context = context
        self.presentationContext = presentationContext
        let theme = presentationInterfaceState.theme
        let strings = presentationInterfaceState.strings
        self.strings = strings
        
        self.micButtonBackgroundView = GlassBackgroundView()
        self.maskContentView = UIView()
        
        self.micButtonTintMaskView = UIImageView()
        self.micButtonTintMaskView.tintColor = .black
        self.micButton = ChatTextInputMediaRecordingButton(context: context, theme: theme, pause: true, strings: strings, presentController: presentController)
        self.micButton.animationOutput = self.micButtonTintMaskView
        self.micButtonBackgroundView.maskContentView.addSubview(self.micButtonTintMaskView)
        
        self.micButtonHighlightLayer = Self.createHighlightLayer()
        self.sendButtonHighlightLayer = Self.createHighlightLayer()
        self.expandButtonHighlightLayer = Self.createHighlightLayer()
        
        self.sendContainerNode = ASDisplayNode()
        self.sendContainerNode.layer.allowsGroupOpacity = true
        
        self.sendButtonBackgroundView = UIImageView()
        self.sendButtonBackgroundView.image = generateStretchableFilledCircleImage(diameter: 34.0, color: .white)?.withRenderingMode(.alwaysTemplate)
        self.sendButton = HighlightTrackingButtonNode(pointerStyle: nil)
        
        self.textNode = ImmediateAnimatedCountLabelNode()
        self.textNode.isUserInteractionEnabled = false
        
        self.expandMediaInputButton = HighlightTrackingButton()
        self.expandMediaInputButtonBackgroundView = GlassBackgroundView()
        self.expandMediaInputButtonBackgroundView.isUserInteractionEnabled = false
        self.expandMediaInputButton.addSubview(self.expandMediaInputButtonBackgroundView)
        self.expandMediaInputButtonIcon = GlassBackgroundView.ContentImageView()
        self.expandMediaInputButtonBackgroundView.contentView.addSubview(self.expandMediaInputButtonIcon)
        self.expandMediaInputButtonIcon.image = PresentationResourcesChat.chatInputPanelExpandButtonImage(presentationInterfaceState.theme)
        self.expandMediaInputButtonIcon.tintColor = theme.chat.inputPanel.panelControlColor
        self.expandMediaInputButtonIcon.setMonochromaticEffect(tintColor: theme.chat.inputPanel.panelControlColor)
        
        super.init()
        
        self.isAccessibilityElement = true
        self.accessibilityTraits = [.button, .notEnabled]
        
        self.sendButton.highligthedChanged = { [weak self] highlighted in
            guard let self = self else { return }
            self.handleSendButtonHighlight(highlighted)
        }
        
        self.micButton.layer.allowsGroupOpacity = true
        self.view.addSubview(self.micButtonBackgroundView)
        self.micButtonBackgroundView.contentView.addSubview(self.micButton)
        
        self.micButtonBackgroundView.layer.addSublayer(self.micButtonHighlightLayer)
        
        self.addSubnode(self.sendContainerNode)
        self.sendContainerNode.view.addSubview(self.sendButtonBackgroundView)
        self.sendContainerNode.addSubnode(self.sendButton)
        self.sendContainerNode.addSubnode(self.textNode)
        
        self.sendButtonBackgroundView.layer.addSublayer(self.sendButtonHighlightLayer)
        
        self.view.addSubview(self.expandMediaInputButton)
        
        self.expandMediaInputButton.highligthedChanged = { [weak self] highlighted in
            guard let self = self else { return }
            self.handleExpandButtonHighlight(highlighted)
        }
        
        self.expandMediaInputButtonBackgroundView.layer.addSublayer(self.expandButtonHighlightLayer)
        
        self.micButton.onTouchDown = { [weak self] in
            self?.animateMicButtonTouchDown()
        }
        self.micButton.onTouchUp = { [weak self] in
            self?.animateMicButtonTouchUp()
        }
    }
    
    private static func createHighlightLayer() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.colors = [
            UIColor.white.withAlphaComponent(0.35).cgColor,
            UIColor.white.withAlphaComponent(0.1).cgColor,
            UIColor.clear.cgColor
        ]
        layer.locations = [0.0, 0.3, 1.0]
        layer.startPoint = CGPoint(x: 0.5, y: 0)
        layer.endPoint = CGPoint(x: 0.5, y: 1)
        return layer
    }
    
    private func animateMicButtonTouchDown() {
        let config = LiquidGlassAnimations.AnimationConfig.button
        
        UIView.animate(
            withDuration: config.tapDuration,
            delay: 0,
            usingSpringWithDamping: config.tapSpringDamping,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: {
                self.micButtonBackgroundView.transform = CGAffineTransform(scaleX: config.tapScaleDown, y: config.tapScaleDown)
            }
        )
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(config.tapDuration)
        self.micButtonHighlightLayer.opacity = config.highlightOpacityPressed
        CATransaction.commit()
        
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
    }
    
    private func animateMicButtonTouchUp() {
        let config = LiquidGlassAnimations.AnimationConfig.button
        
        UIView.animateKeyframes(
            withDuration: config.bounceDuration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .calculationModeCubic],
            animations: {
                UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.4) {
                    self.micButtonBackgroundView.transform = CGAffineTransform(scaleX: config.bounceOvershoot, y: config.bounceOvershoot)
                }
                UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.6) {
                    self.micButtonBackgroundView.transform = .identity
                }
            }
        )
        
        CATransaction.begin()
        CATransaction.setAnimationDuration(config.bounceDuration * 0.4)
        self.micButtonHighlightLayer.opacity = config.highlightOpacityNormal
        CATransaction.commit()
    }
    
    private func handleSendButtonHighlight(_ highlighted: Bool) {
        let config = LiquidGlassAnimations.AnimationConfig.button
        
        if !self.sendButtonLongPressEnabled {
            if highlighted {
                self.sendContainerNode.layer.removeAnimation(forKey: "opacity")
                self.sendContainerNode.alpha = 0.4
                
                UIView.animate(
                    withDuration: config.tapDuration,
                    delay: 0,
                    usingSpringWithDamping: config.tapSpringDamping,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction],
                    animations: {
                        self.sendContainerNode.view.transform = CGAffineTransform(scaleX: config.tapScaleDown, y: config.tapScaleDown)
                    }
                )
                
                let feedback = UIImpactFeedbackGenerator(style: .light)
                feedback.impactOccurred()
            } else {
                self.sendContainerNode.alpha = 1.0
                self.sendContainerNode.layer.animateAlpha(from: 0.4, to: 1.0, duration: 0.2)
                
                UIView.animateKeyframes(
                    withDuration: config.bounceDuration,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .calculationModeCubic],
                    animations: {
                        UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.4) {
                            self.sendContainerNode.view.transform = CGAffineTransform(scaleX: config.bounceOvershoot, y: config.bounceOvershoot)
                        }
                        UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.6) {
                            self.sendContainerNode.view.transform = .identity
                        }
                    }
                )
            }
        } else {
            if highlighted {
                UIView.animate(
                    withDuration: config.tapDuration,
                    delay: 0,
                    usingSpringWithDamping: config.tapSpringDamping,
                    initialSpringVelocity: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState],
                    animations: {
                        self.sendContainerNode.view.transform = CGAffineTransform(scaleX: config.tapScaleDown, y: config.tapScaleDown)
                    }
                )
                
                CATransaction.begin()
                CATransaction.setAnimationDuration(config.tapDuration)
                self.sendButtonHighlightLayer.opacity = config.highlightOpacityPressed
                CATransaction.commit()
                
                let feedback = UIImpactFeedbackGenerator(style: .light)
                feedback.impactOccurred()
                
            } else if self.sendContainerNode.layer.presentation() != nil {
                UIView.animateKeyframes(
                    withDuration: config.bounceDuration,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .calculationModeCubic],
                    animations: {
                        UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.4) {
                            self.sendContainerNode.view.transform = CGAffineTransform(scaleX: config.bounceOvershoot, y: config.bounceOvershoot)
                        }
                        UIView.addKeyframe(withRelativeStartTime: 0.4, relativeDuration: 0.6) {
                            self.sendContainerNode.view.transform = .identity
                        }
                    }
                )
                
                CATransaction.begin()
                CATransaction.setAnimationDuration(config.bounceDuration * 0.4)
                self.sendButtonHighlightLayer.opacity = config.highlightOpacityNormal
                CATransaction.commit()
            }
        }
    }
    
    private func handleExpandButtonHighlight(_ highlighted: Bool) {
        let config = LiquidGlassAnimations.AnimationConfig.button
        
        if highlighted {
            UIView.animate(
                withDuration: config.tapDuration,
                delay: 0,
                usingSpringWithDamping: config.tapSpringDamping,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: {
                    self.expandMediaInputButton.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
                }
            )
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(config.tapDuration)
            self.expandButtonHighlightLayer.opacity = config.highlightOpacityPressed
            CATransaction.commit()
            
            let feedback = UIImpactFeedbackGenerator(style: .light)
            feedback.impactOccurred()
            
        } else if self.expandMediaInputButton.layer.presentation() != nil {
            UIView.animate(
                withDuration: config.bounceDuration,
                delay: 0,
                usingSpringWithDamping: config.bounceSpringDamping,
                initialSpringVelocity: config.bounceSpringVelocity,
                options: [.allowUserInteraction, .beginFromCurrentState],
                animations: {
                    self.expandMediaInputButton.transform = .identity
                }
            )
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(config.bounceDuration)
            self.expandButtonHighlightLayer.opacity = config.highlightOpacityNormal
            CATransaction.commit()
        }
    }
    
    
    public func startRecordingGlow(color: UIColor = .red) {
        guard micButtonGlowLayer == nil else { return }
        
        let glowLayer = CALayer()
        glowLayer.frame = micButtonBackgroundView.bounds.insetBy(dx: -4, dy: -4)
        glowLayer.backgroundColor = UIColor.clear.cgColor
        glowLayer.cornerRadius = glowLayer.bounds.height / 2
        glowLayer.shadowColor = color.cgColor
        glowLayer.shadowOffset = .zero
        glowLayer.shadowRadius = 8
        glowLayer.shadowOpacity = 0.8
        
        micButtonBackgroundView.layer.insertSublayer(glowLayer, at: 0)
        
        let pulseAnimation = CABasicAnimation(keyPath: "shadowOpacity")
        pulseAnimation.fromValue = 0.8
        pulseAnimation.toValue = 0.24
        pulseAnimation.duration = 0.8
        pulseAnimation.autoreverses = true
        pulseAnimation.repeatCount = .infinity
        pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        glowLayer.add(pulseAnimation, forKey: "recordingGlow")
        
        micButtonGlowLayer = glowLayer
    }
    
    public func stopRecordingGlow(animated: Bool = true) {
        guard let glowLayer = micButtonGlowLayer else { return }
        
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
        
        micButtonGlowLayer = nil
    }
    
    override public func didLoad() {
        super.didLoad()
        
        let gestureRecognizer = ContextGesture(target: nil, action: nil)
        self.gestureRecognizer = gestureRecognizer
        self.sendButton.view.addGestureRecognizer(gestureRecognizer)
        gestureRecognizer.activated = { [weak self] recognizer, _ in
            guard let strongSelf = self else {
                return
            }
            strongSelf.sendButtonLongPressed?(strongSelf, recognizer)
        }
        
        self.micButtonPointerInteraction = PointerInteraction(view: self.micButton, style: .circle(36.0))
        self.sendButtonPointerInteraction = PointerInteraction(view: self.sendButton.view, customInteractionView: self.sendButtonBackgroundView, style: .lift)
    }
    
    public func updateTheme(theme: PresentationTheme, wallpaper: TelegramWallpaper) {
        self.micButton.updateTheme(theme: theme)
        self.expandMediaInputButtonIcon.tintColor = theme.chat.inputPanel.panelControlColor
        self.expandMediaInputButtonIcon.setMonochromaticEffect(tintColor: theme.chat.inputPanel.panelControlColor)
    }
    
    private var absoluteRect: (CGRect, CGSize)?
    public func updateAbsoluteRect(_ rect: CGRect, within containerSize: CGSize, transition: ContainedViewLayoutTransition) {
        let previousContaierSize = self.absoluteRect?.1
        self.absoluteRect = (rect, containerSize)
        
        if let previousContaierSize, previousContaierSize != containerSize {
            Queue.mainQueue().after(0.2) {
                self.micButton.reset()
            }
        }
    }
    
    public func updateLayout(size: CGSize, isMediaInputExpanded: Bool, showTitle: Bool, currentMessageEffectId: Int64?, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> CGSize {
        self.validLayout = size
        
        var innerSize = size
        innerSize.width = 40.0 + 3.0 * 2.0
        
        var starsAmount: Int64?
        if let sendPaidMessageStars = interfaceState.sendPaidMessageStars, interfaceState.interfaceState.editMessage == nil {
            var amount: Int64
            if let forwardedCount = interfaceState.interfaceState.forwardMessageIds?.count, forwardedCount > 0 {
                amount = sendPaidMessageStars.value * Int64(forwardedCount)
                if interfaceState.interfaceState.effectiveInputState.inputText.length > 0 {
                    amount += sendPaidMessageStars.value
                }
            } else {
                if interfaceState.interfaceState.effectiveInputState.inputText.length > 4096 {
                    let messageCount = Int32(ceil(CGFloat(interfaceState.interfaceState.effectiveInputState.inputText.length) / 4096.0))
                    amount = sendPaidMessageStars.value * Int64(messageCount)
                } else {
                    amount = sendPaidMessageStars.value
                }
            }
            starsAmount = amount
        }
        
        if let amount = starsAmount {
            self.sendButton.imageNode.alpha = 0.0
            self.textNode.isHidden = false
            let text = "\(amount)"
            let font = Font.with(size: 17.0, design: .round, weight: .semibold, traits: .monospacedNumbers)
            let badgeString = NSMutableAttributedString(string: "⭐️ ", font: font, textColor: interfaceState.theme.chat.inputPanel.actionControlForegroundColor)
            if let range = badgeString.string.range(of: "⭐️") {
                badgeString.addAttribute(.attachment, value: PresentationResourcesChat.chatPlaceholderStarIcon(interfaceState.theme)!, range: NSRange(range, in: badgeString.string))
                badgeString.addAttribute(.baselineOffset, value: 1.0, range: NSRange(range, in: badgeString.string))
            }
            var segments: [AnimatedCountLabelNode.Segment] = []
            segments.append(.text(0, badgeString))
            for char in text {
                if let intValue = Int(String(char)) {
                    segments.append(.number(intValue, NSAttributedString(string: String(char), font: font, textColor: interfaceState.theme.chat.inputPanel.actionControlForegroundColor)))
                }
            }
            self.textNode.segments = segments
            
            let textSize = self.textNode.updateLayout(size: CGSize(width: 100.0, height: 100.0), animated: transition.isAnimated)
            let buttonInset: CGFloat = 14.0
            if showTitle {
                innerSize.width = textSize.width + buttonInset * 2.0
            }
            transition.updateFrame(node: self.textNode, frame: CGRect(origin: CGPoint(x: showTitle ? 5.0 + 7.0 : floorToScreenPixels((innerSize.width - textSize.width) / 2.0), y: floorToScreenPixels((size.height - textSize.height) / 2.0)), size: textSize))
        } else {
            self.textNode.isHidden = true
        }
        
        transition.updateFrame(view: self.micButtonBackgroundView, frame: CGRect(origin: CGPoint(), size: size))
        self.micButtonBackgroundView.update(size: size, cornerRadius: size.height * 0.5, isDark: interfaceState.theme.overallDarkAppearance, tintColor: .init(kind: .panel, color: interfaceState.theme.chat.inputPanel.inputBackgroundColor.withMultipliedAlpha(0.7)), isInteractive: true, transition: ComponentTransition(transition))
        
        self.micButtonHighlightLayer.frame = CGRect(origin: .zero, size: size)
        let micHighlightMask = CAShapeLayer()
        micHighlightMask.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height * 0.5).cgPath
        self.micButtonHighlightLayer.mask = micHighlightMask
        
        transition.updateFrame(layer: self.micButton.layer, frame: CGRect(origin: CGPoint(), size: size))
        self.micButton.layoutItems()
        
        let sendButtonBackgroundFrame = CGRect(origin: CGPoint(), size: innerSize).insetBy(dx: 3.0, dy: 3.0)
        transition.updateFrame(view: self.sendButtonBackgroundView, frame: sendButtonBackgroundFrame)
        
        self.sendButtonHighlightLayer.frame = sendButtonBackgroundFrame
        let sendHighlightMask = CAShapeLayer()
        sendHighlightMask.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: sendButtonBackgroundFrame.size), cornerRadius: sendButtonBackgroundFrame.height * 0.5).cgPath
        self.sendButtonHighlightLayer.mask = sendHighlightMask
        
        if self.isSendDisabled {
            transition.updateTintColor(view: self.sendButtonBackgroundView, color: interfaceState.theme.chat.inputPanel.panelControlAccentColor.withMultiplied(hue: 1.0, saturation: 0.0, brightness: 0.5).withMultipliedAlpha(0.25))
        } else {
            transition.updateTintColor(view: self.sendButtonBackgroundView, color: self.customSendColor ?? interfaceState.theme.chat.inputPanel.panelControlAccentColor)
        }
        
        if starsAmount == nil {
            if self.isSendDisabled {
                transition.updateAlpha(layer: self.sendButton.imageNode.layer, alpha: 0.4)
            } else {
                transition.updateAlpha(layer: self.sendButton.imageNode.layer, alpha: 1.0)
            }
        }
        
        if let _ = self.customSendColor {
            let sendButtonBackgroundEffectLayer: StarsParticleEffectLayer
            var sendButtonBackgroundEffectLayerTransition = transition
            if let current = self.sendButtonBackgroundEffectLayer {
                sendButtonBackgroundEffectLayer = current
            } else {
                sendButtonBackgroundEffectLayerTransition = .immediate
                sendButtonBackgroundEffectLayer = StarsParticleEffectLayer()
                self.sendButtonBackgroundEffectLayer = sendButtonBackgroundEffectLayer
                self.sendButtonBackgroundView.layer.addSublayer(sendButtonBackgroundEffectLayer)
                if transition.isAnimated {
                    sendButtonBackgroundEffectLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                }
            }
            transition.updateFrame(layer: sendButtonBackgroundEffectLayer, frame: CGRect(origin: CGPoint(), size: sendButtonBackgroundFrame.size))
            sendButtonBackgroundEffectLayer.update(color: UIColor(white: 1.0, alpha: 0.5), size: sendButtonBackgroundFrame.size, cornerRadius: sendButtonBackgroundFrame.height * 0.5, transition: ComponentTransition(sendButtonBackgroundEffectLayerTransition))
        } else if let sendButtonBackgroundEffectLayer = self.sendButtonBackgroundEffectLayer {
            self.sendButtonBackgroundEffectLayer = nil
            transition.updateFrame(layer: sendButtonBackgroundEffectLayer, frame: CGRect(origin: CGPoint(), size: sendButtonBackgroundFrame.size))
            transition.updateAlpha(layer: sendButtonBackgroundEffectLayer, alpha: 0.0, completion: { [weak sendButtonBackgroundEffectLayer] _ in
                sendButtonBackgroundEffectLayer?.removeFromSuperlayer()
            })
        }
        
        transition.updateFrame(layer: self.sendButton.layer, frame: CGRect(origin: CGPoint(), size: innerSize))
        let sendContainerFrame = CGRect(origin: CGPoint(), size: innerSize)
        transition.updatePosition(node: self.sendContainerNode, position: sendContainerFrame.center)
        transition.updateBounds(node: self.sendContainerNode, bounds: CGRect(origin: CGPoint(), size: sendContainerFrame.size))
        
        let backgroundSize = CGSize(width: innerSize.width, height: 40.0)
        let backgroundFrame = CGRect(origin: CGPoint(x: showTitle ? 5.0 + UIScreenPixel : floorToScreenPixels((size.width - backgroundSize.width) / 2.0), y: floorToScreenPixels((size.height - backgroundSize.height) / 2.0)), size: backgroundSize)
        
        transition.updateFrame(view: self.expandMediaInputButton, frame: CGRect(origin: CGPoint(), size: size))
        transition.updateFrame(view: self.expandMediaInputButtonBackgroundView, frame: CGRect(origin: CGPoint(), size: size))
        self.expandMediaInputButtonBackgroundView.update(size: size, cornerRadius: size.height * 0.5, isDark: interfaceState.theme.overallDarkAppearance, tintColor: .init(kind: .panel, color: interfaceState.theme.chat.inputPanel.inputBackgroundColor.withMultipliedAlpha(0.7)), transition: ComponentTransition(transition))
        
        self.expandButtonHighlightLayer.frame = CGRect(origin: .zero, size: size)
        let expandHighlightMask = CAShapeLayer()
        expandHighlightMask.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height * 0.5).cgPath
        self.expandButtonHighlightLayer.mask = expandHighlightMask
        
        if let image = self.expandMediaInputButtonIcon.image {
            let expandIconFrame = CGRect(origin: CGPoint(x: floor((size.width - image.size.width) * 0.5), y: floor((size.height - image.size.height) * 0.5)), size: image.size)
            self.expandMediaInputButtonIcon.center = expandIconFrame.center
            self.expandMediaInputButtonIcon.bounds = CGRect(origin: CGPoint(), size: expandIconFrame.size)
            transition.updateTransformScale(layer: self.expandMediaInputButtonIcon.layer, scale: CGPoint(x: 1.0, y: isMediaInputExpanded ? 1.0 : -1.0))
        }
        
        if let currentMessageEffectId {
            let effectBadgeView: EffectBadgeView
            if let current = self.effectBadgeView {
                effectBadgeView = current
            } else {
                effectBadgeView = EffectBadgeView(context: self.context)
                self.effectBadgeView = effectBadgeView
                self.sendContainerNode.view.addSubview(effectBadgeView)
                
                effectBadgeView.alpha = 0.0
                transition.updateAlpha(layer: effectBadgeView.layer, alpha: 1.0)
            }
            let badgeSize = CGSize(width: 16.0, height: 16.0)
            effectBadgeView.frame = CGRect(origin: CGPoint(x: backgroundFrame.minX + backgroundSize.width + 3.0 - badgeSize.width, y: backgroundFrame.minY + backgroundSize.height + 3.0 - badgeSize.height), size: badgeSize)
            effectBadgeView.update(size: badgeSize, theme: interfaceState.theme, effectId: currentMessageEffectId)
        } else if let effectBadgeView = self.effectBadgeView {
            self.effectBadgeView = nil
            transition.updateAlpha(layer: effectBadgeView.layer, alpha: 0.0, completion: { [weak effectBadgeView] _ in
                effectBadgeView?.removeFromSuperview()
            })
        }
        
        return innerSize
    }
    
    public func updateAccessibility() {
        self.accessibilityTraits = .button
        if !self.micButton.alpha.isZero {
            switch self.micButton.mode {
            case .audio:
                self.accessibilityLabel = self.strings.VoiceOver_Chat_RecordModeVoiceMessage
                self.accessibilityHint = self.strings.VoiceOver_Chat_RecordModeVoiceMessageInfo
            case .video:
                self.accessibilityLabel = self.strings.VoiceOver_Chat_RecordModeVideoMessage
                self.accessibilityHint = self.strings.VoiceOver_Chat_RecordModeVideoMessageInfo
            }
        } else {
            self.accessibilityLabel = self.strings.MediaPicker_Send
            self.accessibilityHint = nil
        }
    }
    
    public func makeCustomContents() -> UIView? {
        if self.sendButtonHasApplyIcon || self.effectBadgeView != nil {
            let result = UIView()
            result.frame = self.bounds
            if let copyView = self.sendContainerNode.view.snapshotView(afterScreenUpdates: false) {
                copyView.frame = self.sendContainerNode.frame
                result.addSubview(copyView)
            }
            return result
        }
        return nil
    }
}
