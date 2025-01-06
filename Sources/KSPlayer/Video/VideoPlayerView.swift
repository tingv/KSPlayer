//
//  VideoPlayerView.swift
//  Pods
//
//  Created by kintan on 16/4/29.
//
//
import AVKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import Combine
import MediaPlayer

/// 内部枚举,用于检查滑动手势的方向
public enum KSPanDirection {
    case horizontal // 水平方向
    case vertical   // 垂直方向
}

public protocol LoadingIndector {
    // 定义加载指示器的协议,需要实现开始和停止动画两个方法
    func startAnimating()
    func stopAnimating()
}

#if canImport(UIKit)
extension UIActivityIndicatorView: LoadingIndector {}
#endif
// MARK: - VideoPlayerView 核心类定义
// swiftlint:disable type_body_length file_length
open class VideoPlayerView: PlayerView {
    // 延迟执行项,用于控制UI的自动隐藏
    private var delayItem: DispatchWorkItem?
    /// 手势相关属性
    // 用于显示/隐藏控制视图的点击手势
    public let tapGesture = UITapGestureRecognizer()
    // 双击手势
    public let doubleTapGesture = UITapGestureRecognizer()
    // 滑动手势
    public let panGesture = UIPanGestureRecognizer()
    /// 滑动方向
    var scrollDirection = KSPanDirection.horizontal
    // 滑动时的临时值存储
    var tmpPanValue: Float = 0
    // 是否正在滑动进度条
    private var isSliderSliding = false

    // MARK: - UI组件
     // 底部遮罩视图
    public let bottomMaskView = LayerContainerView()
    // 顶部遮罩视图
    public let topMaskView = LayerContainerView()
    // 是否播放过
    private(set) var isPlayed = false
    // Combine订阅存储
    private var cancellable: AnyCancellable?

    // 当前清晰度
    public private(set) var currentDefinition = 0 {
        didSet {
            if let resource {
                toolBar.definitionButton.setTitle(resource.definitions[currentDefinition].definition, for: .normal)
            }
        }
    }

    // 播放资源相关属性
    public private(set) var resource: KSPlayerResource? {
        didSet {
            if let resource, oldValue != resource {
                // 当资源改变时的处理逻辑
                if let subtitleDataSouce = resource.subtitleDataSouce {
                    srtControl.addSubtitle(dataSouce: subtitleDataSouce)
                }
                subtitleBackView.isHidden = true
                subtitleBackView.image = nil
                subtitleLabel.attributedText = nil
                titleLabel.text = resource.name
                toolBar.definitionButton.isHidden = resource.definitions.count < 2
                autoFadeOutViewWithAnimation()
                isMaskShow = true
                MPNowPlayingInfoCenter.default().nowPlayingInfo = resource.nowPlayingInfo?.nowPlayingInfo
            }
        }
    }

    // MARK: - UI核心组件
    // 内容覆盖视图，用于显示自定义内容
    public let contentOverlayView = UIView()
    // 控制器视图，包含各种播放控制元素
    public let controllerView = UIView()
    // 导航栏，采用UIStackView实现
    public var navigationBar = UIStackView()
    // 标题标签
    public var titleLabel = UILabel()
    // 字幕标签
    public var subtitleLabel = UILabel()
    // 字幕背景视图
    public var subtitleBackView = UIImageView()
    /// 加载指示器，显示加载状态
    public var loadingIndector: UIView & LoadingIndector = UIActivityIndicatorView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
    /// 快进快退提示视图
    public var seekToView: UIView & SeekViewProtocol = SeekView()
    /// 重播按钮
    public var replayButton = UIButton()
    /// 锁定按钮
    public var lockButton = UIButton()
    /// 是否锁定状态
    public var isLock: Bool { lockButton.isSelected }
    // 控制界面显示状态
    open var isMaskShow = true {
        didSet {
            // 根据锁定状态决定透明度
            let alpha: CGFloat = isMaskShow && !isLock ? 1.0 : 0.0
            UIView.animate(withDuration: 0.3) {
                if self.isPlayed {
                    self.replayButton.alpha = self.isMaskShow ? 1.0 : 0.0
                }
                self.lockButton.alpha = self.isMaskShow ? 1.0 : 0.0
                self.topMaskView.alpha = alpha
                self.bottomMaskView.alpha = alpha
                self.delegate?.playerController(maskShow: self.isMaskShow)
                self.layoutIfNeeded()
            }
            if isMaskShow {
                autoFadeOutViewWithAnimation()
            }
        }
    }

    // 播放器图层
    override public var playerLayer: KSPlayerLayer? {
        didSet {
            // 移除旧的播放视图
            oldValue?.player.view?.removeFromSuperview()
            // 添加新的播放视图
            if let view = playerLayer?.player.view {
                #if canImport(UIKit)
                insertSubview(view, belowSubview: contentOverlayView)
                #else
                addSubview(view, positioned: .below, relativeTo: contentOverlayView)
                #endif
                // 设置自动布局约束
                view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    view.topAnchor.constraint(equalTo: topAnchor),
                    view.leadingAnchor.constraint(equalTo: leadingAnchor),
                    view.bottomAnchor.constraint(equalTo: bottomAnchor),
                    view.trailingAnchor.constraint(equalTo: trailingAnchor),
                ])
            }
        }
    }

    // MARK: - 初始化和事件处理
    // 初始化方法
    override public init(frame: CGRect) {
        super.init(frame: frame)
        setupUIComponents()
        cancellable = playerLayer?.$isPipActive.assign(to: \.isSelected, on: toolBar.pipButton)
        toolBar.onFocusUpdate = { [weak self] _ in
            self?.autoFadeOutViewWithAnimation()
        }
    }

    // MARK: - 按钮事件处理

    override open func onButtonPressed(type: PlayerButtonType, button: UIButton) {
        // 自动隐藏控制界面
        autoFadeOutViewWithAnimation()
        super.onButtonPressed(type: type, button: button)
        // 处理画中画按钮事件
        if type == .pictureInPicture {
            if #available(tvOS 14.0, *) {
                playerLayer?.isPipActive.toggle()
            }
        }
        #if os(tvOS)
        // tvOS平台特定的按钮处理逻辑
        if type == .srt {
            changeSrt(button: button)
        } else if type == .rate {
            changePlaybackRate(button: button)
        } else if type == .definition {
            changeDefinitions(button: button)
        } else if type == .audioSwitch || type == .videoSwitch {
            changeAudioVideo(type, button: button)
        }
        #elseif os(macOS)
