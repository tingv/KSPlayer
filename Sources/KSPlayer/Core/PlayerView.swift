//
//  PlayerView.swift
//  VoiceNote
//
//  Created by kintan on 2018/8/16.
//

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import AVFoundation

public enum PlayerButtonType: Int {
    case play = 101      // 播放按钮
    case pause           // 暂停按钮
    case back           // 返回按钮
    case srt            // 字幕按钮
    case landscape      // 横屏按钮
    case replay         // 重播按钮
    case lock           // 锁定按钮
    case rate           // 播放速率按钮
    case definition     // 清晰度按钮
    case pictureInPicture // 画中画按钮
    case audioSwitch    // 音频切换按钮
    case videoSwitch    // 视频切换按钮
    case extended       // 扩展设置按钮
}

/// 播放器控制器代理协议
public protocol PlayerControllerDelegate: AnyObject {
    /// 播放器状态变化回调
    func playerController(state: KSPlayerState)
    /// 播放进度更新回调
    func playerController(currentTime: TimeInterval, totalTime: TimeInterval)
    /// 播放完成回调
    func playerController(finish error: Error?)
    /// 控制界面显示/隐藏回调
    func playerController(maskShow: Bool)
    /// 按钮动作回调
    func playerController(action: PlayerButtonType)
    /// 缓冲进度回调
    /// - Parameters:
    ///   - bufferedCount: 缓冲次数，0 表示首次加载
    ///   - consumeTime: 缓冲耗时
    func playerController(bufferedCount: Int, consumeTime: TimeInterval)
    /// 跳转进度回调
    func playerController(seek: TimeInterval)
}

/// 播放器视图类，实现了基础播放器功能
open class PlayerView: UIView, KSPlayerLayerDelegate, KSSliderDelegate {
    // MARK: - 公共属性
    public typealias ControllerDelegate = PlayerControllerDelegate
    /// 播放层，负责实际的视频播放
    public var playerLayer: KSPlayerLayer? {
        didSet {
            playerLayer?.delegate = self
        }
    }

    /// 控制器代理
    public weak var delegate: ControllerDelegate?
    /// 工具栏，包含播放控制按钮等界面元素
    public let toolBar = PlayerToolBar()
    /// 字幕控制器
    public let srtControl = SubtitleModel()
    /// 播放时间变化回调
    public var playTimeDidChange: ((TimeInterval, TimeInterval) -> Void)?
    /// 返回按钮回调
    public var backBlock: (() -> Void)?

    // MARK: - 初始化方法

    public convenience init() {
        #if os(macOS)
        self.init(frame: .zero)
        #else
        self.init(frame: CGRect(origin: .zero, size: KSOptions.sceneSize))
        #endif
    }

    override public init(frame: CGRect) {
        super.init(frame: frame)
        toolBar.timeSlider.delegate = self
        toolBar.addTarget(self, action: #selector(onButtonPressed(_:)))
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 公共方法

    @objc func onButtonPressed(_ button: UIButton) {
        guard let type = PlayerButtonType(rawValue: button.tag) else { return }

        #if os(macOS)
        if let menu = button.menu,
           let item = button.menu?.items.first(where: { $0.state == .on })
        {
            menu.popUp(positioning: item,
                       at: button.frame.origin,
                       in: self)
        } else {
            onButtonPressed(type: type, button: button)
        }
        #elseif os(tvOS)
        onButtonPressed(type: type, button: button)
        #else
        if #available(iOS 14.0, *), button.menu != nil {
            return
        }
        onButtonPressed(type: type, button: button)
        #endif
    }

    /// 处理按钮点击事件
    open func onButtonPressed(type: PlayerButtonType, button: UIButton) {
        // 处理播放/暂停按钮状态切换
        var type = type
        if type == .play, button.isSelected {
            type = .pause
        }
        switch type {
        case .back:
            backBlock?()
        case .play, .replay:
            play()
        case .pause:
            pause()
        default:
            break
        }
        delegate?.playerController(action: type)
    }

    #if canImport(UIKit)
    override open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let presse = presses.first else {
            return
        }
        switch presse.type {
        case .playPause:
            if let playerLayer, playerLayer.state.isPlaying {
                pause()
            } else {
                play()
            }
        default: super.pressesBegan(presses, with: event)
        }
    }
    #endif
    /// 开始播放
    open func play() {
        becomeFirstResponder()
        playerLayer?.play()
        toolBar.playButton.isSelected = true
    }

    /// 暂停播放
    open func pause() {
        playerLayer?.pause()
    }

    /// 跳转到指定时间点
    /// - Parameters:
    ///   - time: 目标时间
    ///   - completion: 完成回调
    open func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        playerLayer?.seek(time: time, autoPlay: KSOptions.isSeekedAutoPlay, completion: completion)
    }

    /// 重新播放
    open func resetPlayer() {
        pause()
        totalTime = 0.0
    }

    /// 设置播放地址和选项
    /// - Parameters:
    ///   - url: 视频URL
    ///   - options: 播放选项
    open func set(url: URL, options: KSOptions) {
        srtControl.url = url
        toolBar.currentTime = 0
        totalTime = 0
        playerLayer = KSPlayerLayer(url: url, options: options)
    }

    // MARK: - KSSliderDelegate

    /// 处理进度条滑动事件
    open func slider(value: Double, event: ControlEvents) {
        if event == .valueChanged {
            toolBar.currentTime = value
        } else if event == .touchUpInside {
            seek(time: value) { [weak self] _ in
                self?.delegate?.playerController(seek: value)
            }
        }
    }

    // MARK: - KSPlayerLayerDelegate

    /// 处理播放器状态变化
    open func player(layer: KSPlayerLayer, state: KSPlayerState) {
        delegate?.playerController(state: state)
        if state == .readyToPlay {
            totalTime = layer.player.duration
            toolBar.isSeekable = layer.player.seekable
            toolBar.playButton.isSelected = true
        } else if state == .playedToTheEnd || state == .paused || state == .error {
            toolBar.playButton.isSelected = false
        }
    }

    /// 处理播放进度更新
    open func player(layer _: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        delegate?.playerController(currentTime: currentTime, totalTime: totalTime)
        playTimeDidChange?(currentTime, totalTime)
        toolBar.currentTime = currentTime
        self.totalTime = totalTime
    }

    /// 处理播放完成事件
    open func player(layer _: KSPlayerLayer, finish error: Error?) {
        delegate?.playerController(finish: error)
    }

    /// 处理缓冲进度更新
    open func player(layer _: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval) {
        delegate?.playerController(bufferedCount: bufferedCount, consumeTime: consumeTime)
    }
}

public extension PlayerView {
    var totalTime: TimeInterval {
        get {
            toolBar.totalTime
        }
        set {
            toolBar.totalTime = newValue
        }
    }
}

extension UIView {
    /// 获取当前视图所属的视图控制器
    /// 通过遍历响应链(responder chain)来查找持有该视图的UIViewController
    var viewController: UIViewController? {
        // 获取响应链中的下一个响应者
        var next = next
        // 循环遍历响应链
        while next != nil {
            // 尝试将响应者转换为UIViewController
            if let viewController = next as? UIViewController {
                return viewController
            }
            // 继续查找下一个响应者
            next = next?.next
        }
        // 如果没有找到对应的视图控制器，返回nil
        return nil
    }
}
