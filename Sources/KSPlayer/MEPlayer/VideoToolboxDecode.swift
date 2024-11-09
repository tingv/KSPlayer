//
//  VideoToolboxDecode.swift
//  KSPlayer
//
//  Created by kintan on 2018/3/10.
//

import FFmpegKit
import Libavformat
#if canImport(VideoToolbox)
import VideoToolbox

class VideoToolboxDecode: DecodeProtocol {
    private var session: DecompressionSession {
        didSet {
            VTDecompressionSessionInvalidate(oldValue.decompressionSession)
            lastPosition = 0
            startTime = 0
        }
    }

    private let options: KSOptions
    private var startTime = Int64(0)
    private var lastPosition = Int64(0)
    private var needReconfig = false

    init(options: KSOptions, session: DecompressionSession) {
        self.options = options
        options.decodeType = .asynchronousHardware
        self.session = session
    }

    func decodeFrame(from packet: Packet, completionHandler: @escaping (Result<MEFrame, Error>) -> Void) {
        if needReconfig {
            // 解决从后台切换到前台，解码失败的问题
            session = DecompressionSession(assetTrack: session.assetTrack, options: options)!
            needReconfig = false
        }
        guard let corePacket = packet.corePacket?.pointee, let data = corePacket.data else {
            return
        }
        do {
            var tuple = (data, Int(corePacket.size))
            let bitStreamFilter = session.assetTrack.bitStreamFilter
            if let bitStreamFilter {
                tuple = try bitStreamFilter.filter(tuple)
            }
            let sampleBuffer = try session.formatDescription.createSampleBuffer(tuple: tuple)
            let flags: VTDecodeFrameFlags = [
                ._EnableAsynchronousDecompression,
                ._EnableTemporalProcessing,
            ]
            var flagOut = VTDecodeInfoFlags(rawValue: 0)
            let timestamp = packet.timestamp
            let packetFlags = corePacket.flags
            let duration = corePacket.duration
            let size = corePacket.size
            let position = packet.position
            let isKeyFrame = packet.isKeyFrame
            let status = VTDecompressionSessionDecodeFrame(session.decompressionSession, sampleBuffer: sampleBuffer, flags: flags, infoFlagsOut: &flagOut) { [weak self] status, infoFlags, imageBuffer, _, _ in
                guard let self, !infoFlags.contains(.frameDropped) else {
                    return
                }
                guard status == noErr else {
                    KSLog("[video] videoToolbox decode block error \(status) isKeyFrame: \(isKeyFrame)")
                    if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                        // tvos在这边抛出NSError的话，会crash。所以就先不切换了解码器了。看下会怎么样
                        // 这个地方同步解码只会调用一次，但是异步解码，会调用多次。所以用状态来判断。
                        self.needReconfig = true
                    }
                    return
                }
                guard let imageBuffer else {
                    return
                }
                let frame = VideoVTBFrame(pixelBuffer: imageBuffer, fps: session.assetTrack.nominalFrameRate, isDovi: session.assetTrack.dovi != nil)
                frame.timebase = session.assetTrack.timebase
                if isKeyFrame, packetFlags & AV_PKT_FLAG_DISCARD != 0, self.lastPosition > 0 {
                    self.startTime = self.lastPosition - timestamp
                }
                self.lastPosition = max(self.lastPosition, timestamp)
                frame.position = position
                frame.timestamp = self.startTime + timestamp
                frame.duration = duration
                frame.size = size
                self.lastPosition += frame.duration
                completionHandler(.success(frame))
            }
            // 要在VTDecompressionSessionDecodeFrame之后才进行释放内容，不然在tvos上会crash
            if bitStreamFilter != nil {
                tuple.0.deallocate()
            }
            if status != noErr {
                KSLog("[video] videoToolbox decode error \(status) isKeyFrame: \(isKeyFrame)")
                /// tvOS切换app会导致硬解失败，并且只在这里返回错误，不会走到block里面，所以这里也要判断错误。
                /// 而iOS是在block里面返回错误，也会在这里返回错误
                if status == kVTInvalidSessionErr || status == kVTVideoDecoderMalfunctionErr || status == kVTVideoDecoderBadDataErr {
                    // 从后台切换到前台会报错-12903，关键帧也会。所以要重建session
                    session = DecompressionSession(assetTrack: session.assetTrack, options: options)!
                    //                if isKeyFrame {
                    //                    throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
                    //                }
                }
            }
        } catch {
            completionHandler(.failure(error))
        }
    }

    func doFlushCodec() {
        lastPosition = 0
        startTime = 0
        VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
    }

    func shutdown() {
        // 需要先调用WaitForAsynchronousFrames，才不会有Packet泄漏
        VTDecompressionSessionWaitForAsynchronousFrames(session.decompressionSession)
        VTDecompressionSessionInvalidate(session.decompressionSession)
    }

    func decode() {
        lastPosition = 0
        startTime = 0
    }

    deinit {}
}

