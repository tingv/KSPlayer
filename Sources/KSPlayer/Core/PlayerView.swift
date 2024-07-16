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
    case play = 101
    case pause
    case back
    case srt
    case landscape
    case replay
    case lock
    case rate
    case definition
    case pictureInPicture
    case audioSwitch
    case videoSwitch
}

public protocol PlayerControllerDelegate: AnyObject {
    func playerController(state: KSPlayerState)
    func playerController(currentTime: TimeInterval, totalTime: TimeInterval)
    func playerController(finish error: Error?)
    func playerController(maskShow: Bool)
    func playerController(action: PlayerButtonType)
    // `bufferedCount: 0` indicates first time loading
    func playerController(bufferedCount: Int, consumeTime: TimeInterval)
    func playerController(seek: TimeInterval)
}

open class PlayerView: UIView, KSPlayerLayerDelegate, KSSliderDelegate {
    public typealias ControllerDelegate = PlayerControllerDelegate
    public var playerLayer: KSPlayerLayer? {
        didSet {
            playerLayer?.delegate = self
        }
    }

    public weak var delegate: ControllerDelegate?
    public let toolBar = PlayerToolBar()
    public let srtControl = SubtitleModel()
    // Listen to play time change
    public var playTimeDidChange: ((TimeInterval, TimeInterval) -> Void)?
    public var backBlock: (() -> Void)?
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

    open func onButtonPressed(type: PlayerButtonType, button: UIButton) {
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
    open func play() {
        becomeFirstResponder()
        playerLayer?.play()
        toolBar.playButton.isSelected = true
    }

    open func pause() {
        playerLayer?.pause()
    }

    open func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        playerLayer?.seek(time: time, autoPlay: KSOptions.isSeekedAutoPlay, completion: completion)
    }

    open func resetPlayer() {
        pause()
        totalTime = 0.0
    }

    open func set(url: URL, options: KSOptions) {
        srtControl.url = url
        toolBar.currentTime = 0
        totalTime = 0
        playerLayer = KSPlayerLayer(url: url, options: options)
    }

    // MARK: - KSSliderDelegate

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

    open func player(layer: KSPlayerLayer, state: KSPlayerState) {
        delegate?.playerController(state: state)
        if state == .readyToPlay {
            totalTime = layer.player.duration
            toolBar.isSeekable = layer.player.seekable
            toolBar.playButton.isSelected = true
            if #available(iOS 14.0, tvOS 15.0, *) {
                buildMenusForButtons()
            }
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
        } else if state == .playedToTheEnd || state == .paused || state == .error {
            toolBar.playButton.isSelected = false
        }
    }

    open func player(layer _: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval) {
        delegate?.playerController(currentTime: currentTime, totalTime: totalTime)
        playTimeDidChange?(currentTime, totalTime)
        toolBar.currentTime = currentTime
        self.totalTime = totalTime
    }

    open func player(layer _: KSPlayerLayer, finish error: Error?) {
        delegate?.playerController(finish: error)
    }

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

    @available(iOS 14.0, tvOS 15.0, *)
    func buildMenusForButtons() {
        #if !os(tvOS)
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

    func set(subtitleTrack: any SubtitleInfo) {
        // setup the subtitle track
        srtControl.selectedSubtitleInfo = subtitleTrack
    }
}

extension UIView {
    var viewController: UIViewController? {
        var next = next
        while next != nil {
            if let viewController = next as? UIViewController {
                return viewController
            }
            next = next?.next
        }
        return nil
    }
}
