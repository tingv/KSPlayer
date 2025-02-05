//
//  KSMPVPlayer.swift
//
//
//  Created by kintan on 5/2/24.
//

import AVFoundation
import AVKit
import CoreGraphics
import Dispatch
import Foundation
import KSPlayer
import libmpv
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
public class KSMPVPlayer: MPVHandle {
    public weak var delegate: MediaPlayerDelegate?
    public var allowsExternalPlayback: Bool = false
    public var usesExternalPlaybackWhileExternalScreenIsActive: Bool = false
    public private(set) var isReadyToPlay = false
    public private(set) var playbackState = MediaPlaybackState.idle
    public private(set) var loadState = MediaLoadState.idle
    public var seekable: Bool = false
    public var duration: TimeInterval = 0
    public var fileSize: Int64 = 0
    public var naturalSize: CGSize = .zero
    private lazy var _playbackCoordinator: Any? = {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, *) {
            let coordinator = AVDelegatingPlaybackCoordinator(playbackControlDelegate: self)
            coordinator.suspensionReasonsThatTriggerWaiting = [.stallRecovery]
            return coordinator
        } else {
            return nil
        }
    }()

    private var tracks = [MPVTrack]()
    private var bufferingCountDownTimer: Timer?
    private var url: URL
    @MainActor
    public var pipController: KSPictureInPictureProtocol? = nil
    @MainActor
    public required init(url: URL, options: KSOptions) {
        self.url = url
        super.init(options: options)
    }

    override public func event(_ event: mpv_event) {
        super.event(event)
        switch event.event_id {
        case MPV_EVENT_FILE_LOADED:
            sourceDidOpened()
        default:
            break
        }
    }

    override public func change(property: mpv_event_property, name: String) {
        super.change(property: property, name: name)
        switch name {
        case "pause":
            if let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                if paused {
                    playbackState = .paused
                }
            }
        case MPVProperty.pausedForCache:
            if let paused = UnsafePointer<Bool>(OpaquePointer(property.data))?.pointee {
                loadState = paused ? .loading : .playable
            }
        default:
            break
        }
    }

    func sourceDidOpened() {
        isReadyToPlay = true
        seekable = getFlag(MPVProperty.seekable)
        duration = getDouble(MPVProperty.duration)
        fileSize = Int64(getInt(MPVProperty.fileSize))
        naturalSize = CGSize(width: getInt(MPVProperty.width), height: getInt(MPVProperty.height))
        let trackCount = getInt(MPVProperty.trackListCount)
        tracks = (0 ..< trackCount).compactMap { index in
            guard let trackType = getString(MPVProperty.trackListNType(index)), let mediaType = trackType.mpvToMediaType else {
                return nil
            }
            let track = MPVTrack(trackID: Int32(getInt(MPVProperty.trackListNId(index))), name: getString(MPVProperty.trackListNTitle(index)) ?? "", mediaType: mediaType, nominalFrameRate: Float(getDouble(MPVProperty.trackListNDemuxFps(index))), bitRate: 0, bitDepth: 0, isEnabled: getFlag(MPVProperty.trackListNSelected(index)), isImageSubtitle: false, rotation: 0, fieldOrder: .unknown, description: getString(MPVProperty.trackListNDecoderDesc(index)) ?? "")
            track.languageCode = getString(MPVProperty.trackListNLang(index))
            return track
        }
        runOnMainThread { [weak self] in
            guard let self else {
                return
            }
            self.delegate?.readyToPlay(player: self)
        }
    }
}

extension KSMPVPlayer: MediaPlayerProtocol {
    public func startRecord(url _: URL) {}

    public func stopRecord() {}

    public var view: UIView {
        metalView
    }

    public var playableTime: TimeInterval {
        1
    }

    public var isMuted: Bool {
        get {
            getFlag(MPVOption.Audio.mute)
        }
        set(newValue) {
            setFlag(MPVOption.Audio.mute, newValue)
        }
    }

    public var playbackRate: Float {
        get {
            Float(getDouble(MPVOption.PlaybackControl.speed))
        }
        set(newValue) {
            setDouble(MPVOption.PlaybackControl.speed, Double(newValue))
        }
    }

    public var playbackVolume: Float {
        get {
            Float(getDouble(MPVOption.Audio.volume))
        }
        set(newValue) {
            setDouble(MPVOption.Audio.volume, Double(newValue))
        }
    }

    public var subtitleDataSource: (any KSPlayer.ConstantSubtitleDataSource)? {
        nil
    }

    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    public var playbackCoordinator: AVPlaybackCoordinator {
        // swiftlint:disable force_cast
        _playbackCoordinator as! AVPlaybackCoordinator
        // swiftlint:enable force_cast
    }

    public var dynamicInfo: KSPlayer.DynamicInfo? {
        nil
    }

    public func replace(url: URL, options _: KSPlayer.KSOptions) {
        self.url = url
        prepareToPlay()
    }

