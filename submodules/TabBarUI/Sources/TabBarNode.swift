import Foundation
import UIKit
import AsyncDisplayKit
import SwiftSignalKit
import Display
import UIKitRuntimeUtils
import AnimatedStickerNode
import TelegramAnimatedStickerNode
import TelegramPresentationData

private extension CGRect {
    var center: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
}

private let separatorHeight: CGFloat = 1.0 / UIScreen.main.scale
private func tabBarItemImage(_ image: UIImage?, title: String, backgroundColor: UIColor, tintColor: UIColor, horizontal: Bool, imageMode: Bool, centered: Bool = false) -> (UIImage, CGFloat) {
    let font = horizontal ? Font.regular(13.0) : Font.medium(10.0)
    let titleSize = (title as NSString).boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], attributes: [NSAttributedString.Key.font: font], context: nil).size
    
    let imageSize: CGSize
    if let image = image {
        if horizontal {
            let factor: CGFloat = 0.8
            imageSize = CGSize(width: floor(image.size.width * factor), height: floor(image.size.height * factor))
        } else {
            imageSize = image.size
        }
    } else {
        imageSize = CGSize()
    }
    
    let horizontalSpacing: CGFloat = 4.0
    
    let size: CGSize
    let contentWidth: CGFloat
    if horizontal {
        let width = max(1.0, centered ? imageSize.width : ceil(titleSize.width) + horizontalSpacing + imageSize.width)
        size = CGSize(width: width, height: 34.0)
        contentWidth = size.width
    } else {
        let width =  max(1.0, centered ? imageSize.width : max(ceil(titleSize.width), imageSize.width), 1.0)
        size = CGSize(width: width, height: 45.0)
        contentWidth = imageSize.width
    }
    
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    if let context = UIGraphicsGetCurrentContext() {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(CGRect(origin: CGPoint(), size: size))
        
        if let image = image, imageMode {
            let imageRect: CGRect
            if horizontal {
                imageRect = CGRect(origin: CGPoint(x: 0.0, y: floor((size.height - imageSize.height) / 2.0)), size: imageSize)
            } else {
                imageRect = CGRect(origin: CGPoint(x: floorToScreenPixels((size.width - imageSize.width) / 2.0), y: centered ? floor((size.height - imageSize.height) / 2.0) : 0.0), size: imageSize)
            }
            context.saveGState()
            context.translateBy(x: imageRect.midX, y: imageRect.midY)
            context.scaleBy(x: 1.0, y: -1.0)
            context.translateBy(x: -imageRect.midX, y: -imageRect.midY)
            if image.renderingMode == .alwaysOriginal {
                context.draw(image.cgImage!, in: imageRect)
            } else {
                context.clip(to: imageRect, mask: image.cgImage!)
                context.setFillColor(tintColor.cgColor)
                context.fill(imageRect)
            }
            context.restoreGState()
        }
    }
    
    if !imageMode {
        if horizontal {
            (title as NSString).draw(at: CGPoint(x: imageSize.width + horizontalSpacing, y: floor((size.height - titleSize.height) / 2.0)), withAttributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: tintColor])
        } else {
            (title as NSString).draw(at: CGPoint(x: floorToScreenPixels((size.width - titleSize.width) / 2.0), y: size.height - titleSize.height - 1.0), withAttributes: [NSAttributedString.Key.font: font, NSAttributedString.Key.foregroundColor: tintColor])
        }
    }
    
    let resultImage = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return (resultImage!, contentWidth)
}

private let badgeFont = Font.regular(13.0)

private final class TabBarItemNode: ASDisplayNode {
    let extractedContainerNode: ContextExtractedContentContainingNode
    let containerNode: ContextControllerSourceNode
    let imageNode: ASImageNode
    let animationContainerNode: ASDisplayNode
    let animationNode: AnimatedStickerNode
    let textImageNode: ASImageNode
    let contextImageNode: ASImageNode
    let contextTextImageNode: ASImageNode
    var contentWidth: CGFloat?
    var isSelected: Bool = false
    
    let ringImageNode: ASImageNode
    var ringColor: UIColor? {
        didSet {
            if let ringColor = self.ringColor {
                self.ringImageNode.image = generateCircleImage(diameter: 29.0, lineWidth: 1.0, color: ringColor, backgroundColor: nil)
            } else {
                self.ringImageNode.image = nil
            }
        }
    }
    
    private var glassBackgroundView: UIVisualEffectView?
    private var glassBlurView: UIVisualEffectView?
    private var glassContentMaskView: UIView?
    
    var swiped: ((TabBarItemSwipeDirection) -> Void)?
    
    var pointerInteraction: PointerInteraction?
    
