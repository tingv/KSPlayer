//
//  AppKitExtend.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

/// 'NSWindow' is unavailable in Mac Catalyst
#if !canImport(UIKit)
import AppKit
import CoreMedia
import IOKit.pwr_mgt

public typealias UIApplicationDelegate = NSApplicationDelegate
public typealias UIApplication = NSApplication
public typealias UIWindow = NSWindow
public typealias UIViewController = NSViewController
public typealias UIColor = NSColor
public typealias UIStackView = NSStackView
public typealias UIPanGestureRecognizer = NSPanGestureRecognizer
public typealias UIGestureRecognizer = NSGestureRecognizer
public typealias UIGestureRecognizerDelegate = NSGestureRecognizerDelegate
public typealias UIViewContentMode = ContentMode
public typealias UIFont = NSFont
public typealias UIFontDescriptor = NSFontDescriptor
public typealias UIControl = NSControl
public typealias UITextField = NSTextField
public typealias UIImageView = NSImageView
public typealias UITapGestureRecognizer = NSClickGestureRecognizer
public typealias UXSlider = NSSlider
public typealias UITableView = NSTableView
public typealias UITableViewDelegate = NSTableViewDelegate
public typealias UITableViewDataSource = NSTableViewDataSource
public typealias UITouch = NSTouch
public typealias UIEvent = NSEvent
public typealias UIButton = KSButton
public extension UIFontDescriptor.SymbolicTraits {
    static let traitItalic = italic
    static let traitBold = bold
}

public extension NSClickGestureRecognizer {
    var numberOfTapsRequired: Int {
        get {
            numberOfClicksRequired
        }
        set {
            numberOfClicksRequired = newValue
        }
    }

    func require(toFail otherGestureRecognizer: NSClickGestureRecognizer) {
        buttonMask = otherGestureRecognizer.buttonMask << 1
    }
}

public extension NSView {
    @objc internal var contentMode: UIViewContentMode {
        get {
            if let contentsGravity = backingLayer?.contentsGravity {
                switch contentsGravity {
                case .resize:
                    return .scaleToFill
                case .resizeAspect:
                    return .scaleAspectFit
                case .resizeAspectFill:
                    return .scaleAspectFill
                default:
                    return .scaleAspectFit
                }
            } else {
                return .scaleAspectFit
            }
        }
        set {
            switch newValue {
            case .scaleToFill:
                backingLayer?.contentsGravity = .resize
            case .scaleAspectFit:
                backingLayer?.contentsGravity = .resizeAspect
            case .scaleAspectFill:
                backingLayer?.contentsGravity = .resizeAspectFill
            case .center:
                backingLayer?.contentsGravity = .center
            default:
                break
            }
        }
    }

    var center: CGPoint {
        CGPoint(x: frame.midX, y: frame.midY)
    }

    var alpha: CGFloat {
        get {
            alphaValue
        }
        set {
            alphaValue = newValue
        }
    }

    var backgroundColor: UIColor? {
        get {
            if let layer, let cgColor = layer.backgroundColor {
                return UIColor(cgColor: cgColor)
            } else {
                return nil
            }
        }
        set {
            backingLayer?.backgroundColor = newValue?.cgColor
        }
    }

    var clipsToBounds: Bool {
        get {
            if let layer {
                return layer.masksToBounds
            } else {
                return false
            }
        }
        set {
            backingLayer?.masksToBounds = newValue
        }
    }

    class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void, completion: ((Bool) -> Void)? = nil) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setCompletionBlock {
            completion?(true)
        }
        animations()
        CATransaction.commit()
    }

    class func animate(withDuration duration: TimeInterval, animations: @escaping () -> Void) {
        animate(withDuration: duration, animations: animations, completion: nil)
    }

    func layoutIfNeeded() {
        layer?.layoutIfNeeded()
    }

    func centerRotate(byDegrees: Double) {
        layer?.position = center
        layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(Double.pi * byDegrees / 180.0)))
    }
}

public extension NSImage {
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize.zero)
    }

    @available(macOS 11.0, *)
    convenience init?(systemName: String) {
        self.init(systemSymbolName: systemName, accessibilityDescription: nil)
    }
}

extension NSButton {
    var titleFont: UIFont? {
        get {
            font
        }
        set {
            font = newValue
        }
    }

    var tintColor: UIColor? {
        get {
            contentTintColor
        }
        set {
            contentTintColor = newValue
        }
    }
}

public extension NSControl {
    var textAlignment: NSTextAlignment {
        get {
            alignment
        }
        set {
            alignment = newValue
        }
    }

    var text: String {
        get {
            stringValue
        }
        set {
            stringValue = newValue
        }
    }

    var attributedText: NSAttributedString? {
        get {
            attributedStringValue
        }
        set {
            attributedStringValue = newValue ?? NSAttributedString()
        }
    }

