//
//  Decoder.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//
import AVFoundation
import CoreMedia
import Libavformat

protocol PlayerItemTrackProtocol: CapacityProtocol, AnyObject {
    init(mediaType: AVFoundation.AVMediaType, frameCapacity: UInt8, options: KSOptions, expanding: Bool)
    // 是否无缝循环
    var isLoopModel: Bool { get set }
    var isEndOfFile: Bool { get set }
    var delegate: CodecCapacityDelegate? { get set }
    func decode()
    func seek(time: TimeInterval)
    func seekCache(time: TimeInterval, needKeyFrame: Bool) -> (UInt, TimeInterval)?
    func updateCache(headIndex: UInt, time: TimeInterval)
    func putPacket(packet: Packet)
//    func getOutputRender<Frame: ObjectQueueItem>(where predicate: ((Frame) -> Bool)?) -> Frame?
    func shutdown()
}

class SyncPlayerItemTrack<Frame: MEFrame>: PlayerItemTrackProtocol, CustomStringConvertible {
    var seekTime = 0.0
    fileprivate let options: KSOptions
    fileprivate var decoderMap = [Int32: DecodeProtocol]()
    fileprivate var state = MECodecState.idle {
        didSet {
            if state == .finished {
                seekTime = 0
            }
        }
    }

    var isEndOfFile: Bool = false
    var packetCount: Int { 0 }
    let description: String
    weak var delegate: CodecCapacityDelegate?
    let mediaType: AVFoundation.AVMediaType
    let outputRenderQueue: CircularBuffer<Frame>
    var isLoopModel = false
    var frameCount: Int { outputRenderQueue.count }
    var frameMaxCount: Int {
        outputRenderQueue.maxCount
    }

    var fps: Float {
        outputRenderQueue.fps
    }

    required init(mediaType: AVFoundation.AVMediaType, frameCapacity: UInt8, options: KSOptions, expanding: Bool = false) {
        self.options = options
        self.mediaType = mediaType
        description = mediaType.rawValue
        // 默认缓存队列大小跟帧率挂钩,经测试除以4，最优
        if mediaType == .audio {
            outputRenderQueue = CircularBuffer(initialCapacity: Int(frameCapacity), expanding: expanding)
        } else if mediaType == .video {
            // 用ffmpeg解码的话，会对视频帧进行排序在输出，但是直接用VideoToolboxDecode，是不会排序的，所以需要在放入的时候排序
            outputRenderQueue = CircularBuffer(initialCapacity: Int(frameCapacity), sorted: true, expanding: expanding)
        } else {
            // 有的图片字幕不按顺序来输出，所以要排序下。
            outputRenderQueue = CircularBuffer(initialCapacity: Int(frameCapacity), sorted: true, expanding: expanding, isClearItem: !options.seekUsePacketCache)
        }
    }

    func decode() {
        isNeedKeyFrame = true
        isEndOfFile = false
        state = .decoding
    }

    func seek(time: TimeInterval) {
        if options.isAccurateSeek {
            seekTime = time
        } else {
            seekTime = 0
        }
        isEndOfFile = false
        state = .flush
        isNeedKeyFrame = true
        outputRenderQueue.flush()
        isLoopModel = false
    }

    func putPacket(packet: Packet) {
        if state == .flush {
            decoderMap.values.forEach { $0.doFlushCodec() }
            state = .decoding
        }
        if state == .decoding {
            doDecode(packet: packet)
        }
    }

    func getOutputRender(where predicate: ((Frame, Int) -> Bool)?) -> Frame? {
        let outputFecthRender = outputRenderQueue.pop(where: predicate)
        if outputFecthRender == nil {
            if state == .finished, frameCount == 0 {
                delegate?.codecDidFinished(track: self)
            }
        }
        return outputFecthRender
    }

    func seekCache(time _: TimeInterval, needKeyFrame _: Bool) -> (UInt, TimeInterval)? {
        nil
    }

    func updateCache(headIndex _: UInt, time _: TimeInterval) {}

    func shutdown() {
        if state == .idle {
            return
        }
        state = .closed
        outputRenderQueue.shutdown()
        decoderMap.values.forEach { $0.shutdown() }
        decoderMap.removeAll()
    }

