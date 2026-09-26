import Foundation

// Run with the three model files in App/Scan; no simulator is needed.
@main
struct CTScanChecks {
  @MainActor static func main() async throws {
    let sample = try CTScanVolume.read(URL(fileURLWithPath: "App/Resources/TorsoCT.nii.gz"))
    precondition(sample.dimensions == [384, 320, 89])
    precondition(sample.spacing[2] == 5)
    for axis in ScanAxis.allCases {
      let count = sample.dimensions[axis.rawValue]
      for index in [0, count / 2, count - 1] {
        precondition(sample.slice(axis: axis, index: index, window: .tissue) != nil)
      }
    }
    precondition(FoldScanSession.position(forHinge: 180) == 0)
    precondition(FoldScanSession.position(forHinge: 90) == 1)
    precondition(FoldScanSession.position(forHinge: 135) == 0.5)
    precondition(FoldScanSession.position(forHinge: 0) == 1)
    precondition(FoldScanSession.index(position: 1, count: 89) == 88)
    precondition(FoldScanSession.index(position: 0, count: 89) == 0)
    precondition(FoldScanSession.index(position: 0.5, count: 89) == 44)
    let previousFollow = UserDefaults.standard.object(forKey: "foldScan.followsFold")
    defer { UserDefaults.standard.set(previousFollow, forKey: "foldScan.followsFold") }
    let session = FoldScanSession()
    session.setFollowsFold(true)
    session.updateHinge(angle: 135, isClosed: false)
    precondition(session.position == 0.5)
    session.scrub(0.8)
    session.updateHinge(angle: 100, isClosed: false)
    precondition(session.position == 0.8)
    session.setFollowsFold(true)
    precondition(abs(session.position - 80.0 / 90) < 0.001)
    session.updateHinge(angle: 0, isClosed: true)
    precondition(abs(session.position - 80.0 / 90) < 0.001)

    var fixture = Data(repeating: 0, count: 352 + 2 * 3 * 4 * 2)
    func put<T>(_ value: T, at offset: Int) {
      var value = value
      withUnsafeBytes(of: &value) { fixture.replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }
    put(Int32(348), at: 0)
    put(Int16(3), at: 40)
    for (i, dim) in [2, 3, 4].enumerated() { put(Int16(dim), at: 42 + i * 2) }
    put(Int16(4), at: 70)
    put(Float(352), at: 108)
    put(Float(2), at: 112)
    put(Float(-10), at: 116)
    fixture[123] = 2
    put(Int16(1), at: 254)
    put(Float(-1), at: 280)
    put(Float(2), at: 300)
    put(Float(3), at: 320)
    fixture.replaceSubrange(344..<348, with: [110, 43, 49, 0])
    for i in 0..<24 { put(Int16(i), at: 352 + i * 2) }
    let volume = try CTScanVolume.decode(fixture)
    precondition(volume.voxels[0] == -8 && volume.voxels[1] == -10, "Negative X must reorient into RAS")
    precondition(volume.voxels[23] == 34, "Rescale slope and intercept must be applied")
    precondition(volume.aspectRatio(for: .axial) == 1.0 / 3)
    let image = volume.slice(axis: .axial, index: 0, window: .tissue)!
    let pixels = image.dataProvider!.data! as Data
    precondition(pixels[0] == UInt8((Float(-2) + 160) * 255 / 400), "Top-left axial pixel must be right/anterior")
    put(Float(0.5), at: 284)
    do { _ = try CTScanVolume.decode(fixture); preconditionFailure("Oblique scan must be rejected") }
    catch ScanFileError.orientation { }
    do { _ = try CTScanVolume.decode(Data(fixture.prefix(100))); preconditionFailure("Truncated scan must fail") }
    catch ScanFileError.invalid { }
    print("PASS: CT loading, three planes, RAS orientation, voxel scaling, malformed files, fold endpoints, touch override, and close continuity")
  }
}
