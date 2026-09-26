import simd

/// Adapter for ODL-style analytic anatomy in PatientPhantom. Intensities follow SynthSeg's
/// SampleConditionalGMM (ext/lab2im/layers.py); deterministic 1 mm noise is fixed in world space.
struct AnalyticPhantomSource: VolumeSource {
  func label(atMM point: SIMD3<Float>) -> TissueLabel {
    guard PatientSpace.contains(point) else { return .air }
    return PatientPhantom.label(atMM: point)
  }

  func hu(atMM point: SIMD3<Float>) -> Float {
    let tissue = label(atMM: point)
    guard tissue != .air else { return -1000 }
    let noise = NoiseHash.gaussian(
      x: Int32(point.x.rounded(.down)),
      y: Int32(point.y.rounded(.down)),
      z: Int32(point.z.rounded(.down))
    )
    return tissue.huMean + tissue.huSigma * noise
  }
}
