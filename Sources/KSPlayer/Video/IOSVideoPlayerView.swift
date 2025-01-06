//
//  IOSVideoPlayerView.swift
//  Pods
//
//  Created by kintan on 2018/10/31.
//
#if canImport(UIKit) && canImport(CallKit)
import AVKit
import Combine
import CoreServices
import MediaPlayer
import UIKit

// 用于 iOS 平台的视频播放界面实现
open class IOSVideoPlayerView: VideoPlayerView {
    // 保存视图的原始 superview,用于全屏切换时还原
    private weak var originalSuperView: UIView?
    // 保存原始的布局约束,用于全屏切换时还原
    private var originalframeConstraints: [NSLayoutConstraint]?
    // 保存原始的 frame,用于全屏切换时还原
    private var originalFrame = CGRect.zero
    // 保存原始的屏幕方向设置,用于全屏切换时还原
    private var originalOrientations: UIInterfaceOrientationMask?
    // 全屏模式的代理
    private weak var fullScreenDelegate: PlayerViewFullScreenDelegate?
    // 标记当前调节的是音量还是亮度
    private var isVolume = false
    // 音量和亮度调节的视图控制器
    private let volumeView = BrightnessVolume()
    // 系统音量滑块控件
    public var volumeViewSlider = UXSlider()
    // 返回按钮
    public var backButton = UIButton()
    // AirPlay 投屏状态视图
    public var airplayStatusView: UIView = AirplayStatusView()
    // AirPlay 路由选择按钮
    #if !os(xrOS)
    public var routeButton = AVRoutePickerView()
    #endif
    // AirPlay 路由检测器
    private let routeDetector = AVRouteDetector()
    // 视频封面图片视图
    public var maskImageView = UIImageView()
    // 横屏/竖屏切换按钮
    public var landscapeButton: UIControl = UIButton()
    // 重写父类的 isMaskShow 属性,用于控制播放控件的显示和隐藏
    override open var isMaskShow: Bool {
        didSet {
            fullScreenDelegate?.player(isMaskShow: isMaskShow, isFullScreen: landscapeButton.isSelected)
        }
    }

    // 屏幕亮度控制
    #if !os(xrOS)
    private var brightness: CGFloat = UIScreen.main.brightness {
        didSet {
            UIScreen.main.brightness = brightness
        }
    }
    #endif

