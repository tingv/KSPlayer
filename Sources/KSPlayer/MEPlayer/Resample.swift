//
//  Resample.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/27.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Libavcodec
import Libswresample
import Libswscale

protocol FrameChange {
    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame
    func shutdown()
}

class VideoSwresample: FrameChange {
    private var imgConvertCtx: OpaquePointer?
    private var format: AVPixelFormat = AV_PIX_FMT_NONE
    private var height: Int32 = 0
    private var width: Int32 = 0
    private var pool: CVPixelBufferPool?
    private var dstHeight: Int32?
    private var dstWidth: Int32?
    private let dstFormat: AVPixelFormat?
    private let fps: Float
    private let isDovi: Bool
    init(dstWidth: Int32? = nil, dstHeight: Int32? = nil, dstFormat: AVPixelFormat? = nil, fps: Float = 60, isDovi: Bool) {
        self.dstWidth = dstWidth
        self.dstHeight = dstHeight
        self.dstFormat = dstFormat
        self.fps = fps
        self.isDovi = isDovi
    }

    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        let pixelBuffer: PixelBufferProtocol
        if avframe.pointee.format == AV_PIX_FMT_VIDEOTOOLBOX.rawValue {
            pixelBuffer = unsafeBitCast(avframe.pointee.data.3, to: CVPixelBuffer.self)
        } else {
            pixelBuffer = try transfer(frame: avframe.pointee)
        }
        let frame = VideoVTBFrame(pixelBuffer: pixelBuffer, fps: fps, isDovi: isDovi)
        return frame
    }

    private func setup(format: AVPixelFormat, width: Int32, height: Int32, linesize: Int32) {
        if self.format == format, self.width == width, self.height == height {
            return
        }
        self.format = format
        self.height = height
        self.width = width
        let dstWidth = dstWidth ?? width
        let dstHeight = dstHeight ?? height
        let pixelFormatType: OSType
        if self.dstWidth == nil, self.dstHeight == nil, dstFormat == nil, let osType = format.osType() {
            pixelFormatType = osType
            sws_freeContext(imgConvertCtx)
            imgConvertCtx = nil
        } else {
            let dstFormat = dstFormat ?? format.bestPixelFormat
            pixelFormatType = dstFormat.osType()!
//            imgConvertCtx = sws_getContext(width, height, self.format, width, height, dstFormat, SWS_FAST_BILINEAR, nil, nil, nil)
            // AV_PIX_FMT_VIDEOTOOLBOX格式是无法进行swscale的
            imgConvertCtx = sws_getCachedContext(imgConvertCtx, width, height, self.format, dstWidth, dstHeight, dstFormat, SWS_FAST_BILINEAR, nil, nil, nil)
        }
        pool = CVPixelBufferPool.create(width: dstWidth, height: dstHeight, bytesPerRowAlignment: linesize, pixelFormatType: pixelFormatType)
    }

    func transfer(frame: AVFrame) throws -> PixelBufferProtocol {
        let format = AVPixelFormat(rawValue: frame.format)
        let width = frame.width
        let height = frame.height
        if format.leftShift > 0 {
            return PixelBuffer(frame: frame)
        }
        let pbuf = transfer(format: format, width: width, height: height, data: Array(tuple: frame.data), linesize: Array(tuple: frame.linesize))
        if let pbuf {
            pbuf.aspectRatio = frame.sample_aspect_ratio.size
            pbuf.yCbCrMatrix = frame.colorspace.ycbcrMatrix
            pbuf.colorPrimaries = frame.color_primaries.colorPrimaries
            pbuf.transferFunction = frame.color_trc.transferFunction
            // vt_pixbuf_set_colorspace
            if pbuf.transferFunction == kCVImageBufferTransferFunction_UseGamma {
                let gamma = NSNumber(value: frame.color_trc == AVCOL_TRC_GAMMA22 ? 2.2 : 2.8)
                CVBufferSetAttachment(pbuf, kCVImageBufferGammaLevelKey, gamma, .shouldPropagate)
            }
            if let chroma = frame.chroma_location.chroma {
                CVBufferSetAttachment(pbuf, kCVImageBufferChromaLocationTopFieldKey, chroma, .shouldPropagate)
            }
            return pbuf
        } else {
            throw NSError(errorCode: .pixelBufferPoolCreate, userInfo: ["format": format, "width": width, "height": height])
        }
    }

    func transfer(format: AVPixelFormat, width: Int32, height: Int32, data: [UnsafeMutablePointer<UInt8>?], linesize: [Int32]) -> CVPixelBuffer? {
        setup(format: format, width: width, height: height, linesize: linesize[1] == 0 ? linesize[0] : linesize[1])
        guard let pool else {
            return nil
        }
        return autoreleasepool {
            var pbuf: CVPixelBuffer?
            let ret = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pbuf)
            guard let pbuf, ret == kCVReturnSuccess else {
                return nil
            }
            CVPixelBufferLockBaseAddress(pbuf, CVPixelBufferLockFlags(rawValue: 0))
            let bufferPlaneCount = pbuf.planeCount
            if let imgConvertCtx {
                let bytesPerRow = (0 ..< bufferPlaneCount).map { i in
                    Int32(CVPixelBufferGetBytesPerRowOfPlane(pbuf, i))
                }
                let contents = (0 ..< bufferPlaneCount).map { i in
                    pbuf.baseAddressOfPlane(at: i)?.assumingMemoryBound(to: UInt8.self)
                }
                _ = sws_scale(imgConvertCtx, data.map { UnsafePointer($0) }, linesize, 0, height, contents, bytesPerRow)
            } else {
                let planeCount = format.planeCount
                let byteCount = format.bitDepth > 8 ? 2 : 1
                loop(iterations: bufferPlaneCount) { i in
                    let height = pbuf.heightOfPlane(at: i)
                    let size = Int(linesize[i])
                    let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pbuf, i)
                    var contents = pbuf.baseAddressOfPlane(at: i)
                    var source = data[i]!
                    if bufferPlaneCount < planeCount, i + 2 == planeCount {
                        var sourceU = data[i]!
                        var sourceV = data[i + 1]!
                        loop(iterations: height) { _ in
                            var j = 0
                            loop(iterations: size, stride: byteCount) { j in
                                contents?.advanced(by: 2 * j).copyMemory(from: sourceU.advanced(by: j), byteCount: byteCount)
                                contents?.advanced(by: 2 * j + byteCount).copyMemory(from: sourceV.advanced(by: j), byteCount: byteCount)
                            }
                            contents = contents?.advanced(by: bytesPerRow)
                            sourceU = sourceU.advanced(by: size)
                            sourceV = sourceV.advanced(by: size)
                        }
                    } else if bytesPerRow == size {
                        contents?.copyMemory(from: source, byteCount: height * size)
                    } else {
                        loop(iterations: height) { j in
                            contents?.advanced(by: j * bytesPerRow).copyMemory(from: source.advanced(by: j * size), byteCount: size)
                        }
                    }
                }
            }
            CVPixelBufferUnlockBaseAddress(pbuf, CVPixelBufferLockFlags(rawValue: 0))
            return pbuf
        }
    }

    func shutdown() {
        sws_freeContext(imgConvertCtx)
        imgConvertCtx = nil
    }

    deinit {}
}

