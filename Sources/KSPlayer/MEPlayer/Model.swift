//
//  Model.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/9.
//

import AVFoundation
import CoreMedia
import FFmpegKit
import Libavcodec
#if canImport(UIKit)
import UIKit
#endif

// MARK: enum

enum MESourceState {
    case idle
    case opening
    case opened
    case reading
    case seeking
    case paused
    case finished
    case closed
    case failed
}

// MARK: delegate

public protocol OutputRenderSourceDelegate: AnyObject {
    func getVideoOutputRender(force: Bool) -> VideoVTBFrame?
    func getAudioOutputRender() -> AudioFrame?
    func setAudio(time: CMTime, position: Int64)
    func setVideo(time: CMTime, position: Int64)
}

protocol CodecCapacityDelegate: AnyObject {
    func codecDidFinished(track: some CapacityProtocol)
}

protocol MEPlayerDelegate: AnyObject {
    func sourceDidChange(loadingState: LoadingState)
    func sourceDidOpened()
    func sourceDidFailed(error: NSError?)
    func sourceDidFinished()
    func sourceDidChange(oldBitRate: Int64, newBitrate: Int64)
}

// MARK: protocol

public protocol ObjectQueueItem {
    var timebase: Timebase { get }
    var timestamp: Int64 { get set }
    var duration: Int64 { get set }
    // byte position
    var position: Int64 { get set }
    var size: Int32 { get set }
}

extension ObjectQueueItem {
    var seconds: TimeInterval { cmtime.seconds }
    var cmtime: CMTime { timebase.cmtime(for: timestamp) }
}

@MainActor
public protocol FrameOutput: AnyObject {
    nonisolated(unsafe) var renderSource: OutputRenderSourceDelegate? { get set }
    func play()
    func pause()
    func flush()
    func invalidate()
}

protocol MEFrame: ObjectQueueItem {
    var timebase: Timebase { get set }
}

// MARK: model

// for MEPlayer
public extension KSOptions {
    /*
     CGColorSpaceCreateICCBased
     */
    static func colorSpace(ycbcrMatrix: CFString?, transferFunction: CFString?) -> CGColorSpace? {
        switch ycbcrMatrix {
        case kCVImageBufferYCbCrMatrix_ITU_R_709_2:
            return CGColorSpace(name: CGColorSpace.itur_709)
        case kCVImageBufferYCbCrMatrix_ITU_R_601_4:
            return CGColorSpace(name: CGColorSpace.sRGB)
        case kCVImageBufferYCbCrMatrix_ITU_R_2020:
            if transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
                if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2100_PQ)
                } else if #available(macOS 10.15.4, iOS 13.4, tvOS 13.4, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2020_PQ)
                } else {
                    return CGColorSpace(name: CGColorSpace.itur_2020_PQ_EOTF)
                }
            } else if transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
                if #available(macOS 11.0, iOS 14.0, tvOS 14.0, *) {
                    return CGColorSpace(name: CGColorSpace.itur_2100_HLG)
                } else {
                    return CGColorSpace(name: CGColorSpace.itur_2020)
                }
            } else {
                return CGColorSpace(name: CGColorSpace.itur_2020)
            }
        default:
            return CGColorSpace(name: CGColorSpace.sRGB)
        }
    }

    static func pixelFormat(planeCount: Int, bitDepth: Int32) -> [MTLPixelFormat] {
        if planeCount == 3 {
            if bitDepth > 8 {
                return [.r16Unorm, .r16Unorm, .r16Unorm]
            } else {
                return [.r8Unorm, .r8Unorm, .r8Unorm]
            }
        } else if planeCount == 2 {
            if bitDepth > 8 {
                return [.r16Unorm, .rg16Unorm]
            } else {
                return [.r8Unorm, .rg8Unorm]
            }
        } else {
            return [colorPixelFormat(bitDepth: bitDepth)]
        }
    }

    static func colorPixelFormat(bitDepth: Int32) -> MTLPixelFormat {
        if bitDepth == 10 {
            return .bgr10a2Unorm
        } else {
            return .bgra8Unorm
        }
    }
}

enum MECodecState {
    case idle
    case decoding
    case flush
    case closed
    case failed
    case finished
}

public struct Timebase: Sendable {
    static let defaultValue = Timebase(num: 1, den: 1)
    public let num: Int32
    public let den: Int32
    func getPosition(from seconds: TimeInterval) -> Int64 { Int64(seconds * TimeInterval(den) / TimeInterval(num)) }

    func cmtime(for timestamp: Int64) -> CMTime { CMTime(value: timestamp * Int64(num), timescale: den) }
}

extension Timebase {
    public var rational: AVRational { AVRational(num: num, den: den) }

