//
//  Shaders.metal
#include <metal_stdlib>
using namespace metal;
#import "Utility.metal"

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
    rgb = data.nonlinear*(rgb + data.nonlinear_offset);
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
    rgb = data.nonlinear*(rgb + data.nonlinear_offset);
    return float4(rgb, 1);
}
