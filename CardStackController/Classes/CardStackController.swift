import UIKit

@objc public protocol CardStackControllerDelegate: class {
    @objc optional func didFinishStacking(viewController: UIViewController)
    @objc optional func didFinishUnstacking(viewController: UIViewController)
    @objc optional func shouldDismiss(viewController: UIViewController) -> Bool
    @objc optional func didFinishDismissingCardController()
}

public class CardStackController: UIViewController {
    
    public typealias CompletionBlock = (Void) -> ()

    fileprivate struct CardStackControllerPalette {
        static let backgroundColor = UIColor.black.withAlphaComponent(0.4)
    }

    fileprivate struct Constants {
        static let topCornerRadius: CGFloat = 14.0
        static let dragLimitToDismiss: CGFloat = 100.0
        static let dragAmountToDimBackgroundColor: CGFloat = 1000.0
        static let fakeViewHeight: CGFloat = 500.0
        static let dimDuration: TimeInterval = 0.4
    }

    fileprivate(set) var viewControllers: [UIViewController] = []
    public fileprivate(set) var rootViewController: UIViewController?


    /// Space between top of the screen and first card.
    ///
    /// *Default value*: status bar frame height
    public var firstCardTopOffset: CGFloat = UIApplication.shared.statusBarFrame.height

    /// Space between two consecutive cards.
    ///
    /// *Default value*: 10
    public var topOffsetBetweenCards: CGFloat = 10

    /// Amount of time since `stackCard` is called until the dynamic animator starts animating the stacking card. *Note: this animation is different from the scaling animation of the previous card. The scaling animation occurs with no delay after calling `stackCard`*
    ///
    /// *Default value*: 0.1
    public var cardDelay: CFTimeInterval = 0.1

    /// After calling `stackCard`, the last card on the stack animates its size. This value indicates how much each card scales from it original frame.
    ///
    /// *Default value*: 0.95
    public var cardScaleFactor: CGFloat = 0.95

    /// This value indicates how much should the card move vertically while being scaled.
    ///
    /// *Default value*: -20
    public var verticalTranslation: CGFloat = -20

    /// Similar to UITableView, set it to false if you don't want the user to drag the card vertically more than its height.
    ///
    /// *Default value*: true
    public var bounces = true

    /// If this property is set to false, after the last card is unstacked you are responsible to also dismiss `CardStackController`.
    ///
    /// *Default value*: true
    public var automaticallyDismiss = true

    /// Controls the amount of dampling applied to the card that is going to be presented
    ///
    /// *Default value*: 1
    public var damping: CGFloat = 1

    /// Controls the amount of frequency applied to the card that is going to be presented
    ///
    /// *Default value*: 5
    public var frequency: CGFloat = 5

    public weak var delegate: CardStackControllerDelegate?

    public var numberOfCards: Int {
        return viewControllers.count
    }

    public var topViewController: UIViewController? {
        return viewControllers.last
    }

    fileprivate var animator: UIDynamicAnimator!
    fileprivate var collisionBehavior: UICollisionBehavior!
    fileprivate var attachmentBehaviors: [UIAttachmentBehavior] = []
    fileprivate var dynamicItemBehavior: UIDynamicItemBehavior!
    fileprivate var panAttachmentBehavior: UIAttachmentBehavior!
    fileprivate var panGestureRecognizer: UIPanGestureRecognizer!
    fileprivate var isPresentingCard = false
    fileprivate var initialDraggingPoint = CGPoint.zero
    fileprivate var stackCompletionBlock: CompletionBlock?

    fileprivate var previousViewController: UIViewController? {
        let previousCardIndex = viewControllers.count - 2
        guard previousCardIndex >= 0 else { return nil }
        return viewControllers[previousCardIndex]
    }

    public init(rootViewController: UIViewController) {
        self.rootViewController = rootViewController

        super.init(nibName: nil, bundle: nil)
    }

