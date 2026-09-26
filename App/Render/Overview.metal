// Overview.metal
// Orthographic front-to-back raymarch of the label volume ("peel" view), clipped by the
// cut plane. See docs/contracts/render-interface.md, docs/viz/SPEC.md section 2, and
// ShaderTypes.swift (kept in sync by hand).

#include <metal_stdlib>
using namespace metal;

struct OverviewUniforms {
    float4 camRight;
    float4 camUp;
    float4 camForward;
    float4 camPos;
    float4 texScale;
    float4 texOffset;
    float4 cutOrigin;
    float4 cutNormal;
    float4 cutUAxis;
    float4 cutVAxis;
    float4 findingCenter;
    float4 boxMin;
    float4 boxMax;
    float4 params0; // halfWidth, halfHeight, stepMM, maxSteps
    float4 params1; // findingRadius, hasFinding, unused, window level
    float4 params2; // window width, unused, unused, unused
};

struct OverviewVertexOut {
    float4 position [[position]];
    float2 ndc;
};

vertex OverviewVertexOut overviewVertex(uint vid [[vertex_id]]) {
    constexpr float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    OverviewVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.ndc = positions[vid];
    return out;
}

// SPEC.md section 1/4: label voxel is floor((mm-origin)/spacing), never the CT texture's
// +0.5 texel-centre offset. tc*dims - 0.5 already removes that offset exactly.
static uint labelAt(texture3d<uint, access::read> labelTex, float3 tc, uint3 dims) {
    int3 voxel = clamp(int3(floor(tc * float3(dims) - 0.5)), int3(0), int3(dims) - 1);
    return labelTex.read(uint3(voxel), 0).r;
}

// Gradient of the (trilinearly-sampled) blurred visible-occupancy field, sampled at a
// wide offset as a cheap stand-in for the reference's sigma=1 voxel Gaussian blur.
static float3 occupancyGradient(texture3d<float, access::sample> occTex, sampler s, float3 tc, float3 texel) {
    float dx = occTex.sample(s, tc + float3(texel.x, 0, 0)).r - occTex.sample(s, tc - float3(texel.x, 0, 0)).r;
    float dy = occTex.sample(s, tc + float3(0, texel.y, 0)).r - occTex.sample(s, tc - float3(0, texel.y, 0)).r;
    float dz = occTex.sample(s, tc + float3(0, 0, texel.z)).r - occTex.sample(s, tc - float3(0, 0, texel.z)).r;
    float3 g = float3(dx, dy, dz);
    float len = length(g);
    return len > 1e-5 ? (g / len) : float3(0, 0, 1);
}

// Windowed CT + label tint at overlay alpha 0.42, with the same screen/slice-space
// boundary outline as the 2D slice shader (approximated here with a half-voxel step
// along the cut plane's own axes, since the cut face has no fixed screen pixel pitch).
static float3 sliceColor(texture3d<float, access::sample> ctTex,
                          texture3d<uint, access::read> labelTex,
                          constant float4 *colorTable,
                          sampler linSampler,
                          float3 mm, float3 tc, float3 uAxis, float3 vAxis,
                          float3 texScale, float3 texOffset,
                          float stepMM, float level, float width) {
    float ctNorm = ctTex.sample(linSampler, tc).r;
    float hu = ctNorm * 32767.0;
    float windowed = saturate((hu - (level - width * 0.5)) / width);
    uint3 dims = uint3(ctTex.get_width(), ctTex.get_height(), ctTex.get_depth());
    uint label = labelAt(labelTex, tc, dims);
    float4 lc = (label < 256) ? colorTable[label] : float4(0.0);
    float3 gray3 = float3(windowed);
    bool visible = label != 0 && lc.a > 0.001;
    const float overlayAlpha = 0.42;
    float3 base = visible ? mix(gray3, lc.rgb, overlayAlpha) : gray3;

    bool edge = false;
    if (visible) {
        float3 offsets3[4] = {
            (mm + stepMM * uAxis) * texScale + texOffset,
            (mm - stepMM * uAxis) * texScale + texOffset,
            (mm + stepMM * vAxis) * texScale + texOffset,
            (mm - stepMM * vAxis) * texScale + texOffset
        };
        for (int i = 0; i < 4; i++) {
            float3 t2 = clamp(offsets3[i], float3(0.0), float3(1.0));
            if (labelAt(labelTex, t2, dims) != label) { edge = true; break; }
        }
    }
    return edge ? lc.rgb : base;
}

