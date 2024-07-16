//
//  Shaders.metal
#include <metal_stdlib>
#import "Utility.metal"
using namespace metal;

vertex VertexOut mapTexture(VertexIn input [[stage_in]]) {
    VertexOut outVertex;
    outVertex.renderedCoordinate = input.pos;
    outVertex.textureCoordinate = input.uv;
    return outVertex;
}

vertex VertexOut mapSphereTexture(VertexIn input [[stage_in]], constant float4x4& uniforms [[ buffer(2) ]]) {
    VertexOut outVertex;
    outVertex.renderedCoordinate = uniforms * input.pos;
    outVertex.textureCoordinate = input.uv;
    return outVertex;
}

fragment half4 displayTexture(VertexOut in [[ stage_in ]],
                              texture2d<half> texture [[ texture(0) ]],
                              sampler textureSampler [[ sampler(0) ]]) {
    return texture.sample(textureSampler, in.textureCoordinate);
}

fragment float4 displayYUVTexture(VertexOut in [[ stage_in ]],
                                  texture2d<half> yTexture [[ texture(0) ]],
                                  texture2d<half> uTexture [[ texture(1) ]],
                                  texture2d<half> vTexture [[ texture(2) ]],
                                  sampler textureSampler [[ sampler(0) ]],
                                  constant float3x3& yuvToBGRMatrix [[ buffer(0) ]],
                                  constant float3& colorOffset [[ buffer(1) ]],
                                  constant uchar3& leftShift [[ buffer(2) ]])
{
    float3 yuv;
    yuv.x = yTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.y = uTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.z = vTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv = yuv*float3(leftShift);
    return float4(yuvToBGRMatrix*(yuv+colorOffset), 1);
}

fragment float4 displayNV12Texture(VertexOut in [[ stage_in ]],
                                   texture2d<half> lumaTexture [[ texture(0) ]],
                                   texture2d<half> chromaTexture [[ texture(1) ]],
                                   sampler textureSampler [[ sampler(0) ]],
                                   constant float3x3& yuvToBGRMatrix [[ buffer(0) ]],
                                   constant float3& colorOffset [[ buffer(1) ]],
                                   constant uchar3& leftShift [[ buffer(2) ]])
{
    float3 yuv;
    yuv.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
    yuv.yz = float2(chromaTexture.sample(textureSampler, in.textureCoordinate).rg);
    yuv = yuv*float3(leftShift);
    return float4(yuvToBGRMatrix*(yuv+colorOffset), 1);
}
