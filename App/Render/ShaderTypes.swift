// ShaderTypes.swift
// Uniform layouts shared with Slice.metal / Overview.metal.
//
// No bridging header is wired up in Project.json (owned by L3b), so these structs are
// mirrored by hand in the .metal files. To keep Swift's layout and Metal's layout
// identical without relying on SIMD3 packing rules (which differ subtly between the
// two), every field here is either a scalar (Float / UInt32) or a SIMD4<Float>, laid
// out in the same order as the matching Metal struct. Keep the two in sync.

import simd

/// "what patients see" (colored layers) vs "what doctors see" (grayscale CT).
enum SliceMode: Equatable {
    case layers
    case ct
}

/// Matches `SliceUniforms` in Slice.metal.
struct SliceUniforms {
    var originMM: SIMD4<Float>
    var uAxis: SIMD4<Float>
    var vAxis: SIMD4<Float>
    var texScale: SIMD4<Float>
    var texOffset: SIMD4<Float>
    var findingCenter: SIMD4<Float>
    /// halfU (mm), halfV (mm), window level, window width
    var params0: SIMD4<Float>
    /// finding radius (mm), hasFinding (0/1), mode (0 = ct, 1 = layers), unused
    var params1: SIMD4<Float>
    /// mm per screen pixel along uAxis, mm per screen pixel along vAxis (for the boundary outline), unused, unused
    var params2: SIMD4<Float>
}

/// Matches `OverviewUniforms` in Overview.metal.
struct OverviewUniforms {
    var camRight: SIMD4<Float>
    var camUp: SIMD4<Float>
    var camForward: SIMD4<Float>
    var camPos: SIMD4<Float>
    var texScale: SIMD4<Float>
    var texOffset: SIMD4<Float>
    var cutOrigin: SIMD4<Float>
    var cutNormal: SIMD4<Float>
    var cutUAxis: SIMD4<Float>
    var cutVAxis: SIMD4<Float>
    var findingCenter: SIMD4<Float>
    var boxMin: SIMD4<Float>
    var boxMax: SIMD4<Float>
    /// halfWidth (mm), halfHeight (mm), stepMM, maxSteps
    var params0: SIMD4<Float>
    /// findingRadius (mm), hasFinding (0/1), unused, window level
    var params1: SIMD4<Float>
    /// window width, unused, unused, unused
    var params2: SIMD4<Float>
}