class DecompressionSession {
    fileprivate let formatDescription: CMFormatDescription
    fileprivate let decompressionSession: VTDecompressionSession
    fileprivate var assetTrack: FFmpegAssetTrack
    init?(assetTrack: FFmpegAssetTrack, options: KSOptions) {
        self.assetTrack = assetTrack
        guard let pixelFormatType = assetTrack.pixelFormatType, let formatDescription = assetTrack.formatDescription else {
            return nil
        }
        self.formatDescription = formatDescription
        #if os(macOS)
        VTRegisterProfessionalVideoWorkflowVideoDecoders()
        if #available(macOS 11.0, *) {
            VTRegisterSupplementalVideoDecoderIfAvailable(formatDescription.mediaSubType.rawValue)
        }
        #endif
//        VTDecompressionSessionCanAcceptFormatDescription(<#T##session: VTDecompressionSession##VTDecompressionSession#>, formatDescription: <#T##CMFormatDescription#>)
        let attributes: NSMutableDictionary = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormatType,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferWidthKey: assetTrack.codecpar.width,
            kCVPixelBufferHeightKey: assetTrack.codecpar.height,
            kCVPixelBufferIOSurfacePropertiesKey: NSDictionary(),
        ]
        var session: VTDecompressionSession?
        // swiftlint:disable line_length
        // 不能用kCFAllocatorNull，不然会报错，todo: ffmpeg的硬解seek ts文件的话，不会花屏，还要找下原因
        let status = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: formatDescription, decoderSpecification: CMFormatDescriptionGetExtensions(formatDescription), imageBufferAttributes: attributes, outputCallback: nil, decompressionSessionOut: &session)
        // swiftlint:enable line_length
        guard status == noErr, let decompressionSession = session else {
            return nil
        }
        if #available(iOS 14.0, tvOS 14.0, macOS 11.0, *) {
            VTSessionSetProperty(decompressionSession, key: kVTDecompressionPropertyKey_PropagatePerFrameHDRDisplayMetadata,
                                 value: kCFBooleanTrue)
        }
        if let destinationDynamicRange = options.availableDynamicRange() {
            let pixelTransferProperties = [
                kVTPixelTransferPropertyKey_DestinationColorPrimaries: destinationDynamicRange.colorPrimaries,
                kVTPixelTransferPropertyKey_DestinationTransferFunction: destinationDynamicRange.transferFunction,
                kVTPixelTransferPropertyKey_DestinationYCbCrMatrix: destinationDynamicRange.yCbCrMatrix,
            ]
            VTSessionSetProperty(decompressionSession,
                                 key: kVTDecompressionPropertyKey_PixelTransferProperties,
                                 value: pixelTransferProperties as CFDictionary)
        }
        self.decompressionSession = decompressionSession
    }
}
#endif

protocol BitStreamFilter {
    static func filter(_ tuple: (UnsafeMutablePointer<UInt8>, Int)) throws -> (UnsafeMutablePointer<UInt8>, Int)
}