    private var lastPacketBytes = Int64(0)
    private var lastPacketSeconds = Double(-1)
    /// 视频帧在第一次解码(有可能设置了startPlayTime，相当于seek)或是seek之后，
    /// 需要定位到isKeyFrame，这样才不会解码失败或者花屏
    /// （主要是ts会，mkv会自动第一个是isKeyFrame）
    fileprivate var isNeedKeyFrame = false
    var bitrate = Double(0)
    fileprivate func doDecode(packet: Packet) {
        guard let corePacket = packet.corePacket else {
            return
        }
        if packet.isKeyFrame, packet.assetTrack.mediaType != .subtitle {
            let seconds = packet.seconds
            let diff = seconds - lastPacketSeconds
            if lastPacketSeconds < 0 || diff < 0 {
                bitrate = 0
                lastPacketBytes = 0
                lastPacketSeconds = seconds
            } else if diff > 1 {
                bitrate = Double(lastPacketBytes) / diff
                lastPacketBytes = 0
                lastPacketSeconds = seconds
            }
        }
        lastPacketBytes += Int64(packet.size)
        if isNeedKeyFrame {
            // 有的av1视频，所有的帧的flags一直为0，不是关键帧。所以需要排除掉av1
            if packet.assetTrack.mediaType == .video, packet.assetTrack.codecpar.codec_id != AV_CODEC_ID_AV1, !packet.isKeyFrame {
                return
            }
            isNeedKeyFrame = false
        }
        if corePacket.pointee.side_data_elems > 0 {
            for i in 0 ..< Int(corePacket.pointee.side_data_elems) {
                let sideData = corePacket.pointee.side_data[i]
                if sideData.type == AV_PKT_DATA_DOVI_CONF {
                    let dovi = sideData.data.withMemoryRebound(to: DOVIDecoderConfigurationRecord.self, capacity: 1) { $0 }.pointee
                } else if sideData.type == AV_PKT_DATA_A53_CC {
                } else if sideData.type == AV_PKT_DATA_WEBVTT_IDENTIFIER || sideData.type == AV_PKT_DATA_WEBVTT_SETTINGS {
                    //                    let str = String(cString: sideData.data)
                    //                    KSLog(str)
                }
            }
        }

        let decoder = decoderMap.value(for: packet.assetTrack.trackID, default: makeDecode(assetTrack: packet.assetTrack))
        //        var startTime = CACurrentMediaTime()
        decoder.decodeFrame(from: packet) { [weak self, weak decoder] result in
            guard let self else {
                return
            }
            do {
//                if packet.assetTrack.mediaType == .video {
//                    KSLog("[video] decode time: \(CACurrentMediaTime()-startTime)")
//                    startTime = CACurrentMediaTime()
//                }
                let frame = try result.get()
                if state == .flush || state == .closed {
                    return
                }
                if seekTime > 0 {
                    let timestamp = frame.timestamp + frame.duration
//                    KSLog("seektime \(self.seekTime), frame \(frame.seconds), mediaType \(packet.assetTrack.mediaType)")
                    if timestamp <= 0 || frame.timebase.cmtime(for: timestamp).seconds < seekTime {
                        return
                    } else {
                        seekTime = 0.0
                    }
                }
                if let frame = frame as? Frame {
                    outputRenderQueue.push(frame)
                    outputRenderQueue.fps = packet.assetTrack.nominalFrameRate
                }
            } catch {
                KSLog("Decoder did Failed : \(error)")
                if decoder is VideoToolboxDecode {
                    // 因为异步解码报错会回调多次，所以这边需要做一下判断，不要重复创建FFmpegDecode
                    if decoderMap[packet.assetTrack.trackID] === decoder {
                        // 在回调里面直接掉用VTDecompressionSessionInvalidate，会卡住,所以要异步。
                        DispatchQueue.global().async {
                            decoder?.shutdown()
                        }
                        options.asynchronousDecompression = false
                        decoderMap[packet.assetTrack.trackID] = nil
                        KSLog("[video] VideoToolboxDecode fail. switch to ffmpeg decode")
                    }
                    // packet不要在复用了。因为有可能进行了bitStreamFilter，导致内存被释放了，如果调用avcodec_send_packet的话，就会crashcrash
//                    self.doDecode(packet: packet)
                } else {
                    state = .failed
                }
            }
        }
        if options.decodeAudioTime == 0, mediaType == .audio {
            options.decodeAudioTime = CACurrentMediaTime()
        }
        if options.decodeVideoTime == 0, mediaType == .video {
            options.decodeVideoTime = CACurrentMediaTime()
        }
    }
}