    var numberOfLines: Int {
        get {
            usesSingleLineMode ? 1 : 0
        }
        set {
            usesSingleLineMode = newValue == 1
        }
    }
}

public extension NSTextContainer {
    var numberOfLines: Int {
        get {
            maximumNumberOfLines
        }
        set {
            maximumNumberOfLines = newValue
        }
    }
}

public extension NSResponder {
    var next: NSResponder? {
        nextResponder
    }
}

public extension NSSlider {
    var minimumTrackTintColor: UIColor? {
        get {
            trackFillColor
        }
        set {
            trackFillColor = newValue
        }
    }

    var maximumTrackTintColor: UIColor? {
        get {
            nil
        }
        set {}
    }
}

public extension NSStackView {
    var axis: NSUserInterfaceLayoutOrientation {
        get {
            orientation
        }
        set {
            orientation = newValue
        }
    }
}

public extension NSGestureRecognizer {
    func addTarget(_ target: AnyObject, action: Selector) {
        self.target = target
        self.action = action
    }
}

public extension UIApplication {
    private static var assertionID = IOPMAssertionID()
    static var isIdleTimerDisabled = false {
        didSet {
            if isIdleTimerDisabled != oldValue {
                if isIdleTimerDisabled {
                    _ = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                    "KSPlayer is playing video" as CFString,
                                                    &assertionID)
                } else {
                    _ = IOPMAssertionRelease(assertionID)
                }
            }
        }
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    var isIdleTimerDisabled: Bool {
        get {
            UIApplication.isIdleTimerDisabled
        }
        set {
            UIApplication.isIdleTimerDisabled = newValue
        }
    }
}

//    @available(*, unavailable, renamed: "UIView.ContentMode")
@objc public enum ContentMode: Int {
    case scaleToFill

    case scaleAspectFit // contents scaled to fit with fixed aspect. remainder is transparent

    case scaleAspectFill // contents scaled to fill with fixed aspect. some portion of content may be clipped.

    case redraw // redraw on bounds change (calls -setNeedsDisplay)

    case center // contents remain same size. positioned adjusted.

    case top

    case bottom

    case left

    case right

    case topLeft

    case topRight

    case bottomLeft

    case bottomRight
}

public extension UIControl {
    @MainActor
    struct State: @preconcurrency OptionSet {
        public var rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = State(rawValue: 1 << 0)
        public static let highlighted = State(rawValue: 1 << 1)
        public static let disabled = State(rawValue: 1 << 2)
        public static let selected = State(rawValue: 1 << 3)
        public static let focused = State(rawValue: 1 << 4)
        public static let application = State(rawValue: 1 << 5)
        public static let reserved = State(rawValue: 1 << 6)
    }
}

extension UIControl.State: Hashable {}
public class UILabel: NSTextField {
    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        alignment = .left
        isBordered = false
        isEditable = false
        isSelectable = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        textColor = NSColor.white
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public class KSButton: NSButton {
    private var images = [UIControl.State: UIImage]()
    private var titles = [UIControl.State: String]()
    private var titleColors = [State: UIColor]()
    private var targetActions = [ControlEvents: (AnyObject?, Selector)]()

    override public init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        isBordered = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var isSelected: Bool = false {
        didSet {
            update(state: isSelected ? .selected : .normal)
        }
    }

    override public var isEnabled: Bool {
        didSet {
            update(state: isEnabled ? .normal : .disabled)
        }
    }

    open func setImage(_ image: UIImage?, for state: UIControl.State) {
        images[state] = image
        if state == .normal, isEnabled, !isSelected {
            self.image = image
        }
    }

    open func setTitle(_ title: String, for state: UIControl.State) {
        titles[state] = title
        if state == .normal, isEnabled, !isSelected {
            self.title = title
        }
    }

    open func setTitleColor(_ titleColor: UIColor?, for state: UIControl.State) {
        titleColors[state] = titleColor
        if state == .normal, isEnabled, !isSelected {
//            self.titleColor = titleColor
        }
    }

    private func update(state: UIControl.State) {
        if let stateImage = images[state] {
            image = stateImage
        }
        if let stateTitle = titles[state] {
            title = stateTitle
        }
    }

    open func addTarget(_ target: AnyObject?, action: Selector, for controlEvents: ControlEvents) {
        targetActions[controlEvents] = (target, action)
    }

    open func removeTarget(_: AnyObject?, action _: Selector?, for controlEvents: ControlEvents) {
        targetActions.removeValue(forKey: controlEvents)
    }

    override open func updateTrackingAreas() {
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }

    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if let (target, action) = targetActions[.touchUpInside] ?? targetActions[.primaryActionTriggered] {
            _ = target?.perform(action, with: self)
        }
    }