//        if let menu = button.menu, let event = NSApplication.shared.currentEvent {
//            NSMenu.popUpContextMenu(menu, with: event, for: button)
//        }
        #endif
    }

    // MARK: - setup UI

    // MARK: - UI组件初始化
    open func setupUIComponents() {
        // 添加主要视图层
        addSubview(contentOverlayView)
        addSubview(controllerView)

        // 设置遮罩层渐变效果
        #if os(macOS)
        topMaskView.gradientLayer.colors = [UIColor.clear.cgColor, UIColor.black.withAlphaComponent(0.5).cgColor]
        #else
        topMaskView.gradientLayer.colors = [UIColor.black.withAlphaComponent(0.5).cgColor, UIColor.clear.cgColor]
        #endif
        bottomMaskView.gradientLayer.colors = topMaskView.gradientLayer.colors
        // 根据配置决定顶部栏显示状态
        topMaskView.isHidden = KSOptions.topBarShowInCase != .always
        // 设置渐变方向
        topMaskView.gradientLayer.startPoint = .zero
        topMaskView.gradientLayer.endPoint = CGPoint(x: 0, y: 1)
        bottomMaskView.gradientLayer.startPoint = CGPoint(x: 0, y: 1)
        bottomMaskView.gradientLayer.endPoint = .zero

        // 初始化加载指示器
        loadingIndector.isHidden = true
        controllerView.addSubview(loadingIndector)
        // MARK: - 顶部视图配置
        // 添加导航栏到顶部遮罩
        topMaskView.addSubview(navigationBar)
        navigationBar.addArrangedSubview(titleLabel)
        // 设置标题样式
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16)

        // MARK: - 底部视图配置
        // 添加工具栏到底部遮罩
        bottomMaskView.addSubview(toolBar)
        toolBar.timeSlider.delegate = self

        // MARK: - 控制器视图配置
        // 添加快进快退提示视图
        controllerView.addSubview(seekToView)
        // 配置重播按钮
        controllerView.addSubview(replayButton)
        replayButton.cornerRadius = 32
        replayButton.titleFont = .systemFont(ofSize: 16)
        replayButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        replayButton.addTarget(self, action: #selector(onButtonPressed(_:)), for: .primaryActionTriggered)
        replayButton.tag = PlayerButtonType.replay.rawValue
        // 配置锁定按钮
        lockButton.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        lockButton.cornerRadius = 32
        lockButton.tag = PlayerButtonType.lock.rawValue
        lockButton.addTarget(self, action: #selector(onButtonPressed(_:)), for: .primaryActionTriggered)
        lockButton.isHidden = true
        // 设置系统图标（如果可用）
        if #available(macOS 11.0, *) {
            replayButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
            replayButton.setImage(UIImage(systemName: "arrow.counterclockwise"), for: .selected)
            lockButton.setImage(UIImage(systemName: "lock.open"), for: .normal)
            lockButton.setImage(UIImage(systemName: "lock"), for: .selected)
        }
        // 设置按钮颜色
        lockButton.tintColor = .white
        replayButton.tintColor = .white
        // 添加到控制器视图
        controllerView.addSubview(lockButton)
        controllerView.addSubview(topMaskView)
        controllerView.addSubview(bottomMaskView)
        // 设置自动布局约束
        addConstraint()
        // 自定义UI组件
        customizeUIComponents()
        // 设置字幕控制
        setupSrtControl()
        // 立即更新布局
        layoutIfNeeded()
    }

    // MARK: - 自定义UI和手势配置
    open func customizeUIComponents() {
        // 配置单击手势
        tapGesture.addTarget(self, action: #selector(tapGestureAction(_:)))
        tapGesture.numberOfTapsRequired = 1
        controllerView.addGestureRecognizer(tapGesture)
        // 配置滑动手势
        panGesture.addTarget(self, action: #selector(panGestureAction(_:)))
        controllerView.addGestureRecognizer(panGesture)
        panGesture.isEnabled = false
        // 配置双击手势
        doubleTapGesture.addTarget(self, action: #selector(doubleTapGestureAction))
        doubleTapGesture.numberOfTapsRequired = 2
        // 确保单击手势在双击失败后才触发
        tapGesture.require(toFail: doubleTapGesture)
        controllerView.addGestureRecognizer(doubleTapGesture)
        #if canImport(UIKit)
        // 添加远程控制手势（用于支持遥控器等设备）
        addRemoteControllerGestures()
        #endif
    }

    override open func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        // 如果正在滑动进度条，不更新时间
        guard !isSliderSliding else { return }
        super.player(layer: layer, currentTime: currentTime, totalTime: totalTime)
        // 处理字幕显示
        if srtControl.subtitle(currentTime: currentTime) {
            if let part = srtControl.parts.first {
                subtitleBackView.image = part.image
                subtitleLabel.attributedText = part.text
                subtitleBackView.isHidden = false
            } else {
                subtitleBackView.image = nil
                subtitleLabel.attributedText = nil
                subtitleBackView.isHidden = true
            }
        }
    }

    // MARK: - 播放状态代理方法
    override open func player(layer: KSPlayerLayer, state: KSPlayerState) {
        super.player(layer: layer, state: state)
        switch state {
        case .readyToPlay:
            // 播放器准备就绪
            toolBar.timeSlider.isPlayable = true
            // 根据媒体轨道数量决定切换按钮的显示状态
            toolBar.videoSwitchButton.isHidden = layer.player.tracks(mediaType: .video).count < 2
            toolBar.audioSwitchButton.isHidden = layer.player.tracks(mediaType: .audio).count < 2
            if #available(iOS 14.0, tvOS 15.0, *) {
                buildMenusForButtons()
            }
            // 处理字幕
            if let subtitleDataSouce = layer.player.subtitleDataSouce {
                // 要延后增加内嵌字幕。因为有些内嵌字幕是放在视频流的。所以会比readyToPlay回调晚。
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 1) { [weak self] in
                    guard let self else { return }
                    self.srtControl.addSubtitle(dataSouce: subtitleDataSouce)
                    if self.srtControl.selectedSubtitleInfo == nil, layer.options.autoSelectEmbedSubtitle {
                        self.srtControl.selectedSubtitleInfo = self.srtControl.subtitleInfos.first { $0.isEnabled }
                    }
                    self.toolBar.srtButton.isHidden = self.srtControl.subtitleInfos.isEmpty
                    if #available(iOS 14.0, tvOS 15.0, *) {
                        self.buildMenusForButtons()
                    }
                }
            }
        case .buffering:
            // 缓冲中状态
            isPlayed = true
            replayButton.isHidden = true
            replayButton.isSelected = false
            showLoader()
        case .bufferFinished:
            // 缓冲完成状态
            isPlayed = true
            replayButton.isHidden = true
            replayButton.isSelected = false
            hideLoader()
            autoFadeOutViewWithAnimation()
        case .paused, .playedToTheEnd, .error:
            // 暂停、播放结束或错误状态
            hideLoader()
            replayButton.isHidden = false
            seekToView.isHidden = true
            delayItem?.cancel()
            isMaskShow = true
            if state == .playedToTheEnd {
                replayButton.isSelected = true
            }
        case .initialized, .preparing:
            break
        }
    }

    // 重置播放器状态
    override open func resetPlayer() {
        super.resetPlayer()
        delayItem = nil
        toolBar.reset()
        isMaskShow = false
        hideLoader()
        replayButton.isSelected = false
        replayButton.isHidden = false
        seekToView.isHidden = true
        isPlayed = false
        lockButton.isSelected = false
    }

    // MARK: - KSSliderDelegate

    override open func slider(value: Double, event: ControlEvents) {
        if event == .valueChanged {
            delayItem?.cancel()
        } else if event == .touchUpInside {
            autoFadeOutViewWithAnimation()
        }
        super.slider(value: value, event: event)
        if event == .touchDown {
            isSliderSliding = true
        } else if event == .touchUpInside {
            isSliderSliding = false
        }
    }

    // MARK: - 播放控制相关方法
    // 切换清晰度
    open func change(definitionIndex: Int) {
        guard let resource else { return }
        var shouldSeekTo = 0.0
        if let playerLayer, playerLayer.state != .playedToTheEnd {
            shouldSeekTo = playerLayer.player.currentPlaybackTime
        }
        currentDefinition = definitionIndex >= resource.definitions.count ? resource.definitions.count - 1 : definitionIndex
        let asset = resource.definitions[currentDefinition]
        super.set(url: asset.url, options: asset.options)
        if shouldSeekTo > 0 {
            seek(time: shouldSeekTo) { _ in }
        }
    }

    // 设置播放资源
    open func set(resource: KSPlayerResource, definitionIndex: Int = 0, isSetUrl: Bool = true) {
        currentDefinition = definitionIndex >= resource.definitions.count ? resource.definitions.count - 1 : definitionIndex
        if isSetUrl {
            let asset = resource.definitions[currentDefinition]
            super.set(url: asset.url, options: asset.options)
        }
        self.resource = resource
    }

    override open func set(url: URL, options: KSOptions) {
        set(resource: KSPlayerResource(url: url, options: options))
    }

    // MARK: - 手势处理相关方法
    // 处理双击手势
    @objc open func doubleTapGestureAction() {
        // 触发播放/暂停按钮事件
        toolBar.playButton.sendActions(for: .primaryActionTriggered)
        isMaskShow = true
    }

    // 处理单击手势
    @objc open func tapGestureAction(_: UITapGestureRecognizer) {
        // 切换控制界面显示状态
        isMaskShow.toggle()
    }

    // 处理滑动手势开始
    open func panGestureBegan(location _: CGPoint, direction: KSPanDirection) {
        if direction == .horizontal {
            // 给tmpPanValue初值
            if totalTime > 0 {
                tmpPanValue = toolBar.timeSlider.value
            }
        }
    }

    // 处理滑动手势变化
    open func panGestureChanged(velocity point: CGPoint, direction: KSPanDirection) {
        // 如果禁用了播放时间手势，直接返回
        if direction == .horizontal {
            if !KSOptions.enablePlaytimeGestures {
                return
            }
            isSliderSliding = true
            if totalTime > 0 {
                // 每次滑动需要叠加时间，通过一定的比例，使滑动一直处于统一水平
                tmpPanValue += panValue(velocity: point, direction: direction, currentTime: Float(toolBar.currentTime), totalTime: Float(totalTime))
                tmpPanValue = max(min(tmpPanValue, Float(totalTime)), 0)
                // 显示快进/快退提示
                showSeekToView(second: Double(tmpPanValue), isAdd: point.x > 0)
            }
        }
    }

    // 计算滑动值
    open func panValue(velocity point: CGPoint, direction: KSPanDirection, currentTime _: Float, totalTime: Float) -> Float {
        if direction == .horizontal {
            return max(min(Float(point.x) / 0x40000, 0.01), -0.01) * totalTime
        } else {
            return -Float(point.y) / 0x2800
        }
    }

    // 处理滑动手势结束
    open func panGestureEnded() {
        // 移动结束也需要判断垂直或者平移
        // 比如水平移动结束时，要快进到指定位置，如果这里没有判断，当我们调节音量完之后，会出现屏幕跳动的bug
        if scrollDirection == .horizontal, KSOptions.enablePlaytimeGestures {
            hideSeekToView()
            isSliderSliding = false
            slider(value: Double(tmpPanValue), event: .touchUpInside)
            tmpPanValue = 0.0
        }
    }
}

