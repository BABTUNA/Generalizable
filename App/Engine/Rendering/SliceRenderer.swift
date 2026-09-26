import CoreGraphics
import Foundation
import simd

/// CPU oblique reslice of the analytic phantom into an RGBA8 image.
/// Stepping follows VTK vtkImageResliceExecute (origin + row·yAxis + col·xAxis, Imaging/Core/vtkImageReslice.cxx)
/// and the pixel-centre convention of Cornerstone3D's PlanarCPUVolumeSampler. Rows are rendered in parallel
/// with DispatchQueue.concurrentPerform. Evaluating the shapes per pixel (ODL's "3D phantom as a slice")
/// keeps a 9 mm kidney stone crisp at any tilt instead of smearing it through a coarse voxel grid.
enum SliceRenderer {
  static func render(plane: CutPlane, width: Int, height: Int, options: RenderOptions) -> CGImage? {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let topLeft = plane.topLeftMM(width: width, height: height)
    let dx = plane.columnStepMM(width: width)
    let dy = plane.rowStepMM(height: height)
    let hidden = options.hiddenLayers
    let mode = options.mode
    let preset = options.windowPreset

    pixels.withUnsafeMutableBufferPointer { buffer in
      let base = buffer.baseAddress!
      DispatchQueue.concurrentPerform(iterations: height) { row in
        var p = topLeft + Float(row) * dy
        var o = row * width * 4
        for _ in 0..<width {
          let rgba = shade(p, hidden: hidden, mode: mode, preset: preset)
          base[o] = rgba.x
          base[o + 1] = rgba.y
          base[o + 2] = rgba.z
          base[o + 3] = rgba.w
          o += 4
          p += dx
        }
      }
    }

    let data = Data(pixels) as CFData
    guard let provider = CGDataProvider(data: data) else { return nil }
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    )
  }

  @inline(__always)
  private static func shade(_ p: SIMD3<Float>, hidden: Set<TissueLayer>, mode: RenderOptions.Mode, preset: WindowPreset) -> SIMD4<UInt8> {
    guard PatientSpace.contains(p) else { return SIMD4(0, 0, 0, 0) }
    let q = SIMD3<Int32>(Int32((p.x).rounded(.down)), Int32((p.y).rounded(.down)), Int32((p.z).rounded(.down)))
    let noise = NoiseHash.gaussian(x: q.x, y: q.y, z: q.z)

    switch mode {
    case .ct:
      let label = PatientPhantom.label(atMM: p)
      let hu = label.huMean + label.huSigma * noise
      let g = UInt8(preset.normalized(hu) * 255)
      return SIMD4(g, g, g, 255)
    case .layers:
      let label = PatientPhantom.label(atMM: p, hidden: hidden)
      if label == .air { return SIMD4(0, 0, 0, 0) }
      if label == .trachea { return SIMD4(0, 0, 0, 0) }
      let c = label.color
      // A little of the CT grain keeps the colour fields from looking like flat vector art.
      let shadeFactor: Float = label.isFinding ? 1 : 0.9 + 0.06 * max(min(noise, 1.5), -1.5)
      let r = UInt8(min(Float(c.x) * shadeFactor, 255))
      let g = UInt8(min(Float(c.y) * shadeFactor, 255))
      let b = UInt8(min(Float(c.z) * shadeFactor, 255))
      return SIMD4(r, g, b, 255)
    }
  }
}