    override init() {
        self.extractedContainerNode = ContextExtractedContentContainingNode()
        self.containerNode = ContextControllerSourceNode()
        
        self.ringImageNode = ASImageNode()
        self.ringImageNode.isUserInteractionEnabled = false
        self.ringImageNode.displayWithoutProcessing = true
        self.ringImageNode.displaysAsynchronously = false
        
        self.imageNode = ASImageNode()
        self.imageNode.isUserInteractionEnabled = false
        self.imageNode.displayWithoutProcessing = true
        self.imageNode.displaysAsynchronously = false
        self.imageNode.isAccessibilityElement = false
        
        self.animationContainerNode = ASDisplayNode()
        
        self.animationNode = DefaultAnimatedStickerNodeImpl()
        self.animationNode.autoplay = true
        self.animationNode.automaticallyLoadLastFrame = true
        
        self.textImageNode = ASImageNode()
        self.textImageNode.isUserInteractionEnabled = false
        self.textImageNode.displayWithoutProcessing = true
        self.textImageNode.displaysAsynchronously = false
        self.textImageNode.isAccessibilityElement = false
        
        self.contextImageNode = ASImageNode()
        self.contextImageNode.isUserInteractionEnabled = false
        self.contextImageNode.displayWithoutProcessing = true
        self.contextImageNode.displaysAsynchronously = false
        self.contextImageNode.isAccessibilityElement = false
        self.contextImageNode.alpha = 0.0
        self.contextTextImageNode = ASImageNode()
        self.contextTextImageNode.isUserInteractionEnabled = false
        self.contextTextImageNode.displayWithoutProcessing = true
        self.contextTextImageNode.displaysAsynchronously = false
        self.contextTextImageNode.isAccessibilityElement = false
        self.contextTextImageNode.alpha = 0.0
        
        super.init()
        
        self.isAccessibilityElement = true
        
        self.extractedContainerNode.contentNode.addSubnode(self.ringImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.textImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.imageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.animationContainerNode)
        self.animationContainerNode.addSubnode(self.animationNode)
        self.extractedContainerNode.contentNode.addSubnode(self.contextTextImageNode)
        self.extractedContainerNode.contentNode.addSubnode(self.contextImageNode)
        self.containerNode.addSubnode(self.extractedContainerNode)
        self.containerNode.targetNodeForActivationProgress = self.extractedContainerNode.contentNode
        self.addSubnode(self.containerNode)
        
        self.extractedContainerNode.willUpdateIsExtractedToContextPreview = { [weak self] isExtracted, transition in
            guard let strongSelf = self else {
                return
            }
            transition.updateAlpha(node: strongSelf.ringImageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.imageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.animationNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.textImageNode, alpha: isExtracted ? 0.0 : 1.0)
            transition.updateAlpha(node: strongSelf.contextImageNode, alpha: isExtracted ? 1.0 : 0.0)
            transition.updateAlpha(node: strongSelf.contextTextImageNode, alpha: isExtracted ? 1.0 : 0.0)
        }
    }
    
    override func didLoad() {
        super.didLoad()
        self.pointerInteraction = PointerInteraction(node: self, style: .rectangle(CGSize(width: 90.0, height: 50.0)))
        self.setupLiquidGlassEffect()
    }
    
    private func setupLiquidGlassEffect() {
        guard self.glassBackgroundView == nil, self.isNodeLoaded else { return }
        
        let blurEffect = UIBlurEffect(style: .systemThinMaterial)
        let glassBlurView = UIVisualEffectView(effect: blurEffect)
        glassBlurView.clipsToBounds = true
        glassBlurView.isUserInteractionEnabled = false
        glassBlurView.alpha = 0.0
        self.glassBlurView = glassBlurView
        
        let glassBackgroundView = UIVisualEffectView(effect: nil)
        glassBackgroundView.clipsToBounds = true
        glassBackgroundView.isUserInteractionEnabled = false
        glassBackgroundView.alpha = 0.0
        self.glassBackgroundView = glassBackgroundView
        
        let maskView = UIView()
        maskView.backgroundColor = .white
        self.glassContentMaskView = maskView
        
        self.view.insertSubview(glassBlurView, at: 0)
        self.view.insertSubview(glassBackgroundView, at: 1)
    }
    
    private func ensureGlassEffectSetup() {
        if !self.isNodeLoaded {
            return
        }
        if self.glassBackgroundView == nil {
            self.setupLiquidGlassEffect()
        }
    }
    
