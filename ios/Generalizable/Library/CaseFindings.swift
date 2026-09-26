// Findings bundled with a case (Cases/<id>/findings.json), e.g. the CQ500 subdural bleed.
// Schema is the one Generalizable's data pipeline writes: id, label_id, title, center_mm
// (RAS world mm), radius_mm, explanation.
import Foundation
import simd

struct CaseFinding: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var labelID: Int?
    var title: String
    var centerMM: [Double]
    var radiusMM: Double?
    var explanation: String?

    enum CodingKeys: String, CodingKey {
        case id, title, explanation
        case labelID = "label_id", centerMM = "center_mm", radiusMM = "radius_mm"
    }

    /// World (RAS mm) → canonical voxel via the inverse of the geometry affine.
    func voxel(in g: VolumeGeometry) -> SIMD3<Float>? {
        guard centerMM.count == 3 else { return nil }
        let w = SIMD4<Float>(Float(centerMM[0]), Float(centerMM[1]), Float(centerMM[2]), 1)
        let v = g.affine.inverse * w
        let p = SIMD3<Float>(v.x, v.y, v.z).rounded(.toNearestOrAwayFromZero)
        guard p.x.isFinite, p.y.isFinite, p.z.isFinite else { return nil }
        return g.clamp(p)
    }
}

enum CaseFindings {
    static func load(dir: URL) -> [CaseFinding]? {
        guard let d = try? Data(contentsOf: dir.appendingPathComponent("findings.json")) else { return nil }
        let list = try? JSONDecoder().decode([CaseFinding].self, from: d)
        return (list?.isEmpty ?? true) ? nil : list
    }
    static func load(for info: CaseInfo) -> [CaseFinding]? {
        guard let ct = info.ctURL, ct.isFileURL else { return nil }
        return load(dir: ct.deletingLastPathComponent())
    }
}
