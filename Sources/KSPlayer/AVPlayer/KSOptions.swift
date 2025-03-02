//
//  KSOptions.swift
//  KSPlayer-tvOS
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import SwiftUI
#if os(tvOS) || os(visionOS)
internal import DisplayCriteria
#endif
import AVKit
import Libavformat
import OSLog
#if canImport(Translation)
import Translation
#endif

open class KSOptions {
    public internal(set) var formatName = ""
    public internal(set) var prepareTime = 0.0
    public internal(set) var dnsStartTime = 0.0
    public internal(set) var tcpStartTime = 0.0
    public internal(set) var tcpConnectedTime = 0.0
    public internal(set) var openTime = 0.0
    public internal(set) var findTime = 0.0
    public internal(set) var readyTime = 0.0
    public internal(set) var readAudioTime = 0.0
    public internal(set) var readVideoTime = 0.0
    public internal(set) var decodeAudioTime = 0.0
    public internal(set) var decodeVideoTime = 0.0
    @MainActor
    public init() {
        useSystemHTTPProxy = KSOptions.useSystemHTTPProxy
        yadifMode = KSOptions.yadifMode
        deInterlaceAddIdet = KSOptions.deInterlaceAddIdet
        stackSize = KSOptions.stackSize
        hardwareDecode = KSOptions.hardwareDecode
        asynchronousDecompression = KSOptions.asynchronousDecompression
        videoSoftDecodeThreadCount = KSOptions.videoSoftDecodeThreadCount
        isLoopPlay = KSOptions.isLoopPlay
        display = KSOptions.displayEnumPlane
        isSecondOpen = KSOptions.isSecondOpen
        maxBufferDuration = KSOptions.maxBufferDuration
        preferredForwardBufferDuration = KSOptions.preferredForwardBufferDuration
        isAccurateSeek = KSOptions.isAccurateSeek
        isSeekedAutoPlay = KSOptions.isSeekedAutoPlay
        canStartPictureInPictureAutomaticallyFromInline = KSOptions.canStartPictureInPictureAutomaticallyFromInline
        formatContextOptions["user_agent"] = userAgent
        // 参数的配置可以参考protocols.texi 和 http.c
        // 这个一定要，不然有的流就会判断不准FieldOrder
        formatContextOptions["scan_all_pmts"] = 1
        /// ts直播流需要加这个才能一直直播下去，不然播放一小段就会结束了。
        /// 但是日志会报Will reconnect at，导致重复播放一段时间，所以要重新建立链接。
        /// 重新建立链接会有概率在playerItem.prepareToPlay()crash。所以改成不自动重新建立链接了。
        /// 最好是在播放结束的时候重新调用prepareToPlay方法
//        formatContextOptions["reconnect"] = 1
        formatContextOptions["reconnect_streamed"] = 1
        // 需要加这个超时，不然从wifi切换到4g就会一直卡住, 超时不能为5，不然iptv的ts流会隔30s就超时
        formatContextOptions["rw_timeout"] = 10_000_000
        // 这个是用来开启http的链接复用（keep-alive）。vlc默认是打开的，所以这边也默认打开。
        // 开启这个，百度网盘的视频链接无法播放
        // formatContextOptions["multiple_requests"] = 1
        // 下面是用来处理秒开的参数，有需要的自己打开。默认不开，不然在播放某些特殊的ts直播流会频繁卡顿。
//        formatContextOptions["auto_convert"] = 0
//        formatContextOptions["fps_probe_size"] = 3
//        formatContextOptions["max_analyze_duration"] = 300 * 1000
        // 默认情况下允许所有协议，只有嵌套协议才需要指定这个协议子集，例如m3u8里面有http。
//        formatContextOptions["protocol_whitelist"] = "file,http,https,tcp,tls,crypto,async,cache,data,httpproxy"
        // 开启这个，纯ipv6地址会无法播放。并且有些视频结束了，但还会一直尝试重连。所以这个值默认不设置
//        formatContextOptions["reconnect_at_eof"] = 1
        // 开启这个，会导致tcp Failed to resolve hostname 还会一直重试
//        formatContextOptions["reconnect_on_network_error"] = 1
        // There is total different meaning for 'listen_timeout' option in rtmp
        // set 'listen_timeout' = -1 for rtmp、rtsp
//        formatContextOptions["listen_timeout"] = 3
        /// 不需要设置这个参数了
        ///  The new decode APIs(avcodec_send_packet/avcodec_receive_frame) always work with reference
        ///  counted frames.
//        decoderOptions["refcounted_frames"] = "1"
        /// threads:auto和flags:+copy_opaque 只能二选一。不然的话，打开emby的链接，速度会慢很多。
        /// 因为不知道flags:+copy_opaque的作用，所以先注释掉flags:+copy_opaque
        decoderOptions["threads"] = "auto"
//        decoderOptions["flags"] = "+copy_opaque"
    }