    // 重写父类方法,用于自定义 UI 组件的初始化
    override open func customizeUIComponents() {
        super.customizeUIComponents()
        // 根据设备类型设置字幕字体大小
        if UIDevice.current.userInterfaceIdiom == .phone {
            subtitleLabel.font = .systemFont(ofSize: 14)
        }
        // 设置视频封面图片视图
        insertSubview(maskImageView, at: 0)
        maskImageView.contentMode = .scaleAspectFit
        // 设置工具栏的横屏切换按钮
        toolBar.addArrangedSubview(landscapeButton)
        landscapeButton.tag = PlayerButtonType.landscape.rawValue
        landscapeButton.addTarget(self, action: #selector(onButtonPressed(_:)), for: .touchUpInside)
        landscapeButton.tintColor = .white
        if let landscapeButton = landscapeButton as? UIButton {
            landscapeButton.setImage(UIImage(systemName: "arrow.up.left.and.arrow.down.right"), for: .normal)
            landscapeButton.setImage(UIImage(systemName: "arrow.down.right.and.arrow.up.left"), for: .selected)
        }
        // 设置返回按钮
        backButton.tag = PlayerButtonType.back.rawValue
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.addTarget(self, action: #selector(onButtonPressed(_:)), for: .touchUpInside)
        backButton.tintColor = .white
        navigationBar.insertArrangedSubview(backButton, at: 0)

        // 添加 AirPlay 状态视图
        addSubview(airplayStatusView)
        // 添加音量亮度控制视图
        volumeView.move(to: self)
        #if !targetEnvironment(macCatalyst)
        let tmp = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 0, height: 0))
        if let first = (tmp.subviews.first { $0 is UISlider }) as? UISlider {
            volumeViewSlider = first
        }
        #endif
        backButton.translatesAutoresizingMaskIntoConstraints = false
        landscapeButton.translatesAutoresizingMaskIntoConstraints = false
        maskImageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            maskImageView.topAnchor.constraint(equalTo: topAnchor),
            maskImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            maskImageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            maskImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 25),
            landscapeButton.widthAnchor.constraint(equalToConstant: 30),
            airplayStatusView.centerXAnchor.constraint(equalTo: centerXAnchor),
            airplayStatusView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        #if !os(xrOS)
        routeButton.isHidden = true
        navigationBar.addArrangedSubview(routeButton)
        routeButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            routeButton.widthAnchor.constraint(equalToConstant: 25),
        ])
        #endif
        addNotification()
    }

    // 重置播放器状态
    override open func resetPlayer() {
        super.resetPlayer()
        // 重置封面图显示
        maskImageView.alpha = 1
        maskImageView.image = nil
        // 禁用手势控制
        panGesture.isEnabled = false
        // 隐藏 AirPlay 按钮(除非检测到多个播放路由)
        #if !os(xrOS)
        routeButton.isHidden = !routeDetector.multipleRoutesDetected
        #endif
    }

    // 处理按钮点击事件
    override open func onButtonPressed(type: PlayerButtonType, button: UIButton) {
        // 处理返回按钮点击
        if type == .back, viewController is PlayerFullScreenViewController {
            updateUI(isFullScreen: false)
            return
        }
        super.onButtonPressed(type: type, button: button)
        // 处理锁定按钮点击
        if type == .lock {
            button.isSelected.toggle()
            isMaskShow = !button.isSelected
            button.alpha = 1.0
        }
        // 处理横竖屏切换按钮点击
        else if type == .landscape {
            updateUI(isFullScreen: !landscapeButton.isSelected)
        }
    }

    // 判断视频是否为横向
    open func isHorizonal() -> Bool {
        playerLayer?.player.naturalSize.isHorizonal ?? true
    }

    // 更新 全屏/非全屏 UI状态
    open func updateUI(isFullScreen: Bool) {
        guard let viewController else {
            return
        }
        // 更新横屏按钮状态
        landscapeButton.isSelected = isFullScreen
        let isHorizonal = isHorizonal()
        // 控制导航手势
        viewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = !isFullScreen
        // 处理全屏切换
        if isFullScreen {
            // 已经是全屏状态则直接返回
            if viewController is PlayerFullScreenViewController {
                return
            }
            // 保存当前视图状态
            originalSuperView = superview
            originalframeConstraints = frameConstraints
            if let originalframeConstraints {
                NSLayoutConstraint.deactivate(originalframeConstraints)
            }
            originalFrame = frame
            originalOrientations = viewController.supportedInterfaceOrientations
            // 创建全屏控制器
            let fullVC = PlayerFullScreenViewController(isHorizonal: isHorizonal)
            fullScreenDelegate = fullVC
            // 将播放器视图添加到全屏控制器
            fullVC.view.addSubview(self)
            translatesAutoresizingMaskIntoConstraints = false
            // 设置全屏时的约束
            NSLayoutConstraint.activate([
                topAnchor.constraint(equalTo: fullVC.view.readableTopAnchor),
                leadingAnchor.constraint(equalTo: fullVC.view.leadingAnchor),
                trailingAnchor.constraint(equalTo: fullVC.view.trailingAnchor),
                bottomAnchor.constraint(equalTo: fullVC.view.bottomAnchor),
            ])
            // 配置全屏显示的模式
            fullVC.modalPresentationStyle = .fullScreen
            fullVC.modalPresentationCapturesStatusBarAppearance = true
            fullVC.transitioningDelegate = self
            // 展示全屏控制器
            viewController.present(fullVC, animated: true) {
                KSOptions.supportedInterfaceOrientations = fullVC.supportedInterfaceOrientations
            }
        } else {
            // 退出全屏
            guard viewController is PlayerFullScreenViewController else {
                return
            }
            let presentingVC = viewController.presentingViewController ?? viewController
            // 恢复原始屏幕方向设置
            if let originalOrientations {
                KSOptions.supportedInterfaceOrientations = originalOrientations
            }
            // 关闭全屏并恢复原始布局
            presentingVC.dismiss(animated: true) {
                self.originalSuperView?.addSubview(self)
                if let constraints = self.originalframeConstraints, !constraints.isEmpty {
                    NSLayoutConstraint.activate(constraints)
                } else {
                    self.translatesAutoresizingMaskIntoConstraints = true
                    self.frame = self.originalFrame
                }
            }
        }
        let isLandscape = isFullScreen && isHorizonal
        updateUI(isLandscape: isLandscape)
    }

    // 根据横竖屏状态更新UI
    open func updateUI(isLandscape: Bool) {
        // 根据配置和横竖屏状态控制顶部栏显示
        if isLandscape {
            topMaskView.isHidden = KSOptions.topBarShowInCase == .none
        } else {
            topMaskView.isHidden = KSOptions.topBarShowInCase != .always
        }
        // 更新工具栏按钮显示状态
        toolBar.playbackRateButton.isHidden = false
        toolBar.srtButton.isHidden = srtControl.subtitleInfos.isEmpty
        // 针对手机设备的特殊处理
        if UIDevice.current.userInterfaceIdiom == .phone {
            if isLandscape {
                landscapeButton.isHidden = true
                toolBar.srtButton.isHidden = srtControl.subtitleInfos.isEmpty
            } else {
                toolBar.srtButton.isHidden = true
                // 根据视频尺寸决定是否显示横屏按钮
                if let image = maskImageView.image {
                    landscapeButton.isHidden = image.size.width < image.size.height
                } else {
                    landscapeButton.isHidden = false
                }
            }
            toolBar.playbackRateButton.isHidden = !isLandscape
        } else {
            landscapeButton.isHidden = true
        }
        // 只在横屏时显示锁定按钮
        lockButton.isHidden = !isLandscape
        // 更新手势状态
        judgePanGesture()
    }

    // 处理播放器状态改变
    override open func player(layer: KSPlayerLayer, state: KSPlayerState) {
        super.player(layer: layer, state: state)
        if state == .readyToPlay {
            // 准备播放时淡出封面图
            UIView.animate(withDuration: 0.3) {
                self.maskImageView.alpha = 0.0
            }
        }
        judgePanGesture()
    }

    // 处理播放时间更新
    override open func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        // 更新 AirPlay 状态显示
        airplayStatusView.isHidden = !layer.player.isExternalPlaybackActive
        super.player(layer: layer, currentTime: currentTime, totalTime: totalTime)
    }

    // 设置播放资源
    override open func set(resource: KSPlayerResource, definitionIndex: Int = 0, isSetUrl: Bool = true) {
        super.set(resource: resource, definitionIndex: definitionIndex, isSetUrl: isSetUrl)
        // 设置视频封面图
        maskImageView.image(url: resource.cover)
    }

    // 切换视频清晰度
    override open func change(definitionIndex: Int) {
        Task {
            // 获取当前帧作为切换时的封面图
            let image = await playerLayer?.player.thumbnailImageAtCurrentTime()
            if let image {
                self.maskImageView.image = UIImage(cgImage: image)
                self.maskImageView.alpha = 1
            }
            super.change(definitionIndex: definitionIndex)
        }
    }

    // 手势开始时的处理
    override open func panGestureBegan(location point: CGPoint, direction: KSPanDirection) {
        if direction == .vertical {
            // 根据触摸位置判断是调节音量还是亮度
            if point.x > bounds.size.width / 2 {
                isVolume = true
                tmpPanValue = volumeViewSlider.value
            } else {
                isVolume = false
            }
        } else {
            super.panGestureBegan(location: point, direction: direction)
        }
    }

    // 手势移动时的处理
    override open func panGestureChanged(velocity point: CGPoint, direction: KSPanDirection) {
        if direction == .vertical {
            if isVolume {
                // 调节音量
                if KSOptions.enableVolumeGestures {
                    tmpPanValue += panValue(velocity: point, direction: direction, currentTime: Float(toolBar.currentTime), totalTime: Float(totalTime))
                    tmpPanValue = max(min(tmpPanValue, 1), 0)
                    volumeViewSlider.value = tmpPanValue
                }
            } else if KSOptions.enableBrightnessGestures {
                // 调节亮度
                #if !os(xrOS)
                brightness += CGFloat(panValue(velocity: point, direction: direction, currentTime: Float(toolBar.currentTime), totalTime: Float(totalTime)))
                #endif
            }
        } else {
            super.panGestureChanged(velocity: point, direction: direction)
        }
    }

    // 判断是否启用手势控制
    open func judgePanGesture() {
        if landscapeButton.isSelected || UIDevice.current.userInterfaceIdiom == .pad {
            // 横屏或iPad时，在播放状态下启用手势
            panGesture.isEnabled = isPlayed && !replayButton.isSelected
        } else {
            // 非横屏时只在播放时启用手势
            panGesture.isEnabled = toolBar.playButton.isSelected
        }
    }
}

