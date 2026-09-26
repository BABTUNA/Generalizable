import simd

/// A stylized, concentric solar interior. The shared label IDs are material channels here,
/// not anatomy: skin = corona, fat = photosphere, muscle = convection zone,
/// bone = radiative zone, blood = core. This model illustrates slicing, not stellar scale.
/// Uses the sphere subset of ODL src/odl/core/phantom/geometric.py's ellipsoid inside test.
struct SolarVolumeSource: VolumeSource {
  static var centerMM: SIMD3<Float> { PatientSpace.centerMM }

  func label(atMM point: SIMD3<Float>) -> TissueLabel {
    guard PatientSpace.contains(point) else { return .air }
    let d = point - Self.centerMM
    let r2 = simd_length_squared(d)
    if r2 <= 42 * 42 { return .aorta }
    if r2 <= 92 * 92 { return .boneCortical }
    if r2 <= 135 * 135 { return .muscle }
    if r2 <= 151 * 151 { return .fat }
    if r2 <= 165 * 165 { return .skin }
    return .air
  }

  /// A normalized density-style scalar, used by the same grayscale display path as CT.
  /// Values are illustrative and are not Hounsfield units for a real star.
  func hu(atMM point: SIMD3<Float>) -> Float {
    switch label(atMM: point) {
    case .aorta: 350
    case .boneCortical: 130
    case .muscle: 20
    case .fat: -50
    case .skin: -100
    default: -1000
    }
  }

  func rgba(for label: TissueLabel) -> SIMD4<UInt8> {
    switch label {
    case .aorta: SIMD4(255, 251, 203, 255)
    case .boneCortical: SIMD4(255, 205, 78, 255)
    case .muscle: SIMD4(251, 113, 45, 255)
    case .fat: SIMD4(246, 57, 83, 255)
    case .skin: SIMD4(121, 68, 184, 255)
    default: SIMD4(0, 0, 0, 0)
    }
  }

  static func displayName(for layer: TissueLayer) -> String {
    switch layer {
    case .skin: "Corona"
    case .fat: "Photosphere"
    case .muscle: "Convection"
    case .bone: "Radiative zone"
    case .blood: "Core"
    case .lungs, .organs: "Space"
    }
  }
}
