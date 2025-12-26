import Foundation
import UIKit
import Display
import TelegramPresentationData
import ComponentFlow
import ComponentDisplayAdapters
import MultilineTextComponent
import LottieComponent
import UIKitRuntimeUtils
import BundleIconComponent
import TextBadgeComponent

private final class LiquidGlassLensView: UIView {
    
    
    private let containerView: UIView
    private let blurView: UIVisualEffectView
    private let highlightLayer: CAGradientLayer
    private let borderLayer: CAShapeLayer
    private let contentLayer: CALayer
    
    private static let sharedCIContext: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()
    
    private var cachedSnapshotImage: CGImage?
    private var cachedSnapshotFrame: CGRect = .zero
    
    private var displayLink: CADisplayLink?
    private var isAnimating: Bool = false
    
    
    private struct Config {
        static let blurRadius: CGFloat = 1.5
        
        static let refractionScale: CGFloat = 0.25
        static let refractionRadiusFactor: CGFloat = 0.85
        
        static let chromaticAberrationEnabled: Bool = false
        static let chromaticOffset: CGFloat = 0.8
        
        static let highlightHeightRatio: CGFloat = 0.5
        
        static let borderWidth: CGFloat = 0.5
        
        static let shadowRadius: CGFloat = 6.0
        static let shadowOpacity: Float = 0.18
        static let shadowOffset = CGSize(width: 0, height: 2.0)
        
        static let stretchDuration: TimeInterval = 0.55
        static let stretchDamping: CGFloat = 0.7
        static let stretchVelocity: CGFloat = 0.3
        static let verticalSquish: CGFloat = 0.94
        
        static let tapScaleDown: CGFloat = 0.95
        static let tapScaleDuration: TimeInterval = 0.08
        static let tapBounceDamping: CGFloat = 0.6
    }
    
    override init(frame: CGRect) {
        self.containerView = UIView()
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        self.highlightLayer = CAGradientLayer()
        self.borderLayer = CAShapeLayer()
        self.contentLayer = CALayer()
        
        super.init(frame: frame)
        
        setupViews()
        setupLayers()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        stopDisplayLink()
    }
    
    private func setupViews() {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        
        containerView.clipsToBounds = true
        addSubview(containerView)
        
        blurView.clipsToBounds = true
        blurView.alpha = 0.85
        containerView.addSubview(blurView)
    }
    
    private func setupLayers() {
        contentLayer.masksToBounds = true
        contentLayer.contentsGravity = .resizeAspectFill
        blurView.contentView.layer.insertSublayer(contentLayer, at: 0)
        
        highlightLayer.type = .axial
        highlightLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        highlightLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        blurView.contentView.layer.addSublayer(highlightLayer)
        
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = Config.borderWidth
        layer.addSublayer(borderLayer)
        
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowRadius = Config.shadowRadius
        layer.shadowOpacity = Config.shadowOpacity
        layer.shadowOffset = Config.shadowOffset
    }
    
    func updateStyle(isDark: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        if isDark {
            highlightLayer.colors = [
                UIColor.white.withAlphaComponent(0.22).cgColor,
                UIColor.white.withAlphaComponent(0.06).cgColor,
                UIColor.clear.cgColor
            ]
            highlightLayer.locations = [0.0, 0.4, 1.0]
            borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
            layer.shadowOpacity = 0.22
            layer.shadowColor = UIColor.black.cgColor
            blurView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            blurView.alpha = 0.92
        } else {
            highlightLayer.colors = [
                UIColor.white.withAlphaComponent(0.55).cgColor,
                UIColor.white.withAlphaComponent(0.15).cgColor,
                UIColor.clear.cgColor
            ]
            highlightLayer.locations = [0.0, 0.45, 1.0]
            borderLayer.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
            layer.shadowOpacity = Config.shadowOpacity
            layer.shadowColor = UIColor(white: 0, alpha: 1).cgColor
            blurView.effect = UIBlurEffect(style: .systemUltraThinMaterialLight)
            blurView.alpha = 0.88
        }
        
        CATransaction.commit()
    }
    
    func updateSnapshot(from sourceView: UIView, in rect: CGRect, excluding excludedView: UIView? = nil) {
        guard isAnimating else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            contentLayer.contents = nil
            contentLayer.isHidden = true
            CATransaction.commit()
            return
        }
        
        guard rect.width > 0, rect.height > 0 else { return }
        guard let window = sourceView.window else { return }
        
        let scale = min(window.screen.scale, 2.0)
        
        let wasHidden = isHidden
        isHidden = true
        
        var hiddenViews: [(UIView, Bool)] = []
        if let excludedView = excludedView {
            func hideRecursively(_ view: UIView) {
                hiddenViews.append((view, view.isHidden))
                view.isHidden = true
                for subview in view.subviews {
                    hideRecursively(subview)
                }
            }
            hideRecursively(excludedView)
        }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        
        let renderer = UIGraphicsImageRenderer(size: rect.size, format: format)
        let image = renderer.image { ctx in
            ctx.cgContext.translateBy(x: -rect.origin.x, y: -rect.origin.y)
            sourceView.layer.render(in: ctx.cgContext)
        }
        
        isHidden = wasHidden
        for (view, wasHiddenBefore) in hiddenViews.reversed() {
            view.isHidden = wasHiddenBefore
        }
        
        guard let cgImage = applyLensEffect(to: image) else { return }
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = cgImage
        