// 实现 UIViewControllerTransitioningDelegate 协议，处理全屏切换动画
extension IOSVideoPlayerView: UIViewControllerTransitioningDelegate {
    // 设置present动画控制器
    public func animationController(forPresented _: UIViewController, presenting _: UIViewController, source _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        // 创建动画控制器，处理进入全屏的动画
        if let originalSuperView, let animationView = playerLayer?.player.view {
            return PlayerTransitionAnimator(containerView: originalSuperView, animationView: animationView)
        }
        return nil
    }

    // 设置dismiss动画控制器
    public func animationController(forDismissed _: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        // 创建动画控制器，处理退出全屏的动画
        if let originalSuperView, let animationView = playerLayer?.player.view {
            return PlayerTransitionAnimator(containerView: originalSuperView, animationView: animationView, isDismiss: true)
        } else {
            return nil
        }
    }
}

// MARK: - private functions

// 播放器私有扩展
extension IOSVideoPlayerView {
    // 添加通知观察者
    private func addNotification() {
//        NotificationCenter.default.addObserver(self, selector: #selector(orientationChanged), name: UIApplication.didChangeStatusBarOrientationNotification, object: nil)
        // 监听 AirPlay 路由变化
        NotificationCenter.default.addObserver(self, selector: #selector(routesAvailableDidChange), name: .AVRouteDetectorMultipleRoutesDetectedDidChange, object: nil)
    }

    // 处理 AirPlay 路由变化
    @objc private func routesAvailableDidChange(notification _: Notification) {
        #if !os(xrOS)
        // 根据是否有多个播放路由来显示/隐藏 AirPlay 按钮
        routeButton.isHidden = !routeDetector.multipleRoutesDetected
        #endif
    }

    // 处理屏幕方向变化
    @objc private func orientationChanged(notification _: Notification) {
        guard isHorizonal() else {
            return
        }
        // 根据设备方向更新全屏状态
        updateUI(isFullScreen: UIApplication.isLandscape)
    }
}

// AirPlay 状态视图实现
public class AirplayStatusView: UIView {
    override public init(frame: CGRect) {
        super.init(frame: frame)
        // 创建 AirPlay 图标
        let airplayicon = UIImageView(image: UIImage(systemName: "airplayvideo"))
        addSubview(airplayicon)
        // 创建状态文本标签
        let airplaymessage = UILabel()
        airplaymessage.backgroundColor = .clear
        airplaymessage.textColor = .white
        airplaymessage.font = .systemFont(ofSize: 14)
        airplaymessage.text = NSLocalizedString("AirPlay 投放中", comment: "")
        airplaymessage.textAlignment = .center
        addSubview(airplaymessage)

        // 设置自动布局约束
        translatesAutoresizingMaskIntoConstraints = false
        airplayicon.translatesAutoresizingMaskIntoConstraints = false
        airplaymessage.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 100),
            heightAnchor.constraint(equalToConstant: 115),
            airplayicon.topAnchor.constraint(equalTo: topAnchor),
            airplayicon.centerXAnchor.constraint(equalTo: centerXAnchor),
            airplayicon.widthAnchor.constraint(equalToConstant: 100),
            airplayicon.heightAnchor.constraint(equalToConstant: 100),
            airplaymessage.bottomAnchor.constraint(equalTo: bottomAnchor),
            airplaymessage.leadingAnchor.constraint(equalTo: leadingAnchor),
            airplaymessage.trailingAnchor.constraint(equalTo: trailingAnchor),
            airplaymessage.heightAnchor.constraint(equalToConstant: 15),
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// KSOptions 全局配置扩展
public extension KSOptions {
    /// func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask
    /// 设置应用程序支持的界面方向
    static var supportedInterfaceOrientations = UIInterfaceOrientationMask.portrait
}

// UIApplication 扩展
extension UIApplication {
    // 判断当前是否为横屏状态
    static var isLandscape: Bool {
        UIApplication.shared.windows.first?.windowScene?.interfaceOrientation.isLandscape ?? false
    }
}

// MARK: - menu

// 播放器菜单相关扩展
extension IOSVideoPlayerView {
    // 是否可以成为第一响应者
    override open var canBecomeFirstResponder: Bool {
        true
    }