    open func playerLayerDeinit() {
        #if os(tvOS) || os(visionOS)
        runOnMainThread {
            UIApplication.shared.windows.first?.avDisplayManager.preferredDisplayCriteria = nil
        }
        #endif
    }

    // MARK: avplayer options

    public var avOptions = [String: Any]()

    // MARK: playback options

    @MainActor
    public static var stackSize: Int = 65536
    public let stackSize: Int
    public var startPlayTime: TimeInterval = 0
    public var startPlayRate: Float = 1.0
    public var registerRemoteControll: Bool = true // 默认支持来自系统控制中心的控制
    @MainActor
    public static var firstPlayerType: MediaPlayerProtocol.Type = KSAVPlayer.self
    @MainActor
    public static var secondPlayerType: MediaPlayerProtocol.Type? = KSMEPlayer.self
    @MainActor
    public static var playerLayerType: KSPlayerLayer.Type = KSComplexPlayerLayer.self
    /// 是否开启秒开
    @MainActor
    public static var isSecondOpen = false
    /// Applies to short videos only
    @MainActor
    public static var isLoopPlay = false
    /// 是否自动播放，默认true
    @MainActor
    public static var isAutoPlay = true
    /// seek完是否自动播放
    @MainActor
    public static var isSeekedAutoPlay = true
    /// 是否开启秒开
    public var isSecondOpen: Bool

    /// Applies to short videos only
    public var isLoopPlay: Bool
    @MainActor
    open func adaptable(state: VideoAdaptationState?) -> (Int64, Int64)? {
        guard let state, let last = state.bitRateStates.last, CACurrentMediaTime() - last.time > maxBufferDuration / 2, let index = state.bitRates.firstIndex(of: last.bitRate) else {
            return nil
        }
        let isUp = state.loadedCount > Int(Double(state.fps) * maxBufferDuration / 2)
        if isUp != state.isPlayable {
            return nil
        }
        if isUp {
            if index < state.bitRates.endIndex - 1 {
                return (last.bitRate, state.bitRates[index + 1])
            }
        } else {
            if index > state.bitRates.startIndex {
                return (last.bitRate, state.bitRates[index - 1])
            }
        }
        return nil
    }

    open func liveAdaptivePlaybackRate(loadingState _: LoadingState) -> Float? {
        nil
        //        if loadingState.isFirst {
        //            return nil
        //        }
        //        if loadingState.loadedTime > preferredForwardBufferDuration + 5 {
        //            return 1.2
        //        } else if loadingState.loadedTime < preferredForwardBufferDuration / 2 {
        //            return 0.8
        //        } else {
        //            return 1
        //        }
    }

    // MARK: seek options

    /// 开启精确seek
    @MainActor
    public static var isAccurateSeek = false
    /// 开启精确seek
    public var isAccurateSeek: Bool
    /// seek完是否自动播放
    public var isSeekedAutoPlay: Bool
    /*
     AVSEEK_FLAG_BACKWARD: 1
     AVSEEK_FLAG_BYTE: 2
     AVSEEK_FLAG_ANY: 4
     AVSEEK_FLAG_FRAME: 8
     */
    public var seekFlags = Int32(1)
    @MainActor
    public static var seekInterruptIO = false

    // MARK: record options

    public var outputURL: URL?

    // MARK: Demuxer options

    public var formatContextOptions = [String: Any]()
    public var nobuffer = false
    // interrupt用于seek的时候中断之前的网络请求。
    open func process(url _: URL, interrupt _: AVIOInterruptCB) -> AbstractAVIOContext? {
        nil
    }

    // MARK: decoder options

