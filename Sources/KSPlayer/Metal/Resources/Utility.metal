//
//  Utility.metal
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