        contentLayer.isHidden = false
        CATransaction.commit()
    }
    
    private func applyLensEffect(to image: UIImage) -> CGImage? {
        guard var ciImage = CIImage(image: image) else { return nil }
        let extent = ciImage.extent
        
        guard extent.width > 0, extent.height > 0 else { return nil }
        
        let center = CIVector(x: extent.midX, y: extent.midY)
        
        let radius = min(extent.width, extent.height) * Config.refractionRadiusFactor
        
        if let bumpFilter = CIFilter(name: "CIBumpDistortion") {
            bumpFilter.setValue(ciImage, forKey: kCIInputImageKey)
            bumpFilter.setValue(center, forKey: kCIInputCenterKey)
            bumpFilter.setValue(radius, forKey: kCIInputRadiusKey)
            bumpFilter.setValue(Config.refractionScale, forKey: kCIInputScaleKey)
            
            if let output = bumpFilter.outputImage?.cropped(to: extent) {
                ciImage = output
            }
        }
        
        if Config.blurRadius > 0, let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.setValue(ciImage, forKey: kCIInputImageKey)
            blurFilter.setValue(Config.blurRadius, forKey: kCIInputRadiusKey)
            
            if let output = blurFilter.outputImage?.cropped(to: extent) {
                ciImage = output
            }
        }
        
        return Self.sharedCIContext.createCGImage(ciImage, from: extent)
    }
    
    func invalidateSnapshot() {
        cachedSnapshotImage = nil
        cachedSnapshotFrame = .zero
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        let bounds = self.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        
        let cornerRadius = bounds.height / 2.0
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        
        containerView.frame = bounds
        containerView.layer.cornerRadius = cornerRadius
        
        blurView.frame = bounds
        blurView.layer.cornerRadius = cornerRadius
        
        contentLayer.frame = bounds
        contentLayer.cornerRadius = cornerRadius
        
        let highlightHeight = bounds.height * Config.highlightHeightRatio
        highlightLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: highlightHeight)
        
        let borderInset = Config.borderWidth / 2.0
        let borderPath = UIBezierPath(
            roundedRect: bounds.insetBy(dx: borderInset, dy: borderInset),
            cornerRadius: cornerRadius - borderInset
        )
        borderLayer.path = borderPath.cgPath
        borderLayer.frame = bounds
        
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: cornerRadius).cgPath
        
        CATransaction.commit()
    }
    
    func animateTap() {
        createGhostPillEffect()
        
        UIView.animate(
            withDuration: 0.1,
            delay: 0,
            options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        } completion: { _ in
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                usingSpringWithDamping: 0.5,
                initialSpringVelocity: 1.0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = .identity
            }
        }
    }
    
    
    func createGhostAtFrame(_ frame: CGRect, in containerView: UIView) {
        let ghostStartFrame = frame
        
        let ghost = UIView(frame: ghostStartFrame)
        ghost.isUserInteractionEnabled = false
        ghost.clipsToBounds = false
        
        ghost.backgroundColor = UIColor.white.withAlphaComponent(0.12)
        ghost.layer.cornerRadius = ghostStartFrame.height / 2.0
        
        ghost.layer.borderWidth = 1.0
        ghost.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        
        ghost.layer.shadowColor = UIColor.black.cgColor
        ghost.layer.shadowOffset = CGSize(width: 0, height: 3)
        ghost.layer.shadowRadius = 8
        ghost.layer.shadowOpacity = 0.2
        ghost.layer.masksToBounds = false
        
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        blur.frame = ghost.bounds
        blur.layer.cornerRadius = ghostStartFrame.height / 2.0
        blur.clipsToBounds = true
        blur.alpha = 0.5
        ghost.addSubview(blur)
        
        containerView.insertSubview(ghost, belowSubview: self)
        ghost.alpha = 1.0
        
        let expandAmount: CGFloat = 10.0
        
        let targetFrame = CGRect(
            x: ghostStartFrame.minX - expandAmount,
            y: ghostStartFrame.minY - expandAmount,
            width: ghostStartFrame.width + expandAmount * 2,
            height: ghostStartFrame.height + expandAmount * 2
        )
        let targetRadius = targetFrame.height / 2.0
        
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseOut, .allowUserInteraction]
        ) {
            ghost.frame = targetFrame
            ghost.layer.cornerRadius = targetRadius
            blur.frame = ghost.bounds
            blur.layer.cornerRadius = targetRadius
        } completion: { _ in
            UIView.animate(
                withDuration: 0.5,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction]
            ) {
                ghost.alpha = 0.0
            } completion: { _ in
                ghost.removeFromSuperview()
            }
        }
    }
    
    private func createGhostPillEffect() {
        guard let containerView = self.superview?.superview ?? self.window else {
            return
        }
        
        let frameInContainer = self.convert(self.bounds, to: containerView)
        
        let initialCornerRadius = frameInContainer.height / 2.0
        
        let ghostPill = UIView(frame: frameInContainer)
        ghostPill.backgroundColor = UIColor.white.withAlphaComponent(0.15)
        ghostPill.layer.cornerRadius = initialCornerRadius
        ghostPill.isUserInteractionEnabled = false
        
        ghostPill.layer.borderWidth = 1.5
        ghostPill.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        
        ghostPill.layer.shadowColor = UIColor.black.cgColor
        ghostPill.layer.shadowOffset = CGSize(width: 0, height: 4)
        ghostPill.layer.shadowRadius = 10
        ghostPill.layer.shadowOpacity = 0.3
        ghostPill.layer.masksToBounds = false
        
        let blurEffect = UIBlurEffect(style: .systemChromeMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.frame = ghostPill.bounds
        blurView.layer.cornerRadius = initialCornerRadius
        blurView.clipsToBounds = true
        blurView.alpha = 0.6
        ghostPill.insertSubview(blurView, at: 0)
        
        containerView.addSubview(ghostPill)
        
        containerView.bringSubviewToFront(ghostPill)
        
        ghostPill.alpha = 1.0
        ghostPill.transform = .identity
        
        let expandUpward: CGFloat = 35.0
        let expandHorizontal: CGFloat = 1.2
        
        let targetWidth = frameInContainer.width * expandHorizontal
        let targetHeight = frameInContainer.height + expandUpward
        let targetX = frameInContainer.midX - targetWidth / 2.0
        let targetY = frameInContainer.minY - expandUpward
        
        let targetFrame = CGRect(x: targetX, y: targetY, width: targetWidth, height: targetHeight)
        let targetCornerRadius = targetHeight / 2.5
        
        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            usingSpringWithDamping: 0.55,
            initialSpringVelocity: 1.2,
            options: [.allowUserInteraction, .curveEaseOut]
        ) {
            ghostPill.frame = targetFrame
            ghostPill.layer.cornerRadius = targetCornerRadius
            ghostPill.alpha = 0.0
            ghostPill.layer.borderColor = UIColor.clear.cgColor
            blurView.frame = ghostPill.bounds
            blurView.layer.cornerRadius = targetCornerRadius
        } completion: { _ in
            ghostPill.removeFromSuperview()
        }
    }
    
    func animateStretch(
        to targetFrame: CGRect,
        duration: TimeInterval = Config.stretchDuration,
        completion: (() -> Void)? = nil
    ) {
        let startFrame = self.frame
        guard startFrame != .zero, !startFrame.equalTo(targetFrame) else {
            self.frame = targetFrame
            layoutSubviews()
            completion?()
            return
        }
        
        invalidateSnapshot()
        
        self.animationStartFrame = startFrame
        self.animationTargetFrame = targetFrame
        self.animationSourceView = superview
        self.animationStartTime = CACurrentMediaTime()
        self.animationDuration = duration
        startDisplayLink()
        
        let stretchMinX = min(startFrame.minX, targetFrame.minX)
        let stretchMaxX = max(startFrame.maxX, targetFrame.maxX)
        let stretchWidth = stretchMaxX - stretchMinX
        
        let centerY = startFrame.midY
        
        let normalHeight = startFrame.height
        let stretchedHeight = normalHeight * 0.94
        
        UIView.animateKeyframes(
            withDuration: duration,
            delay: 0,
            options: [.calculationModeCubic, .allowUserInteraction]
        ) {
            UIView.addKeyframe(withRelativeStartTime: 0.0, relativeDuration: 0.45) {
                self.frame = CGRect(
                    x: stretchMinX,
                    y: centerY - stretchedHeight / 2.0,
                    width: stretchWidth,
                    height: stretchedHeight
                )
                self.layoutSubviews()
            }
            
            UIView.addKeyframe(withRelativeStartTime: 0.45, relativeDuration: 0.55) {
                self.frame = targetFrame
                self.layoutSubviews()
            }
            
        } completion: { [weak self] _ in
            guard let self else { return }
            self.stopDisplayLink()
            self.animationStartFrame = nil
            self.animationTargetFrame = nil
            self.animationSourceView = nil
            self.animationStartTime = nil
            self.animationDuration = nil
            self.invalidateSnapshot()
            
            completion?()
        }
    }
    
    
    private var animationStartFrame: CGRect?
    private var animationTargetFrame: CGRect?
    private weak var animationSourceView: UIView?
    private var animationStartTime: CFTimeInterval?
    private var animationDuration: TimeInterval?
    
    func setFrame(_ frame: CGRect, animated: Bool) {
        if animated {
            UIView.animate(
                withDuration: 0.22,
                delay: 0,
                usingSpringWithDamping: 0.85,
                initialSpringVelocity: 0.4,
                options: [.allowUserInteraction]
            ) {
                self.frame = frame
                self.layoutSubviews()
            }
        } else {
            self.frame = frame
            layoutSubviews()
        }
    }
    
    private func startDisplayLink() {
        guard displayLink == nil else { return }
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        displayLink?.add(to: .main, forMode: .common)
        isAnimating = true
    }
    
    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        isAnimating = false
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = nil
        contentLayer.isHidden = true
        CATransaction.commit()
    }
    
    @objc private func displayLinkFired() {
        guard isAnimating,
              let sourceView = animationSourceView else { return }
        
        guard let presentationFrame = layer.presentation()?.frame,
              presentationFrame.width > 0, presentationFrame.height > 0 else { return }
        
        cachedSnapshotImage = nil
        cachedSnapshotFrame = .zero
        
        updateSnapshot(from: sourceView, in: presentationFrame, excluding: nil)
    }
}

