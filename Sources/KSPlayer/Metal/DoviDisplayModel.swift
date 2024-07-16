//
//  DoviDisplayModel.swift
//
//
//  Created by kintan on 6/21/24.
//

import FFmpegKit
import Foundation
import Metal

public class DoviDisplayModel: PlaneDisplayModel {
    private lazy var iCtCp10LE = MetalRender.makePipelineState(fragmentFunction: "displayICtCpTexture", bitDepth: 10)
    private lazy var iCtCpBiPlanar10LE = MetalRender.makePipelineState(fragmentFunction: "displayICtCpBiPlanarTexture", bitDepth: 10)
    private var pipelineMap = [String: MTLRenderPipelineState]()
    override public func set(frame: VideoVTBFrame, encoder: MTLRenderCommandEncoder) {
        if var doviData = frame.doviData {
            let state: MTLRenderPipelineState
            let planeCount = frame.pixelBuffer.planeCount
            if let source = doviData.pipeline {
                state = pipeline(source: source, fragmentFunction: planeCount == 3 ? "displayICtCpTexture" : "displayICtCpBiPlanarTexture")
            } else {
                state = planeCount == 3 ? iCtCp10LE : iCtCpBiPlanar10LE
            }
            encoder.setRenderPipelineState(state)
            let isFullRangeVideo = frame.pixelBuffer.isFullRangeVideo
            let leftShift = frame.pixelBuffer.leftShift == 0 ? MetalRender.leftShiftMatrixBuffer : MetalRender.leftShiftSixMatrixBuffer
            doviData.linear = KSOptions.doviMatrix * doviData.linear
            let buffer1 = MetalRender.device.makeBuffer(bytes: &doviData, length: MemoryLayout<dovi_metadata>.size)
            buffer1?.label = "dovi"
            encoder.setFragmentBuffer(buffer1, offset: 0, index: 0)
            encoder.setFragmentBuffer(leftShift, offset: 0, index: 1)
            encoder.setFrontFacing(.clockwise)
            encoder.setVertexBuffer(posBuffer, offset: 0, index: 0)
            encoder.setVertexBuffer(uvBuffer, offset: 0, index: 1)
            encoder.drawIndexedPrimitives(type: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer, indexBufferOffset: 0)
        } else {
            super.set(frame: frame, encoder: encoder)
        }
    }

    private func pipeline(source: String, fragmentFunction: String, bitDepth: Int32 = 10) -> MTLRenderPipelineState {
        if let pipeline = pipelineMap[source] {
            return pipeline
        }
        var library = try! MetalRender.device.makeLibrary(source: source, options: nil)
        let pipeline = library.makePipelineState(vertexFunction: "mapTexture", fragmentFunction: fragmentFunction, bitDepth: 10)
        pipelineMap[source] = pipeline
        return pipeline
    }
}

