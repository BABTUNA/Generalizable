// Oblique cross-section through the volume along the fold's cut plane.
// Same idea as NiiVue's arbitrary-plane slice (packages/niivue/src/shader-srcs.ts,
// vertSliceMMShader: each fragment carries a millimetre position on the plane, which is then
// mapped to texture space) and VTK's vtkImageReslice (a reslice axes matrix = origin + two
// in-plane direction vectors). Nearest-voxel reads; blending matches Slice.metal.
#include <metal_stdlib>
using namespace metal;

struct ObliqueUniforms {
    float3 originMM;    // plane point at the quad centre (mm, voxel-grid frame)
    float3 rightMM;     // screen-right direction × half-width (mm)
    float3 upMM;        // screen-up direction × half-height (mm)
    float3 spacing;     // mm per voxel
    float winLow;
    float winHigh;
    float labelOpacity;
    float aiOpacity;
    int hasLabels;
    int hasAI;
    int selected;
    uint mask[8];
};

struct OVert { float2 position; float2 ndc; };
struct OOut { float4 position [[position]]; float2 ndc; };

vertex OOut obliqueVertex(uint vid [[vertex_id]], constant OVert *v [[buffer(0)]]) {
    OOut o; o.position = float4(v[vid].position, 0, 1); o.ndc = v[vid].ndc; return o;
}

static inline bool visibleLabel(constant ObliqueUniforms &U, uint l) {
    return l != 0 && ((U.mask[l >> 5] >> (l & 31)) & 1u) != 0;
}

fragment float4 obliqueFragment(OOut in [[stage_in]],
                                constant ObliqueUniforms &U [[buffer(0)]],
                                texture3d<short, access::read> ct [[texture(0)]],
                                texture3d<uint, access::read> labels [[texture(1)]],
                                texture1d<float, access::read> lut [[texture(2)]],
                                texture3d<float, access::read> heat [[texture(3)]],
                                texture1d<float, access::read> heatLUT [[texture(4)]]) {
    float3 mm = U.originMM + in.ndc.x * U.rightMM + in.ndc.y * U.upMM;
    float3 vox = mm / U.spacing - 0.5;
    int3 dims = int3(ct.get_width(), ct.get_height(), ct.get_depth());
    int3 p = int3(round(vox));
    if (any(p < int3(0)) || any(p >= dims)) return float4(0, 0, 0, 1);

    float hu = float(ct.read(uint3(p)).r);
    float g = clamp((hu - U.winLow) / max(U.winHigh - U.winLow, 1.0), 0.0, 1.0);
    float3 rgb = float3(g);

    if (U.hasLabels != 0) {
        uint l = labels.read(uint3(p)).r;
        if (visibleLabel(U, l)) {
            float a = U.labelOpacity * (int(l) == U.selected ? 1.6 : 1.0);
            rgb = mix(rgb, lut.read(l).rgb, clamp(a, 0.0, 0.85));
        }
    }
    if (U.hasAI != 0) {
        float h = heat.read(uint3(p)).r;
        if (h > 0.15) {
            float4 c = heatLUT.read(uint(clamp(h, 0.0, 1.0) * 255.0));
            rgb = mix(rgb, c.rgb, clamp(h * U.aiOpacity, 0.0, 1.0));
        }
    }
    return float4(rgb, 1);
}
