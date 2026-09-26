import SwiftUI
import Observation

@MainActor @Observable
final class FoldScanSession {
  var axis = ScanAxis.axial
  var window = ScanWindow.tissue {
    didSet { UserDefaults.standard.set(window.rawValue, forKey: "foldScan.window") }
  }
  var followsFold = true {
    didSet { UserDefaults.standard.set(followsFold, forKey: "foldScan.followsFold") }
  }
  var position = 0.52
  var hingeAngle: Double?
  var isLoading = false
  var error: String?
  var studyName = "Torso CT"
  var isDemo = true
  var volume: CTScanVolume?
  var frame: ScanFrame?
  @ObservationIgnored private var loadGeneration = 0
  @ObservationIgnored private var volumeGeneration = 0
  @ObservationIgnored private var renderTask: Task<Void, Never>?

  init() {
    window = ScanWindow(rawValue: UserDefaults.standard.string(forKey: "foldScan.window") ?? "") ?? .tissue
    if UserDefaults.standard.object(forKey: "foldScan.followsFold") != nil {
      followsFold = UserDefaults.standard.bool(forKey: "foldScan.followsFold")
    }
  }

  var sliceCount: Int { volume?.dimensions[axis.rawValue] ?? 1 }
  var sliceIndex: Int { Self.index(position: position, count: sliceCount) }
  var renderKey: ScanRenderKey { ScanRenderKey(generation: volumeGeneration, axis: axis, window: window, index: sliceIndex) }

  static func index(position: Double, count: Int) -> Int {
    guard count > 1, position.isFinite else { return 0 }
    return Int((min(1, max(0, position)) * Double(count - 1)).rounded())
  }

  static func position(forHinge angle: Double) -> Double {
    guard angle.isFinite else { return 0 }
    return min(1, max(0, (180 - angle) / 90))
  }

  func updateHinge(angle: Double?, isClosed: Bool) {
    guard let angle, angle.isFinite, !isClosed else { hingeAngle = nil; return }
    hingeAngle = angle
    if followsFold { position = Self.position(forHinge: angle) }
  }

  func setFollowsFold(_ value: Bool) {
    followsFold = value
    if value, let hingeAngle { position = Self.position(forHinge: hingeAngle) }
  }

  func scrub(_ value: Double) {
    followsFold = false
    position = min(1, max(0, value))
  }

  func step(_ delta: Int) {
    scrub(Double(min(sliceCount - 1, max(0, sliceIndex + delta))) / Double(max(1, sliceCount - 1)))
  }

  func loadDemo() async {
    guard let url = Bundle.main.url(forResource: "TorsoCT", withExtension: "nii.gz") else {
      error = "The bundled CT scan could not be found."
      return
    }
    await load(url, demo: true)
  }

  func load(_ url: URL, demo: Bool = false) async {
    loadGeneration += 1
    let generation = loadGeneration
    isLoading = true
    error = nil
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    do {
      let loaded = try await Task.detached(priority: .userInitiated) { try CTScanVolume.read(url) }.value
      guard generation == loadGeneration else { return }
      volume = loaded
      volumeGeneration += 1
      studyName = demo ? "Torso CT" : url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: ".nii", with: "")
      isDemo = demo
      frame = nil
      position = followsFold ? hingeAngle.map(Self.position(forHinge:)) ?? 0.52 : 0.52
      requestRender()
    } catch {
      guard generation == loadGeneration else { return }
      self.error = error.localizedDescription
    }
    isLoading = false
  }

  func requestRender() {
    guard renderTask == nil, let volume else { return }
    let key = renderKey
    renderTask = Task {
      let result = await Task.detached(priority: .userInitiated) {
        let overviewAxis = key.axis.overviewAxis
        return ScanFrame(key: key,
          image: volume.slice(axis: key.axis, index: key.index, window: key.window),
          overview: volume.slice(axis: overviewAxis, index: volume.dimensions[overviewAxis.rawValue] / 2, window: key.window),
          aspectRatio: volume.aspectRatio(for: key.axis), overviewAspectRatio: volume.aspectRatio(for: overviewAxis),
          count: volume.dimensions[key.axis.rawValue], spacing: volume.spacing[key.axis.rawValue])
      }.value
      if key.generation == volumeGeneration { frame = result }
      renderTask = nil
      if key != renderKey { requestRender() }
    }
  }
}

struct ScanRenderKey: Equatable, Sendable {
  var generation: Int
  var axis: ScanAxis
  var window: ScanWindow
  var index: Int
}

struct ScanFrame: Sendable {
  var key: ScanRenderKey
  var image: CGImage?
  var overview: CGImage?
  var aspectRatio: Double
  var overviewAspectRatio: Double
  var count: Int
  var spacing: Double
  var fraction: Double { Double(key.index) / Double(max(1, count - 1)) }
}