public final class TabBarComponent: Component {
    
    public final class Item: Equatable {
        public let item: UITabBarItem
        public let action: (Bool) -> Void
        public let contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?
        
        fileprivate var id: AnyHashable {
            return AnyHashable(ObjectIdentifier(self.item))
        }
        
        public init(
            item: UITabBarItem,
            action: @escaping (Bool) -> Void,
            contextAction: ((ContextGesture, ContextExtractedContentContainingView) -> Void)?
        ) {
            self.item = item
            self.action = action
            self.contextAction = contextAction
        }
        
        public static func ==(lhs: Item, rhs: Item) -> Bool {
            if lhs === rhs { return true }
            if lhs.item !== rhs.item { return false }
            if (lhs.contextAction == nil) != (rhs.contextAction == nil) { return false }
            return true
        }
    }
    
    public let theme: PresentationTheme
    public let items: [Item]
    public let selectedId: AnyHashable?
    public let isTablet: Bool
    
    public init(
        theme: PresentationTheme,
        items: [Item],
        selectedId: AnyHashable?,
        isTablet: Bool
    ) {
        self.theme = theme
        self.items = items
        self.selectedId = selectedId
        self.isTablet = isTablet
    }
    
    public static func ==(lhs: TabBarComponent, rhs: TabBarComponent) -> Bool {
        if lhs.theme !== rhs.theme { return false }
        if lhs.items != rhs.items { return false }
        if lhs.selectedId != rhs.selectedId { return false }
        if lhs.isTablet != rhs.isTablet { return false }
        return true
    }
    
    
    public final class View: UIView, UITabBarDelegate, UIGestureRecognizerDelegate {
        
        private let barBackgroundView: UIView
        private let contextGestureContainerView: ContextControllerSourceView
        private let nativeTabBar: UITabBar?
        private var liquidGlassLens: LiquidGlassLensView?
        private var lastSelectedId: AnyHashable?
        private var itemViews: [AnyHashable: ComponentView<Empty>] = [:]
        private var selectedItemViews: [AnyHashable: ComponentView<Empty>] = [:]
        private var itemWithActiveContextGesture: AnyHashable?
        private var component: TabBarComponent?
        private weak var state: EmptyComponentState?
        private var firstItemView: UIView?
        
        private struct Layout {
            static let innerInset: CGFloat = 4.0
            
            static let itemHeight: CGFloat = 52.0
            
            static let maxItemWidth: CGFloat = 88.0
            
