#include <metal_stdlib>
using namespace metal;

kernel void assembleScenePositions(device packed_float3* outputVertices [[buffer(0)]],
                         device const packed_float3* inputVertices [[buffer(1)]],
                         constant uint& positionsCount [[buffer(2)]],
                         constant uint& offset [[buffer(3)]],
                         constant float4x4& transform [[buffer(4)]],
                         uint gid [[thread_position_in_grid]])
{
    if (gid >= positionsCount) { return; }
    float3 position = inputVertices[gid];
    float4 transformedVertex = transform * float4(position, 1.0);
    outputVertices[gid + offset] = transformedVertex.xyz;
}

kernel void assembleSceneIndices(device uint* outputIndices [[buffer(0)]],
                         device const uint* inputIndices [[buffer(1)]],
                         constant uint& indicesCount [[buffer(2)]],
                         constant uint& offset [[buffer(3)]],
                         constant uint& vertexOffset [[buffer(4)]],
                         constant float4x4& transform [[buffer(5)]],
                         uint gid [[thread_position_in_grid]])
{
    if (gid >= indicesCount) { return; }
    uint inputIndex = inputIndices[gid];
    outputIndices[gid + offset] = inputIndex + vertexOffset;
}
