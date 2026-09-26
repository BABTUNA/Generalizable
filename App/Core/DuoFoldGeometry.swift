// DuoFoldGeometry.swift
// DEMO ONLY. Physical geometry of a partially folded iPhone Duo in table pose, used so the
// slice shown on the upper display is the *physical* plane of that display ("a window into
// the body lying on the table") without stretching as the lid moves. See PRD addendum A10.
//
// Hinge API facts (iOS 27.1, see A10): SwiftUI `.onHingeChange` gives `DeviceHinge.angle` as a
// SwiftUI `Angle`; UIKit `UIHinge.angle` is a CGFloat in RADIANS. Apple does not document the
// range. We assume the opening angle convention (0 = closed, pi = flat); `HingeConvention`
// makes that one switch if Duo testing shows otherwise.
//
// World frame for table pose (matches the case's RAS frame once the case is placed):
//   - lower display lies flat on the table, facing up (+z), hinge line along x at y = 0,
//     lower display extends toward -y (toward the viewer).
//   - upper display rises from the hinge line at elevation e = 180° - opening angle.

import Foundation
import simd

enum HingeConvention {
    /// Opening angle: 0 = closed, 180° = flat. The assumption used until Duo hardware confirms it.
    case openingAngle
    /// Deflection from flat: 0 = flat, 180° = closed.
    case deflectionFromFlat

    /// Converts a raw API angle in radians (UIKit `UIHinge.angle`, or `Angle.radians`) to the
    /// opening angle in degrees that `HingeMapping` expects.
    func openingDegrees(fromRadians r: Double) -> Double {
        let deg = r * 180 / .pi
        switch self {
        case .openingAngle: return deg
        case .deflectionFromFlat: return 180 - deg
        }
    }
}

struct DuoFoldGeometry {
    /// Opening angle in degrees (180 = flat), clamped to the A2 working range 90...180.
    var openingDegrees: Double
    /// Display density in points per millimetre (160 pt/in ≈ 6.3 pt/mm on iPhone-class panels;
    /// set from the real device when known). Keeps the on-screen scale physical and isotropic.
    var pointsPerMM: Double = 160.0 / 25.4
    /// Viewer's eye, in mm, in the table frame. Default: seated presenter/audience about 450 mm
    /// in front of the hinge and 350 mm above the table.
    var eyeMM: SIMD3<Double> = [0, -450, 350]

    init(openingDegrees: Double, pointsPerMM: Double = 160.0 / 25.4) {
        self.openingDegrees = min(max(openingDegrees, 90), 180)
        self.pointsPerMM = pointsPerMM
    }

    /// Upper display elevation above the table, in degrees. Equals the A2 cut tilt.
    var elevationDegrees: Double { 180 - openingDegrees }
    private var e: Double { elevationDegrees * .pi / 180 }

    /// Upper display frame in the table frame: `right` along the hinge, `up` from the hinge
    /// toward the display's top edge, `normal` out of the glass toward the viewer.
    var upperRight: SIMD3<Double> { [1, 0, 0] }
    var upperUp: SIMD3<Double> { [0, cos(e), sin(e)] }
    var upperNormal: SIMD3<Double> { simd_cross(upperRight, upperUp) } // (0, -sin e, cos e)

    /// Point on the upper display, `x` points right of centre and `y` points above the hinge
    /// line, mapped to mm in the table frame. This is the anatomy the display "cuts through".
    func tableMM(upperPoint x: Double, _ y: Double) -> SIMD3<Double> {
        upperRight * (x / pointsPerMM) + upperUp * (y / pointsPerMM)
    }

    /// Physical scale that makes 1 mm of anatomy span the same length on glass at every hinge
    /// angle, so the slice doesn't zoom or stretch while folding. `zoom` > 1 magnifies.
    func mmPerPoint(zoom: Double = 1) -> Double { 1 / (pointsPerMM * zoom) }

    /// Foreshortening seen from `eyeMM` at the centre of the upper display, whose height is `heightPts`:
    /// the vertical compression ratio (1 = viewed head-on). The UI can show it, or stretch the
    /// slice vertically by 1/ratio to pre-compensate (keystone), which is off by default.
    func upperForeshortening(heightPts: Double) -> Double {
        let centre = tableMM(upperPoint: 0, heightPts / 2)
        let view = simd_normalize(eyeMM - centre)
        return max(0.05, abs(simd_dot(view, upperNormal)))
    }

    /// Maps the physical upper display onto the case's cut plane. The pivot (finding or
    /// centre) sits at the hinge line, `tilt` = elevation, and screen `up` = `CutPlane.vAxis`.
    /// So a point `y` points above the hinge maps to `pivot + vAxis * y * mmPerPoint`, the
    /// slice row at the hinge is the pivot row, and the image never shears as the lid moves.
    func cutPlane(pivotMM: SIMD3<Float>, rotationDegrees: Double = 0) -> CutPlane {
        CutPlane(pivotMM: pivotMM, tiltDegrees: elevationDegrees,
                 rotationDegrees: rotationDegrees, sliceOffsetMM: 0)
    }
}
