//
//  KSPlayerLayerView.swift
//  Pods
//
//  Created by kintan on 16/4/28.
//
//
import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/**
 Player status emun
 - setURL:      set url
 - readyToPlay:    player ready to play
 - buffering:      player buffering
 - bufferFinished: buffer finished
 - playedToTheEnd: played to the End
 - error:          error with playing
 */
public enum KSPlayerState: CustomStringConvertible {
    case initialized
    case preparing
    case readyToPlay
    case buffering
    case bufferFinished
    case paused
    case playedToTheEnd
    case error
    public var description: String {
        switch self {
        case .initialized:
            return "initialized"
        case .preparing:
            return "preparing"
        case .readyToPlay:
            return "readyToPlay"
        case .buffering:
            return "buffering"
        case .bufferFinished:
            return "bufferFinished"
        case .paused:
            return "paused"
        case .playedToTheEnd:
            return "playedToTheEnd"
        case .error:
            return "error"
        }
    }

    public var isPlaying: Bool { self == .buffering || self == .bufferFinished }
}

@MainActor
public protocol KSPlayerLayerDelegate: AnyObject {
    func player(layer: KSPlayerLayer, state: KSPlayerState)
    func player(layer: KSPlayerLayer, currentTime: TimeInterval, totalTime: TimeInterval)
    func player(layer: KSPlayerLayer, finish error: Error?)
    func player(layer: KSPlayerLayer, bufferedCount: Int, consumeTime: TimeInterval)
}

open class KSPlayerLayer: NSObject, MediaPlayerDelegate {
    public weak var delegate: KSPlayerLayerDelegate?
    @Published
    public var bufferingProgress: Int = 0
    @Published
    public var loopCount: Int = 0
    public private(set) var options: KSOptions {
        didSet {
            options.audioRecognizes = subtitleModel.subtitleInfos.compactMap { info in
                info as? AudioRecognize
            }
        }
    }