    init(_ rational: AVRational) {
        num = rational.num
        den = rational.den
    }
}

final class Packet: ObjectQueueItem {
    var duration: Int64 = 0
    var timestamp: Int64 = 0
    var position: Int64 = 0
    var size: Int32 = 0
    private(set) var corePacket = av_packet_alloc()
    var timebase: Timebase {
        assetTrack.timebase
    }

    var isKeyFrame: Bool {
        if let corePacket {
            return corePacket.pointee.flags & AV_PKT_FLAG_KEY == AV_PKT_FLAG_KEY
        } else {
            return false
        }
    }

    var assetTrack: FFmpegAssetTrack! {
        didSet {
            guard let packet = corePacket?.pointee else {
                return
            }
            if packet.pts == Int64.min {
                if packet.dts != Int64.min {
                    timestamp = packet.dts
                }
            } else {
                timestamp = packet.pts
            }
            position = packet.pos
            duration = packet.duration
            size = packet.size
        }
    }

    deinit {
        av_packet_unref(corePacket)
        av_packet_free(&corePacket)
    }
}

final class SubtitleFrame: MEFrame {
    var timestamp: Int64 = 0
    var timebase: Timebase
    var duration: Int64 = 0
    var position: Int64 = 0
    var size: Int32 = 0
    let part: SubtitlePart
    init(part: SubtitlePart, timebase: Timebase) {
        self.part = part
        self.timebase = timebase
    }
}

public final class AudioFrame: MEFrame {
    public let dataSize: Int
    public let audioFormat: AVAudioFormat
    public internal(set) var timebase = Timebase.defaultValue
    public var timestamp: Int64 = 0
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var size: Int32 = 0
    public var data: [UnsafeMutablePointer<UInt8>?]
    public var numberOfSamples: UInt32 = 0
    public init(dataSize: Int, audioFormat: AVAudioFormat) {
        self.dataSize = dataSize
        self.audioFormat = audioFormat
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        }
    }

    public init(array: [AudioFrame]) {
        audioFormat = array[0].audioFormat
        timebase = array[0].timebase
        timestamp = array[0].timestamp
        position = array[0].position
        var dataSize = 0
        for frame in array {
            duration += frame.duration
            dataSize += frame.dataSize
            size += frame.size
            numberOfSamples += frame.numberOfSamples
        }
        self.dataSize = dataSize
        let count = audioFormat.isInterleaved ? 1 : audioFormat.channelCount
        data = (0 ..< count).map { _ in
            UnsafeMutablePointer<UInt8>.allocate(capacity: dataSize)
        }
        var offset = 0
        for frame in array {
            for i in 0 ..< data.count {
                data[i]?.advanced(by: offset).initialize(from: frame.data[i]!, count: frame.dataSize)
            }
            offset += frame.dataSize
        }
    }

    deinit {
        for i in 0 ..< data.count {
            data[i]?.deinitialize(count: dataSize)
            data[i]?.deallocate()
        }
        data.removeAll()
    }

    public func toFloat() -> [ContiguousArray<Float>] {
        var array = [ContiguousArray<Float>]()
        for i in 0 ..< data.count {
            switch audioFormat.commonFormat {
            case .pcmFormatInt16:
                let capacity = dataSize / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 32767.0, 1.0))
                    }
                    array.append(des)
                }
            case .pcmFormatInt32:
                let capacity = dataSize / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = max(-1.0, min(Float(src[j]) / 2_147_483_647.0, 1.0))
                    }
                    array.append(des)
                }
            default:
                let capacity = dataSize / MemoryLayout<Float>.size
                data[i]?.withMemoryRebound(to: Float.self, capacity: capacity) { src in
                    var des = ContiguousArray<Float>(repeating: 0, count: Int(capacity))
                    for j in 0 ..< capacity {
                        des[j] = src[j]
                    }
                    array.append(ContiguousArray<Float>(des))
                }
            }
        }
        return array
    }

    public func toPCMBuffer() -> AVAudioPCMBuffer? {
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: numberOfSamples) else {
            return nil
        }
        pcmBuffer.frameLength = pcmBuffer.frameCapacity
        for i in 0 ..< min(Int(pcmBuffer.format.channelCount), data.count) {
            switch audioFormat.commonFormat {
            case .pcmFormatInt16:
                let capacity = dataSize / MemoryLayout<Int16>.size
                data[i]?.withMemoryRebound(to: Int16.self, capacity: capacity) { src in
                    pcmBuffer.int16ChannelData?[i].update(from: src, count: capacity)
                }
            case .pcmFormatInt32:
                let capacity = dataSize / MemoryLayout<Int32>.size
                data[i]?.withMemoryRebound(to: Int32.self, capacity: capacity) { src in
                    pcmBuffer.int32ChannelData?[i].update(from: src, count: capacity)
                }
            default:
                let capacity = dataSize / MemoryLayout<Float>.size
                data[i]?.withMemoryRebound(to: Float.self, capacity: capacity) { src in
                    pcmBuffer.floatChannelData?[i].update(from: src, count: capacity)
                }
            }
        }
        return pcmBuffer
    }

    public func toCMSampleBuffer() -> CMSampleBuffer? {
        var outBlockListBuffer: CMBlockBuffer?
        CMBlockBufferCreateEmpty(allocator: kCFAllocatorDefault, capacity: UInt32(data.count), flags: 0, blockBufferOut: &outBlockListBuffer)
        guard let outBlockListBuffer else {
            return nil
        }
        let sampleSize = Int(audioFormat.sampleSize)
        let sampleCount = CMItemCount(numberOfSamples)
        let dataByteSize = sampleCount * sampleSize
        if dataByteSize > dataSize {
            // 关闭空间音频之后， 在打开空间音频，可能就会遇到这个问题，但是也就一瞬间
            assertionFailure("dataByteSize: \(dataByteSize),render.dataSize: \(dataSize)")
        }
        for i in 0 ..< data.count {
            var outBlockBuffer: CMBlockBuffer?
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault,
                memoryBlock: nil,
                blockLength: dataByteSize,
                blockAllocator: kCFAllocatorDefault,
                customBlockSource: nil,
                offsetToData: 0,
                dataLength: dataByteSize,
                flags: kCMBlockBufferAssureMemoryNowFlag,
                blockBufferOut: &outBlockBuffer
            )
            if let outBlockBuffer {
                CMBlockBufferReplaceDataBytes(
                    with: data[i]!,
                    blockBuffer: outBlockBuffer,
                    offsetIntoDestination: 0,
                    dataLength: dataByteSize
                )
                CMBlockBufferAppendBufferReference(
                    outBlockListBuffer,
                    targetBBuf: outBlockBuffer,
                    offsetToData: 0,
                    dataLength: CMBlockBufferGetDataLength(outBlockBuffer),
                    flags: 0
                )
            }
        }
        var sampleBuffer: CMSampleBuffer?
        // 因为sampleRate跟timescale没有对齐，所以导致杂音，改成用timebase.cmtime(for: 1)就不会有杂音了。但是 一定要设置为invalid，不然用airpod播放会有问题
