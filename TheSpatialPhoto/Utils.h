#ifndef Utils_h
#define Utils_h

#include <metal_stdlib>
using namespace metal;

METAL_FUNC float3 closestPointTriangle(float3 p0, float3 p1, float3 p2, float3 p, thread float3& uvw) {
    float b0 = 1.0 / 3.0;
    float b1 = b0;
    float b2 = b0;
    
    float3 d1 = p1 - p0;
    float3 d2 = p2 - p0;
    float3 pp0 = p - p0;
    float a = length_squared(d1);
    float b = dot(d2, d1);
    float c = dot(pp0, d1);
    float d = b;
    float e = length_squared(d2);
    float f = dot(pp0, d2);
    float det = a * e - b * d;
    
    if (det != 0.0) {
        float s = (c * e - b * f) / det;
        float t = (a * f - c * d) / det;
        b0 = 1.0 - s - t; // inside triangle
        b1 = s;
        b2 = t;
        if (b0 < 0.0) { // on edge 1-2
            float3 d = p2 - p1;
            float d2 = length_squared(d);
            float t = (d2 == 0.0) ? 0.5 : dot(d, p - p1) / d2;
            t = saturate(t);

            b0 = 0.0;
            b1 = (1.0 - t);
            b2 = t;
        }
        else if (b1 < 0.0) { // on edge 2-0
            float3 d = p0 - p2;
            float d2 = length_squared(d);
            float t = (d2 == 0.0) ? 0.5 : dot(d, p - p2) / d2;
            t = saturate(t);

            b1 = 0.0;
            b2 = (1.0 - t);
            b0 = t;
        }
        else if (b2 < 0.0) { // on edge 0-1
            float3 d = p1 - p0;
            float d2 = length_squared(d);
            float t = (d2 == 0.0) ? 0.5 : dot(d, (p - p0)) / d2;
            t = saturate(t);

            b2 = 0.0;
            b0 = (1.0 - t);
            b1 = t;
        }
    }
    
    uvw = float3(b0, b1, b2);

    return b0 * p0 + b1 * p1 + b2 * p2;
}

METAL_FUNC float3 computeFriction(float3 norm, float error, float3 relVelocity, float frictionCoeff) {
    float3 friction = float3(0);
    if (frictionCoeff > 0 && error > 0) {
        float3 tanVelocity = relVelocity - norm * dot(relVelocity, norm);
        float tanLength = length(tanVelocity);
        float maxTanLength = error * frictionCoeff;
        friction = -tanVelocity * min(maxTanLength / tanLength, 1.0);
    }

    return friction;
}

#endif /* Utils_h */