    public let subtitleVC: UIHostingController<VideoSubtitleView>
    public var player: MediaPlayerProtocol {
        didSet {
            KSLog("player is \(player)")
            state = .initialized
            runOnMainThread { [weak self] in
                guard let self else { return }
                if let superview = oldValue.view.superview {
                    let view = player.view
                    #if canImport(UIKit)
                    superview.insertSubview(view, belowSubview: oldValue.view)
                    #else
                    superview.addSubview(view, positioned: .below, relativeTo: oldValue.view)
                    #endif
                    view.frame = oldValue.view.frame
                    view.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        view.topAnchor.constraint(equalTo: superview.topAnchor),
                        view.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
                        view.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
                        view.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
                    ])
                }
                oldValue.view.removeFromSuperview()
            }
            player.playbackRate = oldValue.playbackRate
            player.playbackVolume = oldValue.playbackVolume
            player.delegate = self
            player.contentMode = .scaleAspectFit
            if isAutoPlay {
                prepareToPlay()
            }
        }
    }

    public internal(set) var url: URL {
        didSet {
            subtitleModel.url = url
            let firstPlayerType = KSOptions.firstPlayerType
            if type(of: player) == firstPlayerType {
                if url == oldValue, state != .initialized {
                    if isAutoPlay {
                        play()
                    }
                } else {
                    state = .initialized
                    player.replace(url: url, options: options)
                    if isAutoPlay {
                        prepareToPlay()
                    }
                }
            } else {
                player.shutdown()
                player = firstPlayerType.init(url: url, options: options)
            }
        }
    }

    /// 播发器的几种状态

    public private(set) var state = KSPlayerState.initialized {
        willSet {
            if state != newValue {
                change(state: newValue)
            }
        }
    }

    private lazy var timer: Timer = .scheduledTimer(withTimeInterval: options.subtitleTimeInterval, repeats: true) { [weak self] _ in
        guard let self, self.player.isReadyToPlay else {
            return
        }
        self.play(currentTime: self.player.currentPlaybackTime)
    }

    var isAutoPlay: Bool
    private var isWirelessRouteActive = false
    private var bufferedCount = 0
    private var shouldSeekTo: TimeInterval = 0
    private var startTime: TimeInterval = 0
    public let subtitleModel: SubtitleModel

    public required init(url: URL, options: KSOptions, delegate: KSPlayerLayerDelegate? = nil) {
        self.url = url
        self.options = options
        self.delegate = delegate
        let firstPlayerType: MediaPlayerProtocol.Type
        player = KSOptions.firstPlayerType.init(url: url, options: options)
        isAutoPlay = KSOptions.isAutoPlay
        subtitleModel = SubtitleModel(url: url)
        subtitleVC = UIHostingController(rootView: VideoSubtitleView(model: subtitleModel))
        /// macos <=13 会报错-[NSNib _initWithNibNamed:bundle:options:] could not load the nibName: _TtGC7SwiftUI19NSHostingControllerV8KSPlayer17VideoSubtitleView_ in bundle NSBundle
        /// 所以就先注释掉，注释掉之后我测试了下iOS、tvOS、macOS字幕都不会问题。
//        subtitleVC.loadView()
        subtitleVC.view.backgroundColor = .clear
        subtitleVC.view.translatesAutoresizingMaskIntoConstraints = false
        super.init()
        options.audioRecognizes = subtitleModel.subtitleInfos.compactMap { info in
            info as? AudioRecognize
        }
        player.playbackRate = options.startPlayRate
        player.delegate = self
        player.contentMode = .scaleAspectFit
        if isAutoPlay {
            prepareToPlay()
        }
        #if canImport(UIKit) && !os(xrOS)
        NotificationCenter.default.addObserver(self, selector: #selector(wirelessRouteActiveDidChange(notification:)), name: .MPVolumeViewWirelessRouteActiveDidChange, object: nil)
        #endif
        #if !os(macOS)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted), name: AVAudioSession.interruptionNotification, object: nil)
        #endif
    }

    deinit {}

    public func set(url: URL, options: KSOptions) {
        self.options = options
        isAutoPlay = KSOptions.isAutoPlay
        runOnMainThread {
            self.url = url
        }
    }

    open func change(state: KSPlayerState) {
        if state == .initialized {
            bufferedCount = 0
            shouldSeekTo = 0
            player.playbackRate = 1
            player.playbackVolume = 1
            runOnMainThread {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        } else if state == .buffering || state == .bufferFinished {
            timer.fireDate = .distantPast
        } else {
            timer.fireDate = .distantFuture
        }
        runOnMainThread { [weak self] in
            guard let self else { return }
            KSLog("playerStateDidChange - \(state)")
            self.delegate?.player(layer: self, state: state)
        }
    }

    @MainActor
    open func play(currentTime: TimeInterval) {
        if player.playbackState != .seeking {
            if subtitleModel.isHDR != options.dynamicRange.isHDR {
                if KSOptions.enableHDRSubtitle {
                    subtitleModel.isHDR = options.dynamicRange.isHDR
                } else if subtitleModel.isHDR {
                    subtitleModel.isHDR = false
                }
            }
            // pip播放的时候用view.frame.size获取到的大小不对，要用subtitleVC的
            var screenSize = subtitleVC.view.frame.size
            if screenSize.width == 0 || screenSize.height == 0 {
                screenSize = player.view.frame.size
            }
            subtitleModel.subtitle(currentTime: currentTime, playSize: player.naturalSize.within(size: screenSize), screenSize: screenSize)
        }
        delegate?.player(layer: self, currentTime: currentTime, totalTime: player.duration)
        if player.playbackState == .playing, player.loadState == .playable, state == .buffering {
            // 一个兜底保护，正常不能走到这里
            state = .bufferFinished
        }
    }

    open func play() {
        runOnMainThread {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        isAutoPlay = true
        if state == .error || state == .initialized || (state == .playedToTheEnd && !player.seekable) {
            prepareToPlay()
        }
        if player.isReadyToPlay {
            if state == .playedToTheEnd {
                player.seek(time: 0) { [weak self] finished in
                    guard let self else { return }
                    if finished {
                        self.player.play()
                    }
                }
            } else {
                player.play()
            }
        }
    }

    open func pause() {
        isAutoPlay = false
        player.pause()
        runOnMainThread {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // 这个是用来清空资源，例如断开网络和缓存，调用这个方法之后，就要调用replace(url)才能重新开始播放
    public func reset() {
        state = .initialized
        subtitleModel.selectedSubtitleInfo = nil
        player.reset()
    }

//    deinit之前调用stop
    open func stop() {
        KSLog("stop KSPlayerLayer")
        state = .initialized
        subtitleModel.selectedSubtitleInfo = nil
        subtitleVC.view.removeFromSuperview()
        player.stop()
        options.playerLayerDeinit()
    }

    open func seek(time: TimeInterval, autoPlay: Bool, completion: @escaping ((Bool) -> Void)) {
        if time.isInfinite || time.isNaN {
            completion(false)
        }
        if player.isReadyToPlay, player.seekable {
            if abs(time - player.currentPlaybackTime) < 1 {
                if autoPlay {
                    play()
                }
                return
            }
            subtitleModel.cleanParts()
            player.seek(time: time) { [weak self] finished in
                guard let self else { return }
                if finished, autoPlay {
                    state = .buffering
                    self.play()
                }
                completion(finished)
            }
        } else {
            isAutoPlay = autoPlay
            shouldSeekTo = time
            completion(false)
        }
    }

    func seek(time: TimeInterval) {
        seek(time: time, autoPlay: options.isSeekedAutoPlay) { _ in
        }
    }

    open func prepareToPlay() {
        state = .preparing
        startTime = CACurrentMediaTime()
        bufferedCount = 0
        player.prepareToPlay()
    }

    public func readyToPlay(player: some MediaPlayerProtocol) {
        addSubtitle(to: player.view)
        if let subtitleDataSource = player.subtitleDataSource {
            if subtitleModel.selectedSubtitleInfo == nil, let infos = subtitleDataSource.infos as? [MediaPlayerTrack & SubtitleInfo] {
                subtitleModel.selectedSubtitleInfo = options.wantedSubtitle(tracks: infos) as? SubtitleInfo
            }
            // 要延后增加内嵌字幕。因为有些内嵌字幕是放在视频流的。所以会比readyToPlay回调晚。有些视频1s可能不够，所以改成2s
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 2) { [weak self] in
                guard let self else { return }
                self.subtitleModel.addSubtitle(dataSource: subtitleDataSource)
            }
        }
        state = .readyToPlay
        #if os(macOS)
        runOnMainThread { [weak self] in
            guard let self else { return }
            if let window = player.view.window {
                window.isMovableByWindowBackground = true
                if options.automaticWindowResize {
                    let naturalSize = player.naturalSize
                    if naturalSize.width > 0, naturalSize.height > 0 {
                        window.aspectRatio = naturalSize
                        var frame = window.frame
                        frame.size.height = frame.width * naturalSize.height / naturalSize.width
                        window.setFrame(frame, display: true)
                    }
                }
            }
        }
        #endif
        if isAutoPlay {
            if shouldSeekTo > 0 {
                seek(time: shouldSeekTo, autoPlay: true) { [weak self] _ in
                    guard let self else { return }
                    self.shouldSeekTo = 0
                }

            } else {
                play()
            }
        }
    }

    open func changeLoadState(player: some MediaPlayerProtocol) {
        guard player.playbackState != .seeking else {
            // seek的时候不要变成是buffering。不然会以为处于播放状态，显示播放按钮。
            return
        }
        if player.loadState == .playable, startTime > 0 {
            let diff = CACurrentMediaTime() - startTime
            runOnMainThread { [weak self] in
                guard let self else { return }
                delegate?.player(layer: self, bufferedCount: bufferedCount, consumeTime: diff)
            }
            if bufferedCount == 0 {
                var dic = ["firstTime": diff]
                if options.tcpConnectedTime > 0 {
                    dic["initTime"] = options.dnsStartTime - startTime
                    dic["dnsTime"] = options.tcpStartTime - options.dnsStartTime
                    dic["tcpTime"] = options.tcpConnectedTime - options.tcpStartTime
                    dic["openTime"] = options.openTime - options.tcpConnectedTime
                    dic["findTime"] = options.findTime - options.openTime
                } else {
                    dic["openTime"] = options.openTime - startTime
                }
                dic["findTime"] = options.findTime - options.openTime
                dic["readyTime"] = options.readyTime - options.findTime
                dic["readVideoTime"] = options.readVideoTime - options.readyTime
                dic["readAudioTime"] = options.readAudioTime - options.readyTime
                dic["decodeVideoTime"] = options.decodeVideoTime - options.readVideoTime
                dic["decodeAudioTime"] = options.decodeAudioTime - options.readAudioTime
                KSLog(dic)
            }
            bufferedCount += 1
            startTime = 0
        }
        if player.playbackState == .paused {
            state = .paused
        } else if player.playbackState == .playing {
            if player.loadState == .playable {
                state = .bufferFinished
            } else {
                if state == .bufferFinished {
                    startTime = CACurrentMediaTime()
                }
                state = .buffering
            }
        }
    }

    public func changeBuffering(player _: some MediaPlayerProtocol, progress: Int) {
        bufferingProgress = progress
    }

    public func playBack(player _: some MediaPlayerProtocol, loopCount: Int) {
        self.loopCount = loopCount
    }

    public func finish(player: some MediaPlayerProtocol, error: Error?) {
        if let error {
            state = .error
            KSLog(error as CustomStringConvertible)
        } else {
            state = .playedToTheEnd
        }
        bufferedCount = 1
        let duration = player.duration
        runOnMainThread { [weak self] in
            guard let self else { return }
            if error == nil {
                delegate?.player(layer: self, currentTime: duration, totalTime: duration)
            }
            delegate?.player(layer: self, finish: error)
        }
    }

    #if canImport(UIKit) && !os(xrOS)
    @MainActor
    @objc private func wirelessRouteActiveDidChange(notification: Notification) {
        guard let volumeView = notification.object as? MPVolumeView, isWirelessRouteActive != volumeView.isWirelessRouteActive else { return }
        if volumeView.isWirelessRouteActive {
            if !player.allowsExternalPlayback {
                isWirelessRouteActive = true
            }
            player.usesExternalPlaybackWhileExternalScreenIsActive = true
        }
        isWirelessRouteActive = volumeView.isWirelessRouteActive
    }
    #endif
    #if !os(macOS)
    @objc private func audioInterrupted(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else {
            return
        }
        KSLog("[audio] audioInterrupted \(type)")
        switch type {
        case .began:
            pause()

        case .ended:
            // An interruption ended. Resume playback, if appropriate.
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // 一定要延迟下播放，不然播放会没有声音
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.8) { [weak self] in
                    self?.play()
                }
            }

        default:
            break
        }
    }
    #endif
    fileprivate func addSubtitle(to view: UIView) {
        if subtitleVC.view.superview != view {
            view.addSubview(subtitleVC.view)
            subtitleVC.view.translatesAutoresizingMaskIntoConstraints = false
            let constraints = [
                subtitleVC.view.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                subtitleVC.view.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                subtitleVC.view.widthAnchor.constraint(equalTo: view.widthAnchor),
                subtitleVC.view.heightAnchor.constraint(equalTo: view.heightAnchor),
            ]
            #if os(macOS)
            // 要加这个，不然字幕无法显示出来
            if #available(macOS 13.0, *) {
                subtitleVC.sizingOptions = .maxSize
            }
            // 要加这个，不然还没字幕的时候，视频播放界面会变成zero
            for constraint in constraints {
                constraint.priority = .defaultLow
            }
            #endif
            NSLayoutConstraint.activate(constraints)
        }
    }
}

