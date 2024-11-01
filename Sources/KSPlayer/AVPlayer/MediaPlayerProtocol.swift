//
//  MediaPlayerProtocol.swift
//  KSPlayer-tvOS
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import AVKit
import Foundation
#if canImport(RealityKit)
import RealityKit
#endif
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

@MainActor
public protocol MediaPlayback: AnyObject {
    var duration: TimeInterval { get }
    var fileSize: Int64 { get }
    var naturalSize: CGSize { get }
    var chapters: [Chapter] { get }
    var currentPlaybackTime: TimeInterval { get }
    var playbackRate: Float { get set }
    func prepareToPlay()
    func seek(time: TimeInterval, completion: @escaping ((Bool) -> Void))
    func startRecord(url: URL)
    func stopRecord()
    // deinit之前调用stop
    func stop()
}

public class DynamicInfo: ObservableObject {
    private let metadataBlock: () -> [String: String]
    private let bytesReadBlock: () -> Int64
    private let audioBitrateBlock: () -> Int
    private let videoBitrateBlock: () -> Int
    public var metadata: [String: String] {
        metadataBlock()
    }

    // 单位是B
    public var bytesRead: Int64 {
        bytesReadBlock()
    }

    // 单位是b/s
    public var audioBitrate: Int {
        audioBitrateBlock()
    }

    // 单位是b/s
    public var videoBitrate: Int {
        videoBitrateBlock()
    }

    @Published
    public var displayFPS = 0.0
    public var audioVideoSyncDiff = 0.0
    public var byteRate = Int64(0)
    public var droppedVideoFrameCount = UInt32(0)
    public var droppedVideoPacketCount = UInt32(0)
    init(metadata: @escaping () -> [String: String], bytesRead: @escaping () -> Int64, audioBitrate: @escaping () -> Int, videoBitrate: @escaping () -> Int) {
        metadataBlock = metadata
        bytesReadBlock = bytesRead
        audioBitrateBlock = audioBitrate
        videoBitrateBlock = videoBitrate
    }
}

public struct Chapter {
    public let start: TimeInterval
    public let end: TimeInterval
    public let title: String
}

@MainActor
public protocol MediaPlayerProtocol: MediaPlayback {
    var delegate: MediaPlayerDelegate? { get set }
    var view: UIView { get }
    var playableTime: TimeInterval { get }
    var isReadyToPlay: Bool { get }
    var playbackState: MediaPlaybackState { get }
    var loadState: MediaLoadState { get }
    var isPlaying: Bool { get }
    var seekable: Bool { get }
    //    var numberOfBytesTransferred: Int64 { get }
    var isMuted: Bool { get set }
    var allowsExternalPlayback: Bool { get set }
    var usesExternalPlaybackWhileExternalScreenIsActive: Bool { get set }
    var isExternalPlaybackActive: Bool { get }
    var playbackVolume: Float { get set }
    var contentMode: UIViewContentMode { get set }
    var subtitleDataSource: (any EmbedSubtitleDataSource)? { get }
    #if canImport(RealityKit)
//    var videoMaterial: VideoMaterial { get }
//    @available(visionOS 1.0, macOS 15.0, iOS 18.0, *)
//    var videoPlayerComponent: VideoPlayerComponent { get }
    #endif
    @available(macOS 12.0, iOS 15.0, tvOS 15.0, *)
    var playbackCoordinator: AVPlaybackCoordinator { get }
    @available(tvOS 14.0, *)
    var pipController: KSPictureInPictureProtocol? { get set }
    var dynamicInfo: DynamicInfo? { get }
    init(url: URL, options: KSOptions)
    func replace(url: URL, options: KSOptions)
    func play()
    func pause()
    // 这个是用来清空资源，例如断开网络和缓存，调用这个方法之后，就要调用replace(url)才能重新开始播放
    func reset()
    func enterBackground()
    func enterForeground()
    func thumbnailImageAtCurrentTime() async -> CGImage?
    func tracks(mediaType: AVFoundation.AVMediaType) -> [MediaPlayerTrack]
    func select(track: some MediaPlayerTrack)
    func configPIP()
}

public extension MediaPlayerProtocol {
    @MainActor
    var contentMode: UIViewContentMode {
        get {
            view.contentMode
        }
        set {
            view.contentMode = newValue
        }
    }

    var isExternalPlaybackActive: Bool { false }
    var isPlaying: Bool { playbackState == .playing }
    var nominalFrameRate: Float {
        // return the frameRate of the video (xxFPS)
        tracks(mediaType: .video).first { $0.isEnabled }?.nominalFrameRate ?? 0
    }