    public init() {
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        setupView()
        initialiseAnimator()
        addGestureRecognizer()
        if let viewController = rootViewController {
            stack(viewController: viewController)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(false)

        guard isBeingPresented else { return }
        let screenShotImage = drawWindowHierarchy(afterScreenUpdates: false)
        let imageView = UIImageView(image: screenShotImage)
        view.insertSubview(imageView, at: 0)
        imageView.pinEdgesToSuperviewEdges()
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        viewControllers.filter { $0.view.layer.mask != nil }
            .forEach { $0.view.layer.mask = maskLayer(with: $0.view.bounds) }
    }

    fileprivate func setupView() {
        view.backgroundColor = .clear
    }

    fileprivate func addGestureRecognizer() {
        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    }

    fileprivate func initialiseAnimator() {
        animator = UIDynamicAnimator(referenceView: view)
        animator.delegate = self
        dynamicItemBehavior = UIDynamicItemBehavior()
        dynamicItemBehavior.allowsRotation = false
        collisionBehavior = UICollisionBehavior()
        collisionBehavior.collisionMode = .boundaries
        collisionBehavior.addBoundary(withIdentifier: "leftMargin" as NSCopying, from: CGPoint(x: -0.5, y: 0), to: CGPoint(x: -0.5, y: view.bounds.maxY))
        collisionBehavior.addBoundary(withIdentifier: "rightMargin" as NSCopying, from: CGPoint(x: view.bounds.maxX + 0.5, y: 0), to: CGPoint(x: view.bounds.maxX + 0.5, y: view.bounds.maxY))
        animator.addBehavior(dynamicItemBehavior)
        animator.addBehavior(collisionBehavior)
    }

    /// Call this method to present (stack) a new card.
    ///
    /// - Parameters:
    ///   - newController: the viewcontroller you want to present
    ///   - size: used if the viewcontroller requires a specific size. *Default value is .zero*
    ///   - roundedCorners: top right and left corners will be rounded. *Default value is true*
    ///   - isDraggable: the user can drag the card vertically. *Default value is true*
    ///   - bottomBackgroundColor: CardController adds a fake view below each card. Set a desired color. *Default value is the same as the viewcontroller background to be presented*
    ///   - completion: completion block called after the card is presented (stacked)
    public func stack(viewController newController: UIViewController, withSize size: CGSize = .zero, withRoundedTopCorners roundedCorners: Bool = true, draggable isDraggable: Bool = true, bottomBackgroundColor: UIColor? = nil, completion: CompletionBlock? = nil) {
        if viewControllers.isEmpty { rootViewController = newController }
        panGestureRecognizer.isEnabled = isDraggable
        stackCompletionBlock = completion
        isPresentingCard = true
        animateCurrentCardBackToPresentNextOne()

        let containerView = createContainerDimView()
        addChild(viewController: newController, containerView: containerView, fakeViewBackgroundColor: bottomBackgroundColor)

        let numberOfPreviousCards = viewControllers.count - 1
        newController.view.frame = newControllerFrame(fromSize: size, previousCards: numberOfPreviousCards)
        if roundedCorners {
            newController.view.layer.mask = maskLayer(with: newController.view.bounds)
        }
        newController.view.addGestureRecognizer(panGestureRecognizer)

        UIView.animate(withDuration: 0.3) {
            containerView.backgroundColor = CardStackControllerPalette.backgroundColor
        }

        delay(delay: cardDelay) {
            let anchorY = self.view.frame.maxY - newController.view.bounds.midY
            self.attach(view: newController.view, toAnchorPoint: CGPoint(x: self.view.center.x, y: anchorY))
            self.collisionBehavior.addItem(newController.view)
        }
    }

    fileprivate func animateCurrentCardBackToPresentNextOne() {
        guard let viewController = topViewController else { return }

        let transform = CATransform3DMakeScale(cardScaleFactor, cardScaleFactor, 1)
        let finalTransform = CATransform3DTranslate(transform, 0, verticalTranslation, 0)
        let anim = CABasicAnimation(keyPath: "transform")
        anim.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        anim.toValue = NSValue(caTransform3D: finalTransform)
        anim.duration = 0.4
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.5, 0.5, 1)
        anim.fillMode = kCAFillModeForwards
        anim.isRemovedOnCompletion = false
        viewController.view.layer.add(anim, forKey: "transform")
    }

    fileprivate func newControllerFrame(fromSize size: CGSize, previousCards: Int) -> CGRect {
        let viewHeight = view.bounds.height
        let viewWidth = view.bounds.width
        if size != .zero {
            return CGRect(origin: CGPoint(x: 0, y: viewHeight), size: size)
        }
        let topMargin  = firstCardTopOffset + (topOffsetBetweenCards * CGFloat(previousCards))
        return CGRect(origin: CGPoint(x: 0, y: viewHeight), size: CGSize(width: viewWidth, height: viewHeight - topMargin))
    }

    fileprivate func createContainerDimView() -> UIView {
        let containerView = UIView()
        containerView.backgroundColor = .clear
        containerView.frame = view.bounds
        view.addSubview(containerView)
        return containerView
    }

    fileprivate func addChild(viewController newController: UIViewController, containerView: UIView, fakeViewBackgroundColor: UIColor?) {
        viewControllers.append(newController)
        addChildViewController(newController)
        containerView.addSubview(newController.view)
        addFakeBottomView(underneath: newController.view, with: fakeViewBackgroundColor)
        newController.didMove(toParentViewController: self)
    }

