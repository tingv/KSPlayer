//
//  MetalRender.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/11.
//
@preconcurrency import Accelerate
import CoreVideo
internal import FFmpegKit
import Foundation
@preconcurrency import Metal
import QuartzCore
import simd
#if canImport(RealityFoundation)
import RealityFoundation
#endif
#if canImport(MetalKit)
import MetalKit
#endif

public class MetalRender {
    public static let device = MTLCreateSystemDefaultDevice()!
    @MainActor
    public static let mtlTextureCache: CVMetalTextureCache? = {
        var mtlTextureCache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &mtlTextureCache)
        return mtlTextureCache
    }()

    private static let library: MTLLibrary = {
        var library: MTLLibrary!
        library = device.makeDefaultLibrary()
        if library == nil {
            library = try? device.makeDefaultLibrary(bundle: .module)
        }
        return library
    }()

    @MainActor
    private static let renderPassDescriptor = MTLRenderPassDescriptor()
    @MainActor
    private static let commandQueue = MetalRender.device.makeCommandQueue()
    @MainActor
    private static let samplerState: MTLSamplerState? = {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        return MetalRender.device.makeSamplerState(descriptor: samplerDescriptor)
    }()

    private static let colorConversion601VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.videoRange.buffer

    private static let colorConversion601FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_601_4.pointee.buffer

    private static let colorConversion709VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.videoRange.buffer

    private static let colorConversion709FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_709_2.pointee.buffer

    private static let colorConversionSMPTE240MVideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.videoRange.buffer

    private static let colorConversionSMPTE240MFullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995.buffer

    private static let colorConversion2020VideoRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.videoRange.buffer

    private static let colorConversion2020FullRangeMatrixBuffer: MTLBuffer? = kvImage_YpCbCrToARGBMatrix_ITU_R_2020.buffer

    private static let colorOffsetVideoRangeMatrixBuffer: MTLBuffer? = SIMD3<Float>(-16.0 / 255.0, -128.0 / 255.0, -128.0 / 255.0).buffer

    private static let colorOffsetFullRangeMatrixBuffer: MTLBuffer? = SIMD3<Float>(0, -128.0 / 255.0, -128.0 / 255.0).buffer

    static let leftShiftMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(1, 1, 1)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    @MainActor
    static let leftShiftSixMatrixBuffer: MTLBuffer? = {
        var firstColumn = SIMD3<UInt8>(64, 64, 64)
        let buffer = MetalRender.device.makeBuffer(bytes: &firstColumn, length: MemoryLayout<SIMD3<UInt8>>.size)
        buffer?.label = "leftShit"
        return buffer
    }()

    @MainActor
    static func clear(drawable: MTLDrawable) {
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        guard let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
        else {
            return
        }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }

    @MainActor
    static func draw(frame: VideoVTBFrame, display: DisplayEnum, drawable: CAMetalDrawable) {
        let inputTextures = frame.pixelBuffer.textures()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard !inputTextures.isEmpty, let commandBuffer = commandQueue?.makeCommandBuffer(), let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.pushDebugGroup("RenderFrame")
        encoder.setFragmentSamplerState(samplerState, index: 0)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        display.set(frame: frame, encoder: encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        drawable.present()
    }

    #if canImport(RealityFoundation)
    @available(macOS 12.0, iOS 15.0, *)
    @MainActor
    static func draw(frame: VideoVTBFrame, display: DisplayEnum, drawable: TextureResource.Drawable) {
        let inputTextures = frame.pixelBuffer.textures()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        guard !inputTextures.isEmpty, let commandBuffer = commandQueue?.makeCommandBuffer(), let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        encoder.pushDebugGroup("RenderFrame")
        encoder.setFragmentSamplerState(samplerState, index: 0)
        for (index, texture) in inputTextures.enumerated() {
            texture.label = "texture\(index)"
            encoder.setFragmentTexture(texture, index: index)
        }
        display.set(frame: frame, encoder: encoder)
        encoder.popDebugGroup()
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        drawable.present()
    }
    #endif

    @MainActor
    public static func setFragmentBuffer(encoder: MTLRenderCommandEncoder, pixelBuffer: PixelBufferProtocol) {
        if pixelBuffer.planeCount > 1 {
            let isFullRangeVideo = pixelBuffer.isFullRangeVideo
            let leftShift = pixelBuffer.leftShift == 0 ? leftShiftMatrixBuffer : leftShiftSixMatrixBuffer
            let buffer1: MTLBuffer?
            let yCbCrMatrix = pixelBuffer.yCbCrMatrix
            if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_709_2 {
                buffer1 = isFullRangeVideo ? colorConversion709FullRangeMatrixBuffer : colorConversion709VideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_SMPTE_240M_1995 {
                buffer1 = isFullRangeVideo ? colorConversionSMPTE240MFullRangeMatrixBuffer : colorConversionSMPTE240MVideoRangeMatrixBuffer
            } else if yCbCrMatrix == kCVImageBufferYCbCrMatrix_ITU_R_2020 {
                buffer1 = isFullRangeVideo ? colorConversion2020FullRangeMatrixBuffer : colorConversion2020VideoRangeMatrixBuffer
            } else {
                buffer1 = isFullRangeVideo ? colorConversion601FullRangeMatrixBuffer : colorConversion601VideoRangeMatrixBuffer
            }
            let buffer2 = isFullRangeVideo ? colorOffsetFullRangeMatrixBuffer : colorOffsetVideoRangeMatrixBuffer
            encoder.setFragmentBuffer(buffer1, offset: 0, index: 0)
            encoder.setFragmentBuffer(buffer2, offset: 0, index: 1)
            encoder.setFragmentBuffer(leftShift, offset: 0, index: 2)
        }
    }

    public static func makePipelineState(fragmentFunction: String, isSphere: Bool = false, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        library.makePipelineState(vertexFunction: isSphere ? "mapSphereTexture" : "mapTexture", fragmentFunction: fragmentFunction, bitDepth: bitDepth)
    }

    @MainActor
    static func texture(pixelBuffer: CVPixelBuffer) -> [MTLTexture] {
//        guard let iosurface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
//            return []
//        }
//        let formats = KSOptions.pixelFormat(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
//        return (0 ..< formats.count).compactMap { index in
//            let width = pixelBuffer.widthOfPlane(at: index)
//            let height = pixelBuffer.heightOfPlane(at: index)
//            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[index], width: width, height: height, mipmapped: false)
//            return device.makeTexture(descriptor: descriptor, iosurface: iosurface, plane: index)
//        }
        // 苹果推荐用textureCache
        guard let mtlTextureCache else {
            return []
        }
        let formats = KSOptions.pixelFormat(planeCount: pixelBuffer.planeCount, bitDepth: pixelBuffer.bitDepth)
        return (0 ..< formats.count).compactMap { index in
            let width = pixelBuffer.widthOfPlane(at: index)
            let height = pixelBuffer.heightOfPlane(at: index)
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[index], width: width, height: height, mipmapped: false)
            var cvTexture: CVMetalTexture?
            CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                      mtlTextureCache,
                                                      pixelBuffer,
                                                      nil,
                                                      formats[index],
                                                      width,
                                                      height,
                                                      index,
                                                      &cvTexture)
            if let cvTexture {
                return CVMetalTextureGetTexture(cvTexture)
            }
            return nil
        }
    }

    static func textures(formats: [MTLPixelFormat], widths: [Int], heights: [Int], buffers: [MTLBuffer?], lineSizes: [Int]) -> [MTLTexture] {
        (0 ..< formats.count).compactMap { i in
            guard let buffer = buffers[i] else {
                return nil
            }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: formats[i], width: widths[i], height: heights[i], mipmapped: false)
            descriptor.storageMode = buffer.storageMode
            return buffer.makeTexture(descriptor: descriptor, offset: 0, bytesPerRow: lineSizes[i])
        }
    }
}

