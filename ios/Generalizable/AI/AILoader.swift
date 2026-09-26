// AILoader — reads Cases/<id>/ai.json (+ optional ai_heatmap.nii.gz) into AIResult.
// Heatmap decodes through VolumeLoader.decode(kind: .label), so it is reoriented exactly like
// the organ labels. Colormap: NiiVue (github.com/niivue/niivue) packages/niivue/src/colortables.ts
// `makeLut` (piecewise-linear R/G/B between intensity indices I) with the control points of
// packages/niivue/src/cmaps/inferno.json; overlay blend as in shader-srcs.ts `kFragSliceHead`
// (`mix(background, overlay.rgb, overlay.a * opacity)`).
import Foundation
import simd

enum AILoader {
    private struct DTO: Decodable {
        var model: String?; var license: String?; var disclaimer: String?
        var headlineClass: String?; var series: [AIResult.ClassProb]?
        var sliceProbability: [Float]?; var diceVsExpert: Float?
        var runtimeSeconds: Double?; var device: String?
    }

    /// nil when the folder has no ai.json or it cannot be decoded.
    static func load(folder: URL, geometry g: VolumeGeometry) -> (AIResult, runtime: Double?, device: String?)? {
        let json = folder.appendingPathComponent("ai.json")
        guard let data = try? Data(contentsOf: json),
              let d = try? JSONDecoder().decode(DTO.self, from: data) else { return nil }
        var heat: LabelVolume?
        let hURL = folder.appendingPathComponent("ai_heatmap.nii.gz")
        if FileManager.default.fileExists(atPath: hURL.path),
           let dec = try? VolumeLoader.decode(hURL, kind: .label),
           dec.geometry.dims == g.dims, case .label(let v) = dec.data {
            heat = LabelVolume(geometry: g, voxels: v)
        }
        let r = AIResult(model: d.model ?? "Unknown model", license: d.license ?? "",
                         disclaimer: d.disclaimer ?? "Research model, not a medical device.",
                         series: d.series ?? [], sliceProbability: d.sliceProbability ?? [],
                         headlineClass: d.headlineClass ?? (d.series?.max { $0.probability < $1.probability }?.name ?? ""),
                         heatmap: heat, diceVsExpert: d.diceVsExpert)
        return (r, d.runtimeSeconds, d.device)
    }

    /// NiiVue inferno.json control points → 256-entry RGBA LUT (makeLut interpolation).
    static let infernoLUT: [SIMD4<UInt8>] = {
        let R: [Float] = [0, 120, 237, 240], G: [Float] = [0, 28, 105, 249], B: [Float] = [4, 109, 37, 33]
        let I = [0, 64, 192, 255]
        var lut = [SIMD4<UInt8>](repeating: .zero, count: 256)
        for i in 0..<3 {
            for j in I[i]...I[i + 1] {
                let f = Float(j - I[i]) / Float(I[i + 1] - I[i])
                lut[j] = SIMD4(UInt8(R[i] + f * (R[i+1] - R[i])), UInt8(G[i] + f * (G[i+1] - G[i])),
                               UInt8(B[i] + f * (B[i+1] - B[i])), 255)
            }
        }
        return lut
    }()
}

extension AIResult {
    var headlineProbability: Float? {
        series.first { $0.name.lowercased() == headlineClass.lowercased() }?.probability
    }
    /// Probability-weighted centroid (x, y) of the heatmap on axial slice z.
    func heatCentroid(z: Int) -> SIMD2<Float>? {
        guard let h = heatmap else { return nil }
        let d = h.geometry.dims, nx = Int(d.x), ny = Int(d.y)
        guard z >= 0, z < Int(d.z) else { return nil }
        var sx: Float = 0, sy: Float = 0, sw: Float = 0
        let base = z * nx * ny
        h.voxels.withUnsafeBufferPointer { b in
            for y in 0..<ny { for x in 0..<nx {
                let w = Float(b[base + x + y * nx]); if w > 38 { sx += w * Float(x); sy += w * Float(y); sw += w }
            } }
        }
        return sw > 0 ? SIMD2(sx / sw, sy / sw) : nil
    }
}
