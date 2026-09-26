import simd

/// One analytic shape in the synthetic body. Row format follows ODL's `_ellipsoid_phantom_3d`
/// (src/odl/core/phantom/geometric.py) and TomoPhantom's `Object : ellipsoid` rows, in millimetres
/// with a material label and z limits like XCIST's .ppm phantoms.
struct PhantomPrimitive: Equatable {
  enum Kind: Equatable {
    case ellipsoid
    /// An elliptic cylinder along z. A shell thickness makes it a hollow ring (ribs).
    case ellipticCylinder(zRange: ClosedRange<Float>, shellThickness: Float?)
  }

  var kind: Kind
  var label: TissueLabel
  var center: SIMD3<Float>
  var halfAxes: SIMD3<Float>
  /// Optional periodic mask along z (ribs): inside only where (z − start) mod period < width.
  var zBand: SIMD2<Float>?

  var boundsMin: SIMD3<Float> {
    switch kind {
    case .ellipsoid: center - halfAxes
    case .ellipticCylinder(let z, _): SIMD3(center.x - halfAxes.x, center.y - halfAxes.y, z.lowerBound)
    }
  }

  var boundsMax: SIMD3<Float> {
    switch kind {
    case .ellipsoid: center + halfAxes
    case .ellipticCylinder(let z, _): SIMD3(center.x + halfAxes.x, center.y + halfAxes.y, z.upperBound)
    }
  }

  /// ODL's inside test: sum of squared normalised distances ≤ 1.
  @inline(__always)
  func contains(_ p: SIMD3<Float>) -> Bool {
    if any(p .< boundsMin) || any(p .> boundsMax) { return false }
    let d = p - center
    switch kind {
    case .ellipsoid:
      let q = d / halfAxes
      return simd_length_squared(q) <= 1
    case .ellipticCylinder(let z, let shell):
      let qx = d.x / halfAxes.x, qy = d.y / halfAxes.y
      guard qx * qx + qy * qy <= 1 else { return false }
      if let band = zBand {
        let phase = (p.z - z.lowerBound).truncatingRemainder(dividingBy: band.x)
        guard phase < band.y else { return false }
      }
      if let t = shell {
        let ix = d.x / (halfAxes.x - t), iy = d.y / (halfAxes.y - t)
        return ix * ix + iy * iy > 1
      }
      return true
    }
  }
}