            static let pillHorizontalPadding: CGFloat = 6.0
            
            static let pillVerticalPadding: CGFloat = 2.0
        }
        
        public override init(frame: CGRect) {
            self.barBackgroundView = UIView()
            self.contextGestureContainerView = ContextControllerSourceView()
            self.contextGestureContainerView.isGestureEnabled = true
            
            if #available(iOS 26.0, *) {
                let nativeTabBar = UITabBar()
                self.nativeTabBar = nativeTabBar
            } else {
                self.nativeTabBar = nil
            }
            
            super.init(frame: frame)
            
            setupTraitOverrides()
            setupViewHierarchy()
            setupGestures()
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @available(iOS 26.0, *)
        private func configureNativeTabBar(_ tabBar: UITabBar) {
            let itemFont = Font.semibold(10.0)
            let itemColor: UIColor = .clear
            
            tabBar.traitOverrides.verticalSizeClass = .compact
            tabBar.traitOverrides.horizontalSizeClass = .compact
            
            for appearance in [
                tabBar.standardAppearance.stackedLayoutAppearance,
                tabBar.standardAppearance.inlineLayoutAppearance,
                tabBar.standardAppearance.compactInlineLayoutAppearance
            ] {
                appearance.normal.titleTextAttributes = [.foregroundColor: itemColor, .font: itemFont]
                appearance.selected.titleTextAttributes = [.foregroundColor: itemColor, .font: itemFont]
            }
        }
        
        private func setupTraitOverrides() {
            if #available(iOS 17.0, *) {
                traitOverrides.verticalSizeClass = .compact
                traitOverrides.horizontalSizeClass = .compact
            }
        }
        