    public var decoderOptions = [String: Any]()
    public var codecLowDelay = false
    public var lowres = UInt8(0)
    /**
     在创建解码器之前可以对KSOptions和assetTrack做一些处理。例如判断fieldOrder为tt或bb的话，那就自动加videofilters
     */
    open func process(assetTrack: some MediaPlayerTrack) {
        if assetTrack.mediaType == .video {
            if [FFmpegFieldOrder.bb, .bt, .tt, .tb].contains(assetTrack.fieldOrder) {
                // todo 先不要用yadif_videotoolbox，不然会crash。这个后续在看下要怎么解决
                hardwareDecode = false
                asynchronousDecompression = false
                let yadif = hardwareDecode ? "yadif_videotoolbox" : "yadif"
                var yadifMode = yadifMode
                //                if let assetTrack = assetTrack as? FFmpegAssetTrack {
                //                    if assetTrack.realFrameRate.num == 2 * assetTrack.avgFrameRate.num, assetTrack.realFrameRate.den == assetTrack.avgFrameRate.den {
                //                        if yadifMode == 1 {
                //                            yadifMode = 0
                //                        } else if yadifMode == 3 {
                //                            yadifMode = 2
                //                        }
                //                    }
                //                }
                if deInterlaceAddIdet {
                    videoFilters.append("idet")
                }
                videoFilters.append("\(yadif)=mode=\(yadifMode):parity=-1:deint=1")
                if yadifMode == 1 || yadifMode == 3 {
                    assetTrack.nominalFrameRate = assetTrack.nominalFrameRate * 2
                }
            }
        }
    }

    // MARK: network options

    @MainActor
    public static var useSystemHTTPProxy = true
    public let useSystemHTTPProxy: Bool
    // 没事不要设置probesize，不然会导致fps判断不准确。除非是很为了秒开或是其他原因才进行设置。
    public var probesize: Int64?
    public var maxAnalyzeDuration: Int64?
    public var referer: String? {
        didSet {
            if let referer {
                formatContextOptions["referer"] = "Referer: \(referer)"
            } else {
                formatContextOptions["referer"] = nil
            }
        }
    }

    public var userAgent: String? = "KSPlayer" {
        didSet {
            formatContextOptions["user_agent"] = userAgent
        }
    }

    /**
     you can add http-header or other options which mentions in https://developer.apple.com/reference/avfoundation/avurlasset/initialization_options

     to add http-header init options like this
     ```
     options.appendHeader(["Referer":"https:www.xxx.com"])
     ```
     */
    public func appendHeader(_ header: [String: String]) {
        var oldValue = avOptions["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] ?? [
            String: String
        ]()
        oldValue.merge(header) { _, new in new }
        avOptions["AVURLAssetHTTPHeaderFieldsKey"] = oldValue
        var str = formatContextOptions["headers"] as? String ?? ""
        for (key, value) in header {
            str.append("\(key):\(value)\r\n")
        }
        formatContextOptions["headers"] = str
    }

    public func setCookie(_ cookies: [HTTPCookie]) {
        avOptions[AVURLAssetHTTPCookiesKey] = cookies
        let cookieStr = cookies.map { cookie in "\(cookie.name)=\(cookie.value)" }.joined(separator: "; ")
        appendHeader(["Cookie": cookieStr])
    }

    // MARK: cache options

