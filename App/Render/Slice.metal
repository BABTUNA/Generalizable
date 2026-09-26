// Slice.metal
// Full-screen quad slicing the CT / label volumes along the cut plane. See
// docs/contracts/render-interface.md, docs/viz/SPEC.md section 1, and ShaderTypes.swift
// (kept in sync by hand — no bridging header is wired up in Project.json).

#include <metal_stdlib>
using namespace metal;

struct SliceUniforms {
    float4 originMM;
    float4 uAxis;
    float4 vAxis;
    float4 texScale;
    float4 texOffset;
    float4 findingCenter;
    float4 params0; // halfU, halfV, level, width
    float4 params1; // findingRadius, hasFinding, mode (0=ct,1=layers), unused
    float4 params2; // mm per pixel along uAxis, mm per pixel along vAxis, unused, unused
};

struct SliceVertexOut {
    float4 position [[position]];
    float2 ndc;
};

vertex SliceVertexOut sliceVertex(uint vid [[vertex_id]]) {
    constexpr float2 positions[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    SliceVertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.ndc = positions[vid];
    return out;
}

// SPEC.md: label voxel index is floor((mm - origin)/spacing), no +0.5 — the CT texture's
// normalized-coordinate `+0.5` texel-centre offset must never leak into this integer read.
// tc already has that +0.5 baked in (tc*dims - 0.5 == (mm-origin)/spacing exactly), so
// subtracting it back out here keeps CaseBundle.textureCoord(forMM:) as the one shared formula.
static uint labelAt(texture3d<uint, access::read> labelTex, float3 tc, uint3 dims) {
    int3 voxel = clamp(int3(floor(tc * float3(dims) - 0.5)), int3(0), int3(dims) - 1);
    return labelTex.read(uint3(voxel), 0).r;
}

fragment float4 sliceFragment(SliceVertexOut in [[stage_in]],
                               constant SliceUniforms &u [[buffer(0)]],
                               constant float4 *colorTable [[buffer(1)]],
                               texture3d<float, access::sample> ctTex [[texture(0)]],
                               texture3d<uint, access::read> labelTex [[texture(1)]]) {
    float halfU = u.params0.x;
    float halfV = u.params0.y;
    float level = u.params0.z;
    float width = max(u.params0.w, 1.0);
    float mode = u.params1.z;

    float3 mm = u.originMM.xyz + in.ndc.x * halfU * u.uAxis.xyz + in.ndc.y * halfV * u.vAxis.xyz;
    float3 tc = mm * u.texScale.xyz + u.texOffset.xyz;
    if (any(tc < float3(0.0)) || any(tc > float3(1.0))) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }

    constexpr sampler linSampler(filter::linear, address::clamp_to_edge, coord::normalized);
    float ctNorm = ctTex.sample(linSampler, tc).r;
    float hu = ctNorm * 32767.0;
    float windowed = saturate((hu - (level - width * 0.5)) / width);

    uint3 dims = uint3(ctTex.get_width(), ctTex.get_height(), ctTex.get_depth());
    uint label = labelAt(labelTex, tc, dims);

    float4 color;
    if (mode < 0.5) {
        color = float4(windowed, windowed, windowed, 1.0);
    } else {
        float4 lc = (label < 256) ? colorTable[label] : float4(0.0);
        bool visible = label != 0 && lc.a > 0.5;
        const float overlayAlpha = 0.42;
        float3 gray3 = float3(windowed);
        float3 base = visible ? mix(gray3, lc.rgb, overlayAlpha) : gray3;

        // 1px boundary outline, checked in screen (slice) space so it stays crisp on an
        // oblique cut, not along the volume's raw x/y/z voxel grid.
        bool edge = false;
        if (visible) {
            float pxU = u.params2.x;
            float pxV = u.params2.y;
            float3 mmPU = mm + pxU * u.uAxis.xyz;
            float3 mmMU = mm - pxU * u.uAxis.xyz;
            float3 mmPV = mm + pxV * u.vAxis.xyz;
            float3 mmMV = mm - pxV * u.vAxis.xyz;
            float3 tcs[4] = {
                mmPU * u.texScale.xyz + u.texOffset.xyz,
                mmMU * u.texScale.xyz + u.texOffset.xyz,
                mmPV * u.texScale.xyz + u.texOffset.xyz,
                mmMV * u.texScale.xyz + u.texOffset.xyz
            };
            for (int i = 0; i < 4; i++) {
                float3 t2 = clamp(tcs[i], float3(0.0), float3(1.0));
                if (labelAt(labelTex, t2, dims) != label) { edge = true; break; }
            }
        }
        color = edge ? float4(lc.rgb, 1.0) : float4(base, 1.0);
    }

    if (u.params1.y > 0.5) {
        float radius = u.params1.x;
        float dist = length(mm - u.findingCenter.xyz);
        float thickness = max(halfU, halfV) * 0.006;
        if (abs(dist - radius) < thickness) {
            color = float4(1.0, 0.95, 0.1, 1.0);
        }
    }

    return color;
}