        private func setupViewHierarchy() {
            clipsToBounds = false
            
            addSubview(contextGestureContainerView)
            contextGestureContainerView.clipsToBounds = false
            
            if let nativeTabBar = nativeTabBar {
                contextGestureContainerView.addSubview(nativeTabBar)
                nativeTabBar.delegate = self
                
                if #available(iOS 26.0, *) {
                    configureNativeTabBar(nativeTabBar)
                }
            } else {
                
                contextGestureContainerView.addSubview(barBackgroundView)
                barBackgroundView.clipsToBounds = true
                
                let lens = LiquidGlassLensView(frame: .zero)
                self.liquidGlassLens = lens
                contextGestureContainerView.addSubview(lens)
                
                let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
                addGestureRecognizer(tapGesture)
            }
        }
        
        private func setupGestures() {
            contextGestureContainerView.shouldBegin = { [weak self] point in
                guard let self, let component = self.component else { return false }
                
                for (id, itemView) in self.itemViews {
                    guard let view = itemView.view else { continue }
                    
                    if self.convert(view.bounds, from: view).contains(point) {
                        guard let item = component.items.first(where: { $0.id == id }),
                              item.contextAction != nil else { return false }
                        
                        self.itemWithActiveContextGesture = id
                        
                        let startPoint = point
                        self.contextGestureContainerView.contextGesture?.externalUpdated = { [weak self] _, currentPoint in
                            let distance = hypot(startPoint.x - currentPoint.x, startPoint.y - currentPoint.y)
                            if distance > 10.0 {
                                self?.contextGestureContainerView.contextGesture?.cancel()
                            }
                        }
                        
                        return true
                    }
                }
                return false
            }
            
            contextGestureContainerView.activated = { [weak self] gesture, _ in
                guard let self,
                      let component = self.component,
                      let activeId = self.itemWithActiveContextGesture else { return }
                
                let itemView: ItemComponent.View?
                if self.nativeTabBar != nil {
                    itemView = self.selectedItemViews[activeId]?.view as? ItemComponent.View
                } else {
                    itemView = self.itemViews[activeId]?.view as? ItemComponent.View
                }
                
                guard let itemView else { return }
                
                if let nativeTabBar = self.nativeTabBar {
                    DispatchQueue.main.async {
                        self.cancelNativeGestures(in: nativeTabBar)
                    }
                }
                
                guard let item = component.items.first(where: { $0.id == activeId }) else { return }
                item.contextAction?(gesture, itemView.contextContainerView)
            }
        }
        
        private func cancelNativeGestures(in view: UIView) {
            for recognizer in view.gestureRecognizers ?? [] {
                if NSStringFromClass(type(of: recognizer)).contains("sSelectionGestureRecognizer") {
                    recognizer.state = .cancelled
                }
            }
            view.subviews.forEach { cancelNativeGestures(in: $0) }
        }
        
        public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard let component = self.component,
                  let index = tabBar.items?.firstIndex(where: { $0 === item }),
                  index < component.items.count else { return }
            
            component.items[index].action(false)
        }
        
        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return true
        }
        
        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let component = self.component else { return }
            
            let point = recognizer.location(in: self)
            
            var closestItem: (id: AnyHashable, distance: CGFloat)?
            for (id, itemView) in itemViews {
                guard let view = itemView.view else { continue }
                let distance = abs(point.x - view.center.x)
                if closestItem == nil || distance < closestItem!.distance {
                    closestItem = (id, distance)
                }
            }
            
            guard let (tappedId, _) = closestItem,
                  let item = component.items.first(where: { $0.id == tappedId }) else { return }
            
            let touchInBar = recognizer.location(in: barBackgroundView)
            createTabBarFlash(at: touchInBar)
            
            if let tappedItemView = self.itemViews[tappedId]?.view as? ItemComponent.View {
                tappedItemView.animateTapZoom()
            }
            
            let isSameTab = (component.selectedId == tappedId)
            if isSameTab {
                liquidGlassLens?.animateTap()
            }
            
            animateTabBarBounce()
            
            item.action(false)
        }
        
        
        private func animateTabBarBounce() {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            
            UIView.animate(
                withDuration: 0.08,
                delay: 0,
                options: [.curveEaseIn, .allowUserInteraction, .beginFromCurrentState]
            ) {
                self.contextGestureContainerView.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
            }
            
            UIView.animate(
                withDuration: 0.35,
                delay: 0.05,
                usingSpringWithDamping: 0.55,
                initialSpringVelocity: 0.6,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.contextGestureContainerView.transform = .identity
            }
        }
        
        private func createTabBarFlash(at touchPoint: CGPoint) {
            let startSize: CGFloat = 30
            let flash = UIView(frame: CGRect(
                x: touchPoint.x - startSize / 2,
                y: touchPoint.y - startSize / 2,
                width: startSize,
                height: startSize
            ))
            flash.backgroundColor = UIColor.white.withAlphaComponent(0.15)
            flash.layer.cornerRadius = startSize / 2
            flash.alpha = 1.0
            flash.isUserInteractionEnabled = false
            
            barBackgroundView.addSubview(flash)
            
            let maxDimension = max(barBackgroundView.bounds.width, barBackgroundView.bounds.height) * 2
            let scale = maxDimension / startSize
            
            UIView.animate(
                withDuration: 0.4,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction]
            ) {
                flash.transform = CGAffineTransform(scaleX: scale, y: scale)
                flash.alpha = 0
            } completion: { _ in
                flash.removeFromSuperview()
            }
        }
        
        public override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            return super.hitTest(point, with: event)
        }
        
        public func frameForItem(at index: Int) -> CGRect? {
            guard let component = self.component,
                  index >= 0, index < component.items.count,
                  let itemView = itemViews[component.items[index].id]?.view else { return nil }
            
            return convert(itemView.bounds, from: itemView)
        }
        
        public override func didMoveToWindow() {
            super.didMoveToWindow()
            state?.updated()
        }
        
        func update(
            component: TabBarComponent,
            availableSize: CGSize,
            state: EmptyComponentState,
            environment: Environment<Empty>,
            transition: ComponentTransition
        ) -> CGSize {
            
            let constrainedWidth = min(500.0, availableSize.width)
            let previousComponent = self.component
            
            self.component = component
            self.state = state
            self.firstItemView = nil
            
            overrideUserInterfaceStyle = component.theme.overallDarkAppearance ? .dark : .light
            
            if let nativeTabBar = nativeTabBar {
                return updateWithNativeTabBar(
                    nativeTabBar: nativeTabBar,
                    component: component,
                    previousComponent: previousComponent,
                    availableSize: CGSize(width: constrainedWidth, height: availableSize.height),
                    transition: transition
                )
            }
            
            return updateWithCustomTabBar(
                component: component,
                previousComponent: previousComponent,
                availableSize: CGSize(width: constrainedWidth, height: availableSize.height),
                transition: transition
            )
        }
        
        private func updateWithNativeTabBar(
            nativeTabBar: UITabBar,
            component: TabBarComponent,
            previousComponent: TabBarComponent?,
            availableSize: CGSize,
            transition: ComponentTransition
        ) -> CGSize {
            
            if previousComponent?.items.map(\.item.title) != component.items.map(\.item.title) {
                let items = component.items.enumerated().map { index, item in
                    UITabBarItem(title: item.item.title, image: nil, tag: index)
                }
                nativeTabBar.items = items
                
                itemViews.values.forEach { $0.view?.removeFromSuperview() }
                selectedItemViews.values.forEach { $0.view?.removeFromSuperview() }
                
                if let selectedIndex = component.items.firstIndex(where: { $0.id == component.selectedId }) {
                    nativeTabBar.selectedItem = nativeTabBar.items?[selectedIndex]
                }
            }
            
            let tabBarHeight: CGFloat = component.isTablet ? 74.0 : 83.0
            nativeTabBar.frame = CGRect(origin: .zero, size: CGSize(width: availableSize.width, height: tabBarHeight))
            nativeTabBar.layoutSubviews()
            
            let (nativeItemContainers, nativeSelectedContainers) = findNativeItemContainers(in: nativeTabBar)
            
            updateItemViews(
                component: component,
                previousComponent: previousComponent,
                nativeItemContainers: nativeItemContainers,
                nativeSelectedContainers: nativeSelectedContainers,
                availableSize: availableSize,
                transition: transition
            )
            
            let finalSize = CGSize(width: availableSize.width, height: 62.0)
            transition.setFrame(view: contextGestureContainerView, frame: CGRect(origin: .zero, size: finalSize))
            
            return finalSize
        }
        
        private func findNativeItemContainers(in tabBar: UITabBar) -> ([Int: UIView], [Int: UIView]) {
            var itemContainers: [Int: UIView] = [:]
            var selectedContainers: [Int: UIView] = [:]
            
            for subview in tabBar.subviews {
                guard NSStringFromClass(type(of: subview)).contains("PlatterView") else { continue }
                
                for subview in subview.subviews {
                    let className = NSStringFromClass(type(of: subview))
                    
                    if className.hasSuffix("SelectedContentView") {
                        for tabButton in subview.subviews where NSStringFromClass(type(of: tabButton)).hasSuffix("TabButton") {
                            selectedContainers[selectedContainers.count] = tabButton
                        }
                    } else if className.hasSuffix("ContentView") {
                        for tabButton in subview.subviews where NSStringFromClass(type(of: tabButton)).hasSuffix("TabButton") {
                            itemContainers[itemContainers.count] = tabButton
                        }
                    }
                }
            }
            
            return (itemContainers, selectedContainers)
        }
        
        private func updateWithCustomTabBar(
            component: TabBarComponent,
            previousComponent: TabBarComponent?,
            availableSize: CGSize,
            transition: ComponentTransition
        ) -> CGSize {
            
            let itemCount = CGFloat(component.items.count)
            var itemWidth = floor((availableSize.width - Layout.innerInset * 2.0) / itemCount)
            itemWidth = min(Layout.maxItemWidth, itemWidth)
            let itemSize = CGSize(width: itemWidth, height: Layout.itemHeight)
            
            let contentHeight = itemSize.height + Layout.innerInset * 2.0
            var contentX: CGFloat = Layout.innerInset
            
            var validIds: [AnyHashable] = []
            var selectedItemFrame: CGRect?
            
            for (_, item) in component.items.enumerated() {
                validIds.append(item.id)
                
                let itemView: ComponentView<Empty>
                var itemTransition = transition
                
                if let existing = itemViews[item.id] {
                    itemView = existing
                } else {
                    itemTransition = itemTransition.withAnimation(.none)
                    itemView = ComponentView()
                    itemViews[item.id] = itemView
                }
                
                let isSelected = component.selectedId == item.id
                
                let _ = itemView.update(
                    transition: itemTransition,
                    component: AnyComponent(ItemComponent(
                        item: item,
                        theme: component.theme,
                        isSelected: isSelected
                    )),
                    environment: {},
                    containerSize: itemSize
                )
                
                let itemFrame = CGRect(
                    x: contentX,
                    y: floor((contentHeight - itemSize.height) * 0.5),
                    width: itemSize.width,
                    height: itemSize.height
                )
                
                if let itemComponentView = itemView.view as? ItemComponent.View {
                    if itemComponentView.superview == nil {
                        itemComponentView.isUserInteractionEnabled = false
                        contextGestureContainerView.addSubview(itemComponentView)
                    }
                    
                    if firstItemView == nil {
                        firstItemView = itemComponentView
                    }
                    
                    itemTransition.setFrame(view: itemComponentView, frame: itemFrame)
                    
                    if let previous = previousComponent,
                       previous.selectedId != item.id,
                       isSelected {
                        itemComponentView.playSelectionAnimation()
                    }
                }
                
                if isSelected {
                    selectedItemFrame = calculatePillFrame(for: itemFrame)
                }
                
                contentX += itemFrame.width
            }
            
            contentX += Layout.innerInset
            
            removeInvalidItems(validIds: validIds)
            
            updateLiquidGlassLens(
                component: component,
                previousComponent: previousComponent,
                selectedFrame: selectedItemFrame
            )
            
            let size = CGSize(width: min(availableSize.width, contentX), height: contentHeight)
            
            updateBarBackground(size: size, component: component, transition: transition)
            
            transition.setFrame(view: contextGestureContainerView, frame: CGRect(origin: .zero, size: size))
            
            return size
        }
        
        private func updateItemViews(
            component: TabBarComponent,
            previousComponent: TabBarComponent?,
            nativeItemContainers: [Int: UIView],
            nativeSelectedContainers: [Int: UIView],
            availableSize: CGSize,
            transition: ComponentTransition
        ) {
            var itemSize = CGSize(
                width: floor((availableSize.width - Layout.innerInset * 2.0) / CGFloat(component.items.count)),
                height: Layout.itemHeight
            )
            itemSize.width = min(Layout.maxItemWidth, itemSize.width)
            
            if let firstContainer = nativeItemContainers[0] {
                itemSize = firstContainer.bounds.size
            }
            
            for (index, item) in component.items.enumerated() {
                let itemView: ComponentView<Empty>
                var itemTransition = transition
                
                if let existing = itemViews[item.id] {
                    itemView = existing
                } else {
                    itemTransition = itemTransition.withAnimation(.none)
                    itemView = ComponentView()
                    itemViews[item.id] = itemView
                }
                
                let selectedItemView: ComponentView<Empty>
                if let existing = selectedItemViews[item.id] {
                    selectedItemView = existing
                } else {
                    selectedItemView = ComponentView()
                    selectedItemViews[item.id] = selectedItemView
                }
                
                let isSelected = component.selectedId == item.id
                
                let _ = itemView.update(
                    transition: itemTransition,
                    component: AnyComponent(ItemComponent(
                        item: item,
                        theme: component.theme,
                        isSelected: false
                    )),
                    environment: {},
                    containerSize: itemSize
                )
                
                let _ = selectedItemView.update(
                    transition: itemTransition,
                    component: AnyComponent(ItemComponent(
                        item: item,
                        theme: component.theme,
                        isSelected: true
                    )),
                    environment: {},
                    containerSize: itemSize
                )
                
                if let componentView = itemView.view as? ItemComponent.View,
                   let selectedView = selectedItemView.view as? ItemComponent.View {
                    
                    if componentView.superview == nil {
                        componentView.isUserInteractionEnabled = false
                        selectedView.isUserInteractionEnabled = false
                        
                        nativeItemContainers[index]?.addSubview(componentView)
                        nativeSelectedContainers[index]?.addSubview(selectedView)
                    }
                    
                    if let parentView = componentView.superview {
                        let frame = CGRect(
                            x: floor((parentView.bounds.width - itemSize.width) * 0.5),
                            y: floor((parentView.bounds.height - itemSize.height) * 0.5),
                            width: itemSize.width,
                            height: itemSize.height
                        )
                        itemTransition.setFrame(view: componentView, frame: frame)
                        itemTransition.setFrame(view: selectedView, frame: frame)
                    }
                    
                    if let previous = previousComponent,
                       previous.selectedId != item.id,
                       isSelected {
                        componentView.playSelectionAnimation()
                        selectedView.playSelectionAnimation()
                    }
                }
            }
        }
        
        private func calculatePillFrame(for itemFrame: CGRect) -> CGRect {
            return CGRect(
                x: itemFrame.minX - Layout.pillHorizontalPadding,
                y: itemFrame.minY - Layout.pillVerticalPadding,
                width: itemFrame.width + Layout.pillHorizontalPadding * 2,
                height: itemFrame.height + Layout.pillVerticalPadding * 2
            )
        }
        
        private func removeInvalidItems(validIds: [AnyHashable]) {
            let invalidIds = itemViews.keys.filter { !validIds.contains($0) }
            for id in invalidIds {
                itemViews[id]?.view?.removeFromSuperview()
                selectedItemViews[id]?.view?.removeFromSuperview()
                itemViews.removeValue(forKey: id)
                selectedItemViews.removeValue(forKey: id)
            }
        }
        
        private func updateLiquidGlassLens(
            component: TabBarComponent,
            previousComponent: TabBarComponent?,
            selectedFrame: CGRect?
        ) {
            guard nativeTabBar == nil,
                  let lens = liquidGlassLens,
                  let pillFrame = selectedFrame else { return }
            
            if let firstItem = firstItemView,
               lens.superview === contextGestureContainerView {
                contextGestureContainerView.insertSubview(lens, belowSubview: firstItem)
            }
            
            lens.updateStyle(isDark: component.theme.overallDarkAppearance)
            
            let isFirstLayout = lens.frame.width == 0
            let isTabChange = !isFirstLayout &&
            lastSelectedId != nil &&
            lastSelectedId != component.selectedId
            
            if isFirstLayout {
                lens.frame = pillFrame
                lens.layoutSubviews()
            } else if isTabChange {
                
                let targetFrame = pillFrame
                
                lens.animateStretch(to: targetFrame) { [weak self, weak lens] in
                    guard let self, let lens else { return }
                    lens.createGhostAtFrame(targetFrame, in: self.contextGestureContainerView)
                }
            }
            
            let lensRectInContainer = convert(pillFrame, to: contextGestureContainerView)
            let selectedView = component.selectedId.flatMap { itemViews[$0]?.view }
            
            DispatchQueue.main.async { [weak self, weak lens, weak selectedView] in
                guard let self, let lens else { return }
                lens.updateSnapshot(
                    from: self.contextGestureContainerView,
                    in: lensRectInContainer,
                    excluding: selectedView
                )
            }
            
            lastSelectedId = component.selectedId
        }
        
        private func updateBarBackground(
            size: CGSize,
            component: TabBarComponent,
            transition: ComponentTransition
        ) {
            transition.setFrame(view: barBackgroundView, frame: CGRect(origin: .zero, size: size))
            barBackgroundView.backgroundColor = component.theme.rootController.tabBar.backgroundColor
            barBackgroundView.layer.cornerRadius = size.height * 0.5
            barBackgroundView.clipsToBounds = true
        }
    }
    
    public func makeView() -> View {
        return View(frame: .zero)
    }
    
    public func update(
        view: View,
        availableSize: CGSize,
        state: EmptyComponentState,
        environment: Environment<Empty>,
        transition: ComponentTransition
    ) -> CGSize {
        return view.update(
            component: self,
            availableSize: availableSize,
            state: state,
            environment: environment,
            transition: transition
        )
    }
}