    var frameRate: Float {
        // return the frameRate of the video (xxFPS)
        nominalFrameRate
    }

    var subtitlesTracks: [SubtitleInfo] {
        // Return the availables subtitles
        tracks(mediaType: .subtitle).compactMap { $0 as? SubtitleInfo }
    }

    var audioTracks: [MediaPlayerTrack] {
        // Return the availables subtitles
        tracks(mediaType: .audio) ?? []
    }

    var dynamicRange: DynamicRange? {
        // return the dynamic range of the video
        tracks(mediaType: .video).first { $0.isEnabled }?.dynamicRange
    }

    var audioFormat: String? {
        // return the audioFormat of the video (HDR, SDR, ...)
        (tracks(mediaType: .audio).first { $0.isEnabled } as? FFmpegAssetTrack)?.codecName
    }

    var videoFormat: String? {
        // return the videoFormat of the video (SD, HD, Full HD, 4K, ...)
        tracks(mediaType: .video).first { $0.isEnabled }?.dynamicRange?.description
    }

    var progress: CGFloat {
        // return the current Progress of the video
        let total = totalTime
        return total == 0 ? 0 : currentTime / total
    }

    var currentTime: TimeInterval {
        currentPlaybackTime
    }

    var totalTime: TimeInterval {
        duration ?? 1
    }

    var remainingTime: TimeInterval {
        totalTime - currentTime
    }

    func set(audioTrack: some MediaPlayerTrack) {
        // setup the audio track
        select(track: audioTrack)
    }

    func updateProgress(to: CGFloat) {
        seek(time: to * totalTime) { _ in
        }
    }

    func shutdown() {
        stop()
    }
}

@MainActor
public protocol MediaPlayerDelegate: AnyObject {
    func readyToPlay(player: some MediaPlayerProtocol)
    func changeLoadState(player: some MediaPlayerProtocol)
    // 缓冲加载进度，0-100
    func changeBuffering(player: some MediaPlayerProtocol, progress: Int)
    func playBack(player: some MediaPlayerProtocol, loopCount: Int)
    func finish(player: some MediaPlayerProtocol, error: Error?)
}

public protocol MediaPlayerTrack: AnyObject, CustomStringConvertible {
    var trackID: Int32 { get }
    var name: String { get }
    var mediaType: AVFoundation.AVMediaType { get }
    var nominalFrameRate: Float { get set }
    var bitRate: Int64 { get }
    var bitDepth: Int32 { get }
    var isEnabled: Bool { get set }
    var isImageSubtitle: Bool { get }
    var rotation: Int16 { get }
    var fieldOrder: FFmpegFieldOrder { get }
    var languageCode: String? { get }
    var dovi: DOVIDecoderConfigurationRecord? { get }
    var formatDescription: CMFormatDescription? { get }
}

// public extension MediaPlayerTrack: Identifiable {
//    var id: Int32 { trackID }
// }

public enum MediaPlaybackState: Int {
    case idle
    case playing
    case paused
    case seeking
    case finished
    case stopped
}

public enum MediaLoadState: Int {
    case idle
    case loading
    case playable
}

// swiftlint:disable identifier_name
public struct DOVIDecoderConfigurationRecord {
    public let dv_version_major: UInt8
    public let dv_version_minor: UInt8
    public let dv_profile: UInt8
    public let dv_level: UInt8
    public let rpu_present_flag: UInt8
    public let el_present_flag: UInt8
    public let bl_present_flag: UInt8
    public let dv_bl_signal_compatibility_id: UInt8
}

public enum FFmpegFieldOrder: UInt8 {
    case unknown = 0
    case progressive
    case tt // < Top coded_first, top displayed first
    case bb // < Bottom coded first, bottom displayed first
    case tb // < Top coded first, bottom displayed first
    case bt // < Bottom coded first, top displayed first
}

extension FFmpegFieldOrder: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown, .progressive:
            return "progressive"
        case .tt:
            return "top first"
        case .bb:
            return "bottom first"
        case .tb:
            return "top coded first (swapped)"
        case .bt:
            return "bottom coded first (swapped)"
        }
    }
}

extension Locale {
    static var currentLanguage: String? {
        Locale.current.languageCode.flatMap {
            Locale.current.localizedString(forLanguageCode: $0)
        }
    }
}

// swiftlint:enable identifier_name
public extension MediaPlayerTrack {
    var language: String? {
        languageCode.flatMap {
            Locale.current.localizedString(forLanguageCode: $0)
        }
    }