// MARK: - Action Response

extension VideoPlayerView {
    @available(iOS 14.0, tvOS 15.0, *)
    func buildMenusForButtons() {
        #if !os(tvOS)
        toolBar.definitionButton.setMenu(title: NSLocalizedString("video quality", comment: ""), current: resource?.definitions[currentDefinition], list: resource?.definitions ?? []) { value in
            value.definition
        } completition: { [weak self] value in
            guard let self else { return }
            if let value, let index = self.resource?.definitions.firstIndex(of: value) {
                self.change(definitionIndex: index)
            }
        }
        let videoTracks = playerLayer?.player.tracks(mediaType: .video) ?? []
        toolBar.videoSwitchButton.setMenu(title: NSLocalizedString("switch video", comment: ""), current: videoTracks.first(where: { $0.isEnabled }), list: videoTracks) { value in
            value.name + " \(value.naturalSize.width)x\(value.naturalSize.height)"
        } completition: { [weak self] value in
            guard let self else { return }
            if let value {
                self.playerLayer?.player.select(track: value)
            }
        }
        let audioTracks = playerLayer?.player.tracks(mediaType: .audio) ?? []
        toolBar.audioSwitchButton.setMenu(title: NSLocalizedString("switch audio", comment: ""), current: audioTracks.first(where: { $0.isEnabled }), list: audioTracks) { value in
            value.description
        } completition: { [weak self] value in
            guard let self else { return }
            if let value {
                self.playerLayer?.player.select(track: value)
            }
        }
        toolBar.playbackRateButton.setMenu(title: NSLocalizedString("speed", comment: ""), current: playerLayer?.player.playbackRate ?? 1, list: [0.75, 1.0, 1.25, 1.5, 2.0]) { value in
            "\(value) x"
        } completition: { [weak self] value in
            guard let self else { return }
            if let value {
                self.playerLayer?.player.playbackRate = value
            }
        }
        toolBar.srtButton.setMenu(title: NSLocalizedString("subtitle", comment: ""), current: srtControl.selectedSubtitleInfo, list: srtControl.subtitleInfos, addDisabled: true) { value in
            value.name
        } completition: { [weak self] value in
            guard let self else { return }
            self.srtControl.selectedSubtitleInfo = value
        }
        #if os(iOS)
        toolBar.definitionButton.showsMenuAsPrimaryAction = true
        toolBar.videoSwitchButton.showsMenuAsPrimaryAction = true
        toolBar.audioSwitchButton.showsMenuAsPrimaryAction = true
        toolBar.playbackRateButton.showsMenuAsPrimaryAction = true
        toolBar.srtButton.showsMenuAsPrimaryAction = true
        #endif
        #endif
    }
}