fragment float4 overviewFragment(OverviewVertexOut in [[stage_in]],
                                  constant OverviewUniforms &u [[buffer(0)]],
                                  constant float4 *colorTable [[buffer(1)]],
                                  texture3d<float, access::sample> ctTex [[texture(0)]],
                                  texture3d<uint, access::read> labelTex [[texture(1)]],
                                  texture3d<float, access::sample> occTex [[texture(2)]]) {
    constexpr sampler linSampler(filter::linear, address::clamp_to_edge, coord::normalized);

    float halfWidth = u.params0.x;
    float halfHeight = u.params0.y;
    float stepMM = max(u.params0.z, 0.1);
    int maxSteps = int(u.params0.w);
    float findingRadius = u.params1.x;
    bool hasFinding = u.params1.y > 0.5;
    float level = u.params1.w;
    float width = max(u.params2.x, 1.0);

    float3 rayDir = normalize(u.camForward.xyz);
    float3 originOnPlane = u.camPos.xyz + in.ndc.x * halfWidth * u.camRight.xyz + in.ndc.y * halfHeight * u.camUp.xyz;

    float3 invDir = 1.0 / rayDir;
    float3 t0 = (u.boxMin.xyz - originOnPlane) * invDir;
    float3 t1 = (u.boxMax.xyz - originOnPlane) * invDir;
    float3 tsmall = min(t0, t1);
    float3 tbig = max(t0, t1);
    float tStart = max(max(tsmall.x, tsmall.y), tsmall.z);
    float tEnd = min(min(tbig.x, tbig.y), tbig.z);
    tStart = max(tStart, 0.0);

    if (tEnd <= tStart) {
        return float4(0.03, 0.03, 0.05, 1.0);
    }

    float3 texel = 1.0 / float3(ctTex.get_width(), ctTex.get_height(), ctTex.get_depth());
    float3 occTexel = 2.0 / float3(occTex.get_width(), occTex.get_height(), occTex.get_depth());
    float3 lightDir = normalize(float3(0.35, -0.55, 0.75));

    float dn = dot(rayDir, u.cutNormal.xyz);

    float3 accumColor = float3(0.0);
    float accumAlpha = 0.0;
    bool crossedPlane = false;
    float t = tStart;

    for (int i = 0; i < maxSteps; i++) {
        if (t > tEnd || accumAlpha > 0.98) break;
        float3 p = originOnPlane + rayDir * t;
        t += stepMM;

        // Clip-plane test (SPEC.md section 2): a point is nearer the camera than the
        // plane along this ray when signed*dn < 0; when the ray is (near-)parallel to
        // the plane (tilt 0, straight-on) there's no per-ray crossing, so fall back to
        // keeping the plane's own +normal half.
        float signed_ = dot(p - u.cutOrigin.xyz, u.cutNormal.xyz);
        bool clipped = (abs(dn) > 1e-3) ? (signed_ * dn < 0.0) : (signed_ > 0.0);

        float3 tc = p * u.texScale.xyz + u.texOffset.xyz;
        if (any(tc < float3(0.0)) || any(tc > float3(1.0))) continue;

        if (clipped) {
            continue;
        }

        if (!crossedPlane) {
            crossedPlane = true;
            float3 face = sliceColor(ctTex, labelTex, colorTable, linSampler,
                                      p, tc, u.cutUAxis.xyz, u.cutVAxis.xyz,
                                      u.texScale.xyz, u.texOffset.xyz, stepMM, level, width);
            accumColor += (1.0 - accumAlpha) * face * 1.0;
            accumAlpha += (1.0 - accumAlpha) * 1.0;
            continue;
        }

        uint3 dims3 = uint3(ctTex.get_width(), ctTex.get_height(), ctTex.get_depth());
        uint label = labelAt(labelTex, tc, dims3);
        float4 lc = (label < 256) ? colorTable[label] : float4(0.0);

        float dSample = hasFinding ? length(p - u.findingCenter.xyz) : 1e9;
        bool inFinding = hasFinding && dSample < findingRadius;

        if (lc.a <= 0.001 && !inFinding) continue;

        float3 occTc = tc;
        float3 grad = occupancyGradient(occTex, linSampler, occTc, occTexel);
        float3 normal = -grad;
        float shade = clamp(0.35 + 0.65 * abs(dot(normal, lightDir)), 0.0, 1.0);

        if (lc.a > 0.001) {
            // alpha_s = 1-(1-alpha_2mm)^(s/2mm): rescale the reference 2mm-step opacity
            // table to this volume's actual step size.
            float scaledAlpha = 1.0 - pow(1.0 - lc.a, stepMM / 2.0);
            float3 shaded = lc.rgb * shade;
            accumColor += (1.0 - accumAlpha) * shaded * scaledAlpha;
            accumAlpha += (1.0 - accumAlpha) * scaledAlpha;
        }
        if (inFinding && accumAlpha <= 0.98) {
            float3 fColor = float3(1.0, 0.9, 0.15) * shade;
            float fAlpha = 0.6;
            accumColor += (1.0 - accumAlpha) * fColor * fAlpha;
            accumAlpha += (1.0 - accumAlpha) * fAlpha;
        }
    }

    float3 background = float3(0.03, 0.03, 0.05);
    float3 finalColor = accumColor + (1.0 - accumAlpha) * background;
    return float4(finalColor, 1.0);
}
