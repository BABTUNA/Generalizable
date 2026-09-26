import simd

/// A read-only 3D label field. All sources use the same millimetre coordinate space so the
/// VTK-style reslice can operate on anatomy, a star, or a circuit without changing geometry.
protocol VolumeSource: Sendable {
  var extentMM: SIMD3<Float> { get }
  var originMM: SIMD3<Float> { get }
  func label(atMM point: SIMD3<Float>) -> TissueLabel
  func hu(atMM point: SIMD3<Float>) -> Float
  func rgba(for label: TissueLabel) -> SIMD4<UInt8>
}

extension VolumeSource {
  var extentMM: SIMD3<Float> { PatientSpace.extentMM }
  var originMM: SIMD3<Float> { PatientSpace.originMM }
  func rgba(for label: TissueLabel) -> SIMD4<UInt8> { label.color }
}