    public func play() {
        playbackState = .playing
        setFlagAsync(MPVOption.PlaybackControl.pause, false)
    }

    public func pause() {
        playbackState = .paused
        setFlagAsync(MPVOption.PlaybackControl.pause, true)
    }

    public func enterBackground() {}

    public func enterForeground() {}

    public func thumbnailImageAtCurrentTime() async -> CGImage? {
        nil
    }

    public func tracks(mediaType: AVMediaType) -> [any KSPlayer.MediaPlayerTrack] {
        tracks.filter { $0.mediaType == mediaType }
    }

    public func select(track _: some KSPlayer.MediaPlayerTrack) {}

    public var chapters: [KSPlayer.Chapter] {
        []
    }

    public var currentPlaybackTime: TimeInterval {
        getDouble(MPVProperty.timePos)
    }

    public func prepareToPlay() {
        loadFile(url: url)
    }

    public func stop() {
        if let mpv {
            mpv_set_wakeup_callback(mpv, nil, nil)
        }
        command(.stop)
    }

    public func reset() {
        if let mpv {
            mpv_set_wakeup_callback(mpv, nil, nil)
        }
        command(.stop)
    }

    public func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void)) {
        playbackState = .seeking
        command(.seek, args: [String(time), "absolute"]) { [weak self] code in
            completion(code == 0)
        }
    }

    public func configPIP() {}
}

extension KSMPVPlayer {
    private func loadFile(url: URL, options: [String] = []) {
        let urlString: String
        if url.isFileURL {
            urlString = url.path
        } else {
            urlString = url.absoluteString
        }
        var args = [urlString]
        if !options.isEmpty {
            args.append(options.joined(separator: ","))
        }
        command(.loadfile, args: args)
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
@MainActor
extension KSMPVPlayer: AVPlaybackCoordinatorPlaybackControlDelegate {
    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue playCommand: AVDelegatingPlaybackCoordinatorPlayCommand, completionHandler: @escaping () -> Void) {
        guard playCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .playing {
                self.play()
            }
            completionHandler()
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue pauseCommand: AVDelegatingPlaybackCoordinatorPauseCommand, completionHandler: @escaping () -> Void) {
        guard pauseCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            if self.playbackState != .paused {
                self.pause()
            }
            completionHandler()
        }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue seekCommand: AVDelegatingPlaybackCoordinatorSeekCommand) async {
        guard seekCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            return
        }
        let seekTime = fmod(seekCommand.itemTime.seconds, duration)
        if abs(currentPlaybackTime - seekTime) < CGFLOAT_EPSILON {
            return
        }
        seek(time: seekTime) { _ in }
    }

    public func playbackCoordinator(_: AVDelegatingPlaybackCoordinator, didIssue bufferingCommand: AVDelegatingPlaybackCoordinatorBufferingCommand, completionHandler: @escaping () -> Void) {
        guard bufferingCommand.expectedCurrentItemIdentifier == (playbackCoordinator as? AVDelegatingPlaybackCoordinator)?.currentItemIdentifier else {
            completionHandler()
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            guard self.loadState != .playable, let countDown = bufferingCommand.completionDueDate?.timeIntervalSinceNow else {
                completionHandler()
                return
            }
            self.bufferingCountDownTimer?.invalidate()
            self.bufferingCountDownTimer = nil
            self.bufferingCountDownTimer = Timer(timeInterval: countDown, repeats: false) { _ in
                completionHandler()
            }
        }
    }
}

public class MPVTrack: MediaPlayerTrack {
    public var trackID: Int32
    public var name: String
    public var mediaType: AVMediaType

    public var nominalFrameRate: Float

    public var bitRate: Int64

    public var bitDepth: Int32

    public var isEnabled: Bool

    public var isImageSubtitle: Bool

    public var rotation: Int16

    public var fieldOrder: KSPlayer.FFmpegFieldOrder
    public var description: String
    public var languageCode: String? = nil
    public var formatDescription: CMFormatDescription? = nil
    public var dovi: KSPlayer.DOVIDecoderConfigurationRecord? = nil
    init(trackID: Int32, name: String, mediaType: AVMediaType, nominalFrameRate: Float, bitRate: Int64, bitDepth: Int32, isEnabled: Bool, isImageSubtitle: Bool, rotation: Int16, fieldOrder: KSPlayer.FFmpegFieldOrder, description: String) {
        self.trackID = trackID
        self.name = name
        self.mediaType = mediaType
        self.nominalFrameRate = nominalFrameRate
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.isEnabled = isEnabled
        self.isImageSubtitle = isImageSubtitle
        self.rotation = rotation
        self.fieldOrder = fieldOrder
        self.description = description
    }
}

extension String {
    var mpvToMediaType: AVMediaType? {
        switch self {
        case "video":
            return AVMediaType.video
        case "audio":
            return AVMediaType.audio
        case "sub":
            return AVMediaType.subtitle
        default:
            return nil
        }
    }
}
