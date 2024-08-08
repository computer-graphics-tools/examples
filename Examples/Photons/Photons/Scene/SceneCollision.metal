#include "../Utils.h"

kernel void handleVertexTriangleCollision(
    device float4 *positions [[ buffer(0) ]],
    constant float4 *prevPositions [[ buffer(1) ]],
    constant uint *collisionCandidates [[ buffer(2) ]],
    constant packed_float3 *wordPositions [[ buffer(3) ]],
    constant packed_uint3* sceneTriangles [[buffer(4) ]],
    constant float &frictionCoeff [[ buffer(5) ]],
    constant uint& maxCollisionCandidatesCount [[ buffer(6) ]],
    constant uint &gridSize [[ buffer(7) ]],
    uint gid [[ thread_position_in_grid ]]
) {
    if (gid >= gridSize) { return; }
    uint vertexIndex = gid;
    
    float3 position = positions[vertexIndex].xyz;
    float3 prevPosition = prevPositions[vertexIndex].xyz;
    float3 velocity = position - prevPosition;

    const float proximity = 0.025;
    float3 totalCorrection = 0.0;

    for (uint i = 0; i < maxCollisionCandidatesCount; i++) {
        uint triangleIndex = collisionCandidates[gid * maxCollisionCandidatesCount + i];
        if (triangleIndex == UINT_MAX) { continue; }
        uint3 triangleVertices = sceneTriangles[triangleIndex].xyz;


        float3 uvw;
        float3 closestPoint = closestPointTriangle(
            wordPositions[triangleVertices.x].xyz,
            wordPositions[triangleVertices.y].xyz,
            wordPositions[triangleVertices.z].xyz,
            position,
            uvw
        );
        
        float3 pointToVertex = position - closestPoint;
        float distance = length(pointToVertex);
        if (!isnormal(distance)) { continue; }
        float3 direction = pointToVertex / distance;
        float error = distance - proximity;

        if (error < 0) {
            float3 triangleNormal = cross(wordPositions[triangleVertices.y].xyz - wordPositions[triangleVertices.x].xyz, wordPositions[triangleVertices.z].xyz - wordPositions[triangleVertices.x].xyz);
            float3 triangleVelocity = 0;
            float3 relativeVelocity = velocity - triangleVelocity;
            float normalProjection = dot(triangleNormal, direction);
            float3 correction = error * direction;
            if (normalProjection < 0.0) { continue; }

            correction *= sign(normalProjection);

            const float relaxation = 1.0;
            float3 friction = computeFriction(direction, -error, relativeVelocity, frictionCoeff);
            totalCorrection += -correction * relaxation + friction;
            break;
        }
    }

    float3 newPosition = position + totalCorrection;
    positions[vertexIndex].xyz = newPosition;
}