// MARK: - playback rate, definitions, audio and video tracks change

public extension VideoPlayerView {
    // 处理音频和视频切换
    private func changeAudioVideo(_ type: PlayerButtonType, button _: UIButton) {
        // 获取对应类型的媒体轨道
        guard let tracks = playerLayer?.player.tracks(mediaType: type == .audioSwitch ? .audio : .video) else {
            return
        }
        // 创建提示对话框
        let alertController = UIAlertController(title: NSLocalizedString(type == .audioSwitch ? "switch audio" : "switch video", comment: ""), message: nil, preferredStyle: preferredStyle())
        // 为每个轨道添加选项
        for track in tracks {
            let isEnabled = track.isEnabled
            var title = track.name
            if type == .videoSwitch {
                title += " \(track.naturalSize.width)x\(track.naturalSize.height)"
            }
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self, !isEnabled else { return }
                self.playerLayer?.player.select(track: track)
            }
            alertController.addAction(action)
            // 设置当前选中项
            if isEnabled {
                alertController.preferredAction = action
                action.setValue(isEnabled, forKey: "checked")
            }
        }
        // 添加取消按钮
        alertController.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel, handler: nil))
        viewController?.present(alertController, animated: true, completion: nil)
    }

    // 切换清晰度选项
    private func changeDefinitions(button _: UIButton) {
        guard let resource, resource.definitions.count > 1 else { return }
        // 创建清晰度选择对话框
        let alertController = UIAlertController(title: NSLocalizedString("select video quality", comment: ""), message: nil, preferredStyle: preferredStyle())
        // 添加所有清晰度选项
        for (index, definition) in resource.definitions.enumerated() {
            let action = UIAlertAction(title: definition.definition, style: .default) { [weak self] _ in
                guard let self, index != self.currentDefinition else { return }
                self.change(definitionIndex: index)
            }
            alertController.addAction(action)
            // 标记当前选中的清晰度
            if index == currentDefinition {
                alertController.preferredAction = action
                action.setValue(true, forKey: "checked")
            }
        }
        // 添加取消选项
        alertController.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel, handler: nil))
        viewController?.present(alertController, animated: true, completion: nil)
    }

    // 切换字幕
    private func changeSrt(button _: UIButton) {
        let availableSubtitles = srtControl.subtitleInfos
        guard !availableSubtitles.isEmpty else { return }

        // 创建字幕选择对话框
        let alertController = UIAlertController(title: NSLocalizedString("subtitle", comment: ""),
                                                message: nil,
                                                preferredStyle: preferredStyle())

        let currentSub = srtControl.selectedSubtitleInfo

        // 添加禁用字幕选项
        let disableAction = UIAlertAction(title: NSLocalizedString("Disabled", comment: ""), style: .default) { [weak self] _ in
            self?.srtControl.selectedSubtitleInfo = nil
        }
        alertController.addAction(disableAction)
        if currentSub == nil {
            alertController.preferredAction = disableAction
            disableAction.setValue(true, forKey: "checked")
        }

        // 添加所有可用字幕选项
        for (_, srt) in availableSubtitles.enumerated() {
            let action = UIAlertAction(title: srt.name, style: .default) { [weak self] _ in
                self?.srtControl.selectedSubtitleInfo = srt
            }
            alertController.addAction(action)
            // 标记当前选中的字幕
            if currentSub?.subtitleID == srt.subtitleID {
                alertController.preferredAction = action
                action.setValue(true, forKey: "checked")
            }
        }

        // 添加取消选项
        alertController.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel, handler: nil))
        viewController?.present(alertController, animated: true, completion: nil)
    }

    // 更改播放速度
    private func changePlaybackRate(button: UIButton) {
        // 创建播放速度选择对话框
        let alertController = UIAlertController(title: NSLocalizedString("select speed", comment: ""), message: nil, preferredStyle: preferredStyle())
        // 添加预设播放速度选项
        for rate in [0.75, 1.0, 1.25, 1.5, 2.0] {
            let title = "\(rate) x"
            let action = UIAlertAction(title: title, style: .default) { [weak self] _ in
                guard let self else { return }
                button.setTitle(title, for: .normal)
                self.playerLayer?.player.playbackRate = Float(rate)
            }
            alertController.addAction(action)

            // 标记当前选中的播放速度
            if Float(rate) == playerLayer?.player.playbackRate {
                alertController.preferredAction = action
                action.setValue(true, forKey: "checked")
            }
        }
        // 添加取消选项
        alertController.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel, handler: nil))
        viewController?.present(alertController, animated: true, completion: nil)
    }
}

