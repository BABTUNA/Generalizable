import CoreGraphics
import Foundation
import Observation
import simd

@MainActor @Observable
final class ExplorerSession {
  var subject: ExplorerSubject = .patient
  var hingeMode: ExplorerHingeMode = .volume
  var pointIndex = 0
  var layerHeight: Double = 500
  var tiltDegrees: Double = 28
  var sliceOffset: Double = 0
  var hiddenLayers: Set<TissueLayer> = [.skin, .fat, .muscle]
  var mode: RenderOptions.Mode = .layers
  var showsSlice = false
  var followsFold = true
  var hingeAvailable = false
  var hingeAngle: Double?
  var frame: ExplorerSliceFrame?
  var referenceFrame: ExplorerSliceFrame?
  var isRendering = false
  var cameraReset = 0
  @ObservationIgnored private var renderTask: Task<Void, Never>?

  var point: ExplorerPoint { subject.points[min(pointIndex, subject.points.count - 1)] }
  var visibleLayers: Set<TissueLayer> { Set(TissueLayer.allCases).subtracting(hiddenLayers) }
  var cutAnchor: SIMD3<Float> { hingeMode == .layerHeight ? SIMD3(0, 0, Float(layerHeight)) : point.anchor }
  var cutAngle: Double { hingeMode == .layerHeight ? 0 : tiltDegrees }
  var cutOffset: Double { hingeMode == .layerHeight ? 0 : sliceOffset }
  var plane: CutPlane {
    .hinged(pivot: cutAnchor, tiltDegrees: Float(cutAngle), offsetMM: Float(cutOffset), fovMM: SIMD2(repeating: 400))
  }
  var renderKey: String {
    "\(subject.rawValue)-\(pointIndex)-\(hingeMode.rawValue)-\(layerHeight)-\(tiltDegrees)-\(sliceOffset)-\(mode.rawValue)-\(hiddenLayers.map(\.rawValue).sorted().joined())"
  }

  func selectHingeMode(_ value: ExplorerHingeMode) {
    hingeMode = value
    showsSlice = value == .hingeSlice
    sliceOffset = 0
    layerHeight = Double(point.anchor.z)
    frame = nil
    referenceFrame = nil
    cameraReset += 1
    if followsFold, let angle = hingeAngle { applyHinge(angle) }
  }

  func selectSubject(_ value: ExplorerSubject) {
    subject = value
    pointIndex = 0
    sliceOffset = 0
    layerHeight = Double(point.anchor.z)
    hiddenLayers = value == .patient ? [.skin, .fat, .muscle] : []
    mode = .layers
    frame = nil
    referenceFrame = nil
    cameraReset += 1
    if followsFold, let angle = hingeAngle { applyHinge(angle) }
  }

  func selectPoint(_ index: Int) {
    pointIndex = index
    sliceOffset = 0
    hiddenLayers.remove(point.layer)
    layerHeight = Double(point.anchor.z)
    if hingeMode == .layerHeight { followsFold = false }
    frame = nil
    referenceFrame = nil
  }

  func reset() {
    tiltDegrees = 28
    sliceOffset = 0
    layerHeight = Double(point.anchor.z)
    hiddenLayers = subject == .patient ? [.skin, .fat, .muscle] : []
    mode = .layers
    cameraReset += 1
    if followsFold, let angle = hingeAngle { applyHinge(angle) }
  }

  func updateHinge(angle: Double?, partiallyOpen: Bool) {
    hingeAvailable = angle != nil
    hingeAngle = angle
    guard followsFold, let angle else { return }
    // Closed outer-display transitions preserve the selected cut; the usable interaction is 90–180°.
    guard partiallyOpen || angle > 170 else { return }
    applyHinge(angle)
  }

  func applyHinge(_ angle: Double) {
    guard angle.isFinite, angle >= 90 else { return }
    let progress = max(0, min(1, (180 - angle) / 90))
    switch hingeMode {
    case .volume: break
    case .hingeSlice: tiltDegrees = progress * 90
    case .layerHeight: layerHeight = progress * 576
    }
  }

  /// Coalesces rapid hinge events into one background render plus the most recent pending state.
  /// Each image owns its bytes, and its plane is saved with it so the overlay never drifts.
  func requestRender() {
    guard renderTask == nil else { return }
    isRendering = true
    renderTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let key = renderKey
        let cut = plane
        let subjectID = subject
        let pointSnapshot = point
        let angle = cutAngle
        let offset = hingeMode == .layerHeight ? Double(cut.distance(to: point.anchor)) : sliceOffset
        let height = hingeMode == .layerHeight ? layerHeight : nil
        let interaction = hingeMode
        let referenceCut = CutPlane.hinged(pivot: cut.center, tiltDegrees: 0, fovMM: cut.fovMM)
        let modeSnapshot = mode
        let source = subject.source
        let options = RenderOptions(mode: mode, hiddenLayers: hiddenLayers, windowPreset: point.window)
        let result = await Task.detached(priority: .userInitiated) {
          let sampler = CrossSectionSampler(source: source, width: 256, height: 256)
          let image = sampler.render(plane: cut, options: options)
          let reference = interaction == .hingeSlice ? sampler.render(plane: referenceCut, options: options) : nil
          return (image, reference)
        }.value
        guard !Task.isCancelled else { break }
        if subject == subjectID, point.id == pointSnapshot.id, hingeMode == interaction {
          frame = ExplorerSliceFrame(image: result.0, plane: cut, point: pointSnapshot,
            angle: angle, offset: offset, mode: modeSnapshot, subject: subjectID, height: height)
          referenceFrame = result.1.map {
            ExplorerSliceFrame(image: $0, plane: referenceCut, point: pointSnapshot,
              angle: 0, offset: Double(referenceCut.distance(to: pointSnapshot.anchor)), mode: modeSnapshot, subject: subjectID, height: nil)
          }
        }
        if key == renderKey { break }
      }
      isRendering = false
      renderTask = nil
    }
  }
}

/// Image and annotations are one immutable display snapshot, even while the next cut is rendering.
struct ExplorerSliceFrame {
  var image: CGImage
  var plane: CutPlane
  var point: ExplorerPoint
  var angle: Double
  var offset: Double
  var mode: RenderOptions.Mode
  var subject: ExplorerSubject
  var height: Double?
}