enum Nal3ToNal4BitStreamFilter: BitStreamFilter {
    static func filter(_ tuple: (UnsafeMutablePointer<UInt8>, Int)) throws -> (UnsafeMutablePointer<UInt8>, Int) {
        let (data, size) = tuple
        var ioContext: UnsafeMutablePointer<AVIOContext>?
        let status = avio_open_dyn_buf(&ioContext)
        if status == 0 {
            var nalSize: UInt32 = 0
            let end = data + size
            var nalStart = data
            while nalStart < end {
                nalSize = UInt32(nalStart[0]) << 16 | UInt32(nalStart[1]) << 8 | UInt32(nalStart[2])
                avio_wb32(ioContext, nalSize)
                nalStart += 3
                avio_write(ioContext, nalStart, Int32(nalSize))
                nalStart += Int(nalSize)
            }
            var demuxBuffer: UnsafeMutablePointer<UInt8>?
            let demuxSze = avio_close_dyn_buf(ioContext, &demuxBuffer)
            if let demuxBuffer {
                return (demuxBuffer, Int(demuxSze))
            } else {
                throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
            }
        } else {
            throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
        }
    }
}

enum AnnexbToCCBitStreamFilter: BitStreamFilter {
    static func filter(_ tuple: (UnsafeMutablePointer<UInt8>, Int)) throws -> (UnsafeMutablePointer<UInt8>, Int) {
        let (data, size) = tuple
        var ioContext: UnsafeMutablePointer<AVIOContext>?
        let status = avio_open_dyn_buf(&ioContext)
        if status == 0 {
            var nalStart = data
            var i = 0
            var start = 0
            while i < size {
                if i + 2 < size, data[i] == 0x00, data[i + 1] == 0x00, data[i + 2] == 0x01 {
                    if start == 0 {
                        start = 3
                        nalStart += 3
                    } else {
                        let len = i - start
                        avio_wb32(ioContext, UInt32(len))
                        avio_write(ioContext, nalStart, Int32(len))
                        start = i + 3
                        nalStart += len + 3
                    }
                    i += 3
                } else if i + 3 < size, data[i] == 0x00, data[i + 1] == 0x00, data[i + 2] == 0x00, data[i + 3] == 0x01 {
                    if start == 0 {
                        start = 4
                        nalStart += 4
                    } else {
                        let len = i - start
                        avio_wb32(ioContext, UInt32(len))
                        avio_write(ioContext, nalStart, Int32(len))
                        start = i + 4
                        nalStart += len + 4
                    }
                    i += 4
                } else {
                    i += 1
                }
            }
            let len = size - start
            avio_wb32(ioContext, UInt32(len))
            avio_write(ioContext, nalStart, Int32(len))
            var demuxBuffer: UnsafeMutablePointer<UInt8>?
            let demuxSze = avio_close_dyn_buf(ioContext, &demuxBuffer)
            if let demuxBuffer {
                return (demuxBuffer, Int(demuxSze))
            } else {
                throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
            }
        } else {
            throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
        }
    }
}

private extension CMFormatDescription {
    func createSampleBuffer(tuple: (UnsafeMutablePointer<UInt8>, Int)) throws -> CMSampleBuffer {
        let (data, size) = tuple
        var blockBuffer: CMBlockBuffer?
        var sampleBuffer: CMSampleBuffer?
        // swiftlint:disable line_length
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: data, blockLength: size, blockAllocator: kCFAllocatorNull, customBlockSource: nil, offsetToData: 0, dataLength: size, flags: 0, blockBufferOut: &blockBuffer)
        if status == noErr {
            status = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: self, sampleCount: 1, sampleTimingEntryCount: 0, sampleTimingArray: nil, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sampleBuffer)
            if let sampleBuffer {
                return sampleBuffer
            }
        }
        throw NSError(errorCode: .codecVideoReceiveFrame, avErrorCode: status)
        // swiftlint:enable line_length
    }
}

extension CMVideoCodecType {
    var avc: String {
        switch self {
        case kCMVideoCodecType_MPEG4Video:
            return "esds"
        case kCMVideoCodecType_H264:
            return "avcC"
        case kCMVideoCodecType_HEVC:
            return "hvcC"
        case kCMVideoCodecType_VP9:
            return "vpcC"
        case kCMVideoCodecType_AV1:
            return "av1C"
        default: return "avcC"
        }
    }
}
