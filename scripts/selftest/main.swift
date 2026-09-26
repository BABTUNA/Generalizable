// DEMO ONLY. macOS self-test for App/Core: loads every bundle in App/Cases, uploads the Metal
// textures, and checks the loader against the byte layout (A4), the finding anchors, and the Duo fold math.
import Foundation
import Metal
import simd

var failures = 0
func check(_ ok: Bool, _ msg: String) { if !ok { failures += 1; print("FAIL:", msg) } }
func near(_ a: Double, _ b: Double, _ eps: Double = 1e-6) -> Bool { abs(a - b) < eps }

let casesDir = URL(fileURLWithPath: CommandLine.arguments[1])
let device = MTLCreateSystemDefaultDevice()!
for name in ["head", "body", "sun", "circuit"] {
    let dir = casesDir.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: dir.path) else { check(false, "\(name) missing"); continue }
    do {
        let t0 = Date()
        let b = try CaseBundle.load(directory: dir, name: name)
        let d = b.meta.dims
        check(b.ct.count == d[0] * d[1] * d[2] * 2 && b.labels.count == d[0] * d[1] * d[2], "\(name) sizes")
        let ids = Set(b.layers.map(\.id))
        var seen = Set<UInt8>()
        b.labels.withUnsafeBytes { raw in for v in raw.bindMemory(to: UInt8.self) { seen.insert(v) } }
        check(seen.subtracting([0]).allSatisfy { ids.contains(Int($0)) }, "\(name) label ids ⊆ layers.json")
        for f in b.findings {
            let c = f.center
            let ijk = SIMD3<Int>(Int(((c.x - Float(b.meta.originMM[0])) / Float(b.meta.spacingMM[0])).rounded()),
                                 Int(((c.y - Float(b.meta.originMM[1])) / Float(b.meta.spacingMM[1])).rounded()),
                                 Int(((c.z - Float(b.meta.originMM[2])) / Float(b.meta.spacingMM[2])).rounded()))
            check(Int(b.label(at: ijk)) == f.labelID, "\(name) finding '\(f.title)' lands on its label")
            let tc = b.textureCoord(forMM: c)
            check((0...1).contains(tc.x) && (0...1).contains(tc.y) && (0...1).contains(tc.z), "\(name) finding inside volume")
        }
        // Byte layout: the first voxel is byte 0 (x fastest); voxel (1,0,0) is bytes 2..3.
        let v1 = b.ct.withUnsafeBytes { $0.load(fromByteOffset: 2, as: Int16.self) }
        check(b.hu(at: [1, 0, 0]) == Int16(littleEndian: v1), "\(name) x-fastest HU layout")
        let (ct, lab) = try b.makeTextures(device: device)
        check(ct.width == d[0] && ct.height == d[1] && ct.depth == d[2] && ct.pixelFormat == .r16Snorm, "\(name) CT texture")
        check(lab.pixelFormat == .r8Uint && lab.depth == d[2], "\(name) label texture")
        print(String(format: "%-8@ OK dims %@ layers %d findings %d load+upload %.2fs", name, "\(d)", b.layers.count, b.findings.count, Date().timeIntervalSince(t0)))
    } catch { check(false, "\(name) load threw \(error)") }
}

// Duo fold geometry (A10).
let flat = DuoFoldGeometry(openingDegrees: 180), table = DuoFoldGeometry(openingDegrees: 120), upright = DuoFoldGeometry(openingDegrees: 90)
check(near(flat.elevationDegrees, 0) && near(table.elevationDegrees, 60) && near(upright.elevationDegrees, 90), "elevation = A2 tilt")
check(near(HingeMapping.tilt(forHingeAngle: 120), table.elevationDegrees), "fold elevation matches HingeMapping")
check(near(HingeConvention.openingAngle.openingDegrees(fromRadians: .pi), 180), "radians -> opening degrees")
check(near(HingeConvention.deflectionFromFlat.openingDegrees(fromRadians: 0), 180), "deflection convention")
// Isotropic, angle-independent scale: 100 pt up the glass is the same mm length at every angle.
for g in [flat, table, upright] { check(near(simd_length(g.tableMM(upperPoint: 0, 100)), 100 / g.pointsPerMM), "no stretch at \(g.openingDegrees)") }
// The upper display frame matches the cut plane frame: display `up` == CutPlane.vAxis, normal == CutPlane.normal.
for g in [flat, table, upright] {
    let cp = g.cutPlane(pivotMM: .zero)
    let up = SIMD3<Double>(Double(cp.vAxis.x), Double(cp.vAxis.y), Double(cp.vAxis.z))
    let n = SIMD3<Double>(Double(cp.normal.x), Double(cp.normal.y), Double(cp.normal.z))
    check(simd_length(up - g.upperUp) < 1e-5, "display up == vAxis at \(g.openingDegrees)")
    // The table-frame display normal faces the viewer (-y); the case normal must agree once the case lies with feet toward the viewer.
    check(abs(abs(simd_dot(n, g.upperNormal)) - 1) < 1e-5, "display normal ∥ cut normal at \(g.openingDegrees)")
}
check(table.upperForeshortening(heightPts: 400) > 0.3 && table.upperForeshortening(heightPts: 400) <= 1, "foreshortening range")
print(failures == 0 ? "SELFTEST OK" : "SELFTEST FAILED (\(failures))")
exit(failures == 0 ? 0 : 1)