    /// 最低缓存视频时间
    @MainActor
    public static var preferredForwardBufferDuration = 3.0
    /// 最大缓存视频时间
    @MainActor
    public static var maxBufferDuration = 30.0
    public var seekUsePacketCache = false
    /// 最低缓存视频时间
    @Published
    public var preferredForwardBufferDuration: Double
    /// 最大缓存视频时间
    public var maxBufferDuration: Double
    // 缓冲算法函数
    @MainActor
    open func playable(capacitys: [CapacityProtocol], isFirst: Bool, isSeek: Bool) -> LoadingState {
        let packetCount = capacitys.map(\.packetCount).min() ?? 0
        let frameCount = capacitys.map(\.frameCount).min() ?? 0
        let isEndOfFile = capacitys.allSatisfy(\.isEndOfFile)
        /// 这边要用最大值，因为有的视频可能音频达到15秒了，但是视频已经100多秒了，导致内存暴涨。
        /// isPlayable已经保证能够有足够的缓存用于播放了
        let loadedTime = capacitys.map(\.loadedTime).max() ?? 0
        let progress = preferredForwardBufferDuration == 0 ? 100 : loadedTime * 100.0 / preferredForwardBufferDuration
        let isPlayable = capacitys.allSatisfy { capacity in
            if capacity.isEndOfFile {
                return true
            }
            if (syncDecodeVideo && capacity.mediaType == .video) || (syncDecodeAudio && capacity.mediaType == .audio) {
                if capacity.frameCount >= 2 {
                    return true
                }
            }
            /// 高码率或者倍速播放的时候，会触发频繁的丢帧，导致frameCount的值为1的，
            /// 所以就会加载过多的packet，导致内存暴涨，改成capacity.frameCount >= 1 也不行，所以先去掉这个判断。
//            guard capacity.frameCount >= capacity.frameMaxCount / 2 else {
//                return false
//            }
            if isFirst || isSeek {
                guard capacity.frameCount >= 2 else {
                    return false
                }
                if isSecondOpen {
                    return capacity.loadedTime >= self.preferredForwardBufferDuration / 2
                }
            }
            return capacity.loadedTime >= self.preferredForwardBufferDuration
        }
        return LoadingState(loadedTime: loadedTime, progress: progress, packetCount: packetCount,
                            frameCount: frameCount, isEndOfFile: isEndOfFile, isPlayable: isPlayable,
                            isFirst: isFirst, isSeek: isSeek)
    }

    // MARK: audio options

    public nonisolated(unsafe) static var audioPlayerType: AudioOutput.Type = AudioUnitPlayer.self
    public var audioFilters = [String]()
    public var syncDecodeAudio = false
    open func wantedAudio(tracks _: [MediaPlayerTrack]) -> MediaPlayerTrack? {
        nil
    }

    open func audioFrameMaxCount(fps: Float, channelCount: Int) -> UInt8 {
        let count = (Int(fps) * channelCount) >> 2
        return UInt8(min(count, 255))
    }

    // MARK: subtile options

    var fontsDir: URL?
    public nonisolated(unsafe) static var defaultFont: URL?
    public nonisolated(unsafe) static var enableHDRSubtitle = false
    public nonisolated(unsafe) static var isASSUseImageRender = false
    public nonisolated(unsafe) static var isSRTUseImageRender = false
    // 如果图片字幕的比率跟视频的比率不一致，是否要对图片进行伸缩
    public nonisolated(unsafe) static var isResizeImageSubtitle = false
    // 丢弃掉字幕自带的样式，用自定义的样式
    @MainActor
    public static var stripSubtitleStyle = true
    public nonisolated(unsafe) static var textColor: Color = .white
    public nonisolated(unsafe) static var textBackgroundColor: Color = .clear
    @MainActor
    public static var textFont: UIFont {
        var font = UIFont(name: textFontName, size: textFontSize, bold: textBold, italic: textItalic)
        if let font {
            return font
        } else {
            var font = UIFont.systemFont(ofSize: textFontSize)
            if textBold || textItalic {
                var symbolicTrait = UIFontDescriptor.SymbolicTraits()
                if textBold {
                    symbolicTrait = symbolicTrait.union(.traitBold)
                }
                if textItalic {
                    symbolicTrait = symbolicTrait.union(.traitItalic)
                }
                font = font.union(symbolicTrait: symbolicTrait)
            }
            return font
        }
    }

    public nonisolated(unsafe) static var textFontName: String = {
        /// systemFont返回的是AppleSystemUIFont。libass遇到韩语就会无法显示，所以需要指明系统字体名SF Pro。
        return "SF Pro"
        let font = UIFont.systemFont(ofSize: textFontSize)
        // tvos ios需要取familyName，才是对的。而macos familyName和fontName是一样的
        return font.familyName ?? font.fontName
    }()

    public nonisolated(unsafe) static var textFontSize = SubtitleModel.Size.standard.rawValue
    public nonisolated(unsafe) static var textBold = false
    public nonisolated(unsafe) static var textItalic = false
    public nonisolated(unsafe) static var textPosition = TextPosition()
    @MainActor
    @available(iOS 17.0, macOS 14.0, tvOS 17.0, *)
    public static var subtitleDynamicRange = Image.DynamicRange.high
    @MainActor
    public static var showTranslateSourceText = false
    public var audioRecognizes = [any AudioRecognize]()
    public var autoSelectEmbedSubtitle = true
    public var isSeekImageSubtitle = false
    public var subtitleTimeInterval = 0.1
    open func wantedSubtitle(tracks: [MediaPlayerTrack]) -> MediaPlayerTrack? {
        if autoSelectEmbedSubtitle {
            let first = tracks.first {
                $0.language == Locale.currentLanguage
            } ?? tracks.first
            // 不要默认选中dvb_teletext
            if let track = first as? FFmpegAssetTrack, track.isDVBTeletext {
                return nil
            }
            return first
        } else {
            return nil
        }
    }