    var codecType: FourCharCode {
        mediaSubType.rawValue
    }

    var dynamicRange: DynamicRange? {
        if dovi != nil {
            return .dolbyVision
        } else {
            return formatDescription?.dynamicRange
        }
    }

    var colorSpace: CGColorSpace? {
        KSOptions.colorSpace(ycbcrMatrix: yCbCrMatrix as CFString?, transferFunction: transferFunction as CFString?)
    }

    var mediaSubType: CMFormatDescription.MediaSubType {
        formatDescription?.mediaSubType ?? .boxed
    }

    var audioStreamBasicDescription: AudioStreamBasicDescription? {
        formatDescription?.audioStreamBasicDescription
    }

    var naturalSize: CGSize {
        formatDescription?.naturalSize ?? .zero
    }

    var colorPrimaries: String? {
        formatDescription?.colorPrimaries
    }

    var transferFunction: String? {
        formatDescription?.transferFunction
    }

    var yCbCrMatrix: String? {
        formatDescription?.yCbCrMatrix
    }
}

public extension CMFormatDescription {
    var dynamicRange: DynamicRange {
        let contentRange: DynamicRange
        if codecType.string == "dvhe" || codecType == kCMVideoCodecType_DolbyVisionHEVC {
            contentRange = .dolbyVision
        } else if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String {
            /// 10bit也有可能是sdr，所以这里用与来判断，之前有遇到10bit，但是transferFunction 不是2084的hdr10。下次遇到的时候在看下有没有其他的方式判断
            /// FFmpegAssetTrack中的CMFormatDescription 的bitDepth的值不准，因为mediaSubType的值是解码格式hvcc 这类的值，而不是像素格式。所以就先不用加bitDepth 这个判断了
            contentRange = .hdr10
        } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG as String { /// HLG
            contentRange = .hlg
        } else {
            contentRange = .sdr
        }
        return contentRange
    }

    var bitDepth: Int32 {
        codecType.bitDepth
    }

    var codecType: FourCharCode {
        mediaSubType.rawValue
    }

    var colorPrimaries: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferColorPrimariesKey] as? String
        } else {
            return nil
        }
    }

    var transferFunction: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferTransferFunctionKey] as? String
        } else {
            return nil
        }
    }

    var yCbCrMatrix: String? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCVImageBufferYCbCrMatrixKey] as? String
        } else {
            return nil
        }
    }

    var naturalSize: CGSize {
        let aspectRatio = aspectRatio
        return CGSize(width: Int(dimensions.width), height: Int(CGFloat(dimensions.height) * aspectRatio.height / aspectRatio.width))
    }

    var displaySize: CGSize? {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            if let width = (dictionary[kCVImageBufferDisplayWidthKey] as? NSNumber)?.intValue,
               let height = (dictionary[kCVImageBufferDisplayHeightKey] as? NSNumber)?.intValue,
               width > 0, height > 0
            {
                return CGSize(width: width, height: height)
            }
        }
        return nil
    }

    var aspectRatio: CGSize {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            if let ratio = dictionary[kCVImageBufferPixelAspectRatioKey] as? NSDictionary,
               let horizontal = (ratio[kCVImageBufferPixelAspectRatioHorizontalSpacingKey] as? NSNumber)?.intValue,
               let vertical = (ratio[kCVImageBufferPixelAspectRatioVerticalSpacingKey] as? NSNumber)?.intValue,
               horizontal > 0, vertical > 0
            {
                return CGSize(width: horizontal, height: vertical)
            }
        }
        return CGSize.one
    }

    var depth: Int32 {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCMFormatDescriptionExtension_Depth] as? Int32 ?? 24
        } else {
            return 24
        }
    }

    var fullRangeVideo: Bool {
        if let dictionary = CMFormatDescriptionGetExtensions(self) as NSDictionary? {
            return dictionary[kCMFormatDescriptionExtension_FullRangeVideo] as? Bool ?? false
        } else {
            return false
        }
    }
}

func setHttpProxy() {
    guard KSOptions.useSystemHTTPProxy else {
        return
    }
    guard let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as? NSDictionary else {
        unsetenv("http_proxy")
        return
    }
    guard let proxyHost = proxySettings[kCFNetworkProxiesHTTPProxy] as? String, let proxyPort = proxySettings[kCFNetworkProxiesHTTPPort] as? Int else {
        unsetenv("http_proxy")
        return
    }
    let httpProxy = "http://\(proxyHost):\(proxyPort)"
    setenv("http_proxy", httpProxy, 0)
}