    override public func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if let (target, action) = targetActions[.mouseExited] {
            _ = target?.perform(action, with: self)
        }
    }

    override public func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        if let (target, action) = targetActions[.mouseExited] {
            _ = target?.perform(action, with: self)
        }
    }

    open func sendActions(for controlEvents: ControlEvents) {
        if let (target, action) = targetActions[controlEvents] {
            _ = target?.perform(action, with: self)
        }
    }
}

public class KSSlider: NSSlider {
    weak var delegate: KSSliderDelegate?
    public var trackHeigt = CGFloat(2)
    public var isPlayable = false
    public var isUserInteractionEnabled: Bool = true
    var tintColor: UIColor?
    public convenience init() {
        self.init(frame: .zero)
    }

    override public init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(progressSliderTouchEnded(_:))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func progressSliderTouchEnded(_ sender: KSSlider) {
        if isUserInteractionEnabled {
            delegate?.slider(value: Double(sender.floatValue), event: .touchUpInside)
        }
    }

    open func setThumbImage(_: UIImage?, for _: State) {}

    @IBInspectable var maximumValue: Float {
        get {
            Float(maxValue)
        }
        set {
            maxValue = Double(newValue)
        }
    }

    @IBInspectable var minimumValue: Float {
        get {
            Float(minValue)
        }
        set {
            minValue = Double(newValue)
        }
    }

    @IBInspectable var value: Float {
        get {
            floatValue
        }
        set {
            floatValue = newValue
        }
    }
}

extension UIView {
    func image() -> UIImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else {
            return nil
        }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

open class UIAlertController: UIViewController {
    public enum Style: Int {
        case actionSheet
        case alert
    }

    public convenience init(title _: String?, message _: String?, preferredStyle _: UIAlertController.Style) {
        self.init()
    }

    var preferredAction: UIAlertAction?

    open func addAction(_: UIAlertAction) {}
}

open class UIAlertAction: NSObject {
    public enum Style: Int {
        case `default`
        case cancel
        case destructive
    }

    public let title: String?
    public let style: UIAlertAction.Style
    public private(set) var isEnabled: Bool = false
    public init(title: String?, style: UIAlertAction.Style, handler _: ((UIAlertAction) -> Void)? = nil) {
        self.title = title
        self.style = style
    }
}

public extension UIViewController {
    func present(_: UIViewController, animated _: Bool, completion _: (() -> Void)? = nil) {}
}

public extension NSFont {
    static var familyNames: [String] {
        NSFontManager.shared.availableFontFamilies
    }
}

import CoreVideo
import RealityFoundation

class DisplayLink: DisplayLinkProtocol {
    private let displayLink: CVDisplayLink
    private var runloop: RunLoop?
    private var mode = RunLoop.Mode.default
    public var preferredFramesPerSecond = 60
    @available(macOS 12.0, *)
    public var preferredFrameRateRange: CAFrameRateRange {
        get {
            CAFrameRateRange()
        }
        set {}
    }

    public var timestamp: TimeInterval {
        var timeStamp = CVTimeStamp()
        if CVDisplayLinkGetCurrentTime(displayLink, &timeStamp) == kCVReturnSuccess, (timeStamp.flags & CVTimeStampFlags.hostTimeValid.rawValue) != 0 {
            return TimeInterval(timeStamp.hostTime / NSEC_PER_SEC)
        }
        return 0
    }

    public var duration: TimeInterval {
        CVDisplayLinkGetActualOutputVideoRefreshPeriod(displayLink)
    }

    public var targetTimestamp: TimeInterval {
        duration + timestamp
    }

    public var isPaused: Bool {
        get {
            !CVDisplayLinkIsRunning(displayLink)
        }
        set {
            if newValue {
                CVDisplayLinkStop(displayLink)
            } else {
                CVDisplayLinkStart(displayLink)
            }
        }
    }

    public init(target: Any, selector: Selector) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { [weak self] _, _, _, _, _ in
            guard let self else { return kCVReturnSuccess }
            self.runloop?.perform(selector, target: target, argument: self, order: 0, modes: [self.mode])
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    public init(block: @escaping (() -> Void)) {
        var displayLink: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        self.displayLink = displayLink!
        CVDisplayLinkSetOutputHandler(self.displayLink) { _, _, _, _, _ in
            block()
            return kCVReturnSuccess
        }
        CVDisplayLinkStart(self.displayLink)
    }

    open func add(to runloop: RunLoop, forMode mode: RunLoop.Mode) {
        self.runloop = runloop
        self.mode = mode
    }

    public func invalidate() {
        isPaused = true
        runloop = nil
        CVDisplayLinkSetOutputHandler(displayLink) { _, _, _, _, _ in
            kCVReturnError
        }
    }
}

#endif
