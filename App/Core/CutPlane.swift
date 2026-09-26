// CutPlane.swift
// Non-visual Swift only (Foundation / simd / Metal). No SwiftUI or UIKit.
//
// Cut-plane geometry (PRD addendum A1) and the hinge-to-tilt mapping (A2/A3).
//
// Geometry convention (A1/A4), all in RAS mm:
//   - tilt 0°  -> axial plane viewed from the feet (normal -z), anterior up.
//   - tilt rotates the plane about the case's left-right axis (+x). uAxis (+x
//     at tilt 0) stays fixed under tilt, since it IS the tilt axis.
//   - rotation rotates the (already-tilted) frame about the vertical axis (+z).
//   - tilt 90°, rotation 0° -> coronal plane viewed from the front (normal +y), head up.
//   - radiological convention: patient right (RAS +x) on the viewer's left.

import Foundation
import simd

// MARK: - CutPlane

struct CutPlane: Equatable {
    var pivotMM: SIMD3<Float>
    var tiltDegrees: Double
    var rotationDegrees: Double
    var sliceOffsetMM: Float

    init(pivotMM: SIMD3<Float> = .zero,
         tiltDegrees: Double = 0,
         rotationDegrees: Double = 0,
         sliceOffsetMM: Float = 0) {
        self.pivotMM = pivotMM
        self.tiltDegrees = tiltDegrees
        self.rotationDegrees = rotationDegrees
        self.sliceOffsetMM = sliceOffsetMM
    }

    private static func rotateX(_ v: SIMD3<Float>, radians: Float) -> SIMD3<Float> {
        let c = cos(radians), s = sin(radians)
        return SIMD3<Float>(v.x, v.y * c - v.z * s, v.y * s + v.z * c)
    }

    private static func rotateZ(_ v: SIMD3<Float>, radians: Float) -> SIMD3<Float> {
        let c = cos(radians), s = sin(radians)
        return SIMD3<Float>(v.x * c - v.y * s, v.x * s + v.y * c, v.z)
    }

    private var tiltRadians: Float { Float(tiltDegrees) * .pi / 180 }
    private var rotationRadians: Float { Float(rotationDegrees) * .pi / 180 }

    /// Plane normal = uAxis × vAxis, pointing toward the viewer: -z (from the feet) at tilt 0,
    /// +y (from the front, anterior) at tilt 90. Radiological convention: patient's right
    /// (RAS +x) appears on the viewer's left.
    var normal: SIMD3<Float> {
        simd_normalize(simd_cross(uAxis, vAxis))
    }

    /// In-plane screen-right axis. RAS +x is the patient's RIGHT, so screen-right is -x
    /// (radiological convention). This is the tilt axis, so only the rotation control turns it.
    var uAxis: SIMD3<Float> {
        let tilted = Self.rotateX(SIMD3<Float>(-1, 0, 0), radians: tiltRadians)
        return Self.rotateZ(tilted, radians: rotationRadians)
    }

    /// In-plane axis orthogonal to uAxis and normal (completes the right-handed frame).
    var vAxis: SIMD3<Float> {
        let tilted = Self.rotateX(SIMD3<Float>(0, 1, 0), radians: tiltRadians)
        return Self.rotateZ(tilted, radians: rotationRadians)
    }

    /// Point on the plane's own normal offset from the pivot (A1: the slice control moves along this).
    var originMM: SIMD3<Float> {
        pivotMM + normal * sliceOffsetMM
    }

    /// A point on the plane, in mm, at in-plane coordinates (u, v) measured in mm along uAxis/vAxis.
    func point(u: Float, v: Float) -> SIMD3<Float> {
        originMM + uAxis * u + vAxis * v
    }

    /// A1: selecting a finding sets the pivot to its anchor and resets the slice offset to 0.
    /// Tilt and rotation are left as they are.
    mutating func select(_ f: CaseFinding) {
        pivotMM = f.center
        sliceOffsetMM = 0
    }

    /// A1: cut-line drag moves the pivot within the overview's plane.
    mutating func dragPivot(byMM d: SIMD3<Float>) {
        pivotMM += d
    }
}

// MARK: - Hinge mapping (A2)

enum HingeMapping {
    /// tilt = 180 - hingeAngle, with the hinge angle clamped to 90...180 first
    /// (below 90 the tilt is held at 90, per A2).
    static func tilt(forHingeAngle a: Double) -> Double {
        let clamped = min(max(a, 90), 180)
        return 180 - clamped
    }
}

/// Light exponential smoothing so hinge jitter doesn't make the slice flicker,
/// while keeping the tilt visibly continuous as the lid moves (A2).
struct HingeSmoother {
    var alpha: Double = 0.35
    private var smoothed: Double?

    mutating func update(_ tilt: Double) -> Double {
        if let previous = smoothed {
            let next = alpha * tilt + (1 - alpha) * previous
            smoothed = next
            return next
        } else {
            smoothed = tilt
            return tilt
        }
    }
}

// MARK: - Hinge source (A3)

/// One adapter surface for all hinge input; it only ever outputs a tilt-relevant angle.
/// Without the Duo runtime, no source delivers a value and the manual control remains
/// the only way to set tilt (A3).
protocol HingeAngleSource: AnyObject {
    var onAngle: ((Double) -> Void)? { get set }
    func start()
    func stop()
}

/// A3 stub: never reports an angle. The real Duo-backed source is built later in Bitrig
/// behind `#available` once the iOS 27.1 SDK is available.
final class ManualOnlyHingeSource: HingeAngleSource {
    var onAngle: ((Double) -> Void)?
    func start() {}
    func stop() {}
}