    fileprivate func attach(view aView: UIView, toAnchorPoint anchorPoint: CGPoint) {
        let attachmentBehaviour = UIAttachmentBehavior(item: aView,
                                                       attachedToAnchor: anchorPoint)
        //Length should be 0 but there is a bug in iOS... -.-' http://stackoverflow.com/a/21463118
        attachmentBehaviour.length = 1
        attachmentBehaviour.damping = damping
        attachmentBehaviour.frequency = frequency
        animator.addBehavior(attachmentBehaviour)
        attachmentBehaviors.append(attachmentBehaviour)
        dynamicItemBehavior.addItem(aView)
    }

    fileprivate func maskLayer(with bounds: CGRect) -> CAShapeLayer? {
        let layer = CAShapeLayer()
        layer.frame = bounds
        layer.path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: CGSize(width: bounds.width, height: bounds.height + Constants.fakeViewHeight)),
                                  byRoundingCorners: [UIRectCorner.topLeft, UIRectCorner.topRight],
                                  cornerRadii: CGSize(width: Constants.topCornerRadius,
                                                      height: Constants.topCornerRadius)).cgPath
        return layer
    }

    fileprivate func addFakeBottomView(underneath view: UIView, with backgroundColor: UIColor?) {
        let fakeView = UIView()
        fakeView.translatesAutoresizingMaskIntoConstraints = false
        fakeView.backgroundColor = backgroundColor ?? view.backgroundColor
        view.addSubview(fakeView)
        fakeView.pinTop(toBottomOf: view)
        fakeView.pinLeading(toLeadingOf: view)
        fakeView.pinTrailing(toTrailingOf: view)
        fakeView.setHeight(to: Constants.fakeViewHeight)
    }

    /// Unstack last view controller (topViewController)
    ///
    /// - Parameter completion: completion block called after unstacking is complete
    public func unstackLastViewController(completion: CompletionBlock? = nil) {
        guard let attachmentBehaviour = attachmentBehaviors.last, let item = attachmentBehaviour.items.last,
            let topController = topViewController else { return }
        attachmentBehaviour.anchorPoint = CGPoint(x: view.center.x, y: item.center.y + item.bounds.height)
        if let previous = previousViewController { animateCardToFront(viewController: previous) }
        removeDimView(to: topController, animated: true) {
            self.dismissCard()
            completion?()
        }
    }

    /// Unstack all view controllers.
    ///
    /// - Parameter completion: completion block called after unstacking is complete
    public func unstackAllViewControllers(completion: CompletionBlock? = nil) {
        unstack(viewControllers: viewControllers)
    }

    /// Unstack viewcontrollers until a given viewcontroller is founded.
    ///
    /// - Parameter viewController: cards in front of this viewController will be dismissed. This viewController will become `TopViewController`
    /// - Parameter completion: completion block called after unstacking is complete
    public func unstack(to viewController: UIViewController, completion: CompletionBlock? = nil) {
        guard let index = viewControllers.index(of: viewController) else {
            assertionFailure("Viewcontroller was not found in the stack")
            return
        }
        let cardsToUnstack = numberOfCards - index + 1
        unstack(last: cardsToUnstack, completion: completion)
    }

    /// Unstack a given number of viewControllers
    ///
    /// - Parameters:
    ///   - numberOfCards: number of cards to unstack
    ///   - completion: completion block called after unstacking is complete
    public func unstack(last numberOfCards: Int, completion: CompletionBlock? = nil) {
        guard numberOfCards <= viewControllers.count else {
            assertionFailure("the number of cards to unstack must be less or equal than the number of ViewControllers on the stack")
            return
        }
        var viewControllersToUnstack: [UIViewController] = []
        for (index, controller) in viewControllers.reversed().enumerated() {
            if index < numberOfCards {
                viewControllersToUnstack.append(controller)
            }
        }
        unstack(viewControllers: viewControllersToUnstack.reversed(), completion: completion)
    }

    /// Unstack all viewControllers but the root (first).
    ///
    /// - Parameter completion: completion block called after unstacking is complete
    public func unstackToRootViewController(completion: CompletionBlock? = nil) {
        unstack(last: viewControllers.count - 1, completion: completion)
    }

    fileprivate func unstack(viewControllers selectedControllers: [UIViewController], completion: CompletionBlock? = nil) {
        let anchorPoint = CGPoint(x: view.bounds.width / 2, y: view.bounds.height * 3/2)
        let remainingCards = numberOfCards - selectedControllers.count
        let behaviours = attachmentBehaviors.dropFirst(remainingCards)

        behaviours.forEach { $0.anchorPoint = anchorPoint }

        UIView.animate(withDuration: Constants.dimDuration, animations: {
            selectedControllers.forEach { self.removeDimView(to: $0, animated: false) { self.dismissCard() } }
        }) { finished in
            if selectedControllers.count < self.viewControllers.count {
                let index = self.viewControllers.count - selectedControllers.count - 1
                let top = self.viewControllers[index]
                self.animateCardToFront(viewController: top)
            }
            completion?()
        }
    }

    fileprivate func removeDimView(to viewController: UIViewController, animated: Bool, completion: @escaping CompletionBlock) {
        guard let containerView = viewController.view.superview else { return }
        UIView.animate(withDuration: animated ? Constants.dimDuration : 0.0, animations: {
            containerView.backgroundColor = UIColor.clear
        }) { finished in
            completion()
        }
    }

    fileprivate func animateCardToFront(viewController: UIViewController) {
        let duration = 0.4
        let anim = CABasicAnimation(keyPath: "transform")
        anim.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.5, 0.5, 1)
        anim.fillMode = kCAFillModeForwards
        anim.isRemovedOnCompletion = false
        viewController.view.layer.add(anim, forKey: "transformBack")
    }

    @objc fileprivate func handlePan(sender: UIPanGestureRecognizer) {
        guard let topController = topViewController,
            let panningView = topController.view,
            let currentAttachmentBehaviour = attachmentBehaviors.last,
            let currentDimView = panningView.superview else { return }

        let panLocationInView = sender.location(in: view)
        let defaultAnchorPointX = currentAttachmentBehaviour.anchorPoint.x
        let defaultAnchorPointY = self.view.frame.maxY - panningView.bounds.midY

        switch sender.state {
        case .possible: return
        case .began:
            initialDraggingPoint = panLocationInView

        case .changed:
            let newYPosition = defaultAnchorPointY + calculateYPosition(withLocation: panLocationInView.y, initialDragging: initialDraggingPoint.y)
            currentAttachmentBehaviour.anchorPoint = CGPoint(x: defaultAnchorPointX, y: newYPosition)
            let percentageDragged = (Constants.dragAmountToDimBackgroundColor - (panLocationInView.y - initialDraggingPoint.y)) / Constants.dragAmountToDimBackgroundColor
            let alphaPercentage = min(0.4, percentageDragged - 0.6)
            currentDimView.backgroundColor = CardStackControllerPalette.backgroundColor.withAlphaComponent(alphaPercentage)

        case .ended, .cancelled, .failed:
            currentAttachmentBehaviour.anchorPoint = CGPoint(x: defaultAnchorPointX, y: defaultAnchorPointY)
            let velocity = CGPoint(x: 0, y: sender.velocity(in: view).y)
            dynamicItemBehavior.addLinearVelocity(velocity, for: panningView)
            let shouldDismiss = delegate?.shouldDismiss?(viewController: topController) ?? true
            if sender.translation(in: view).y > Constants.dragLimitToDismiss && shouldDismiss {
                unstackLastViewController()
            } else {
                UIView.animate(withDuration: Constants.dimDuration) {
                    currentDimView.backgroundColor = CardStackControllerPalette.backgroundColor
                }
            }
        }
    }

    fileprivate func calculateYPosition(withLocation location: CGFloat, initialDragging: CGFloat) -> CGFloat {
        let totalAmountDragged =  location - initialDragging
        if totalAmountDragged < 0 {
            if !bounces { return 0 }
            return totalAmountDragged * log10(1 + initialDraggingPoint.y/abs(totalAmountDragged))
        } else {
            return totalAmountDragged
        }
    }

    fileprivate func dismissCard() {
        guard let viewController = topViewController,
            let currentBehaviour = attachmentBehaviors.last,
            let viewControllerSuperview = viewController.view.superview else { return }
        viewController.willMove(toParentViewController: nil)
        viewController.view.removeFromSuperview()
        viewControllerSuperview.removeFromSuperview()
        viewController.removeFromParentViewController()
        viewControllers.removeLast()
        animator.removeBehavior(currentBehaviour)
        attachmentBehaviors.removeLast()
        collisionBehavior.removeItem(viewController.view)
        dynamicItemBehavior.removeItem(viewController.view)
        delegate?.didFinishUnstacking?(viewController: viewController)
        if let topViewController = topViewController {
            topViewController.view.addGestureRecognizer(panGestureRecognizer)
            return
        }
        animator.removeBehavior(dynamicItemBehavior)
        animator.removeBehavior(collisionBehavior)
        guard automaticallyDismiss else { return }
        dismiss(animated: false) { finished in
            self.delegate?.didFinishDismissingCardController?()
        }
    }
}

extension CardStackController: UIDynamicAnimatorDelegate {

    public func dynamicAnimatorDidPause(_ animator: UIDynamicAnimator) {
        guard isPresentingCard, let topViewController = topViewController else { return }
        isPresentingCard = false
        delegate?.didFinishStacking?(viewController: topViewController)
        stackCompletionBlock?()
    }
}