@MainActor
public protocol Drawable {
    func draw(frame: VideoVTBFrame, display: DisplayEnum)
    func clear()
}

extension CAMetalLayer: Drawable {
    public func draw(frame: VideoVTBFrame, display: DisplayEnum) {
        #if !os(tvOS)
        /// 设置edrMetadata 需要同时设置对的colorspace，不然会导致过度曝光。
        /// 加了这个代码就会导致iOS截图里面的内容左右颠倒。
        if #available(iOS 16, *) {
            edrMetadata = frame.edrMetadata
        }
        #endif
        let size: CGSize
        if display.isSphere {
            size = KSOptions.sceneSize
        } else {
            let par = frame.pixelBuffer.size
            let sar = frame.pixelBuffer.aspectRatio
            size = CGSize(width: par.width, height: par.height * sar.height / sar.width)
        }
        drawableSize = size
        pixelFormat = KSOptions.colorPixelFormat(bitDepth: frame.pixelBuffer.bitDepth)

        let colorspace = frame.pixelBuffer.colorspace
        if colorspace != nil, self.colorspace != colorspace {
            self.colorspace = colorspace
            KSLog("[video] CAMetalLayer colorspace \(String(describing: colorspace))")
            #if !os(tvOS)
            if #available(iOS 16.0, *) {
                if let name = colorspace?.name, name != CGColorSpace.sRGB {
                    #if os(macOS)
                    if let view = value(forKey: "NS_view") as? UIView, let value = view.window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue, value > 1.0 {
                        wantsExtendedDynamicRangeContent = true
                    } else {
                        wantsExtendedDynamicRangeContent = false
                    }
                    #else
                    wantsExtendedDynamicRangeContent = true
                    #endif
                } else {
                    wantsExtendedDynamicRangeContent = false
                }
                KSLog("[video] CAMetalLayer wantsExtendedDynamicRangeContent \(wantsExtendedDynamicRangeContent)")
            }
            #endif
        }
        guard let drawable = nextDrawable() else {
            KSLog("[video] CAMetalLayer not readyForMoreMediaData")
            return
        }
        MetalRender.draw(frame: frame, display: display, drawable: drawable)
    }

    public func clear() {
        #if !os(tvOS)
        if #available(iOS 16, *) {
            edrMetadata = nil
        }
        #endif
        if let drawable = nextDrawable() {
            MetalRender.clear(drawable: drawable)
        }
    }
}

