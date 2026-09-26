import Foundation
import CoreGraphics
import zlib

/// NIfTI data is normalized to right/anterior/superior voxel order before display.
struct CTScanVolume: Sendable {
  var dimensions: [Int]
  var spacing: [Double]
  var voxels: [Float]

  static func read(_ url: URL) throws -> CTScanVolume {
    let data: Data
    if url.pathExtension.lowercased() == "gz" {
      guard let file = gzopen(url.path, "rb") else { throw ScanFileError.invalid }
      defer { gzclose(file) }
      var decoded = Data()
      var buffer = [UInt8](repeating: 0, count: 65_536)
      while true {
        let count = gzread(file, &buffer, UInt32(buffer.count))
        guard count >= 0 else { throw ScanFileError.invalid }
        if count == 0 { break }
        guard decoded.count + Int(count) <= 256 * 1_024 * 1_024 else { throw ScanFileError.tooLarge }
        decoded.append(contentsOf: buffer.prefix(Int(count)))
      }
      data = decoded
    } else {
      let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
      guard bytes <= 256 * 1_024 * 1_024 else { throw ScanFileError.tooLarge }
      data = try Data(contentsOf: url, options: .mappedIfSafe)
    }
    return try decode(data)
  }

  static func decode(_ data: Data) throws -> CTScanVolume {
    guard data.count >= 352 else { throw ScanFileError.invalid }
    func i16(_ offset: Int) -> Int16 {
      data.withUnsafeBytes { Int16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: Int16.self)) }
    }
    func f32(_ offset: Int) -> Float {
      let bits = data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
      return Float(bitPattern: bits)
    }
    let header = data.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
    guard header == 348, Array(data[344..<348]) == [110, 43, 49, 0] else { throw ScanFileError.format }
    let dimensions = [Int(i16(42)), Int(i16(44)), Int(i16(46))]
    guard (3...7).contains(i16(40)), (4...7).allSatisfy({ i16(40 + $0 * 2) <= 1 }),
          dimensions.allSatisfy({ (2...1024).contains($0) }) else { throw ScanFileError.dimensions }
    let count = dimensions.reduce(1, *)
    guard count <= 40_000_000 else { throw ScanFileError.tooLarge }
    let type = i16(70)
    let bytesPerVoxel: Int
    switch type { case 2: bytesPerVoxel = 1; case 4, 512: bytesPerVoxel = 2; case 16: bytesPerVoxel = 4; default: throw ScanFileError.format }
    let offsetValue = f32(108)
    guard offsetValue.isFinite, offsetValue >= 352, offsetValue <= Float(data.count),
          offsetValue.rounded(.towardZero) == offsetValue else { throw ScanFileError.invalid }
    let offset = Int(offsetValue)
    guard offset <= data.count, count <= (data.count - offset) / bytesPerVoxel else { throw ScanFileError.invalid }
    let slope = f32(112) == 0 ? Float(1) : f32(112)
    let intercept = f32(112) == 0 ? Float(0) : f32(116)
    guard slope.isFinite, intercept.isFinite else { throw ScanFileError.invalid }
    // Reorient axis-aligned sforms; reject oblique scans rather than mislabel anatomy.
    var affine = [[Float]](repeating: [Float](repeating: 0, count: 3), count: 3)
    if i16(254) > 0 {
      for row in 0..<3 { for column in 0..<3 { affine[row][column] = f32(280 + row * 16 + column * 4) } }
    } else if i16(252) > 0 {
      let b = f32(256), c = f32(260), d = f32(264)
      let a = sqrt(max(0, 1 - b*b - c*c - d*d))
      let rotation: [[Float]] = [
        [a*a+b*b-c*c-d*d, 2*(b*c-a*d), 2*(b*d+a*c)],
        [2*(b*c+a*d), a*a+c*c-b*b-d*d, 2*(c*d-a*b)],
        [2*(b*d-a*c), 2*(c*d+a*b), a*a+d*d-c*c-b*b]
      ]
      for row in 0..<3 { for column in 0..<3 {
        affine[row][column] = rotation[row][column] * abs(f32(80 + column * 4)) * (column == 2 && f32(76) < 0 ? -1 : 1)
      } }
    } else { throw ScanFileError.orientation }
    var sourceAxes = [Int](repeating: 0, count: 3)
    var positive = [Bool](repeating: true, count: 3)
    var spacing = [Double](repeating: 1, count: 3)
    for row in 0..<3 {
      guard affine[row].allSatisfy(\.isFinite),
            let axis = (0..<3).max(by: { abs(affine[row][$0]) < abs(affine[row][$1]) }),
            abs(affine[row][axis]) > 0.0001 else { throw ScanFileError.orientation }
      for column in 0..<3 where column != axis {
        guard abs(affine[row][column]) < abs(affine[row][axis]) * 0.001 else { throw ScanFileError.orientation }
      }
      sourceAxes[row] = axis
      positive[row] = affine[row][axis] > 0
      spacing[row] = Double(abs(affine[row][axis]))
    }
    guard Set(sourceAxes).count == 3 else { throw ScanFileError.orientation }
    let unit = data[123] & 7
    let unitScale: Double
    switch unit { case 1: unitScale = 1000; case 2: unitScale = 1; case 3: unitScale = 0.001; default: throw ScanFileError.units }
    spacing = spacing.map { $0 * unitScale }
    let canonicalDimensions = sourceAxes.map { dimensions[$0] }
    let strides = [1, dimensions[0], dimensions[0] * dimensions[1]]
    let deltas = (0..<3).map { (positive[$0] ? 1 : -1) * strides[sourceAxes[$0]] }
    let start = (0..<3).reduce(0) { $0 + (positive[$1] ? 0 : (canonicalDimensions[$1] - 1) * strides[sourceAxes[$1]]) }
    var voxels = [Float](repeating: 0, count: count)
    data.withUnsafeBytes { bytes in
      var target = 0
      for z in 0..<canonicalDimensions[2] { for y in 0..<canonicalDimensions[1] { for x in 0..<canonicalDimensions[0] {
        let source = offset + (start + x*deltas[0] + y*deltas[1] + z*deltas[2]) * bytesPerVoxel
        let value: Float
        switch type {
        case 2: value = Float(bytes[source])
        case 4: value = Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: source, as: Int16.self)))
        case 512: value = Float(UInt16(littleEndian: bytes.loadUnaligned(fromByteOffset: source, as: UInt16.self)))
        default: value = Float(bitPattern: UInt32(littleEndian: bytes.loadUnaligned(fromByteOffset: source, as: UInt32.self)))
        }
        let scaled = value * slope + intercept
        voxels[target] = scaled.isFinite ? scaled : -1024
        target += 1
      } } }
    }
    return CTScanVolume(dimensions: canonicalDimensions, spacing: spacing, voxels: voxels)
  }

  func slice(axis: ScanAxis, index: Int, window: ScanWindow) -> CGImage? {
    let horizontal = axis.horizontalAxis, vertical = axis.verticalAxis
    let width = dimensions[horizontal], height = dimensions[vertical]
    let strides = [1, dimensions[0], dimensions[0] * dimensions[1]]
    let fixed = min(dimensions[axis.rawValue] - 1, max(0, index)) * strides[axis.rawValue]
    let lower = window.level - window.width / 2
    var pixels = [UInt8](repeating: 0, count: width * height)
    for v in 0..<height { for u in 0..<width {
      let source = fixed + (width - 1 - u) * strides[horizontal] + (height - 1 - v) * strides[vertical]
      pixels[v * width + u] = UInt8(min(255, max(0, (voxels[source] - lower) * 255 / window.width)))
    } }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
  }

  func aspectRatio(for axis: ScanAxis) -> Double {
    Double(dimensions[axis.horizontalAxis]) * spacing[axis.horizontalAxis]
      / (Double(dimensions[axis.verticalAxis]) * spacing[axis.verticalAxis])
  }
}

enum ScanFileError: LocalizedError {
  case invalid, format, dimensions, tooLarge, orientation, units
  var errorDescription: String? {
    switch self {
    case .invalid: "This scan is incomplete or damaged. Choose another NIfTI file."
    case .format: "Choose a little-endian NIfTI-1 scan (.nii or .nii.gz) with 8-bit, 16-bit, or float32 voxels."
    case .dimensions: "Choose a single three-dimensional scan. Time series are not supported yet."
    case .tooLarge: "This scan is too large for this viewer. Use a scan under 256 MB and 40 million voxels."
    case .orientation: "This scan needs axis-aligned orientation metadata. Oblique scans are not supported yet."
    case .units: "This scan does not specify its physical measurement units."
    }
  }
}