//        let duration = CMTime(value: CMTimeValue(1), timescale: CMTimeScale(audioFormat.sampleRate))
//        let duration = timebase.cmtime(for: 1)
        let duration = CMTime.invalid
        let timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: cmtime, decodeTimeStamp: .invalid)
        let sampleSizeEntryCount: CMItemCount
        let sampleSizeArray: [Int]?
        if audioFormat.isInterleaved {
            sampleSizeEntryCount = 1
            sampleSizeArray = [sampleSize]
        } else {
            sampleSizeEntryCount = 0
            sampleSizeArray = nil
        }
        CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: outBlockListBuffer, formatDescription: audioFormat.formatDescription, sampleCount: sampleCount, sampleTimingEntryCount: 1, sampleTimingArray: [timing], sampleSizeEntryCount: sampleSizeEntryCount, sampleSizeArray: sampleSizeArray, sampleBufferOut: &sampleBuffer)
        return sampleBuffer
    }
}

public final class VideoVTBFrame: MEFrame {
    public var timebase = Timebase.defaultValue
    // 交叉视频的duration会不准，直接减半了
    public var duration: Int64 = 0
    public var position: Int64 = 0
    public var timestamp: Int64 = 0
    public var size: Int32 = 0
    public let fps: Float
    public let isDovi: Bool
    public var edrMetaData: EDRMetaData? = nil
    public var pixelBuffer: PixelBufferProtocol
    public var doviData: dovi_metadata? = nil {
        didSet {
            if doviData != nil {
                pixelBuffer.cvPixelBuffer?.colorspace = CGColorSpace(name: CGColorSpace.itur_2020_PQ_EOTF)
            }
        }
    }

    public init(pixelBuffer: PixelBufferProtocol, fps: Float, isDovi: Bool) {
        self.pixelBuffer = pixelBuffer
        // ffmpeg硬解码出来的colorspace不对，所以要自己设置下。我自己实现的硬解在macos是对的，但是在iOS也会不对，所以统一设置下。
        pixelBuffer.updateColorspace()
        self.fps = fps
        self.isDovi = isDovi
    }
}