    // MARK: video options

    /// 开启VR模式的陀飞轮
    @MainActor
    public static var enableSensor = true
    @MainActor
    public static var isClearVideoWhereReplace = true
    @MainActor
    public static var videoPlayerType: (VideoOutput & UIView).Type = MetalPlayView.self
    @MainActor
    public static var yadifMode = 1
    @MainActor
    public static var deInterlaceAddIdet = false
    public let yadifMode: Int
    public let deInterlaceAddIdet: Bool
    @MainActor
    public static var hardwareDecode = true
    /// 默认不用自研的硬解，因为有些视频的AVPacket的pts顺序是不对的，只有解码后的AVFrame里面的pts是对的。
    /// m3u8的Interlaced流，需要关闭自研的硬解才能判断是Interlaced
    /// 但是ts格式的视频seek完之后，FFmpeg的硬解会失败，需要切换到硬解才可以。自研的硬解不会失败，但是会有一小段的花屏。
    /// 异步硬解支持直播流Annexb格式了。并且当前只有异步硬解支持av1硬解
    @MainActor
    public static var asynchronousDecompression = false
    @MainActor
    public static var canStartPictureInPictureAutomaticallyFromInline = true
    @MainActor
    public static var preferredFrame = false
    #if os(tvOS)
    // tvos 只能在tmp上创建文件
    @MainActor
    public static var recordDir: URL? = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("record")
    #else
    @MainActor
    public static var recordDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("record")
    #endif
    @MainActor
    public static var doviMatrix = simd_float3x3(1)
    @MainActor
    public static let displayEnumPlane = PlaneDisplayModel()
    public nonisolated(unsafe) static let displayEnumDovi = DoviDisplayModel()
    @MainActor
    public static let displayEnumVR = VRDisplayModel()
    @MainActor
    public static let displayEnumVRBox = VRBoxDisplayModel()
    @available(tvOS 14.0, *)
    @MainActor
    public static var pictureInPictureType: KSPictureInPictureProtocol.Type = KSPictureInPictureController.self
    @MainActor
    public static var videoSoftDecodeThreadCount = 4
    @MainActor
    public static var audioVideoClockSync = true
    public var dynamicRange: DynamicRange = .sdr
    public var display: DisplayEnum
    public var videoDelay = 0.0 // s
    public var autoRotate = true
    public var destinationDynamicRange: DynamicRange?
    public var videoAdaptable = true
    public var videoFilters = [String]()
    public var syncDecodeVideo = false
    public internal(set) var decodeType = DecodeType.asynchronousHardware
    public var hardwareDecode: Bool
    public var asynchronousDecompression: Bool
    public var videoDisable = false
    public var canStartPictureInPictureAutomaticallyFromInline: Bool
    public var automaticWindowResize = true
    public var videoSoftDecodeThreadCount: Int
    @MainActor
    open func preferredFrame(fps: Float) -> Bool {
        KSOptions.preferredFrame || fps > 61
    }

    /// 这个函数只在异步硬解才生效
    open func decodeSize(width: Int32, height: Int32) -> CGSize {
        #if os(iOS)
        // ios 要iPhone 15 pro max 播放8k的才不会卡顿，其他都会硬件解码耗时太久。所以把分辨率减半，降低解码耗时
        if UITraitCollection.current.userInterfaceIdiom == .phone, width >= 7680 {
            return CGSize(width: Int(width) / 2, height: Int(height) / 2)
        } else {
            return CGSize(width: Int(width), height: Int(height))
        }
        #else
        return CGSize(width: Int(width), height: Int(height))
        #endif
    }

    open func recreateContext(hasDecodeSuccess: Bool) -> Bool {
        !hasDecodeSuccess
    }

    open func wantedVideo(tracks _: [MediaPlayerTrack]) -> MediaPlayerTrack? {
        nil
    }