extension dovi_metadata {
    var pipeline: String? {
        var str = """
        #include <metal_stdlib>
        using namespace metal;

        inline float3 pqEOTF(float3 rgb) {
        rgb = pow(max(rgb,0), float3(4096.0/(2523 * 128)));
        rgb = max(rgb - float3(3424./4096), 0.0) / (float3(2413./4096 * 32) - float3(2392./4096 * 32) * rgb);
        rgb = pow(rgb, float3(4096.0 * 4 / 2610));
        return rgb;
        }

        inline float3 pqOETF(float3 rgb) {
        rgb = pow(max(rgb,0), float3(2610./4096 / 4));
        rgb = (float3(3424./4096) + float3(2413./4096 * 32) * rgb) / (float3(1.0) + float3(2392./4096 * 32) * rgb);
        rgb = pow(rgb, float3(2523./4096 * 128));
        return rgb;
        }

        struct VertexIn
        {
        float4 pos [[attribute(0)]];
        float2 uv [[attribute(1)]];
        };

        struct VertexOut {
        float4 renderedCoordinate [[position]];
        float2 textureCoordinate;
        };

        vertex VertexOut mapTexture(VertexIn input [[stage_in]]) {
        VertexOut outVertex;
        outVertex.renderedCoordinate = input.pos;
        outVertex.textureCoordinate = input.uv;
        return outVertex;
        }

        struct dovi_metadata {
        // Colorspace transformation metadata
        float3x3 nonlinear;     // before PQ, also called "ycc_to_rgb"
        float3x3 linear;        // after PQ, also called "rgb_to_lms"
        simd_float3 nonlinear_offset;  // input offset ("ycc_to_rgb_offset")
        float minLuminance;
        float maxLuminance;
        struct reshape_data {
        float4 coeffs[8];
        float4 mmr[8*6];
        float pivots[7];
        float lo;
        float hi;
        uint8_t min_order;
        uint8_t max_order;
        uint8_t num_pivots;
        bool has_poly;
        bool has_mmr;
        bool mmr_single;
        } comp[3];
        };

        float reshape_poly(float s, float4 coeffs)
        {
        s = (coeffs.z * s + coeffs.y) * s + coeffs.x;
        return s;
        }

        #define pivot(i) float4(bool4(s >= data.pivots[i]))
        #define coef(i) data.coeffs[i]

        """
        str += """
        float3 reshape3(float3 rgb, constant dovi_metadata::reshape_data datas[3]) {
        float3 sig = clamp(rgb, 0.0, 1.0);
        float s;
        float4 coeffs;
        dovi_metadata::reshape_data data;

        """
        let array = Array(tuple: comp)
        for i in 0 ..< 3 {
            let data = array[i]
            str += """
            s = sig[\(i)];
            data = datas[\(i)];

            """
            if data.num_pivots > 2 {
                str += """
                coeffs = mix(mix(mix(coef(0), coef(1), pivot(0)),
                             mix(coef(2), coef(3), pivot(2)),
                             pivot(1)),
                         mix(mix(coef(4), coef(5), pivot(4)),
                             mix(coef(6), coef(7), pivot(6)),
                             pivot(5)),
                         pivot(3));

                """
            } else {
                str += """
                coeffs = data.coeffs[0];

                """
            }
            if data.has_poly, data.has_mmr {
                str += """
                if (coeffs.w == 0.0) {
                    s = reshape_poly(s, coeffs);
                } else {
                    \(data.reshapeMMR())
                }

                """
            } else if data.has_poly {
                str += """
                s = reshape_poly(s, coeffs);

                """
            } else {
                str += """
                {
                    \(data.reshapeMMR())
                }

                """
            }
            str += """
            rgb[\(i)] = clamp(s, data.lo, data.hi);

            """
        }
        str += """
        return rgb;
        }

        """
        str += """
        fragment float4 displayICtCpTexture(VertexOut in [[ stage_in ]],
                                    texture2d<half> yTexture [[ texture(0) ]],
                                    texture2d<half> uTexture [[ texture(1) ]],
                                    texture2d<half> vTexture [[ texture(2) ]],
                                    sampler textureSampler [[ sampler(0) ]],
                                    constant dovi_metadata& data [[ buffer(0) ]],
                                    constant uchar3& leftShift [[ buffer(1) ]])
        {
        float3 rgb;
        rgb.x = yTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.y = uTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.z = vTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb = rgb*float3(leftShift);
        rgb = reshape3(rgb, data.comp);
        rgb = data.nonlinear*(rgb + data.nonlinear_offset);
        rgb = pqEOTF(rgb);
        rgb = data.linear*rgb;
        rgb = pqOETF(rgb);
        return float4(rgb, 1);
        }

        fragment float4 displayICtCpBiPlanarTexture(VertexOut in [[ stage_in ]],
                                            texture2d<half> lumaTexture [[ texture(0) ]],
                                            texture2d<half> chromaTexture [[ texture(1) ]],
                                            sampler textureSampler [[ sampler(0) ]],
                                            constant dovi_metadata& data [[ buffer(0) ]],
                                            constant uchar3& leftShift [[ buffer(1) ]])
        {
        float3 rgb;
        rgb.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
        rgb.yz = float2(chromaTexture.sample(textureSampler, in.textureCoordinate).rg);
        rgb = rgb*float3(leftShift);
        rgb = reshape3(rgb, data.comp);
        rgb = data.nonlinear*(rgb + data.nonlinear_offset);
        rgb = pqEOTF(rgb);
        rgb = data.linear*rgb;
        rgb = pqOETF(rgb);
        return float4(rgb, 1);
        }
        """
        return str
    }
}

extension reshape_data {
    func reshapeMMR() -> String {
        var str = """
        """
        if mmr_single {
            str += """
            uint mmr_idx = 0;
            """
        } else {
            str += """
            uint mmr_idx = coeffs.y;
            """
        }
        str += """
        s = coeffs.x;
        float4 sigX;
        s = coeffs.x;
        sigX.xyz = sig.xxy * sig.yzz;
        sigX.w = sigX.x * sig.z;
        s += dot(data.mmr[mmr_idx + 0].xyz, sig);
        s += dot(data.mmr[mmr_idx + 1], sigX);
        """
        if max_order >= 2 {
            if min_order < max_order {
                str += """
                uint order = uint(coeffs.w);
                """
            }
            if min_order < 2 {
                str += """
                if (order >= 2) {
                """
            }
            str += """
            float3 sig2 = sig * sig;
            float4 sigX2 = sigX * sigX;
            s += dot(data.mmr[mmr_idx + 2].xyz, sig2);
            s += dot(data.mmr[mmr_idx + 3], sigX2);
            """
            if max_order == 3 {
                if min_order < 3 {
                    str += """
                    if (order >= 3) {
                    """
                }
                str += """
                s += dot(data.mmr[mmr_idx + 4].xyz, sig2 * sig);
                s += dot(data.mmr[mmr_idx + 5], sigX2 * sigX);
                """
                if min_order < 3 {
                    str += """
                    }
                    """
                }
            }
            if min_order < 2 {
                str += """
                }
                """
            }
        }
        return str
    }
}
