import Foundation

/// CT window/level presets from 3D Slicer's Modules/Loadable/Volumes/Resources/VolumeDisplayPresets.json.
/// Gray mapping is cornerstone3D's toLowHighRange LINEAR formula (DICOM C.11.2.1.2.1).
enum WindowPreset: String, CaseIterable, Codable, Identifiable {
  case lung, abdomen, bone

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .lung: "Lung"
    case .abdomen: "Soft tissue"
    case .bone: "Bone"
    }
  }

  var window: Float {
    switch self {
    case .lung: 1400
    case .abdomen: 350
    case .bone: 1000
    }
  }

  var level: Float {
    switch self {
    case .lung: -500
    case .abdomen: 40
    case .bone: 400
    }
  }

  @inline(__always)
  func normalized(_ hu: Float) -> Float {
    let lower = level - 0.5 - (window - 1) / 2
    let upper = level - 0.5 + (window - 1) / 2
    return min(max((hu - lower) / (upper - lower), 0), 1)
  }
}