    open func videoFrameMaxCount(fps _: Float, naturalSize _: CGSize, isLive _: Bool) -> UInt8 {
        4
    }

    /// customize dar
    /// - Parameters:
    ///   - sar: SAR(Sample Aspect Ratio)
    ///   - par: PAR(Pixel Aspect Ratio)
    /// - Returns: DAR(Display Aspect Ratio)
    open func customizeDar(sar _: CGSize, par _: CGSize) -> CGSize? {
        nil
    }

    // 虽然只有iOS才支持PIP。但是因为AVSampleBufferDisplayLayer能够支持HDR10+。所以默认还是推荐用AVSampleBufferDisplayLayer
    @MainActor
    open func isUseDisplayLayer() -> Bool {
        display === KSOptions.displayEnumPlane
    }

    open func availableDynamicRange() -> DynamicRange? {
        guard let destinationDynamicRange else {
            return nil
        }
        let availableHDRModes = DynamicRange.availableHDRModes
        if availableHDRModes.contains(destinationDynamicRange) {
            return destinationDynamicRange
        } else {
            return availableHDRModes.first
        }
    }

    @MainActor
    open func updateVideo(refreshRate: Float, isDovi: Bool, formatDescription: CMFormatDescription) {
        dynamicRange = isDovi ? .dolbyVision : formatDescription.dynamicRange
        #if os(tvOS) || os(visionOS)
        guard let displayManager = UIApplication.shared.windows.first?.avDisplayManager,
              displayManager.isDisplayCriteriaMatchingEnabled
        else {
            return
        }
        /// 因为目前formatDescription里面没有信息可以看出是dovi。
        /// 所以当设备只是dv，内容是dv的话，用videoDynamicRange。
        if DynamicRange.availableHDRModes.contains(.dolbyVision), dynamicRange == .dolbyVision {
            displayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: refreshRate, videoDynamicRange: dynamicRange.rawValue)
        } else if #available(tvOS 17.0, *) {
            /// 用formatDescription的话，显示的颜色会更准确，特别是hlg就不会显示dovi了
            displayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: refreshRate, formatDescription: formatDescription)
        } else {
            displayManager.preferredDisplayCriteria = AVDisplayCriteria(refreshRate: refreshRate, videoDynamicRange: dynamicRange.rawValue)
        }
        #endif
    }

    private var videoClockDelayCount = 0
    open func videoClockSync(main: KSClock, nextVideoTime: TimeInterval, fps: Double, frameCount: Int) -> (Double, ClockProcessType) {
        let desire = main.getTime() - videoDelay
        let diff = nextVideoTime - desire
        if diff > 8 {
            videoClockDelayCount += 1
            let log = "[video] video delay=\(diff), clock=\(desire), frameCount=\(frameCount) delay count=\(videoClockDelayCount)"
            KSLog(log)
            // 只对前几帧进行显示，如果后续还是超前的话，那就一直等待
            if videoClockDelayCount <= Int(ceil(fps / 3)) {
                return (diff, .next)
            } else {
                return (diff, .remain)
            }
        } else if diff >= 1 / fps / 2 {
            return (diff, .remain)
        } else if diff < -4 / fps {
            videoClockDelayCount += 1
            /// 之前有一次因为mainClock的时间戳不准，导致diff很大，所以这边要判断下delay的次数在做seek、dropGOPPacket、flush处理，避免误伤。
            let log = "[video] video delay=\(diff), clock=\(desire), frameCount=\(frameCount) delay count=\(videoClockDelayCount)"

            if diff < -8, videoClockDelayCount % 80 == 0 {
                KSLog("\(log) seek video track")
                return (diff, .seek)
            }
            if diff < -1, videoClockDelayCount % 10 == 0 {
                if frameCount == 1 {
                    KSLog("\(log) drop gop Packet")
                    return (diff, .dropGOPPacket)
                } else {
                    KSLog("\(log) flush video track")
                    return (diff, .flush)
                }
            }
            let count: Int
            if videoClockDelayCount == 1 {
                // 第一次delay的话，就先只丢一帧。防止seek之后第一次播放丢太多帧
                count = 1
            } else {
                count = Int(-diff * fps / 4.0)
            }
            KSLog("\(log) drop \(count) frame")
            return (diff, .dropFrame(count: count))
        } else {
            videoClockDelayCount = 0
            return (diff, .next)
        }
    }

    // MARK: log options

    public nonisolated(unsafe) static var logLevel = LogLevel.warning
    public nonisolated(unsafe) static var logger: LogHandler = OSLog(lable: "KSPlayer")
    open func urlIO(log: String) {
        if log.starts(with: "Original list of addresses"), dnsStartTime == 0 {
            dnsStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Starting connection attempt to"), tcpStartTime == 0 {
            tcpStartTime = CACurrentMediaTime()
        } else if log.starts(with: "Successfully connected to"), tcpConnectedTime == 0 {
            tcpConnectedTime = CACurrentMediaTime()
        }
    }

    open func filter(log _: String) {}

    open func sei(string: String) {
        KSLog("sei \(string)")
    }
}

