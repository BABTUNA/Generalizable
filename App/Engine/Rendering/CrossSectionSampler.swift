import CoreGraphics
import Foundation
import simd

/// The source-independent counterpart of SliceRenderer. Incremental pixel-centre stepping
/// follows VTK Imaging/Core/vtkImageReslice.cxx's vtkImageResliceExecute and Cornerstone3D's
/// PlanarCPUVolumeSampler. The returned image owns copied RGBA bytes, so a subsequent render
/// cannot mutate a frame that SwiftUI is still displaying. Run rendering away from the main actor.
final class CrossSectionSampler: @unchecked Sendable {
  let source: any VolumeSource
  let width: Int
  let height: Int

  init(source: any VolumeSource, width: Int = 256, height: Int = 256) {
    precondition(width > 0 && height > 0)
    self.source = source
    self.width = width
    self.height = height
  }

  func render(plane: CutPlane, options: RenderOptions) -> CGImage {
    let width = width
    let height = height
    let source = source
    let topLeft = plane.topLeftMM(width: width, height: height)
    let dx = plane.columnStepMM(width: width)
    let dy = plane.rowStepMM(height: height)
    let lower = source.originMM
    let upper = lower + source.extentMM
    var pixels = [UInt8](repeating: 0, count: width * height * 4)

    pixels.withUnsafeMutableBufferPointer { buffer in
      let bytes = buffer.baseAddress!
      DispatchQueue.concurrentPerform(iterations: height) { row in
        var point = topLeft + Float(row) * dy
        var offset = row * width * 4
        for _ in 0..<width {
          if all(point .>= lower), all(point .<= upper) {
            let label = source.label(atMM: point)
            var color = SIMD4<UInt8>(repeating: 0)
            switch options.mode {
            case .ct:
              if label != .air {
                let gray = UInt8(options.windowPreset.normalized(source.hu(atMM: point)) * 255)
                color = SIMD4(gray, gray, gray, 255)
              }
            case .layers:
              if let layer = label.layer,
                 !options.hiddenLayers.contains(layer) || label.isFinding {
                color = source.rgba(for: label)
              }
            }
            bytes[offset] = color.x
            bytes[offset + 1] = color.y
            bytes[offset + 2] = color.z
            bytes[offset + 3] = color.w
          }
          point += dx
          offset += 4
        }
      }
    }

    let data = Data(pixels) as CFData
    let provider = CGDataProvider(data: data)!
    return CGImage(
      width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    )!
  }
}