// MARK: - 进度控制相关功能

public extension VideoPlayerView {
    /**
     处理用户使用滑动条进行快进快退时的显示

     - parameter second: 目标时间点
     - parameter isAdd: 是否为快进
     */
    func showSeekToView(second: TimeInterval, isAdd: Bool) {
        // 显示控制界面
        isMaskShow = true
        // 显示快进快退提示
        seekToView.isHidden = false
        // 更新当前时间显示
        toolBar.currentTime = second
        // 设置提示文本和方向
        seekToView.set(text: second.toString(for: toolBar.timeType), isAdd: isAdd)
    }

    // 隐藏快进快退提示
    func hideSeekToView() {
        seekToView.isHidden = true
    }
}

// MARK: - 私有辅助方法

extension VideoPlayerView {
    // 处理滑动手势
    @objc private func panGestureAction(_ pan: UIPanGestureRecognizer) {
        // 播放结束时，忽略手势,锁屏状态忽略手势
        guard !replayButton.isSelected, !isLock else { return }
        // 根据上次和本次移动的位置，算出一个速率的point
        let velocityPoint = pan.velocity(in: self)
        switch pan.state {
        case .began:
            // 使用绝对值来判断移动的方向
            if abs(velocityPoint.x) > abs(velocityPoint.y) {
                scrollDirection = .horizontal
            } else {
                scrollDirection = .vertical
            }
            panGestureBegan(location: pan.location(in: self), direction: scrollDirection)
        case .changed:
            panGestureChanged(velocity: velocityPoint, direction: scrollDirection)
        case .ended:
            panGestureEnded()
        default:
            break
        }
    }