public extension KSOptions {
    internal static func deviceCpuCount() -> Int {
        var ncpu = UInt(0)
        var len: size_t = MemoryLayout.size(ofValue: ncpu)
        sysctlbyname("hw.ncpu", &ncpu, &len, nil, 0)
        return Int(ncpu)
    }

    static func setAudioSession() {
        #if os(macOS)
//        try? AVAudioSession.sharedInstance().setRouteSharingPolicy(.longFormAudio)
        #else
        var category = AVAudioSession.sharedInstance().category
        if category != .playAndRecord {
            category = .playback
        }
        #if os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormAudio)
        #else
        try? AVAudioSession.sharedInstance().setCategory(category, mode: .moviePlayback, policy: .longFormVideo)
        #endif
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    #if !os(macOS)
    static func isSpatialAudioEnabled(channelCount _: AVAudioChannelCount) -> Bool {
        if #available(tvOS 15.0, iOS 15.0, *) {
            let isSpatialAudioEnabled = AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.isSpatialAudioEnabled }
            try? AVAudioSession.sharedInstance().setSupportsMultichannelContent(isSpatialAudioEnabled)
            return isSpatialAudioEnabled
        } else {
            return false
        }
    }

    static func outputNumberOfChannels(channelCount: AVAudioChannelCount) -> AVAudioChannelCount {
        let maximumOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().maximumOutputNumberOfChannels)
        let preferredOutputNumberOfChannels = AVAudioChannelCount(AVAudioSession.sharedInstance().preferredOutputNumberOfChannels)
        let isSpatialAudioEnabled = isSpatialAudioEnabled(channelCount: channelCount)
        let isUseAudioRenderer = KSOptions.audioPlayerType == AudioRendererPlayer.self
        KSLog("[audio] maximumOutputNumberOfChannels: \(maximumOutputNumberOfChannels), preferredOutputNumberOfChannels: \(preferredOutputNumberOfChannels), isSpatialAudioEnabled: \(isSpatialAudioEnabled), isUseAudioRenderer: \(isUseAudioRenderer) ")
        let maxRouteChannelsCount = AVAudioSession.sharedInstance().currentRoute.outputs.compactMap {
            $0.channels?.count
        }.max() ?? 2
        KSLog("[audio] currentRoute max channels: \(maxRouteChannelsCount)")
        var channelCount = channelCount
        if channelCount > 2 {
            let minChannels = min(maximumOutputNumberOfChannels, channelCount)
            #if os(tvOS) || targetEnvironment(simulator)
            if !(isUseAudioRenderer && isSpatialAudioEnabled) {
                // 不要用maxRouteChannelsCount来判断，有可能会不准。导致多音道设备也返回2（一开始播放一个2声道，就容易出现），也不能用outputNumberOfChannels来判断，有可能会返回2
//                channelCount = AVAudioChannelCount(min(AVAudioSession.sharedInstance().outputNumberOfChannels, maxRouteChannelsCount))
                channelCount = minChannels
            }
            #else
            // iOS 外放是会自动有空间音频功能，但是蓝牙耳机有可能没有空间音频功能或者把空间音频给关了，。所以还是需要处理。
            if !isSpatialAudioEnabled {
                channelCount = minChannels
            }
            #endif
        } else {
            channelCount = 2
        }
        // 不在这里设置setPreferredOutputNumberOfChannels,因为这个方法会在获取音轨信息的时候，进行调用。
        KSLog("[audio] outputNumberOfChannels: \(AVAudioSession.sharedInstance().outputNumberOfChannels) output channelCount: \(channelCount)")
        return channelCount
    }
    #endif
}