    // 判断是否可以执行指定的操作
    override open func canPerformAction(_ action: Selector, withSender _: Any?) -> Bool {
        if action == #selector(IOSVideoPlayerView.openFileAction) {
            return true
        }
        return true
    }

    // 打开文件操作
    @objc fileprivate func openFileAction(_: AnyObject) {
        // 创建文件选择器，支持音频、视频和文本文件
        let documentPicker = UIDocumentPickerViewController(documentTypes: [kUTTypeAudio, kUTTypeMovie, kUTTypePlainText] as [String], in: .open)
        documentPicker.delegate = self
        viewController?.present(documentPicker, animated: true, completion: nil)
    }
}

// 实现文件选择器代理
extension IOSVideoPlayerView: UIDocumentPickerDelegate {
    // 处理文件选择结果
    public func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let url = urls.first {
            if url.isMovie || url.isAudio {
                // 如果选择的是音视频文件，设置为播放源
                set(url: url, options: KSOptions())
            } else {
                // 如果选择的是其他文件（如字幕），设置为字幕
                srtControl.selectedSubtitleInfo = URLSubtitleInfo(url: url)
            }
        }
    }
}

#endif

// iOS 系统菜单控制器
#if os(iOS)
@MainActor
public class MenuController {
    public init(with builder: UIMenuBuilder) {
        // 移除格式菜单
        builder.remove(menu: .format)
        // 在文件菜单开始处插入打开文件菜单
        builder.insertChild(MenuController.openFileMenu(), atStartOfMenu: .file)
//        builder.insertChild(MenuController.openURLMenu(), atStartOfMenu: .file)
//        builder.insertChild(MenuController.navigationMenu(), atStartOfMenu: .file)
    }