private final class ItemComponent: Component {
    let item: TabBarComponent.Item
    let theme: PresentationTheme
    let isSelected: Bool
    
    init(item: TabBarComponent.Item, theme: PresentationTheme, isSelected: Bool) {
        self.item = item
        self.theme = theme
        self.isSelected = isSelected
    }
    
    static func ==(lhs: ItemComponent, rhs: ItemComponent) -> Bool {
        if lhs.item != rhs.item { return false }
        if lhs.theme !== rhs.theme { return false }
        if lhs.isSelected != rhs.isSelected { return false }
        return true
    }
    
    final class View: UIView {
        let contextContainerView: ContextExtractedContentContainingView
        
        private var imageIcon: ComponentView<Empty>?
        private var animationIcon: ComponentView<Empty>?
        private let title = ComponentView<Empty>()
        private var badge: ComponentView<Empty>?
        
        private var component: ItemComponent?
        private weak var state: EmptyComponentState?
        
        private var setImageListener: Int?
        private var setSelectedImageListener: Int?
        private var setBadgeListener: Int?
        
        override init(frame: CGRect) {
            self.contextContainerView = ContextExtractedContentContainingView()
            super.init(frame: frame)
            addSubview(contextContainerView)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        deinit {
            cleanupListeners()
        }
        
        private func cleanupListeners() {
            guard let component = component else { return }
            
            if let listener = setImageListener {
                component.item.item.removeSetImageListener(listener)
            }
            if let listener = setSelectedImageListener {
                component.item.item.removeSetSelectedImageListener(listener)
            }
            if let listener = setBadgeListener {
                component.item.item.removeSetBadgeListener(listener)
            }
        }
        
        func playSelectionAnimation() {
            if let animationView = animationIcon?.view as? LottieComponent.View {
                animationView.playOnce()
            }
        }
        
        func animateTapZoom() {
            let target = self.contextContainerView.contentView
            
            target.layer.removeAllAnimations()
            target.transform = .identity
            
            UIView.animate(
                withDuration: 0.09,
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]
            ) {
                target.transform = CGAffineTransform(scaleX: 1.12, y: 1.12)
            } completion: { _ in
                UIView.animate(
                    withDuration: 0.28,
                    delay: 0,
                    usingSpringWithDamping: 0.6,
                    initialSpringVelocity: 0.9,
                    options: [.allowUserInteraction, .beginFromCurrentState]
                ) {
                    target.transform = .identity
                }
            }
        }
        