public extension KSPlayerLayer {
    var isPictureInPictureActive: Bool {
        player.pipController?.isPictureInPictureActive ?? false
    }
}

open class KSComplexPlayerLayer: KSPlayerLayer {
    private var urls = [URL]()

    @MainActor
    public required init(url: URL, options: KSOptions, delegate: KSPlayerLayerDelegate? = nil) {
        super.init(url: url, options: options, delegate: delegate)
        if options.registerRemoteControll {
            registerRemoteControllEvent()
        }
        #if canImport(UIKit)
        runOnMainThread { [weak self] in
            guard let self else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(enterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(enterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
        #endif
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    public func pipStart() {
        if let pipController = player.pipController {
            pipController.start(layer: self)
        } else {
            player.configPIP()
            if #available(tvOS 14.0, *) {
                player.pipController?.delegate = self
            }
            // 刚创建pip的话，需要等待0.3才能pip
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, let pipController = self.player.pipController else { return }
                pipController.start(layer: self)
            }
        }
    }

    @MainActor
    public func pipStop(restoreUserInterface: Bool) {
        player.pipController?.stop(restoreUserInterface: restoreUserInterface)
    }

    public func set(urls: [URL]) {
        self.urls.removeAll()
        self.urls.append(contentsOf: urls)
        if let first = urls.first {
            runOnMainThread {
                self.url = first
            }
        }
    }

    override open func change(state: KSPlayerState) {
        super.change(state: state)
        if state == .initialized {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }

    override open func play(currentTime: TimeInterval) {
        super.play(currentTime: currentTime)
        if player.isPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
    }

    override open func play() {
        super.play()
        MPNowPlayingInfoCenter.default().playbackState = .playing
        if #available(tvOS 14.0, *) {
            KSOptions.pictureInPictureType.mute()
        }
    }

    override open func pause() {
        super.pause()
        MPNowPlayingInfoCenter.default().playbackState = .paused
    }

    override public func readyToPlay(player: some MediaPlayerProtocol) {
        super.readyToPlay(player: player)
        if options.canStartPictureInPictureAutomaticallyFromInline, player.pipController == nil {
            player.configPIP()
            if #available(tvOS 14.0, *) {
                player.pipController?.delegate = self
            }
        }
        updateNowPlayingInfo()
    }

    override public func finish(player: some MediaPlayerProtocol, error: (any Error)?) {
        if let error {
            KSLog(error as CustomStringConvertible)
            if type(of: player) != KSOptions.secondPlayerType, let secondPlayerType = KSOptions.secondPlayerType {
                self.player = secondPlayerType.init(url: url, options: options)
                return
            }
        }
        super.finish(player: player, error: error)
        if error == nil {
            nextPlayer()
        }
    }

    override open func stop() {
        super.stop()
        if #available(tvOS 14.0, *) {
            player.pipController?.delegate = nil
        }
        player.pipController = nil
        NotificationCenter.default.removeObserver(self)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        removeRemoteControllEvent()
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@available(tvOS 14.0, *)
extension KSComplexPlayerLayer: AVPictureInPictureControllerDelegate {
    @MainActor
    public func pictureInPictureControllerDidStartPictureInPicture(_: AVPictureInPictureController) {
        pipAddSubtitle()
        player.pipController?.didStart(layer: self)
    }

    @MainActor
    public func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        pipStop(restoreUserInterface: false)
        addSubtitle(to: player.view)
    }

    @MainActor
    public func pictureInPictureController(_: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler _: @escaping (Bool) -> Void) {
        pipStop(restoreUserInterface: true)
    }
}

// MARK: - private functions

extension KSComplexPlayerLayer {
    private func updateNowPlayingInfo() {
        if MPNowPlayingInfoCenter.default().nowPlayingInfo == nil {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyPlaybackDuration: player.duration]
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyPlaybackDuration] = player.duration
        }
        if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] == nil, let title = player.dynamicInfo?.metadata["title"] {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] = title
        }
        if MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtist] == nil, let artist = player.dynamicInfo?.metadata["artist"] {
            MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyArtist] = artist
        }
        var current: [MPNowPlayingInfoLanguageOption] = []
        var langs: [MPNowPlayingInfoLanguageOptionGroup] = []
        for track in player.tracks(mediaType: .audio) {
            if let lang = track.language {
                let audioLang = MPNowPlayingInfoLanguageOption(type: .audible, languageTag: lang, characteristics: nil, displayName: track.name, identifier: track.name)
                let audioGroup = MPNowPlayingInfoLanguageOptionGroup(languageOptions: [audioLang], defaultLanguageOption: nil, allowEmptySelection: false)
                langs.append(audioGroup)
                if track.isEnabled {
                    current.append(audioLang)
                }
            }
        }
        if !langs.isEmpty {
            MPRemoteCommandCenter.shared().enableLanguageOptionCommand.isEnabled = true
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyAvailableLanguageOptions] = langs
        MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyCurrentLanguageOptions] = current
    }

    private func nextPlayer() {
        if urls.count > 1, let index = urls.firstIndex(of: url), index < urls.count - 1 {
            isAutoPlay = true
            url = urls[index + 1]
        }
    }

    private func previousPlayer() {
        if urls.count > 1, let index = urls.firstIndex(of: url), index > 0 {
            isAutoPlay = true
            url = urls[index - 1]
        }
    }

    public func removeRemoteControllEvent() {
        MPRemoteCommandCenter.shared().playCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().pauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().stopCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changeRepeatModeCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackRateCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().skipForwardCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().skipBackwardCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(nil)
        MPRemoteCommandCenter.shared().enableLanguageOptionCommand.removeTarget(nil)
    }

    public func registerRemoteControllEvent() {
        let remoteCommand = MPRemoteCommandCenter.shared()
        remoteCommand.playCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.play()
            return .success
        }
        remoteCommand.pauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.pause()
            return .success
        }
        remoteCommand.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            if self.state.isPlaying {
                self.pause()
            } else {
                self.play()
            }
            return .success
        }
        remoteCommand.stopCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.player.shutdown()
            return .success
        }
        remoteCommand.nextTrackCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.nextPlayer()
            return .success
        }
        remoteCommand.previousTrackCommand.addTarget { [weak self] _ in
            guard let self else {
                return .commandFailed
            }
            self.previousPlayer()
            return .success
        }
        remoteCommand.changeRepeatModeCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeRepeatModeCommandEvent else {
                return .commandFailed
            }
            self.options.isLoopPlay = event.repeatType != .off
            return .success
        }
        remoteCommand.changeShuffleModeCommand.isEnabled = false
        // remoteCommand.changeShuffleModeCommand.addTarget {})
        remoteCommand.changePlaybackRateCommand.supportedPlaybackRates = [0.5, 1, 1.5, 2]
        remoteCommand.changePlaybackRateCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackRateCommandEvent else {
                return .commandFailed
            }
            self.player.playbackRate = event.playbackRate
            return .success
        }
        remoteCommand.skipForwardCommand.preferredIntervals = [15]
        remoteCommand.skipForwardCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            self.seek(time: self.player.currentPlaybackTime + event.interval)
            return .success
        }
        remoteCommand.skipBackwardCommand.preferredIntervals = [15]
        remoteCommand.skipBackwardCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPSkipIntervalCommandEvent else {
                return .commandFailed
            }
            self.seek(time: self.player.currentPlaybackTime - event.interval)
            return .success
        }
        remoteCommand.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            self.seek(time: event.positionTime)
            return .success
        }
        remoteCommand.enableLanguageOptionCommand.addTarget { [weak self] event in
            guard let self, let event = event as? MPChangeLanguageOptionCommandEvent else {
                return .commandFailed
            }
            let selectLang = event.languageOption
            if selectLang.languageOptionType == .audible,
               let trackToSelect = self.player.tracks(mediaType: .audio).first(where: { $0.name == selectLang.displayName })
            {
                self.player.select(track: trackToSelect)
            }
            return .success
        }
    }

    @objc private func enterBackground() {
        guard state.isPlaying, !player.isExternalPlaybackActive else {
            return
        }
        if isPictureInPictureActive {
            pipAddSubtitle()
            return
        }

        if KSOptions.canBackgroundPlay {
            player.enterBackground()
            return
        }
        pause()
    }

    @objc private func enterForeground() {
        guard !player.isExternalPlaybackActive else {
            return
        }
        if isPictureInPictureActive {
            if !options.canStartPictureInPictureAutomaticallyFromInline {
                pipStop(restoreUserInterface: true)

                // 要延迟清空，这样delegate的方法才能调用，不然会导致回到前台，字幕无法显示了。并且1秒还不行，一定要2秒
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self else { return }
                    if #available(tvOS 14.0, *) {
                        player.pipController?.delegate = nil
                    }
                    player.pipController = nil
                }
            }
            return
        }
        if !KSOptions.canBackgroundPlay {
            player.enterForeground()
        }
    }

    private func pipAddSubtitle() {
        if let pipVC = (player.pipController as? NSObject)?.value(forKey: "pictureInPictureViewController") as? UIViewController {
            addSubtitle(to: pipVC.view)
        }
    }
}