    func updateGlassEffect(isSelected: Bool, theme: PresentationTheme, animated: Bool = true) {
        self.ensureGlassEffectSetup()
        
        guard let glassBlurView = self.glassBlurView,
              let glassBackgroundView = self.glassBackgroundView,
              let glassContentMaskView = self.glassContentMaskView else {
            //print("TabBarItemNode: Glass views not initialized!")
            return
        }
        
        if isSelected {
            //print("TabBarItemNode: Applying glass effect (animated: \(animated))")
            let iconSize = CGSize(width: 40.0, height: 40.0)
            let glassFrame = CGRect(
                x: (self.bounds.width - iconSize.width) / 2.0,
                y: 0.0,
                width: iconSize.width,
                height: iconSize.height
            )
            
            glassBlurView.frame = glassFrame
            glassBackgroundView.frame = glassFrame
            glassContentMaskView.frame = glassFrame
            
            let cornerRadius = iconSize.height / 2.0
            glassBlurView.layer.cornerRadius = cornerRadius
            glassBackgroundView.layer.cornerRadius = cornerRadius
            glassContentMaskView.layer.cornerRadius = cornerRadius
            
            let tintColor = theme.rootController.tabBar.selectedIconColor.withAlphaComponent(0.15)
            glassBackgroundView.backgroundColor = tintColor
            
            self.addGlassEdgeHighlight(to: glassBlurView, cornerRadius: cornerRadius)
            
            if animated {
                glassBlurView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                glassBackgroundView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                
                UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0.5, options: [.curveEaseOut, .allowUserInteraction]) {
                    glassBlurView.alpha = 1.0
                    glassBackgroundView.alpha = 1.0
                    glassBlurView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                    glassBackgroundView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                } completion: { _ in
                    //print("Glass effect animation completed")
                }
            } else {
                glassBlurView.alpha = 1.0
                glassBackgroundView.alpha = 1.0
                glassBlurView.transform = .identity
                glassBackgroundView.transform = .identity
            }
        } else {
            //print("TabBarItemNode: Removing glass effect (animated: \(animated))")
            
            if animated {
                UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                    glassBlurView.alpha = 0.0
                    glassBackgroundView.alpha = 0.0
                    glassBlurView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                    glassBackgroundView.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                } completion: { _ in
                }
            } else {
                glassBlurView.alpha = 0.0
                glassBackgroundView.alpha = 0.0
            }
        }
    }
    
    private func addGlassEdgeHighlight(to view: UIView, cornerRadius: CGFloat) {
        view.layer.sublayers?.filter { $0.name == "glassHighlight" }.forEach { $0.removeFromSuperlayer() }
        
        let highlightLayer = CAGradientLayer()
        highlightLayer.name = "glassHighlight"
        highlightLayer.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height * 0.5)
        highlightLayer.colors = [
            UIColor.white.withAlphaComponent(0.2).cgColor,
            UIColor.white.withAlphaComponent(0.0).cgColor
        ]
        highlightLayer.locations = [0.0, 1.0]
        highlightLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        highlightLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        view.layer.addSublayer(highlightLayer)
    }
    
    func animateTapInteraction() {
        guard let glassBlurView = self.glassBlurView,
              let glassBackgroundView = self.glassBackgroundView else {
            //print("TabBarItemNode: Cannot animate tap, glass views not initialized")
            return
        }
        
        //print("TabBarItemNode animating tap interaction")
        
        UIView.animate(withDuration: 0.08, delay: 0, options: [.curveEaseIn, .allowUserInteraction]) {
            glassBlurView.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
            glassBackgroundView.transform = CGAffineTransform(scaleX: 0.90, y: 0.90)
        } completion: { _ in
            UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.35, initialSpringVelocity: 1.2, options: [.curveEaseOut, .allowUserInteraction]) {
                glassBlurView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
                glassBackgroundView.transform = CGAffineTransform(scaleX: 1.0, y: 1.0)
            } completion: { _ in
                //print("Tap animation completed")
            }
        }
        
        let stretchAnimation = CAKeyframeAnimation(keyPath: "transform.scale.x")
        stretchAnimation.values = [1.0, 0.94, 1.08, 0.98, 1.02, 1.0]
        stretchAnimation.keyTimes = [0.0, 0.12, 0.28, 0.48, 0.68, 1.0]
        stretchAnimation.duration = 0.65
        stretchAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        
        let verticalStretchAnimation = CAKeyframeAnimation(keyPath: "transform.scale.y")
        verticalStretchAnimation.values = [1.0, 0.96, 0.98, 1.03, 0.99, 1.0]
        verticalStretchAnimation.keyTimes = [0.0, 0.12, 0.28, 0.48, 0.68, 1.0]
        verticalStretchAnimation.duration = 0.65
        verticalStretchAnimation.timingFunctions = [
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut)
        ]
        
        glassBlurView.layer.add(stretchAnimation, forKey: "stretchAnimationX")
        glassBlurView.layer.add(verticalStretchAnimation, forKey: "stretchAnimationY")
        glassBackgroundView.layer.add(stretchAnimation, forKey: "stretchAnimationX")
        glassBackgroundView.layer.add(verticalStretchAnimation, forKey: "stretchAnimationY")
        
        let highlightView = UIView(frame: glassBlurView.bounds)
        highlightView.backgroundColor = UIColor.white.withAlphaComponent(0.35)
        highlightView.layer.cornerRadius = glassBlurView.layer.cornerRadius
        highlightView.alpha = 0.0
        glassBlurView.contentView.addSubview(highlightView)
        
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
            highlightView.alpha = 1.0
        } completion: { _ in
            UIView.animate(withDuration: 0.32, delay: 0, options: [.curveEaseIn]) {
                highlightView.alpha = 0.0
            } completion: { _ in
                highlightView.removeFromSuperview()
            }
        }
        
        let rippleLayer = CAShapeLayer()
        rippleLayer.path = UIBezierPath(ovalIn: glassBlurView.bounds).cgPath
        rippleLayer.fillColor = UIColor.white.withAlphaComponent(0.15).cgColor
        rippleLayer.frame = glassBlurView.bounds
        glassBlurView.layer.addSublayer(rippleLayer)
        
        let rippleScaleAnimation = CABasicAnimation(keyPath: "transform.scale")
        rippleScaleAnimation.fromValue = 0.5
        rippleScaleAnimation.toValue = 1.3
        rippleScaleAnimation.duration = 0.4
        rippleScaleAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        let rippleOpacityAnimation = CABasicAnimation(keyPath: "opacity")
        rippleOpacityAnimation.fromValue = 1.0
        rippleOpacityAnimation.toValue = 0.0
        rippleOpacityAnimation.duration = 0.4
        rippleOpacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            rippleLayer.removeFromSuperlayer()
        }
        rippleLayer.add(rippleScaleAnimation, forKey: "rippleScale")
        rippleLayer.add(rippleOpacityAnimation, forKey: "rippleOpacity")
        CATransaction.commit()
    }
    
    @objc private func swipeGesture(_ gesture: UISwipeGestureRecognizer) {
        if case .ended = gesture.state {
            self.containerNode.cancelGesture()
            
            switch gesture.direction {
            case .left:
                self.swiped?(.left)
            default:
                self.swiped?(.right)
            }
        }
    }
}