extension BinaryInteger {
    func alignment(value: Self) -> Self {
        let remainder = self % value
        return remainder == 0 ? self : self + value - remainder
    }
}

typealias SwrContext = OpaquePointer

class AudioSwresample: FrameChange {
    private var swrContext: SwrContext?
    private var descriptor: AudioDescriptor
    private var outChannel: AVChannelLayout
    init(audioDescriptor: AudioDescriptor) {
        descriptor = audioDescriptor
        outChannel = audioDescriptor.outChannel
        _ = setup(descriptor: descriptor)
    }

    private func setup(descriptor: AudioDescriptor) -> Bool {
        var result = swr_alloc_set_opts2(&swrContext, &descriptor.outChannel, descriptor.audioFormat.sampleFormat, Int32(descriptor.audioFormat.sampleRate), &descriptor.channel, descriptor.sampleFormat, descriptor.sampleRate, 0, nil)
        result = swr_init(swrContext)
        if result < 0 {
            shutdown()
            return false
        } else {
            outChannel = descriptor.outChannel
            return true
        }
    }

    func change(avframe: UnsafeMutablePointer<AVFrame>) throws -> MEFrame {
        if !(descriptor == avframe.pointee) || outChannel != descriptor.outChannel {
            descriptor.update(frame: avframe.pointee)
            if !setup(descriptor: descriptor) {
                throw NSError(errorCode: .auidoSwrInit, userInfo: ["outChannel": descriptor.outChannel, "inChannel": descriptor.channel])
            }
        }
        let numberOfSamples = avframe.pointee.nb_samples
        let outSamples = swr_get_out_samples(swrContext, numberOfSamples)
        var frameBuffer = Array(tuple: avframe.pointee.data).map { UnsafePointer<UInt8>($0) }
        let channels = descriptor.outChannel.nb_channels
        var bufferSize = [Int32(0)]
        // 返回值是有乘以声道，所以不用返回值
        _ = av_samples_get_buffer_size(&bufferSize, channels, outSamples, descriptor.audioFormat.sampleFormat, 1)
        let frame = AudioFrame(dataSize: Int(bufferSize[0]), audioFormat: descriptor.audioFormat)
        frame.numberOfSamples = UInt32(swr_convert(swrContext, &frame.data, outSamples, &frameBuffer, numberOfSamples))
        return frame
    }

    func shutdown() {
        swr_free(&swrContext)
    }

    deinit {}
}

public class AudioDescriptor: Equatable {
    public var sampleRate: Int32
    public private(set) var audioFormat: AVAudioFormat
    fileprivate(set) var channel: AVChannelLayout
    fileprivate var sampleFormat: AVSampleFormat
    fileprivate var outChannel: AVChannelLayout