    /// 播放期间更新字幕
    public func updateSrt() {
        // 设置字幕字体
        subtitleLabel.font = SubtitleModel.textFont
        if #available(macOS 11.0, iOS 14, tvOS 14, *) {
            // 设置字幕颜色和背景色
            subtitleLabel.textColor = UIColor(SubtitleModel.textColor)
            subtitleBackView.backgroundColor = UIColor(SubtitleModel.textBackgroundColor)
        }
    }

    private func setupSrtControl() {
        // 配置字幕标签的基本属性
        subtitleLabel.numberOfLines = 0 // 允许多行显示
        subtitleLabel.textAlignment = .center   // 文本居中对齐
        // 设置字幕标签的阴影效果,使字幕在不同背景下都清晰可见
        subtitleLabel.backingLayer?.shadowColor = UIColor.black.cgColor // 阴影颜色为黑色
        subtitleLabel.backingLayer?.shadowOffset = CGSize(width: 1.0, height: 1.0)   // 阴影偏移量
        subtitleLabel.backingLayer?.shadowOpacity = 0.9 // 阴影不透明度
        subtitleLabel.backingLayer?.shadowRadius = 1.0  // 阴影半径
        subtitleLabel.backingLayer?.shouldRasterize = true  // 开启光栅化以提高性能
        // 更新字幕样式(字体、颜色等)
        updateSrt()
        // 配置字幕背景视图
        subtitleBackView.contentMode = .scaleAspectFit // 设置内容缩放模式为自适应填充
        subtitleBackView.cornerRadius = 2 // 设置圆角半径
        subtitleBackView.addSubview(subtitleLabel) // 将字幕标签添加到背景视图
        subtitleBackView.isHidden = true // 初始状态下隐藏字幕背景
        addSubview(subtitleBackView) // 将字幕背景视图添加到播放器视图
        // 设置自动布局属性
        subtitleBackView.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        // 添加布局约束
        NSLayoutConstraint.activate([
            // 设置字幕背景视图距离底部的间距
            subtitleBackView.bottomAnchor.constraint(equalTo: safeBottomAnchor, constant: -5),
            // 水平居中对齐
            subtitleBackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            // 设置最大宽度(不超过父视图宽度减去10像素)
            subtitleBackView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -10),
            // 设置字幕标签在背景视图中的位置约束
            subtitleLabel.leadingAnchor.constraint(equalTo: subtitleBackView.leadingAnchor, constant: 10),
            subtitleLabel.trailingAnchor.constraint(equalTo: subtitleBackView.trailingAnchor, constant: -10),
            subtitleLabel.topAnchor.constraint(equalTo: subtitleBackView.topAnchor, constant: 2),
            subtitleLabel.bottomAnchor.constraint(equalTo: subtitleBackView.bottomAnchor, constant: -2),
        ])
    }

    /**
     自动隐藏控制视图的动画效果
     */
    private func autoFadeOutViewWithAnimation() {
        // 取消之前的延时任务(如果存在)
        delayItem?.cancel()
        // 只在视频播放状态下自动隐藏控件
        guard toolBar.playButton.isSelected else { return }
        // 创建新的延时任务
        delayItem = DispatchWorkItem { [weak self] in
            // 延时后隐藏控制界面
            self?.isMaskShow = false
        }
        // 延迟指定时间后执行隐藏操作
        // KSOptions.animateDelayTimeInterval 默认为5秒
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + KSOptions.animateDelayTimeInterval,
                                      execute: delayItem!)
    }

    // 显示加载指示器
    private func showLoader() {
        loadingIndector.isHidden = false
        loadingIndector.startAnimating()
    }

    // 隐藏加载指示器
    private func hideLoader() {
        loadingIndector.isHidden = true
        loadingIndector.stopAnimating()
    }

    private func addConstraint() {
        if #available(macOS 11.0, *) {
            #if !targetEnvironment(macCatalyst)
            toolBar.timeSlider.setThumbImage(UIImage(systemName: "circle.fill"), for: .normal)
            #if os(macOS)
            toolBar.timeSlider.setThumbImage(UIImage(systemName: "circle.fill"), for: .highlighted)
            #else
            toolBar.timeSlider.setThumbImage(UIImage(systemName: "circle.fill", withConfiguration: UIImage.SymbolConfiguration(scale: .large)), for: .highlighted)
            #endif
            #endif
        }
        bottomMaskView.addSubview(toolBar.timeSlider)
        toolBar.audioSwitchButton.isHidden = true
        toolBar.videoSwitchButton.isHidden = true
        toolBar.pipButton.isHidden = true
        contentOverlayView.translatesAutoresizingMaskIntoConstraints = false
        controllerView.translatesAutoresizingMaskIntoConstraints = false
        toolBar.timeSlider.translatesAutoresizingMaskIntoConstraints = false
        topMaskView.translatesAutoresizingMaskIntoConstraints = false
        bottomMaskView.translatesAutoresizingMaskIntoConstraints = false
        navigationBar.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingIndector.translatesAutoresizingMaskIntoConstraints = false
        seekToView.translatesAutoresizingMaskIntoConstraints = false
        replayButton.translatesAutoresizingMaskIntoConstraints = false
        lockButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentOverlayView.topAnchor.constraint(equalTo: topAnchor),
            contentOverlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentOverlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentOverlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
            controllerView.topAnchor.constraint(equalTo: topAnchor),
            controllerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            controllerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            controllerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topMaskView.topAnchor.constraint(equalTo: topAnchor),
            topMaskView.leadingAnchor.constraint(equalTo: leadingAnchor),
            topMaskView.trailingAnchor.constraint(equalTo: trailingAnchor),
            topMaskView.heightAnchor.constraint(equalToConstant: 105),
            navigationBar.topAnchor.constraint(equalTo: topMaskView.topAnchor),
            navigationBar.leadingAnchor.constraint(equalTo: topMaskView.safeLeadingAnchor, constant: 15),
            navigationBar.trailingAnchor.constraint(equalTo: topMaskView.safeTrailingAnchor, constant: -15),
            navigationBar.heightAnchor.constraint(equalToConstant: 44),
            bottomMaskView.bottomAnchor.constraint(equalTo: bottomAnchor),
            bottomMaskView.leadingAnchor.constraint(equalTo: leadingAnchor),
            bottomMaskView.trailingAnchor.constraint(equalTo: trailingAnchor),
            bottomMaskView.heightAnchor.constraint(equalToConstant: 105),
            loadingIndector.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingIndector.centerXAnchor.constraint(equalTo: centerXAnchor),
            seekToView.centerYAnchor.constraint(equalTo: centerYAnchor),
            seekToView.centerXAnchor.constraint(equalTo: centerXAnchor),
            seekToView.widthAnchor.constraint(equalToConstant: 100),
            seekToView.heightAnchor.constraint(equalToConstant: 40),
            replayButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            replayButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            lockButton.leadingAnchor.constraint(equalTo: safeLeadingAnchor, constant: 22),
            lockButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        configureToolBarConstraints()
    }

    private func configureToolBarConstraints() {
        #if os(tvOS)
        toolBar.spacing = 10
        toolBar.addArrangedSubview(toolBar.playButton)
        toolBar.addArrangedSubview(toolBar.timeLabel)
        toolBar.addArrangedSubview(toolBar.playbackRateButton)
        toolBar.addArrangedSubview(toolBar.definitionButton)
        toolBar.addArrangedSubview(toolBar.audioSwitchButton)
        toolBar.addArrangedSubview(toolBar.videoSwitchButton)
        toolBar.addArrangedSubview(toolBar.srtButton)
        toolBar.addArrangedSubview(toolBar.pipButton)

        toolBar.setCustomSpacing(20, after: toolBar.timeLabel)
        toolBar.setCustomSpacing(20, after: toolBar.playbackRateButton)
        toolBar.setCustomSpacing(20, after: toolBar.definitionButton)
        toolBar.setCustomSpacing(20, after: toolBar.srtButton)

        NSLayoutConstraint.activate([
            toolBar.bottomAnchor.constraint(equalTo: bottomMaskView.safeBottomAnchor),
            toolBar.leadingAnchor.constraint(equalTo: bottomMaskView.safeLeadingAnchor, constant: 10),
            toolBar.trailingAnchor.constraint(equalTo: bottomMaskView.safeTrailingAnchor, constant: -15),
            toolBar.timeSlider.bottomAnchor.constraint(equalTo: toolBar.topAnchor, constant: -8),
            toolBar.timeSlider.leadingAnchor.constraint(equalTo: bottomMaskView.safeLeadingAnchor, constant: 15),
            toolBar.timeSlider.trailingAnchor.constraint(equalTo: bottomMaskView.safeTrailingAnchor, constant: -15),
            toolBar.timeSlider.heightAnchor.constraint(equalToConstant: 16),
        ])

        #else

        toolBar.playButton.tintColor = .white
        toolBar.playbackRateButton.tintColor = .white
        toolBar.definitionButton.tintColor = .white
        toolBar.audioSwitchButton.tintColor = .white
        toolBar.videoSwitchButton.tintColor = .white
        toolBar.srtButton.tintColor = .white
        toolBar.pipButton.tintColor = .white

        toolBar.spacing = 10
        toolBar.addArrangedSubview(toolBar.playButton)
        toolBar.addArrangedSubview(toolBar.timeLabel)
        toolBar.addArrangedSubview(toolBar.playbackRateButton)
        toolBar.addArrangedSubview(toolBar.definitionButton)
        toolBar.addArrangedSubview(toolBar.audioSwitchButton)
        toolBar.addArrangedSubview(toolBar.videoSwitchButton)
        toolBar.addArrangedSubview(toolBar.srtButton)
        toolBar.addArrangedSubview(toolBar.pipButton)

        toolBar.setCustomSpacing(20, after: toolBar.timeLabel)
        toolBar.setCustomSpacing(20, after: toolBar.playbackRateButton)
        toolBar.setCustomSpacing(20, after: toolBar.definitionButton)
        toolBar.setCustomSpacing(20, after: toolBar.srtButton)

        NSLayoutConstraint.activate([
            toolBar.bottomAnchor.constraint(equalTo: bottomMaskView.safeBottomAnchor),
            toolBar.leadingAnchor.constraint(equalTo: bottomMaskView.safeLeadingAnchor, constant: 10),
            toolBar.trailingAnchor.constraint(equalTo: bottomMaskView.safeTrailingAnchor, constant: -15),
            toolBar.timeSlider.bottomAnchor.constraint(equalTo: toolBar.topAnchor),
            toolBar.timeSlider.leadingAnchor.constraint(equalTo: bottomMaskView.safeLeadingAnchor, constant: 15),
            toolBar.timeSlider.trailingAnchor.constraint(equalTo: bottomMaskView.safeTrailingAnchor, constant: -15),
            toolBar.timeSlider.heightAnchor.constraint(equalToConstant: 30),
        ])
        #endif
    }

    private func preferredStyle() -> UIAlertController.Style {
        #if canImport(UIKit)
        // 在手机设备上使用 actionSheet 样式,其他设备使用 alert 样式
        return UIDevice.current.userInterfaceIdiom == .phone ? .actionSheet : .alert
        #else
        return .alert
        #endif
    }

    #if canImport(UIKit)
    // 添加遥控器手势
    private func addRemoteControllerGestures() {
        // 添加右箭头按键手势识别
        let rightPressRecognizer = UITapGestureRecognizer()
        rightPressRecognizer.addTarget(self, action: #selector(rightArrowButtonPressed(_:)))
        rightPressRecognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.rightArrow.rawValue)]
        addGestureRecognizer(rightPressRecognizer)

        // 添加左箭头按键手势识别
        let leftPressRecognizer = UITapGestureRecognizer()
        leftPressRecognizer.addTarget(self, action: #selector(leftArrowButtonPressed(_:)))
        leftPressRecognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.leftArrow.rawValue)]
        addGestureRecognizer(leftPressRecognizer)

        // 添加选择按键(确认)手势识别
        let selectPressRecognizer = UITapGestureRecognizer()
        selectPressRecognizer.addTarget(self, action: #selector(selectButtonPressed(_:)))
        selectPressRecognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
        addGestureRecognizer(selectPressRecognizer)

        // 添加向上滑动手势识别
        let swipeUpRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipedUp(_:)))
        swipeUpRecognizer.direction = .up
        addGestureRecognizer(swipeUpRecognizer)

        // 添加向下滑动手势识别
        let swipeDownRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(swipedDown(_:)))
        swipeDownRecognizer.direction = .down
        addGestureRecognizer(swipeDownRecognizer)
    }

    @objc
    private func rightArrowButtonPressed(_: UITapGestureRecognizer) {
        // 确保播放器正在播放且可以进行跳转
        guard let playerLayer, playerLayer.state.isPlaying, toolBar.isSeekable else { return }
        // 快进15秒
        seek(time: toolBar.currentTime + 15) { _ in }
    }

    @objc
    private func leftArrowButtonPressed(_: UITapGestureRecognizer) {
        // 确保播放器正在播放且可以进行跳转
        guard let playerLayer, playerLayer.state.isPlaying, toolBar.isSeekable else { return }
        // 快退15秒
        seek(time: toolBar.currentTime - 15) { _ in }
    }

    @objc
    private func selectButtonPressed(_: UITapGestureRecognizer) {
        // 确保可以进行播放控制
        guard toolBar.isSeekable else { return }
        // 切换播放/暂停状态
        if let playerLayer, playerLayer.state.isPlaying {
            pause()
        } else {
            play()
        }
    }

    @objc
    private func swipedUp(_: UISwipeGestureRecognizer) {
        // 确保播放器正在播放
        guard let playerLayer, playerLayer.state.isPlaying else { return }
        // 如果控制界面当前是隐藏状态,则显示
        if isMaskShow == false {
            isMaskShow = true
        }
    }

    @objc
    private func swipedDown(_: UISwipeGestureRecognizer) {
        // 确保播放器正在播放
        guard let playerLayer, playerLayer.state.isPlaying else { return }
        // 如果控制界面当前是显示状态,则隐藏
        if isMaskShow == true {
            isMaskShow = false
        }
    }
    #endif
}