private final class TabBarNodeContainer {
    let item: UITabBarItem
    let updateBadgeListenerIndex: Int
    let updateTitleListenerIndex: Int
    let updateImageListenerIndex: Int
    let updateSelectedImageListenerIndex: Int
    
    let imageNode: TabBarItemNode
    let badgeContainerNode: ASDisplayNode
    let badgeBackgroundNode: ASImageNode
    let badgeTextNode: ImmediateTextNode
    
    var badgeValue: String?
    var appliedBadgeValue: String?
    
    var titleValue: String?
    var appliedTitleValue: String?
    
    var imageValue: UIImage?
    var appliedImageValue: UIImage?
    
    var selectedImageValue: UIImage?
    var appliedSelectedImageValue: UIImage?
    
    init(item: TabBarNodeItem, imageNode: TabBarItemNode, updateBadge: @escaping (String) -> Void, updateTitle: @escaping (String, Bool) -> Void, updateImage: @escaping (UIImage?) -> Void, updateSelectedImage: @escaping (UIImage?) -> Void, contextAction: @escaping (ContextExtractedContentContainingNode, ContextGesture) -> Void, swipeAction: @escaping (TabBarItemSwipeDirection) -> Void) {
        self.item = item.item
        
        self.imageNode = imageNode
        self.imageNode.isAccessibilityElement = true
        self.imageNode.accessibilityTraits = .button
        
        self.badgeContainerNode = ASDisplayNode()
        self.badgeContainerNode.isUserInteractionEnabled = false
        self.badgeContainerNode.isAccessibilityElement = false
        
        self.badgeBackgroundNode = ASImageNode()
        self.badgeBackgroundNode.isUserInteractionEnabled = false
        self.badgeBackgroundNode.displayWithoutProcessing = true
        self.badgeBackgroundNode.displaysAsynchronously = false
        self.badgeBackgroundNode.isAccessibilityElement = false
        
        self.badgeTextNode = ImmediateTextNode()
        self.badgeTextNode.maximumNumberOfLines = 1
        self.badgeTextNode.isUserInteractionEnabled = false
        self.badgeTextNode.displaysAsynchronously = false
        self.badgeTextNode.isAccessibilityElement = false
        
        self.badgeContainerNode.addSubnode(self.badgeBackgroundNode)
        self.badgeContainerNode.addSubnode(self.badgeTextNode)
        
        self.badgeValue = item.item.badgeValue ?? ""
        self.updateBadgeListenerIndex = UITabBarItem_addSetBadgeListener(item.item, { value in
            updateBadge(value ?? "")
        })
        
        self.titleValue = item.item.title
        self.updateTitleListenerIndex = item.item.addSetTitleListener { value, animated in
            updateTitle(value ?? "", animated)
        }
        
        self.imageValue = item.item.image
        self.updateImageListenerIndex = item.item.addSetImageListener { value in
            updateImage(value)
        }
        
        self.selectedImageValue = item.item.selectedImage
        self.updateSelectedImageListenerIndex = item.item.addSetSelectedImageListener { value in
            updateSelectedImage(value)
        }
        
        imageNode.containerNode.activated = { [weak self] gesture, _ in
            guard let strongSelf = self else {
                return
            }
            contextAction(strongSelf.imageNode.extractedContainerNode, gesture)
        }
        imageNode.swiped = { [weak imageNode] direction in
            guard let imageNode = imageNode, imageNode.isSelected else {
                return
            }
            swipeAction(direction)
        }
        imageNode.containerNode.isGestureEnabled = item.contextActionType != .none
        let contextActionType = item.contextActionType
        imageNode.containerNode.shouldBegin = { [weak imageNode] _ in
            switch contextActionType {
            case .none:
                return false
            case .always:
                return true
            case .whenActive:
                return imageNode?.isSelected ?? false
            }
        }
    }
    
    deinit {
        self.item.removeSetBadgeListener(self.updateBadgeListenerIndex)
        self.item.removeSetTitleListener(self.updateTitleListenerIndex)
        self.item.removeSetImageListener(self.updateImageListenerIndex)
        self.item.removeSetSelectedImageListener(self.updateSelectedImageListenerIndex)
    }
}

final class TabBarNodeItem {
    let item: UITabBarItem
    let contextActionType: TabBarItemContextActionType
    
    init(item: UITabBarItem, contextActionType: TabBarItemContextActionType) {
        self.item = item
        self.contextActionType = contextActionType
    }
}

class TabBarNode: ASDisplayNode, ASGestureRecognizerDelegate {
    var tabBarItems: [TabBarNodeItem] = [] {
        didSet {
            self.reloadTabBarItems()
        }
    }
    
