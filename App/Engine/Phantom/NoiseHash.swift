import Foundation

/// Deterministic Gaussian noise from an integer position, so the CT grain stays fixed in 3D as the cut tilts.
/// The label → intensity step follows SynthSeg's SampleConditionalGMM (ext/lab2im/layers.py):
/// value = mean[label] + std[label] · N(0,1).
enum NoiseHash {
  @inline(__always)
  static func hash(_ x: UInt32) -> UInt32 {
    // PCG output permutation (O'Neill, pcg-random.org reference implementation).
    let state = x &* 747_796_405 &+ 2_891_336_453
    let word = ((state >> ((state >> 28) &+ 4)) ^ state) &* 277_803_737
    return (word >> 22) ^ word
  }

  @inline(__always)
  static func gaussian(x: Int32, y: Int32, z: Int32) -> Float {
    let h1 = hash(UInt32(bitPattern: x) &* 73_856_093 ^ UInt32(bitPattern: y) &* 19_349_663 ^ UInt32(bitPattern: z) &* 83_492_791)
    let h2 = hash(h1 ^ 0x9E37_79B9)
    let u1 = max(Float(h1) / Float(UInt32.max), 1e-7)
    let u2 = Float(h2) / Float(UInt32.max)
    return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
  }
}