#if canImport(RealityFoundation)
@available(macOS 12.0, iOS 15.0, *)
extension TextureResource: Drawable {
    public func draw(frame: VideoVTBFrame, display: any DisplayEnum) {
        if let drawableQueue, drawableQueue.width == frame.pixelBuffer.width, drawableQueue.height == frame.pixelBuffer.height {
            drawableQueue.draw(frame: frame, display: display)
        } else {
            if let drawableQueue = try? TextureResource.DrawableQueue(TextureResource.DrawableQueue.Descriptor(
                pixelFormat: KSOptions.colorPixelFormat(bitDepth: frame.pixelBuffer.bitDepth),
                width: frame.pixelBuffer.width,
                height: frame.pixelBuffer.height,
                usage: [.renderTarget, .shaderRead, .shaderWrite],
                mipmapsMode: .none
            )) {
                replace(withDrawables: drawableQueue)
                drawableQueue.draw(frame: frame, display: display)
            }
        }
    }

    public func clear() {
        drawableQueue?.clear()
    }
}

@available(macOS 12.0, iOS 15.0, *)
extension TextureResource.DrawableQueue: Drawable {
    public func draw(frame: VideoVTBFrame, display: any DisplayEnum) {
        guard let drawable = try? nextDrawable() else {
            KSLog("[video] TextureResource not readyForMoreMediaData")
            return
        }
        MetalRender.draw(frame: frame, display: display, drawable: drawable)
    }

    public func clear() {}
}
#endif

// swiftlint:disable identifier_name
// private let kvImage_YpCbCrToARGBMatrix_ITU_R_601_4 = vImage_YpCbCrToARGBMatrix(Kr: 0.299, Kb: 0.114)
// private let kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 = vImage_YpCbCrToARGBMatrix(Kr: 0.2126, Kb: 0.0722)
private let kvImage_YpCbCrToARGBMatrix_SMPTE_240M_1995 = vImage_YpCbCrToARGBMatrix(Kr: 0.212, Kb: 0.087)
private let kvImage_YpCbCrToARGBMatrix_ITU_R_2020 = vImage_YpCbCrToARGBMatrix(Kr: 0.2627, Kb: 0.0593)
extension vImage_YpCbCrToARGBMatrix {
    /**
     https://en.wikipedia.org/wiki/YCbCr
     @textblock
            | R |    | 1    0                                                            2-2Kr |   | Y' |
            | G | = | 1   -Kb * (2 - 2 * Kb) / Kg   -Kr * (2 - 2 * Kr) / Kg |  | Cb |
            | B |    | 1   2 - 2 * Kb                                                     0  |  | Cr |
     @/textblock
     */
    init(Kr: Float, Kb: Float) {
        let Kg = 1 - Kr - Kb
        self.init(Yp: 1, Cr_R: 2 - 2 * Kr, Cr_G: -Kr * (2 - 2 * Kr) / Kg, Cb_G: -Kb * (2 - 2 * Kb) / Kg, Cb_B: 2 - 2 * Kb)
    }

    var videoRange: vImage_YpCbCrToARGBMatrix {
        vImage_YpCbCrToARGBMatrix(Yp: 255 / 219 * Yp, Cr_R: 255 / 224 * Cr_R, Cr_G: 255 / 224 * Cr_G, Cb_G: 255 / 224 * Cb_G, Cb_B: 255 / 224 * Cb_B)
    }

    var simd: simd_float3x3 {
        // 初始化函数是用columns
        simd_float3x3([Yp, Yp, Yp], [0.0, Cb_G, Cb_B], [Cr_R, Cr_G, 0.0])
    }

    var buffer: MTLBuffer? {
        simd.buffer
    }
}

extension simd_float3x3 {
    var buffer: MTLBuffer? {
        var matrix = self
        let buffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3x3>.size)
        buffer?.label = "colorConversionMatrix"
        return buffer
    }
}

extension simd_float3 {
    var buffer: MTLBuffer? {
        var matrix = self
        let buffer = MetalRender.device.makeBuffer(bytes: &matrix, length: MemoryLayout<simd_float3>.size)
        buffer?.label = "colorOffset"
        return buffer
    }
}

// swiftlint:enable identifier_name

extension MTLLibrary {
    func makePipelineState(vertexFunction: String, fragmentFunction: String, bitDepth: Int32 = 8) -> MTLRenderPipelineState {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = KSOptions.colorPixelFormat(bitDepth: bitDepth)
        descriptor.vertexFunction = makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = makeFunction(name: fragmentFunction)
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<simd_float4>.stride
        vertexDescriptor.layouts[1].stride = MemoryLayout<simd_float2>.stride
        descriptor.vertexDescriptor = vertexDescriptor
        // swiftlint:disable force_try
        return try! device.makeRenderPipelineState(descriptor: descriptor)
        // swftlint:enable force_try
    }
}
