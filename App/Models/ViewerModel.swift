import CoreGraphics
import Foundation
import Observation
import simd

/// State for one open case: the selected finding, the cut, visible layers, and the rendered images.
/// Rendering runs off the main actor and coalesces requests so hinge motion never queues stale frames.
@MainActor
@Observable
final class ViewerModel {
  static let sliceFOV = SIMD2<Float>(300, 300)
  static let sideFOV = SIMD2<Float>(384, 576)
  static let slicePixels = 320

  var scanCase: ScanCase
  var selectedFindingID: Finding.ID?
  var manualTilt: Double = 0 { didSet { render() } }
  var offsetMM: Double = 0 { didSet { render() } }
  var mode: RenderOptions.Mode = .layers { didSet { render() } }
  var hiddenLayers: Set<TissueLayer> = [] { didSet { render() } }
  var windowPreset: WindowPreset = .abdomen { didSet { render() } }

  /// Set while the device is partially folded; the hinge then drives the tilt.
  private(set) var hingeTilt: Double?
  private(set) var hingeAngle: Double?
  private(set) var deviceHasHinge = false

  private(set) var sliceImage: CGImage?
  private(set) var sideImage: CGImage?

  private var renderTask: Task<Void, Never>?
  private var renderPending = false
  private var sideImageKey: String?

  init(scanCase: ScanCase) {
    self.scanCase = scanCase
    if let first = scanCase.findings.first {
      apply(first)
    }
    render()
  }

  var tilt: Double { hingeTilt ?? manualTilt }
  var isHingeDriving: Bool { hingeTilt != nil }

  var selectedFinding: Finding? {
    scanCase.findings.first { $0.id == selectedFindingID }
  }

  var pivot: SIMD3<Float> { selectedFinding?.anchorMM ?? SIMD3(0, 0, 300) }

  var plane: CutPlane {
    .hinged(pivot: pivot, tiltDegrees: Float(tilt), offsetMM: Float(offsetMM), fovMM: Self.sliceFOV)
  }

  var sidePlane: CutPlane {
    .sagittal(x: pivot.x, center: PatientSpace.centerMM, fovMM: Self.sideFOV)
  }

  var options: RenderOptions {
    RenderOptions(mode: mode, hiddenLayers: hiddenLayers, windowPreset: windowPreset)
  }

  /// Plain description of the current cut, for readouts and VoiceOver.
  var viewDescription: String {
    switch tilt {
    case ..<10: "Looking up from the feet"
    case 80...: "Looking from the front"
    default: "Tilted \(Int(tilt.rounded()))° toward the front"
    }
  }

  func select(_ finding: Finding) {
    apply(finding)
    render()
  }

  private func apply(_ finding: Finding) {
    selectedFindingID = finding.id
    offsetMM = 0
    hiddenLayers = finding.region.layersToPeel
    windowPreset = finding.region.windowPreset
  }

  func toggle(_ layer: TissueLayer) {
    if hiddenLayers.contains(layer) {
      hiddenLayers.remove(layer)
    } else {
      hiddenLayers.insert(layer)
    }
  }

  /// Peels every layer outside `layer`, like peeling an onion.
  func peel(to layer: TissueLayer) {
    let all = TissueLayer.allCases
    guard let index = all.firstIndex(of: layer) else { return }
    hiddenLayers = Set(all[..<index])
  }

  func reset() {
    offsetMM = 0
    manualTilt = 0
    hiddenLayers = selectedFinding?.region.layersToPeel ?? []
  }

  /// Hinge input: 180° (flat) is a cut seen from the feet, 90° (an L on the table) is a cut seen from the front.
  /// No open-source precedent maps a hinge to a slice angle; this is the PRD's mapping, kept in one line so it can be tuned on hardware.
  func updateHinge(angleDegrees: Double?, partiallyOpen: Bool, hasHinge: Bool) {
    deviceHasHinge = hasHinge
    if partiallyOpen, let angleDegrees {
      hingeAngle = angleDegrees
      hingeTilt = min(max(180 - angleDegrees, 0), 90)
    } else {
      hingeAngle = nil
      hingeTilt = nil
    }
    render()
  }

  func render() {
    if renderTask != nil {
      renderPending = true
      return
    }
    let plane = self.plane
    let side = sidePlane
    let options = self.options
    let sideKey = "\(side.center.x)|\(options.hashValue)"
    let needsSide = sideKey != sideImageKey
    let size = Self.slicePixels
    renderTask = Task { [weak self] in
      let result = await Task.detached(priority: .userInitiated) {
        let slice = SliceRenderer.render(plane: plane, width: size, height: size, options: options)
        let sideImage = needsSide ? SliceRenderer.render(plane: side, width: 192, height: 288, options: options) : nil
        return (slice, sideImage)
      }.value
      guard let self else { return }
      self.sliceImage = result.0
      if let sideImage = result.1 {
        self.sideImage = sideImage
        self.sideImageKey = sideKey
      }
      self.renderTask = nil
      if self.renderPending {
        self.renderPending = false
        self.render()
      }
    }
  }
}
