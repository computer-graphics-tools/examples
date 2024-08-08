#include <metal_stdlib>
using namespace metal;

struct ParticleVertex {
    half4 position;
    float2 uv;
    float2 uv2;
};

kernel void updateVertexBuffer(
    device ParticleVertex *vertices [[buffer(0)]],
    const device float4 *positions [[buffer(1)]],
    constant uint &positionsCount [[ buffer(2) ]],
    const device float2 *uvs [[buffer(3)]],
    constant float &ratio [[ buffer(4) ]],
    constant float &particleSize [[ buffer(5) ]],
    uint id [[ thread_position_in_grid ]]
) {
    
    if (id >= positionsCount) { return; }
    uint particleIndex = id / 4;
    uint vertexInParticleIndex = id % 4;
    
    float4 particlePosition = positions[particleIndex];
    float halfSize = particleSize * -0.5;
    
    float3 newPosition = particlePosition.xyz;
    
    float2 particleUV = uvs[particleIndex];
    float2 uv[4] = {
        particleUV + float2(-halfSize * ratio, -halfSize),
        particleUV + float2(halfSize * ratio, -halfSize),
        particleUV + float2(-halfSize * ratio, halfSize),
        particleUV + float2(halfSize * ratio, halfSize)
    };

    const float2 uv2[4] = {
        float2(0.0, 0.0), float2(1.0, 0.0), float2(0.0, 1.0), float2(1.0, 1.0)
    };
    
    vertices[id].position = half4(half3(newPosition), 1.0);
    
    vertices[id].uv = uv[vertexInParticleIndex % 4];
    vertices[id].uv2 = uv2[vertexInParticleIndex % 4];

}