// 定义顶部栏显示的场景
public enum KSPlayerTopBarShowCase {
    /// 始终显示
    case always
    /// 只在横屏界面显示
    case horizantalOnly
    /// 不显示
    case none
}

// KSOptions 扩展,定义播放器的全局配置选项
public extension KSOptions {
    /// 顶部返回、标题、AirPlay按钮 显示选项，默认.Always，可选.HorizantalOnly、.None
    static var topBarShowInCase = KSPlayerTopBarShowCase.always
    /// 自动隐藏操作栏的时间间隔 默认5秒
    static var animateDelayTimeInterval = TimeInterval(5)
    /// 开启亮度手势 默认true
    static var enableBrightnessGestures = true
    /// 开启音量手势 默认true
    static var enableVolumeGestures = true
    /// 开启进度滑动手势 默认true
    static var enablePlaytimeGestures = true
    /// 播放内核选择策略 先使用firstPlayer，失败了自动切换到secondPlayer，播放内核有KSAVPlayer、KSMEPlayer两个选项
    /// 是否能后台播放视频
    static var canBackgroundPlay = false
}

extension UIView {
    // 获取宽度约束
    var widthConstraint: NSLayoutConstraint? {
        // 防止返回NSContentSizeLayoutConstraint
        // 查找自身约束中第一个作用于width属性的约束
        constraints.first { $0.isMember(of: NSLayoutConstraint.self) && $0.firstAttribute == .width }
    }

