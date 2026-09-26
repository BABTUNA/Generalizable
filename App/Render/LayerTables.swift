// LayerTables.swift
// Builds the 256-entry colour tables the shaders index by label ID. Shared by SliceView
// (alpha = visible 0/1) and OverviewView (alpha = per-sample raymarch opacity).

import simd

enum LayerTables {
    /// Per-layer-group raymarch opacity at the reference 2mm step (docs/viz/SPEC.md).
    /// The shader rescales this to the actual step size via alpha_s = 1-(1-alpha)^(s/2mm).
    static func groupOpacity(_ group: String) -> Float {
        switch group {
        case "skin": return 0.03
        case "fat": return 0.06
        case "muscle": return 0.15
        case "bone": return 0.55
        case "organ": return 0.35
        case "brain": return 0.35
        case "finding": return 0.6
        default: return 0.15
        }
    }

    /// SliceView colour table: rgb = layer colour, a = 1 if visible else 0.
    static func visibilityTable(layers: [CaseLayer], visibleLayerIDs: Set<Int>) -> [SIMD4<Float>] {
        var table = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 0), count: 256)
        for layer in layers where layer.id >= 0 && layer.id < 256 {
            let rgba = layer.rgba
            let visible: Float = visibleLayerIDs.contains(layer.id) ? 1.0 : 0.0
            table[layer.id] = SIMD4<Float>(rgba.x, rgba.y, rgba.z, visible)
        }
        return table
    }

    /// OverviewView colour table: rgb = layer colour, a = raymarch opacity (0 if hidden).
    static func opacityTable(layers: [CaseLayer], visibleLayerIDs: Set<Int>) -> [SIMD4<Float>] {
        var table = [SIMD4<Float>](repeating: SIMD4<Float>(0, 0, 0, 0), count: 256)
        for layer in layers where layer.id >= 0 && layer.id < 256 {
            guard visibleLayerIDs.contains(layer.id) else { continue }
            let rgba = layer.rgba
            let opacity = groupOpacity(layer.group)
            table[layer.id] = SIMD4<Float>(rgba.x, rgba.y, rgba.z, opacity)
        }
        return table
    }

    /// mm -> texture-coordinate scale/offset so that `tc = mm * scale + offset`,
    /// matching `CaseBundle.textureCoord(forMM:)` exactly.
    static func textureScaleOffset(bundle: CaseBundle) -> (scale: SIMD3<Float>, offset: SIMD3<Float>) {
        let dims = SIMD3<Float>(Float(bundle.meta.dims[0]), Float(bundle.meta.dims[1]), Float(bundle.meta.dims[2]))
        let spacing = SIMD3<Float>(Float(bundle.meta.spacingMM[0]), Float(bundle.meta.spacingMM[1]), Float(bundle.meta.spacingMM[2]))
        let origin = SIMD3<Float>(Float(bundle.meta.originMM[0]), Float(bundle.meta.originMM[1]), Float(bundle.meta.originMM[2]))
        let scale = SIMD3<Float>(1, 1, 1) / (spacing * dims)
        let offset = -origin / (spacing * dims) + SIMD3<Float>(0.5, 0.5, 0.5) / dims
        return (scale, offset)
    }

    /// Half-extent (mm) of the volume's AABB projected onto a (unit) direction — the support
    /// function of a box, used to fit the volume to the view while preserving aspect.
    static func projectedHalfExtent(extentMM: SIMD3<Float>, direction: SIMD3<Float>) -> Float {
        let half = extentMM * 0.5
        return half.x * abs(direction.x) + half.y * abs(direction.y) + half.z * abs(direction.z)
    }
}