    var reduceMotion: Bool = false
    
    var selectedIndex: Int? {
        didSet {
            if self.selectedIndex != oldValue {
                if let oldValue = oldValue {
                    self.updateNodeImage(oldValue, layout: true)
                }
                
                if let selectedIndex = self.selectedIndex {
                    self.updateNodeImage(selectedIndex, layout: true)
                }
            }
        }
    }
    
    private let itemSelected: (Int, Bool, [ASDisplayNode]) -> Void
    private let contextAction: (Int, ContextExtractedContentContainingNode, ContextGesture) -> Void
    private let swipeAction: (Int, TabBarItemSwipeDirection) -> Void
    
    private var theme: PresentationTheme
    private var validLayout: (CGSize, CGFloat, CGFloat, UIEdgeInsets, CGFloat)?
    private var horizontal: Bool = false
    private var centered: Bool = false
    
    private var badgeImage: UIImage
    
    let backgroundNode: NavigationBackgroundNode
    private var tabBarNodeContainers: [TabBarNodeContainer] = []
    
    private var tapRecognizer: TapLongTapOrDoubleTapGestureRecognizer?
    
    init(theme: PresentationTheme, itemSelected: @escaping (Int, Bool, [ASDisplayNode]) -> Void, contextAction: @escaping (Int, ContextExtractedContentContainingNode, ContextGesture) -> Void, swipeAction: @escaping (Int, TabBarItemSwipeDirection) -> Void) {
        self.itemSelected = itemSelected
        self.contextAction = contextAction
        self.swipeAction = swipeAction
        self.theme = theme
        
        self.backgroundNode = NavigationBackgroundNode(color: theme.rootController.tabBar.backgroundColor, enableBlur: false)
        
        self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.rootController.tabBar.badgeBackgroundColor, strokeColor: theme.rootController.tabBar.badgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
        
        super.init()
        
        self.isAccessibilityContainer = false
        self.accessibilityTraits = [.tabBar]
        
        self.isOpaque = false
        self.backgroundColor = nil
        
        self.isExclusiveTouch = true
        
        self.addSubnode(self.backgroundNode)
    }
    
