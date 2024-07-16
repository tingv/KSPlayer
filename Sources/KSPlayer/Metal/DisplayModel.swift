//
//  DisplayModel.swift
//  KSPlayer-iOS
//
//  Created by kintan on 2020/1/11.
//

import Foundation
import Metal
import simd
#if canImport(UIKit)
import UIKit
#endif

open class PlaneDisplayModel: DisplayEnum {
    private lazy var yuv = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: false)
    private lazy var yuvp010LE = MetalRender.makePipelineState(fragmentFunction: "displayYUVTexture", isSphere: false, bitDepth: 10)
    private lazy var nv12 = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: false)
    private lazy var p010LE = MetalRender.makePipelineState(fragmentFunction: "displayNV12Texture", isSphere: false, bitDepth: 10)
    private lazy var bgra = MetalRender.makePipelineState(fragmentFunction: "displayTexture", isSphere: false)
    public let isSphere: Bool = false
    let indexCount: Int
    let indexType = MTLIndexType.uint16
    let primitiveType = MTLPrimitiveType.triangleStrip
    let indexBuffer: MTLBuffer
    let posBuffer: MTLBuffer?
    let uvBuffer: MTLBuffer?

    init() {
        let (indices, positions, uvs) = PlaneDisplayModel.genSphere()
        let device = MetalRender.device
        indexCount = indices.count
        indexBuffer = device.makeBuffer(bytes: indices, length: MemoryLayout<UInt16>.size * indexCount)!
        posBuffer = device.makeBuffer(bytes: positions, length: MemoryLayout<simd_float4>.size * positions.count)
        uvBuffer = device.makeBuffer(bytes: uvs, length: MemoryLayout<simd_float2>.size * uvs.count)
    }

    private static func genSphere() -> ([UInt16], [simd_float4], [simd_float2]) {
        let indices: [UInt16] = [0, 1, 2, 3]
        let positions: [simd_float4] = [
            [-1.0, -1.0, 0.0, 1.0],
            [-1.0, 1.0, 0.0, 1.0],
            [1.0, -1.0, 0.0, 1.0],
            [1.0, 1.0, 0.0, 1.0],
        ]
        let uvs: [simd_float2] = [
            [0.0, 1.0],
            [0.0, 0.0],
            [1.0, 1.0],
            [1.0, 0.0],
        ]
        return (indices, positions, uvs)
    }

    public func pipeline(pixelBuffer: PixelBufferProtocol) -> MTLRenderPipelineState {
        let planeCount = pixelBuffer.planeCount
        let bitDepth = pixelBuffer.bitDepth
        switch planeCount {
        case 3:
            if bitDepth == 10 {
                return yuvp010LE
            } else {
                return yuv
            }
        case 2:
            if bitDepth == 10 {
                return p010LE
            } else {
                return nv12
            }
        default:
            return bgra
        }
    }

    public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        let state = pipeline(pixelBuffer: frame.pixelBuffer)
        encoder.setRenderPipelineState(state)
        MetalRender.setFragmentBuffer(encoder: encoder, pixelBuffer: frame.pixelBuffer)
        encoder.setFrontFacing(.clockwise)
        encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
        encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
    }

    public func touchesMoved(touch _: UITouch) {}
}