        func update(
            component: ItemComponent,
            availableSize: CGSize,
            state: EmptyComponentState,
            environment: Environment<Empty>,
            transition: ComponentTransition
        ) -> CGSize {
            let previousComponent = self.component
            
            if previousComponent?.item.item !== component.item.item {
                cleanupListeners()
                setupListeners(for: component)
            }
            
            self.component = component
            self.state = state
            
            if let animationName = component.item.item.animationName {
                updateAnimatedIcon(
                    animationName: animationName,
                    component: component,
                    availableSize: availableSize,
                    transition: transition
                )
            } else {
                updateStaticIcon(
                    component: component,
                    availableSize: availableSize,
                    transition: transition
                )
            }
            
            updateTitle(component: component, availableSize: availableSize)
            
            updateBadge(component: component, availableSize: availableSize, transition: transition)
            
            transition.setFrame(view: contextContainerView, frame: CGRect(origin: .zero, size: availableSize))
            transition.setFrame(view: contextContainerView.contentView, frame: CGRect(origin: .zero, size: availableSize))
            contextContainerView.contentRect = CGRect(origin: .zero, size: availableSize)
            
            return availableSize
        }
        
        private func setupListeners(for component: ItemComponent) {
            setImageListener = component.item.item.addSetImageListener { [weak self] _ in
                self?.state?.updated(transition: .immediate, isLocal: true)
            }
            setSelectedImageListener = component.item.item.addSetSelectedImageListener { [weak self] _ in
                self?.state?.updated(transition: .immediate, isLocal: true)
            }
            setBadgeListener = UITabBarItem_addSetBadgeListener(component.item.item) { [weak self] _ in
                self?.state?.updated(transition: .immediate, isLocal: true)
            }
        }
        