    // 获取高度约束
    var heightConstraint: NSLayoutConstraint? {
        // 防止返回NSContentSizeLayoutConstraint
        // 查找自身约束中第一个作用于height属性的约束
        constraints.first { $0.isMember(of: NSLayoutConstraint.self) && $0.firstAttribute == .height }
    }

    // 获取trailing约束(右边缘约束)
    var trailingConstraint: NSLayoutConstraint? {
        // 在父视图的约束中查找第一个作用于当前视图trailing属性的约束
        superview?.constraints.first { $0.firstItem === self && $0.firstAttribute == .trailing }
    }

    // 获取leading约束(左边缘约束)
    var leadingConstraint: NSLayoutConstraint? {
        superview?.constraints.first { $0.firstItem === self && $0.firstAttribute == .leading }
    }

    // 获取top约束(顶部约束)
    var topConstraint: NSLayoutConstraint? {
        superview?.constraints.first { $0.firstItem === self && $0.firstAttribute == .top }
    }

    // 获取bottom约束(底部约束)
    var bottomConstraint: NSLayoutConstraint? {
        superview?.constraints.first { $0.firstItem === self && $0.firstAttribute == .bottom }
    }

    // 获取水平居中约束
    var centerXConstraint: NSLayoutConstraint? {
        superview?.constraints.first { $0.firstItem === self && $0.firstAttribute == .centerX }
    }

    // 获取垂直居中约束
    var centerYConstraint: NSLayoutConstraint? {
        superview?.constraints.first { $0.firstItem === self && $0.firstAttribute == .centerY }
    }

    // 获取所有布局约束
    var frameConstraints: [NSLayoutConstraint] {
        // 获取所有与当前视图相关的约束
        var frameConstraint = superview?.constraints.filter { constraint in
            constraint.firstItem === self
        } ?? [NSLayoutConstraint]()
        // 添加视图自身的宽高约束
        for constraint in constraints where
            constraint.isMember(of: NSLayoutConstraint.self) && constraint.firstItem === self && (constraint.firstAttribute == .width || constraint.firstAttribute == .height)
        {
            frameConstraint.append(constraint)
        }
        return frameConstraint
    }

    // 获取考虑安全区域的顶部锚点
    var safeTopAnchor: NSLayoutYAxisAnchor {
        if #available(macOS 11.0, *) {
            return self.safeAreaLayoutGuide.topAnchor
        } else {
            return topAnchor
        }
    }

    // 获取可读区域的顶部锚点
    var readableTopAnchor: NSLayoutYAxisAnchor {
        #if os(macOS)
        topAnchor
        #else
        readableContentGuide.topAnchor
        #endif
    }

    // 获取考虑安全区域的左侧锚点
    var safeLeadingAnchor: NSLayoutXAxisAnchor {
        if #available(macOS 11.0, *) {
            return self.safeAreaLayoutGuide.leadingAnchor
        } else {
            return leadingAnchor
        }
    }

    // 获取考虑安全区域的右侧锚点
    var safeTrailingAnchor: NSLayoutXAxisAnchor {
        if #available(macOS 11.0, *) {
            return self.safeAreaLayoutGuide.trailingAnchor
        } else {
            return trailingAnchor
        }
    }

    // 获取考虑安全区域的底部锚点
    var safeBottomAnchor: NSLayoutYAxisAnchor {
        if #available(macOS 11.0, *) {
            return self.safeAreaLayoutGuide.bottomAnchor
        } else {
            return bottomAnchor
        }
    }
}