    override func didLoad() {
        super.didLoad()
        
        let recognizer = TapLongTapOrDoubleTapGestureRecognizer(target: self, action: #selector(self.tapLongTapOrDoubleTapGesture(_:)))
        recognizer.delegate = self.wrappedGestureRecognizerDelegate
        recognizer.tapActionAtPoint = { _ in
            return .keepWithSingleTap
        }
        self.tapRecognizer = recognizer
        self.view.addGestureRecognizer(recognizer)
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if otherGestureRecognizer is UIPanGestureRecognizer {
            return false
        }
        return true
    }
    
    @objc private func tapLongTapOrDoubleTapGesture(_ recognizer: TapLongTapOrDoubleTapGestureRecognizer) {
        switch recognizer.state {
        case .ended:
            if let (gesture, location) = recognizer.lastRecognizedGestureAndLocation {
                if case .tap = gesture {
                    self.tapped(at: location, longTap: false)
                }
            }
        default:
            break
        }
    }
    
    func updateTheme(_ theme: PresentationTheme) {
        if self.theme !== theme {
            self.theme = theme
            
            self.backgroundNode.updateColor(color: theme.rootController.tabBar.backgroundColor, enableBlur: false, transition: .immediate)
            
            self.badgeImage = generateStretchableFilledCircleImage(diameter: 18.0, color: theme.rootController.tabBar.badgeBackgroundColor, strokeColor: theme.rootController.tabBar.badgeStrokeColor, strokeWidth: 1.0, backgroundColor: nil)!
            for container in self.tabBarNodeContainers {
                if let attributedText = container.badgeTextNode.attributedText, !attributedText.string.isEmpty {
                    container.badgeTextNode.attributedText = NSAttributedString(string: attributedText.string, font: badgeFont, textColor: theme.rootController.tabBar.badgeTextColor)
                }
            }
            
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
                
                self.tabBarNodeContainers[i].badgeBackgroundNode.image = self.badgeImage
            }
            
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    func frameForControllerTab(at index: Int) -> CGRect? {
        let container = self.tabBarNodeContainers[index]
        return container.imageNode.frame
    }
    
    func viewForControllerTab(at index: Int) -> UIView? {
        let container = self.tabBarNodeContainers[index]
        return container.imageNode.view
    }
    
    private func reloadTabBarItems() {
        for node in self.tabBarNodeContainers {
            node.imageNode.removeFromSupernode()
        }
        
        self.centered = self.theme.rootController.tabBar.textColor == .clear
        
        var tabBarNodeContainers: [TabBarNodeContainer] = []
        for i in 0 ..< self.tabBarItems.count {
            let item = self.tabBarItems[i]
            let node = TabBarItemNode()
            let container = TabBarNodeContainer(item: item, imageNode: node, updateBadge: { [weak self] value in
                self?.updateNodeBadge(i, value: value)
            }, updateTitle: { [weak self] _, _ in
                self?.updateNodeImage(i, layout: true)
            }, updateImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            }, updateSelectedImage: { [weak self] _ in
                self?.updateNodeImage(i, layout: true)
            }, contextAction: { [weak self] node, gesture in
                self?.tapRecognizer?.cancel()
                self?.contextAction(i, node, gesture)
            }, swipeAction: { [weak self] direction in
                self?.swipeAction(i, direction)
            })
            if item.item.ringSelection {
                node.ringColor = self.theme.rootController.tabBar.selectedIconColor
            } else {
                node.ringColor = nil
            }
            
            if let selectedIndex = self.selectedIndex, selectedIndex == i {
                let (textImage, contentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth): (UIImage, CGFloat)
                
                if let _ = item.item.animationName {
                    (image, imageContentWidth) = (UIImage(), 0.0)
                    
                    node.animationNode.isHidden = false
                    let animationSize: Int = Int(51.0 * UIScreen.main.scale)
                    node.animationNode.visibility = true
                    if !node.isSelected {
                        node.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: item.item.animationName ?? ""), width: animationSize, height: animationSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
                    }
                    node.animationNode.setOverlayColor(self.theme.rootController.tabBar.selectedIconColor, replace: true, animated: false)
                    node.animationNode.updateLayout(size: CGSize(width: 51.0, height: 51.0))
                } else {
                    (image, imageContentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                    
                    node.animationNode.isHidden = true
                    node.animationNode.visibility = false
                }
                
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                node.textImageNode.image = textImage
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button, .selected]
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = true
            } else {
                let (textImage, contentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.textColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.iconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                
                node.animationNode.isHidden = true
                node.animationNode.visibility = false
                
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = false
            }
            container.badgeBackgroundNode.image = self.badgeImage
            node.extractedContainerNode.contentNode.addSubnode(container.badgeContainerNode)
            tabBarNodeContainers.append(container)
            self.addSubnode(node)
        }
        
        self.tabBarNodeContainers = tabBarNodeContainers
        
        self.setNeedsLayout()
    }
    
    private func updateNodeImage(_ index: Int, layout: Bool) {
        if index < self.tabBarNodeContainers.count && index < self.tabBarItems.count {
            let node = self.tabBarNodeContainers[index].imageNode
            let item = self.tabBarItems[index]
            
            self.centered = self.theme.rootController.tabBar.textColor == .clear
            
            if item.item.ringSelection {
                node.ringColor = self.theme.rootController.tabBar.selectedIconColor
            } else {
                node.ringColor = nil
            }
            
            let previousImageSize = node.imageNode.image?.size ?? CGSize()
            let previousTextImageSize = node.textImageNode.image?.size ?? CGSize()
            let wasSelected = node.isSelected
            
            if let selectedIndex = self.selectedIndex, selectedIndex == index {
                let (textImage, contentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedTextColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (image, imageContentWidth): (UIImage, CGFloat)
                if let _ = item.item.animationName {
                    (image, imageContentWidth) = (UIImage(), 0.0)
                    
                    node.animationNode.isHidden = false
                    let animationSize: Int = Int(51.0 * UIScreen.main.scale)
                    node.animationNode.visibility = true
                    if !node.isSelected {
                        node.animationNode.setup(source: AnimatedStickerNodeLocalFileSource(name: item.item.animationName ?? ""), width: animationSize, height: animationSize, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
                    }
                    node.animationNode.setOverlayColor(self.theme.rootController.tabBar.selectedIconColor, replace: true, animated: false)
                    node.animationNode.updateLayout(size: CGSize(width: 51.0, height: 51.0))
                } else {
                    if item.item.ringSelection {
                        (image, imageContentWidth) = (item.item.selectedImage ?? UIImage(), item.item.selectedImage?.size.width ?? 0.0)
                    } else {
                        (image, imageContentWidth) = tabBarItemImage(item.item.selectedImage, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.selectedIconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                    }
                    
                    node.animationNode.isHidden = true
                    node.animationNode.visibility = false
                }
                
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button, .selected]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = true
                
                node.updateGlassEffect(isSelected: true, theme: self.theme, animated: !wasSelected)
                
                if !self.reduceMotion && item.item.ringSelection {
                    ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateTransformScale(node: node.ringImageNode, scale: 1.0, delay: 0.1)
                    node.imageNode.layer.animateScale(from: 1.0, to: 0.87, duration: 0.1, removeOnCompletion: false, completion: { [weak node] _ in
                        node?.imageNode.layer.animateScale(from: 0.87, to: 1.0, duration: 0.14, removeOnCompletion: false, completion: { [weak node] _ in
                            node?.imageNode.layer.removeAllAnimations()
                        })
                    })
                }
            } else {
                let (textImage, contentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.textColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                
                let (image, imageContentWidth): (UIImage, CGFloat)
                if item.item.ringSelection {
                    (image, imageContentWidth) = (item.item.image ?? UIImage(), item.item.image?.size.width ?? 0.0)
                } else {
                    (image, imageContentWidth) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.rootController.tabBar.iconColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                }
                let (contextTextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: false, centered: self.centered)
                let (contextImage, _) = tabBarItemImage(item.item.image, title: item.item.title ?? "", backgroundColor: .clear, tintColor: self.theme.contextMenu.extractedContentTintColor, horizontal: self.horizontal, imageMode: true, centered: self.centered)
                
                node.animationNode.stop()
                node.animationNode.isHidden = true
                node.animationNode.visibility = false
                
                node.textImageNode.image = textImage
                node.accessibilityLabel = item.item.title
                node.accessibilityTraits = [.button]
                node.imageNode.image = image
                node.contextTextImageNode.image = contextTextImage
                node.contextImageNode.image = contextImage
                node.contentWidth = max(contentWidth, imageContentWidth)
                node.isSelected = false
                
                node.updateGlassEffect(isSelected: false, theme: self.theme, animated: wasSelected)
                
                ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut).updateTransformScale(node: node.ringImageNode, scale: 0.5)
            }
            
            let updatedImageSize = node.imageNode.image?.size ?? CGSize()
            let updatedTextImageSize = node.textImageNode.image?.size ?? CGSize()
            
            if previousImageSize != updatedImageSize || previousTextImageSize != updatedTextImageSize {
                if let validLayout = self.validLayout, layout {
                    self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
                }
            }
        }
    }
    
    private func updateNodeBadge(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].badgeValue = value
        if self.tabBarNodeContainers[index].badgeValue != self.tabBarNodeContainers[index].appliedBadgeValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    private func updateNodeTitle(_ index: Int, value: String) {
        self.tabBarNodeContainers[index].titleValue = value
        if self.tabBarNodeContainers[index].titleValue != self.tabBarNodeContainers[index].appliedTitleValue {
            if let validLayout = self.validLayout {
                self.updateLayout(size: validLayout.0, leftInset: validLayout.1, rightInset: validLayout.2, additionalSideInsets: validLayout.3, bottomInset: validLayout.4, transition: .immediate)
            }
        }
    }
    
    func updateLayout(size: CGSize, leftInset: CGFloat, rightInset: CGFloat, additionalSideInsets: UIEdgeInsets, bottomInset: CGFloat, transition: ContainedViewLayoutTransition) {
        self.validLayout = (size, leftInset, rightInset, additionalSideInsets, bottomInset)
        
        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: size))
        self.backgroundNode.update(size: size, transition: transition)
        
        let horizontal = !leftInset.isZero
        if self.horizontal != horizontal {
            self.horizontal = horizontal
            for i in 0 ..< self.tabBarItems.count {
                self.updateNodeImage(i, layout: false)
            }
        }
        
        if self.tabBarNodeContainers.count != 0 {
            var tabBarNodeContainers = self.tabBarNodeContainers
            var width = size.width
            
            var callsTabBarNodeContainer: TabBarNodeContainer?
            if tabBarNodeContainers.count == 4 {
                callsTabBarNodeContainer = tabBarNodeContainers[1]
            }
            
            if additionalSideInsets.right > 0.0 {
                width -= additionalSideInsets.right
                
                if let callsTabBarNodeContainer = callsTabBarNodeContainer {
                    tabBarNodeContainers.remove(at: 1)
                    transition.updateAlpha(node: callsTabBarNodeContainer.imageNode, alpha: 0.0)
                    callsTabBarNodeContainer.imageNode.isUserInteractionEnabled = false
                }
            } else {
                if let callsTabBarNodeContainer = callsTabBarNodeContainer {
                    transition.updateAlpha(node: callsTabBarNodeContainer.imageNode, alpha: 1.0)
                    callsTabBarNodeContainer.imageNode.isUserInteractionEnabled = true
                }
            }
            
            let distanceBetweenNodes = width / CGFloat(tabBarNodeContainers.count)
            
            let internalWidth = distanceBetweenNodes * CGFloat(tabBarNodeContainers.count - 1)
            let leftNodeOriginX = (width - internalWidth) / 2.0
            
            for i in 0 ..< tabBarNodeContainers.count {
                let container = tabBarNodeContainers[i]
                let node = container.imageNode
                let nodeSize = node.textImageNode.image?.size ?? CGSize()
                
                let originX = floor(leftNodeOriginX + CGFloat(i) * distanceBetweenNodes - nodeSize.width / 2.0)
                let horizontalHitTestInset = distanceBetweenNodes / 2.0 - nodeSize.width / 2.0
                let nodeFrame = CGRect(origin: CGPoint(x: originX, y: 3.0), size: nodeSize)
                transition.updateFrame(node: node, frame: nodeFrame)
                node.extractedContainerNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.extractedContainerNode.contentNode.frame = node.extractedContainerNode.bounds
                node.extractedContainerNode.contentRect = node.extractedContainerNode.bounds
                node.containerNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.hitTestSlop = UIEdgeInsets(top: -3.0, left: -horizontalHitTestInset, bottom: -3.0, right: -horizontalHitTestInset)
                node.containerNode.hitTestSlop = UIEdgeInsets(top: -3.0, left: -horizontalHitTestInset, bottom: -3.0, right: -horizontalHitTestInset)
                node.accessibilityFrame = nodeFrame.insetBy(dx: -horizontalHitTestInset, dy: 0.0).offsetBy(dx: 0.0, dy: size.height - nodeSize.height - bottomInset)
                if node.ringColor == nil {
                    node.imageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                }
                node.textImageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.contextImageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                node.contextTextImageNode.frame = CGRect(origin: CGPoint(), size: nodeFrame.size)
                
                let scaleFactor: CGFloat = horizontal ? 0.8 : 1.0
                node.animationContainerNode.subnodeTransform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1.0)
                let animationOffset: CGPoint = self.tabBarItems[i].item.animationOffset
                let ringImageFrame: CGRect
                let imageFrame: CGRect
                if horizontal {
                    node.animationNode.frame = CGRect(origin: CGPoint(x: -10.0 - UIScreenPixel, y: -4.0 - UIScreenPixel), size: CGSize(width: 51.0, height: 51.0))
                    ringImageFrame = CGRect(origin: CGPoint(x: UIScreenPixel, y: 5.0 + UIScreenPixel), size: CGSize(width: 23.0, height: 23.0))
                    imageFrame = ringImageFrame.insetBy(dx: -1.0 + UIScreenPixel, dy: -1.0 + UIScreenPixel)
                } else {
                    node.animationNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((nodeSize.width - 51.0) / 2.0), y: -10.0 - UIScreenPixel).offsetBy(dx: animationOffset.x, dy: animationOffset.y), size: CGSize(width: 51.0, height: 51.0))
                    ringImageFrame = CGRect(origin: CGPoint(x: floorToScreenPixels((nodeSize.width - 29.0) / 2.0), y: 1.0), size: CGSize(width: 29.0, height: 29.0))
                    imageFrame = ringImageFrame.insetBy(dx: -1.0, dy: -1.0)
                }
                node.ringImageNode.bounds = CGRect(origin: CGPoint(), size: ringImageFrame.size)
                node.ringImageNode.position = ringImageFrame.center
                
                if node.ringColor != nil {
                    node.imageNode.bounds = CGRect(origin: CGPoint(), size: imageFrame.size)
                    node.imageNode.position = imageFrame.center
                }
                
                if container.badgeValue != container.appliedBadgeValue {
                    container.appliedBadgeValue = container.badgeValue
                    if let badgeValue = container.badgeValue, !badgeValue.isEmpty {
                        container.badgeTextNode.attributedText = NSAttributedString(string: badgeValue, font: badgeFont, textColor: self.theme.rootController.tabBar.badgeTextColor)
                        container.badgeContainerNode.isHidden = false
                    } else {
                        container.badgeContainerNode.isHidden = true
                    }
                }
                
                if !container.badgeContainerNode.isHidden {
                    var hasSingleLetterValue: Bool = false
                    if let string = container.badgeTextNode.attributedText?.string {
                        hasSingleLetterValue = string.count == 1
                    }
                    let badgeSize = container.badgeTextNode.updateLayout(CGSize(width: 200.0, height: 100.0))
                    let backgroundSize = CGSize(width: hasSingleLetterValue ? 18.0 : max(18.0, badgeSize.width + 10.0 + 1.0), height: 18.0)
                    let backgroundFrame: CGRect
                    if horizontal {
                        backgroundFrame = CGRect(origin: CGPoint(x: 13.0, y: 0.0), size: backgroundSize)
                    } else {
                        let contentWidth: CGFloat = 25.0
                        backgroundFrame = CGRect(origin: CGPoint(x: floor(node.frame.width / 2.0) + contentWidth - backgroundSize.width - 5.0, y: self.centered ? 6.0 : -1.0), size: backgroundSize)
                    }
                    transition.updateFrame(node: container.badgeContainerNode, frame: backgroundFrame)
                    container.badgeBackgroundNode.frame = CGRect(origin: CGPoint(), size: backgroundFrame.size)
                    
                    container.badgeContainerNode.subnodeTransform = CATransform3DMakeScale(scaleFactor, scaleFactor, 1.0)
                    
                    container.badgeTextNode.frame = CGRect(origin: CGPoint(x: floorToScreenPixels((backgroundFrame.size.width - badgeSize.width) / 2.0), y: 1.0), size: badgeSize)
                }
            }
        }
    }
    
    private func tapped(at location: CGPoint, longTap: Bool) {
        if let bottomInset = self.validLayout?.4 {
            if location.y > self.bounds.size.height - bottomInset {
                return
            }
            var closestNode: (Int, CGFloat)?
            for i in 0 ..< self.tabBarNodeContainers.count {
                let node = self.tabBarNodeContainers[i].imageNode
                if !node.isUserInteractionEnabled {
                    continue
                }
                let distance = abs(location.x - node.position.x)
                if let previousClosestNode = closestNode {
                    if previousClosestNode.1 > distance {
                        closestNode = (i, distance)
                    }
                } else {
                    closestNode = (i, distance)
                }
            }
            
            if let closestNode = closestNode {
                let container = self.tabBarNodeContainers[closestNode.0]
                let previousSelectedIndex = self.selectedIndex
                
                if closestNode.0 == previousSelectedIndex {
                    container.imageNode.animateTapInteraction()
                }
                
                self.itemSelected(closestNode.0, longTap, [container.imageNode.imageNode, container.imageNode.textImageNode, container.badgeContainerNode])
                if previousSelectedIndex != closestNode.0 {
                    if let selectedIndex = self.selectedIndex, let _ = self.tabBarItems[selectedIndex].item.animationName {
                        container.imageNode.animationNode.play(firstFrame: false, fromIndex: nil)
                    }
                    container.imageNode.animateTapInteraction()
                }
            }
        }
    }
}