        private func updateAnimatedIcon(
            animationName: String,
            component: ItemComponent,
            availableSize: CGSize,
            transition: ComponentTransition
        ) {
            if let imageIcon = imageIcon {
                self.imageIcon = nil
                imageIcon.view?.removeFromSuperview()
            }
            
            let animationIcon: ComponentView<Empty>
            var iconTransition = transition
            
            if let existing = self.animationIcon {
                animationIcon = existing
            } else {
                iconTransition = iconTransition.withAnimation(.none)
                animationIcon = ComponentView()
                self.animationIcon = animationIcon
            }
            
            let iconSize = CGSize(width: 48.0, height: 48.0)
            let _ = animationIcon.update(
                transition: iconTransition,
                component: AnyComponent(LottieComponent(
                    content: LottieComponent.AppBundleContent(name: animationName),
                    color: component.isSelected
                    ? component.theme.rootController.tabBar.selectedTextColor
                    : component.theme.rootController.tabBar.textColor,
                    placeholderColor: nil,
                    startingPosition: .end,
                    size: iconSize,
                    loop: false
                )),
                environment: {},
                containerSize: iconSize
            )
            
            let iconFrame = CGRect(
                x: floor((availableSize.width - iconSize.width) * 0.5) + component.item.item.animationOffset.x,
                y: -4.0 + component.item.item.animationOffset.y,
                width: iconSize.width,
                height: iconSize.height
            )
            
            if let view = animationIcon.view {
                if view.superview == nil {
                    insertIconView(view)
                }
                iconTransition.setFrame(view: view, frame: iconFrame)
            }
        }
        
        private func updateStaticIcon(
            component: ItemComponent,
            availableSize: CGSize,
            transition: ComponentTransition
        ) {
            if let animationIcon = animationIcon {
                self.animationIcon = nil
                animationIcon.view?.removeFromSuperview()
            }
            
            let imageIcon: ComponentView<Empty>
            var iconTransition = transition
            
            if let existing = self.imageIcon {
                imageIcon = existing
            } else {
                iconTransition = iconTransition.withAnimation(.none)
                imageIcon = ComponentView()
                self.imageIcon = imageIcon
            }
            
            let image = component.isSelected
            ? component.item.item.selectedImage
            : component.item.item.image
            
            let iconSize = imageIcon.update(
                transition: iconTransition,
                component: AnyComponent(Image(
                    image: image,
                    tintColor: nil,
                    contentMode: .center
                )),
                environment: {},
                containerSize: CGSize(width: 100.0, height: 100.0)
            )
            
            let iconFrame = CGRect(
                x: floor((availableSize.width - iconSize.width) * 0.5),
                y: 3.0,
                width: iconSize.width,
                height: iconSize.height
            )
            
            if let view = imageIcon.view {
                if view.superview == nil {
                    insertIconView(view)
                }
                iconTransition.setFrame(view: view, frame: iconFrame)
            }
        }
        
        private func insertIconView(_ view: UIView) {
            if let badgeView = badge?.view {
                contextContainerView.contentView.insertSubview(view, belowSubview: badgeView)
            } else {
                contextContainerView.contentView.addSubview(view)
            }
        }
        
        private func updateTitle(component: ItemComponent, availableSize: CGSize) {
            let titleSize = title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(
                        string: component.item.item.title ?? " ",
                        font: Font.semibold(10.0),
                        textColor: component.isSelected
                        ? component.theme.rootController.tabBar.selectedTextColor
                        : component.theme.rootController.tabBar.textColor
                    ))
                )),
                environment: {},
                containerSize: CGSize(width: availableSize.width, height: 100.0)
            )
            
            let titleFrame = CGRect(
                x: floor((availableSize.width - titleSize.width) * 0.5),
                y: availableSize.height - 8.0 - titleSize.height,
                width: titleSize.width,
                height: titleSize.height
            )
            
            if let titleView = title.view {
                if titleView.superview == nil {
                    contextContainerView.contentView.addSubview(titleView)
                }
                titleView.frame = titleFrame
            }
        }
        
        private func updateBadge(
            component: ItemComponent,
            availableSize: CGSize,
            transition: ComponentTransition
        ) {
            guard let badgeText = component.item.item.badgeValue, !badgeText.isEmpty else {
                if let badge = badge {
                    self.badge = nil
                    badge.view?.removeFromSuperview()
                }
                return
            }
            
            let badge: ComponentView<Empty>
            var badgeTransition = transition
            
            if let existing = self.badge {
                badge = existing
            } else {
                badgeTransition = badgeTransition.withAnimation(.none)
                badge = ComponentView()
                self.badge = badge
            }
            
            let badgeSize = badge.update(
                transition: badgeTransition,
                component: AnyComponent(TextBadgeComponent(
                    text: badgeText,
                    font: Font.regular(13.0),
                    background: component.theme.rootController.tabBar.badgeBackgroundColor,
                    foreground: component.theme.rootController.tabBar.badgeTextColor,
                    insets: UIEdgeInsets(top: 0, left: 6, bottom: 1, right: 6)
                )),
                environment: {},
                containerSize: CGSize(width: 100.0, height: 100.0)
            )
            
            let contentWidth: CGFloat = 25.0
            let badgeFrame = CGRect(
                x: floor(availableSize.width / 2.0) + contentWidth - badgeSize.width - 1.0,
                y: 5.0,
                width: badgeSize.width,
                height: badgeSize.height
            )
            
            if let badgeView = badge.view {
                if badgeView.superview == nil {
                    contextContainerView.contentView.addSubview(badgeView)
                }
                badgeTransition.setFrame(view: badgeView, frame: badgeFrame)
            }
        }
    }
    
    func makeView() -> View {
        return View(frame: .zero)
    }
    
    func update(
        view: View,
        availableSize: CGSize,
        state: EmptyComponentState,
        environment: Environment<Empty>,
        transition: ComponentTransition
    ) -> CGSize {
        return view.update(
            component: self,
            availableSize: availableSize,
            state: state,
            environment: environment,
            transition: transition
        )
    }
}
