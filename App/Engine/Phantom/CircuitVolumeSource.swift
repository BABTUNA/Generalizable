import simd

/// An exploded, four-board circuit. Shared channels are renamed by the case UI:
/// muscle = substrate, bone = contacts/supports, organs = silicon, blood = traces.
/// These dimensions match VolumeSceneView's enlarged teaching geometry.
/// Analytic cuboids use TomoPhantom's Phantom3DLibrary.dat cuboid convention;
/// cylindrical vias use ODL's normalized primitive-distance containment test.
struct CircuitVolumeSource: VolumeSource {
  static var centerMM: SIMD3<Float> { PatientSpace.centerMM }
  static let boardCentersZ: [Float] = [112, 220, 328, 436]

  func label(atMM point: SIMD3<Float>) -> TissueLabel {
    guard PatientSpace.contains(point) else { return .air }
    guard abs(point.x) <= 150, abs(point.y) <= 115,
          point.z >= 96, point.z <= 454 else { return .air }

    // The four corner support posts are vertical cylinders through the exploded stack.
    if point.z <= 451 {
      let x = abs(point.x) - 135
      let y = abs(point.y) - 98
      if x * x + y * y <= 3.5 * 3.5 { return .boneCortical }
    }

    for boardZ in Self.boardCentersZ {
      let h = point.z - boardZ
      guard h >= -4.5, h <= 18 else { continue }
      if abs(point.x) <= 31, abs(point.y) <= 24.5, abs(h - 11) <= 6 {
        return .liver
      }
      if abs(point.x) <= 14.5, abs(point.y) <= 12.5, abs(h - 17.5) <= 0.5 {
        return .liver
      }
      for column in 0..<5 {
        let x = Float(column * 49 - 98)
        let y: Float = column.isMultiple(of: 2) ? -63 : 63
        if abs(point.x - x) <= 15.5, abs(point.y - y) <= 14, abs(h - 11) <= 6.5 {
          return .liver
        }
        if abs(h - 7) <= 1.25 {
          for side: Float in [-1, 1] {
            for pin in 0..<5 {
              let pinX = x - 12 + Float(pin * 6)
              if abs(point.x - pinX) <= 1.5, abs(point.y - (y + side * 17)) <= 4 {
                return .boneCortical
              }
            }
          }
        }
        let traceY = -Float(column * 12 - 24)
        let dz = h - 5
        let dx = point.x - x
        let dy = point.y - traceY
        if dz * dz + dx * dx <= 0.75 * 0.75,
           point.y >= min(y, traceY), point.y <= max(y, traceY) {
          return .aorta
        }
        if dz * dz + dy * dy <= 0.75 * 0.75, abs(point.x) <= abs(x) {
          return .aorta
        }
      }
      if abs(h) <= 4.5 { return .muscle }
    }
    return .air
  }

  /// Illustrative density-style contrast; these values are not a physical CT calibration.
  func hu(atMM point: SIMD3<Float>) -> Float {
    switch label(atMM: point) {
    case .aorta: 350
    case .boneCortical: 600
    case .liver: 100
    case .muscle: -20
    default: -1000
    }
  }

  func rgba(for label: TissueLabel) -> SIMD4<UInt8> {
    switch label {
    case .muscle: SIMD4(32, 133, 117, 255)
    case .boneCortical: SIMD4(235, 175, 88, 255)
    case .liver: SIMD4(142, 142, 246, 255)
    case .aorta: SIMD4(100, 239, 231, 255)
    default: SIMD4(0, 0, 0, 0)
    }
  }

  static func displayName(for layer: TissueLayer) -> String {
    switch layer {
    case .muscle: "Substrate"
    case .bone: "Contacts"
    case .organs: "Silicon"
    case .blood: "Traces"
    case .skin, .fat, .lungs: "Air"
    }
  }
}
