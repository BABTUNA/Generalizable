import CoreGraphics
import simd

/// An oriented rectangle through the body.
/// Follows 3D Slicer's SliceToRAS / VTK vtkImageReslice ResliceAxes layout: columns [u, v, n, origin]
/// (Slicer Libs/MRML/Core/vtkMRMLSliceNode.cxx, SetSliceToRASByNTP and UpdateMatrices).
struct CutPlane: Equatable {
  /// Centre of the field of view in mm.
  var center: SIMD3<Float>
  /// Screen right, unit length.
  var u: SIMD3<Float>
  /// Screen up, unit length.
  var v: SIMD3<Float>
  /// Field of view (width, height) in mm.
  var fovMM: SIMD2<Float>

  /// Normal, kept right-handed as Slicer requires (n = u × v).
  var n: SIMD3<Float> { simd_normalize(simd_cross(u, v)) }

  init(center: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, fovMM: SIMD2<Float>) {
    self.center = center
    self.u = simd_normalize(u)
    self.v = simd_normalize(v)
    self.fovMM = fovMM
  }

  /// The hinge cut: contains the patient left–right line through `pivot` and tilts from the axial plane
  /// (0°, seen from the feet like a radiology viewer) to the coronal plane (90°, seen from the front).
  /// Rotation about a fixed pivot is Slicer's vtkMRMLSliceIntersectionWidget::Rotate, T(c)·R·T(−c),
  /// applied to the basis only so the pivot never leaves the plane.
  static func hinged(pivot: SIMD3<Float>, tiltDegrees: Float, offsetMM: Float = 0, fovMM: SIMD2<Float>) -> CutPlane {
    let t = tiltDegrees * .pi / 180
    let u = SIMD3<Float>(1, 0, 0)
    let v = SIMD3<Float>(0, -cos(t), sin(t))
    var plane = CutPlane(center: pivot, u: u, v: v, fovMM: fovMM)
    plane.center += plane.n * offsetMM
    return plane
  }

  /// Side view through `x`, anterior on the left of the screen, superior at the top.
  static func sagittal(x: Float, center: SIMD3<Float>, fovMM: SIMD2<Float>) -> CutPlane {
    CutPlane(center: SIMD3(x, center.y, center.z), u: SIMD3(0, 1, 0), v: SIMD3(0, 0, 1), fovMM: fovMM)
  }

  /// Front view through `y`, patient right on the left of the screen, superior at the top.
  static func coronal(y: Float, center: SIMD3<Float>, fovMM: SIMD2<Float>) -> CutPlane {
    CutPlane(center: SIMD3(center.x, y, center.z), u: SIMD3(1, 0, 0), v: SIMD3(0, 0, 1), fovMM: fovMM)
  }

  /// World position of a pixel centre (Cornerstone3D PlanarCPUVolumeSampler: xStart = −w/2 + step/2, rows go down).
  func topLeftMM(width: Int, height: Int) -> SIMD3<Float> {
    let sx = fovMM.x / Float(width)
    let sy = fovMM.y / Float(height)
    return center + u * (-fovMM.x / 2 + sx / 2) + v * (fovMM.y / 2 - sy / 2)
  }

  func columnStepMM(width: Int) -> SIMD3<Float> { u * (fovMM.x / Float(width)) }
  func rowStepMM(height: Int) -> SIMD3<Float> { -v * (fovMM.y / Float(height)) }

  /// Projects a world point into this plane's image, dropping the normal component (Slicer rasToXY).
  func imagePoint(of world: SIMD3<Float>, imageSize: CGSize) -> CGPoint {
    let d = world - center
    let x = (simd_dot(d, u) / fovMM.x + 0.5) * Float(imageSize.width)
    let y = (0.5 - simd_dot(d, v) / fovMM.y) * Float(imageSize.height)
    return CGPoint(x: CGFloat(x), y: CGFloat(y))
  }

  /// Signed distance from the plane along its normal.
  func distance(to world: SIMD3<Float>) -> Float { simd_dot(world - center, n) }

  /// How `other` crosses this plane's image, as a segment in image coordinates.
  /// Slicer vtkMRMLSliceIntersectionRepresentation2D::IntersectWithFinitePlane; parallel planes are skipped
  /// like Cornerstone3D ReferenceLinesTool's isParallel early return.
  func intersectionSegment(with other: CutPlane, imageSize: CGSize) -> (CGPoint, CGPoint)? {
    if abs(simd_dot(n, other.n)) > 1 - 1e-5 { return nil }
    let hu = other.u * other.fovMM.x / 2
    let hv = other.v * other.fovMM.y / 2
    let c = other.center
    let o = c - hu - hv, px = c + hu - hv, py = c - hu + hv, pxy = c + hu + hv
    var hits: [SIMD3<Float>] = []
    for (a, b) in [(o, px), (o, py), (pxy, py), (pxy, px)] {
      let den = simd_dot(n, b - a)
      if abs(den) < 1e-6 { continue }
      let t = simd_dot(n, center - a) / den
      if t >= 0, t <= 1 {
        hits.append(a + t * (b - a))
        if hits.count == 2 { break }
      }
    }
    guard hits.count == 2 else { return nil }
    return (imagePoint(of: hits[0], imageSize: imageSize), imagePoint(of: hits[1], imageSize: imageSize))
  }
}