extension VideoVTBFrame {
    #if !os(tvOS)
    @available(iOS 16, *)
    var edrMetadata: CAEDRMetadata? {
        if var contentData = edrMetaData?.contentData, var displayData = edrMetaData?.displayData {
            return CAEDRMetadata.hdr10(displayInfo: displayData.toData(), contentInfo: contentData.toData(), opticalOutputScale: 10000)
        }
        if var ambientViewingEnvironment = edrMetaData?.ambientViewingEnvironment {
            if #available(macOS 14.0, iOS 17.0, *) {
                return CAEDRMetadata.hlg(ambientViewingEnvironment: ambientViewingEnvironment.toData())
            } else {
                return CAEDRMetadata.hlg
            }
        }
        if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ {
            return CAEDRMetadata.hdr10(minLuminance: 0.1, maxLuminance: 1000, opticalOutputScale: 10000)
        } else if pixelBuffer.transferFunction == kCVImageBufferTransferFunction_ITU_R_2100_HLG {
            return CAEDRMetadata.hlg
        }
        if let doviData {
            return CAEDRMetadata.hdr10(minLuminance: doviData.minLuminance, maxLuminance: doviData.maxLuminance, opticalOutputScale: 10000)
        }
        return nil
    }
    #endif
}

public struct EDRMetaData {
    var displayData: MasteringDisplayMetadata?
    var contentData: ContentLightMetadata?
    var ambientViewingEnvironment: AmbientViewingEnvironment?
}

public struct MasteringDisplayMetadata {
    let display_primaries_r_x: UInt16
    let display_primaries_r_y: UInt16
    let display_primaries_g_x: UInt16
    let display_primaries_g_y: UInt16
    let display_primaries_b_x: UInt16
    let display_primaries_b_y: UInt16
    let white_point_x: UInt16
    let white_point_y: UInt16
    let minLuminance: UInt32
    let maxLuminance: UInt32
    func toData() -> Data {
        var array = [UInt8]()
        array.append(display_primaries_r_x)
        array.append(display_primaries_r_y)
        array.append(display_primaries_g_x)
        array.append(display_primaries_g_y)
        array.append(display_primaries_b_x)
        array.append(display_primaries_b_y)
        array.append(white_point_x)
        array.append(white_point_y)
        array.append(minLuminance)
        array.append(maxLuminance)
        array = array.reversed()
        return Data(bytes: &array, count: array.count)
    }
}

public struct ContentLightMetadata {
    let MaxCLL: UInt16
    let MaxFALL: UInt16
    func toData() -> Data {
        var array = [UInt8]()
        array.append(MaxCLL)
        array.append(MaxFALL)
        array = array.reversed()
        return Data(bytes: &array, count: array.count)
    }
}

// https://developer.apple.com/documentation/technotes/tn3145-hdr-video-metadata
public struct AmbientViewingEnvironment {
    let ambient_illuminance: UInt32
    let ambient_light_x: UInt16
    let ambient_light_y: UInt16
    func toData() -> Data {
        var array = [UInt8]()
        array.append(ambient_illuminance)
        array.append(ambient_light_x)
        array.append(ambient_light_y)
        array = array.reversed()
        return Data(bytes: &array, count: array.count)
    }
}

extension Data {
    func convertToArray<T>() -> [T] {
        let capacity = count / MemoryLayout<T>.size
        let result = [T](unsafeUninitializedCapacity: capacity) {
            pointer, copied_count in
            let length_written = copyBytes(to: pointer)
            copied_count = length_written / MemoryLayout<T>.size
        }
        return result
    }
}

public extension [UInt8] {
    @inlinable
    mutating func append(_ newElement: UInt16) {
        append(UInt8(newElement & 0xFF))
        append(UInt8(newElement >> 8 & 0xFF))
    }

    @inlinable
    mutating func append(_ newElement: UInt32) {
        append(UInt8(newElement & 0xFF))
        append(UInt8(newElement >> 8 & 0xFF))
        append(UInt8(newElement >> 16 & 0xFF))
        append(UInt8(newElement >> 24 & 0xFF))
    }
}

extension simd_float3 {
    init(tuple: (AVRational, AVRational, AVRational)) {
        self.init(x: tuple.0.float, y: tuple.1.float, z: tuple.2.float)
    }
}

extension simd_float3x3 {
    init(tuple: (AVRational, AVRational, AVRational, AVRational, AVRational, AVRational, AVRational, AVRational, AVRational)) {
        self.init(simd_float3(tuple.0.float, tuple.1.float, tuple.2.float), simd_float3(tuple.3.float, tuple.4.float, tuple.5.float), simd_float3(tuple.6.float, tuple.7.float, tuple.8.float))
    }
}