    // 创建打开文件菜单
    class func openFileMenu() -> UIMenu {
        // 创建打开文件的快捷键命令
        let openCommand = UIKeyCommand(input: "O", modifierFlags: .command, action: #selector(IOSVideoPlayerView.openFileAction(_:)))
        openCommand.title = NSLocalizedString("Open File", comment: "")
        // 创建菜单
        let openMenu = UIMenu(title: "",
                              image: nil,
                              identifier: UIMenu.Identifier("com.example.apple-samplecode.menus.openFileMenu"),
                              options: .displayInline,
                              children: [openCommand])
        return openMenu
    }

//    class func openURLMenu() -> UIMenu {
//        let openCommand = UIKeyCommand(input: "O", modifierFlags: [.command, .shift], action: #selector(IOSVideoPlayerView.openURLAction(_:)))
//        openCommand.title = NSLocalizedString("Open URL", comment: "")
//        let openMenu = UIMenu(title: "",
//                              image: nil,
//                              identifier: UIMenu.Identifier("com.example.apple-samplecode.menus.openURLMenu"),
//                              options: .displayInline,
//                              children: [openCommand])
//        return openMenu
//    }
//    class func navigationMenu() -> UIMenu {
//        let arrowKeyChildrenCommands = Arrows.allCases.map { arrow in
//            UIKeyCommand(title: arrow.localizedString(),
//                         image: nil,
//                         action: #selector(IOSVideoPlayerView.navigationMenuAction(_:)),
//                         input: arrow.command,
//                         modifierFlags: .command)
//        }
//        return UIMenu(title: NSLocalizedString("NavigationTitle", comment: ""),
//                      image: nil,
//                      identifier: UIMenu.Identifier("com.example.apple-samplecode.menus.navigationMenu"),
//                      options: [],
//                      children: arrowKeyChildrenCommands)
//    }

    enum Arrows: String, CaseIterable {
        case rightArrow
        case leftArrow
        case upArrow
        case downArrow
        func localizedString() -> String {
            NSLocalizedString("\(rawValue)", comment: "")
        }

        @MainActor
        var command: String {
            switch self {
            case .rightArrow:
                return UIKeyCommand.inputRightArrow
            case .leftArrow:
                return UIKeyCommand.inputLeftArrow
            case .upArrow:
                return UIKeyCommand.inputUpArrow
            case .downArrow:
                return UIKeyCommand.inputDownArrow
            }
        }
    }
}
#endif
