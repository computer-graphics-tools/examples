#include "../Utils.h"

kernel void predictPositions(
    device float3 *positions [[buffer(0)]],
    device float3 *prevPositions [[buffer(1)]],
    device float3 *predictedPositions [[buffer(2)]],
    constant float3 &gravity [[buffer(3)]],
    constant float &timeStep [[buffer(4)]],
    constant uint &positionsCount [[buffer(5)]],
    constant float3 &left [[buffer(6)]],
    constant float3 &right [[buffer(7)]],
    constant float3 &head [[buffer(8)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= positionsCount) { return; }
    
    float3 position = positions[id];
    float3 prevPosition = prevPositions[id];
    float3 velocity = position - prevPosition;
    
    const float3 attractor = mix(head, (left + right) / 2.0, 2.0);
    float3 toAttractor = attractor - position;
    float3 attractorForce = normalize(toAttractor) * smoothstep(0.2, 0.0, length(left - right)) * 12.0;
    
    const float damping = 0.98;
    velocity *= damping;
    velocity = min(max(velocity, -0.05), 0.05);
    velocity += attractorForce * timeStep * timeStep;
    float3 newPosition = position + velocity + gravity * timeStep * timeStep;
    
    prevPositions[id] = position;
    positions[id] = newPosition;
    predictedPositions[id] = newPosition;
}

kernel void solveConstraints(
    constant float3 &leftHandCollider [[buffer(0)]],
    constant float3 &rightHandCollider [[buffer(1)]],
    device uint *collisionCandidates [[buffer(2)]],
    device float3 *positions [[buffer(3)]],
    device float3 *prevPositions [[buffer(4)]],
    constant uint &collisionCandidatesCount [[buffer(5)]],
    constant float &particleRadius [[buffer(9)]],
    device float3 *targetPositions [[buffer(10)]],
    constant uint &positionsCount [[buffer(11)]],
    uint gid [[ thread_position_in_grid ]]
) {
    if (gid >= positionsCount) { return; }
    uint vertexIndex = gid;
    
    float3 position = positions[vertexIndex].xyz;
    float3 prevPosition = prevPositions[vertexIndex].xyz;
    float3 velocity = position - prevPosition;
    float3 totalCorrection = 0;
    float correctionCount = 0;
    
    if (position.y < 0) {
        float3 direction = float3(0, 1, 0);
        float lambda = -position.y;
        float3 friction = computeFriction(direction, lambda, velocity, 0.5);

        float3 correction = (lambda * direction + friction) * 0.5;
        totalCorrection += correction;
        correctionCount += 1.0;
    }
    
    float leftHandDistance = length(leftHandCollider - position);
    float rightHandDistance = length(rightHandCollider - position);

    if (leftHandDistance < 0.1) {
        float3 direction = normalize(leftHandCollider - position);
        float error = leftHandDistance - 0.1;
        float3 correction = (error * direction);
        totalCorrection += correction;
        correctionCount += 1.0;
    }
    
    if (rightHandDistance < 0.1) {
        float3 direction = normalize(rightHandDistance - position);
        float error = rightHandDistance - 0.1;
        float3 correction = (error * direction);
        totalCorrection += correction;
        correctionCount += 1.0;
    }
    
    for (int i = 0; i < int(collisionCandidatesCount); i++) {
        uint collisionVertexIndex = collisionCandidates[gid * collisionCandidatesCount + i];
        if (collisionVertexIndex != vertexIndex && collisionVertexIndex != UINT_MAX) {
            float3 neighborPosition = positions[collisionVertexIndex].xyz;
            float3 diff = position - neighborPosition;
            float diameter2 = particleRadius * 4;
            float distance = length_squared(diff);
            if (distance < pow(diameter2, 2.0)) {
                distance = sqrt(distance);
                float3 diff = position - neighborPosition;
                float diameter = particleRadius * 2;
                float error = distance - diameter;

                float3 prevNeighborPosition = prevPositions[collisionVertexIndex].xyz;
                float3 neighborVelocity = neighborPosition - prevNeighborPosition;
                if (!isnormal(distance)) { continue; }
                float3 direction = diff / distance;
                float3 friction = computeFriction(direction, -error, velocity - neighborVelocity, 0.5);

                float relaxation = error < 0 ? 0.125 : 0.0000001;
                float3 correction = (-error * direction + friction) * relaxation;
                totalCorrection += correction;
                correctionCount += 1.0;
            }
        }
    }
    
    targetPositions[vertexIndex].xyz = position + (totalCorrection / max(1.0, totalCorrection));
}