final class AsyncPlayerItemTrack<Frame: MEFrame>: SyncPlayerItemTrack<Frame> {
    private let operationQueue = OperationQueue()
    private var decodeOperation: BlockOperation!
    // 无缝播放使用的PacketQueue
    private var loopPacketQueue: CircularBuffer<Packet>?
    var packetQueue: CircularBuffer<Packet>
    override var packetCount: Int { packetQueue.count }
    override var isLoopModel: Bool {
        didSet {
            if isLoopModel {
                loopPacketQueue = CircularBuffer<Packet>()
                isEndOfFile = true
            } else {
                if let loopPacketQueue {
                    packetQueue.shutdown()
                    packetQueue = loopPacketQueue
                    self.loopPacketQueue = nil
                    if decodeOperation.isFinished {
                        decode()
                    }
                }
            }
        }
    }

    required init(mediaType: AVFoundation.AVMediaType, frameCapacity: UInt8, options: KSOptions, expanding: Bool = false) {
        packetQueue = CircularBuffer<Packet>(isClearItem: !options.seekUsePacketCache)
        super.init(mediaType: mediaType, frameCapacity: frameCapacity, options: options, expanding: expanding)
        operationQueue.name = "KSPlayer_" + mediaType.rawValue
        operationQueue.maxConcurrentOperationCount = 1
        operationQueue.qualityOfService = .userInteractive
    }

    override func putPacket(packet: Packet) {
        if isLoopModel {
            loopPacketQueue?.push(packet)
        } else {
            packetQueue.push(packet)
        }
    }

    override func decode() {
        isNeedKeyFrame = true
        isEndOfFile = false
        guard operationQueue.operationCount == 0 else { return }
        decodeOperation = BlockOperation { [weak self] in
            guard let self else { return }
            Thread.current.name = operationQueue.name
            Thread.current.stackSize = options.stackSize
            decodeThread()
        }
        decodeOperation.queuePriority = .veryHigh
        decodeOperation.qualityOfService = .userInteractive
        operationQueue.addOperation(decodeOperation)
    }

    override func seekCache(time: TimeInterval, needKeyFrame: Bool) -> (UInt, TimeInterval)? {
        packetQueue.seek(seconds: time, needKeyFrame: needKeyFrame)
    }

    override func updateCache(headIndex: UInt, time: TimeInterval) {
        if options.isAccurateSeek {
            seekTime = time
        } else {
            seekTime = 0
        }
        isEndOfFile = false
        state = .flush
        outputRenderQueue.flush()
        isLoopModel = false
        packetQueue.update(headIndex: headIndex)
    }

    private func decodeThread() {
        state = .decoding
        isEndOfFile = false
        decoderMap.values.forEach { $0.decode() }
        outerLoop: while !decodeOperation.isCancelled {
            switch state {
            case .idle:
                break outerLoop
            case .finished, .closed, .failed:
                decoderMap.values.forEach { $0.shutdown() }
                decoderMap.removeAll()
                break outerLoop
            case .flush:
                decoderMap.values.forEach { $0.doFlushCodec() }
                state = .decoding
            case .decoding:
                if isEndOfFile, packetQueue.count == 0 {
                    state = .finished
                } else {
                    guard let packet = packetQueue.pop(wait: true), state != .flush, state != .closed else {
                        continue
                    }
                    autoreleasepool {
                        doDecode(packet: packet)
                    }
                }
            }
        }
    }

    override func seek(time: TimeInterval) {
        if decodeOperation.isFinished {
            decode()
        }
        packetQueue.flush()
        super.seek(time: time)
        loopPacketQueue = nil
    }

    override func shutdown() {
        if state == .idle {
            return
        }
        state = .closed
        outputRenderQueue.shutdown()
        packetQueue.shutdown()
    }
}

protocol DecodeProtocol: AnyObject {
    func decode()
    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void)
    func doFlushCodec()
    func shutdown()
}

extension SyncPlayerItemTrack {
    func makeDecode(assetTrack: FFmpegAssetTrack) -> DecodeProtocol {
        autoreleasepool {
            if mediaType == .subtitle {
                return SubtitleDecode(assetTrack: assetTrack, options: options)
            } else {
                if mediaType == .video, options.asynchronousDecompression, options.hardwareDecode,
                   let session = DecompressionSession(assetTrack: assetTrack, options: options)
                {
                    return VideoToolboxDecode(options: options, session: session)
                } else {
                    return FFmpegDecode(assetTrack: assetTrack, options: options)
                }
            }
        }
    }
}
