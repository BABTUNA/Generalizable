import simd

/// The synthetic patient. Primitive format copied from ODL / TomoPhantom / XCIST; the organ layout itself has no
/// open-source precedent (FORBILD's thorax pages are offline and XCAT is closed), so it is sized from anatomy,
/// as tabulated in docs/research-phantom.md §7. Paint order: soft shells → lungs → organs → vessels → bone → findings.
enum PatientPhantom {
  private static func cylinder(_ label: TissueLabel, x: Float, y: Float, a: Float, b: Float, z: ClosedRange<Float>, shell: Float? = nil, band: SIMD2<Float>? = nil) -> PhantomPrimitive {
    PhantomPrimitive(kind: .ellipticCylinder(zRange: z, shellThickness: shell), label: label, center: SIMD3(x, y, (z.lowerBound + z.upperBound) / 2), halfAxes: SIMD3(a, b, (z.upperBound - z.lowerBound) / 2), zBand: band)
  }

  private static func ellipsoid(_ label: TissueLabel, _ c: SIMD3<Float>, _ r: SIMD3<Float>) -> PhantomPrimitive {
    PhantomPrimitive(kind: .ellipsoid, label: label, center: c, halfAxes: r, zBand: nil)
  }

  static let noduleCenter = SIMD3<Float>(-75, -15, 500)
  static let aneurysmCenter = SIMD3<Float>(12, 20, 175)
  static let cystCenter = SIMD3<Float>(-80, -10, 280)
  static let stoneCenter = SIMD3<Float>(46, 50, 205)

  static let primitives: [PhantomPrimitive] = [
    cylinder(.skin, x: 0, y: 0, a: 165, b: 110, z: 0...576),
    cylinder(.fat, x: 0, y: 0, a: 162, b: 107, z: 0...576),
    cylinder(.muscle, x: 0, y: 0, a: 147, b: 92, z: 0...576),
    ellipsoid(.lungRight, SIMD3(-62, 8, 420), SIMD3(55, 60, 120)),
    ellipsoid(.lungLeft, SIMD3(62, 8, 420), SIMD3(52, 60, 118)),
    cylinder(.trachea, x: 0, y: -10, a: 9, b: 9, z: 470...576),
    ellipsoid(.heart, SIMD3(22, -22, 390), SIMD3(55, 45, 55)),
    ellipsoid(.liver, SIMD3(-55, 5, 270), SIMD3(85, 72, 80)),
    ellipsoid(.spleen, SIMD3(100, 38, 290), SIMD3(26, 40, 52)),
    ellipsoid(.kidneyRight, SIMD3(-62, 50, 195), SIMD3(28, 18, 55)),
    ellipsoid(.kidneyLeft, SIMD3(62, 50, 205), SIMD3(28, 18, 55)),
    cylinder(.aorta, x: 12, y: 20, a: 12.5, b: 12.5, z: 250...470),
    cylinder(.aorta, x: 12, y: 20, a: 10, b: 10, z: 130...250),
    cylinder(.aorta, x: -10, y: 28, a: 6, b: 6, z: 60...130),
    cylinder(.aorta, x: 34, y: 28, a: 6, b: 6, z: 60...130),
    cylinder(.boneCortical, x: 0, y: 0, a: 140, b: 86, z: 300...540, shell: 6, band: SIMD2(24, 9)),
    cylinder(.boneCortical, x: 0, y: -84, a: 15, b: 5, z: 340...500),
    cylinder(.boneCortical, x: 0, y: 64, a: 16, b: 22, z: 0...576),
    cylinder(.boneTrabecular, x: 0, y: 64, a: 13, b: 19, z: 0...576),
    cylinder(.spinalCanal, x: 0, y: 72, a: 6, b: 6, z: 0...576),
    ellipsoid(.boneCortical, SIMD3(-78, 25, 60), SIMD3(45, 25, 50)),
    ellipsoid(.boneTrabecular, SIMD3(-78, 25, 60), SIMD3(39, 19, 44)),
    ellipsoid(.boneCortical, SIMD3(78, 25, 60), SIMD3(45, 25, 50)),
    ellipsoid(.boneTrabecular, SIMD3(78, 25, 60), SIMD3(39, 19, 44)),
    ellipsoid(.aneurysmThrombus, aneurysmCenter, SIMD3(22, 22, 30)),
    ellipsoid(.aneurysmLumen, SIMD3(10, 18, 175), SIMD3(13, 13, 28)),
    ellipsoid(.noduleLung, noduleCenter, SIMD3(7, 7, 7)),
    ellipsoid(.cystLiver, cystCenter, SIMD3(12, 12, 12)),
    ellipsoid(.calculusKidney, stoneCenter, SIMD3(4.5, 4.5, 4.5)),
  ]

  /// Painter's algorithm: the last primitive containing `p` wins. Primitives whose layer is hidden are skipped,
  /// which is what "peeling" a layer means. Findings stay visible when `keepFindings` is true.
  @inline(__always)
  static func label(atMM p: SIMD3<Float>, hidden: Set<TissueLayer> = [], keepFindings: Bool = true) -> TissueLabel {
    var i = primitives.count - 1
    while i >= 0 {
      let prim = primitives[i]
      if prim.contains(p) {
        let label = prim.label
        if hidden.isEmpty { return label }
        if let layer = label.layer, hidden.contains(layer), !(keepFindings && label.isFinding) {
          i -= 1
          continue
        }
        return label
      }
      i -= 1
    }
    return .air
  }
}