    convenience init(codecpar: AVCodecParameters) {
        self.init(sampleFormat: AVSampleFormat(rawValue: codecpar.format), sampleRate: codecpar.sample_rate, channel: codecpar.ch_layout)
    }

    init(sampleFormat: AVSampleFormat, sampleRate: Int32, channel: AVChannelLayout) {
        self.channel = channel
        outChannel = channel
        if sampleRate <= 0 {
            self.sampleRate = 48000
        } else {
            self.sampleRate = sampleRate
        }
        self.sampleFormat = sampleFormat
        #if os(macOS)
        let channelCount = AVAudioChannelCount(2)
        #else
        let channelCount = KSOptions.outputNumberOfChannels(channelCount: AVAudioChannelCount(outChannel.nb_channels))
        #endif
        audioFormat = AudioDescriptor.audioFormat(sampleFormat: sampleFormat, sampleRate: self.sampleRate, outChannel: &outChannel, channelCount: channelCount)
    }

    public static func == (lhs: AudioDescriptor, rhs: AudioDescriptor) -> Bool {
        lhs.sampleFormat == rhs.sampleFormat && lhs.sampleRate == rhs.sampleRate && lhs.channel == rhs.channel
    }

    public static func == (lhs: AudioDescriptor, rhs: AVFrame) -> Bool {
        var sampleRate = rhs.sample_rate
        if sampleRate <= 0 {
            sampleRate = 48000
        }
        return lhs.sampleFormat == AVSampleFormat(rawValue: rhs.format) && lhs.sampleRate == sampleRate && lhs.channel == rhs.ch_layout
    }

    static func audioFormat(sampleFormat: AVSampleFormat, sampleRate: Int32, outChannel: inout AVChannelLayout, channelCount: AVAudioChannelCount) -> AVAudioFormat {
        if channelCount != AVAudioChannelCount(outChannel.nb_channels) {
            av_channel_layout_default(&outChannel, Int32(channelCount))
        }
        let layoutTag: AudioChannelLayoutTag
        if let tag = outChannel.layoutTag {
            layoutTag = tag
        } else {
            av_channel_layout_default(&outChannel, Int32(channelCount))
            if let tag = outChannel.layoutTag {
                layoutTag = tag
            } else {
                av_channel_layout_default(&outChannel, 2)
                layoutTag = outChannel.layoutTag!
            }
        }
        KSLog("[audio] out channelLayout: \(outChannel)")
        var commonFormat: AVAudioCommonFormat
        var interleaved: Bool
        switch sampleFormat {
        case AV_SAMPLE_FMT_S16:
            commonFormat = .pcmFormatInt16
            interleaved = true
        case AV_SAMPLE_FMT_S32:
            commonFormat = .pcmFormatInt32
            interleaved = true
        case AV_SAMPLE_FMT_FLT:
            commonFormat = .pcmFormatFloat32
            interleaved = true
        case AV_SAMPLE_FMT_DBL:
            commonFormat = .pcmFormatFloat64
            interleaved = true
        case AV_SAMPLE_FMT_S16P:
            commonFormat = .pcmFormatInt16
            interleaved = false
        case AV_SAMPLE_FMT_S32P:
            commonFormat = .pcmFormatInt32
            interleaved = false
        case AV_SAMPLE_FMT_FLTP:
            commonFormat = .pcmFormatFloat32
            interleaved = false
        case AV_SAMPLE_FMT_DBLP:
            commonFormat = .pcmFormatFloat64
            interleaved = false
        default:
            commonFormat = .pcmFormatFloat32
            interleaved = false
        }
        if KSOptions.audioPlayerType == AudioRendererPlayer.self {
            interleaved = true
        } else if KSOptions.audioPlayerType == AudioEnginePlayer.self || KSOptions.audioPlayerType == AudioGraphPlayer.self {
            // AudioEnginePlayer 和AudioGraphPlayer 不能interleaved 为true，不然会crash
            interleaved = false
        }
        // 都要改成是Float32。这样播放dts才不会有小声的问题
        commonFormat = .pcmFormatFloat32
        return AVAudioFormat(commonFormat: commonFormat, sampleRate: Double(sampleRate), interleaved: interleaved, channelLayout: AVAudioChannelLayout(layoutTag: layoutTag)!)
        //        AVAudioChannelLayout(layout: outChannel.layoutTag.channelLayout)
    }

    public func update(frame: AVFrame) {
        sampleFormat = AVSampleFormat(rawValue: frame.format)
        sampleRate = frame.sample_rate
        if frame.sample_rate <= 0 {
            sampleRate = 48000
        } else {
            sampleRate = frame.sample_rate
        }
        channel = frame.ch_layout
        updateAudioFormat()
    }

    public func updateAudioFormat() {
        #if os(macOS)
        let channelCount = AVAudioChannelCount(2)
        #else
        let channelCount = KSOptions.outputNumberOfChannels(channelCount: AVAudioChannelCount(channel.nb_channels))
        #endif
        audioFormat = AudioDescriptor.audioFormat(sampleFormat: sampleFormat, sampleRate: sampleRate, outChannel: &outChannel, channelCount: channelCount)
    }
}
