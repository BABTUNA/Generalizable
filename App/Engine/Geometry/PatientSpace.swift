import simd

/// World (mm) conventions for every scan in the app.
/// DICOM/ITK LPS order, as described in 3D Slicer's coordinate_systems guide:
/// +x = patient left, +y = posterior, +z = superior.
enum PatientSpace {
  static let extentMM = SIMD3<Float>(384, 384, 576)
  static let originMM = SIMD3<Float>(-192, -192, 0)
  static var centerMM: SIMD3<Float> { SIMD3(0, 0, extentMM.z / 2) }

  static func contains(_ p: SIMD3<Float>) -> Bool {
    let local = p - originMM
    return all(local .>= SIMD3<Float>(repeating: 0)) && all(local .<= extentMM)
  }
}
