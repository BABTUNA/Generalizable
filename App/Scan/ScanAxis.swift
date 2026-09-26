import Foundation

enum ScanAxis: Int, CaseIterable, Identifiable, Sendable {
  case sagittal = 0, coronal = 1, axial = 2
  var id: Int { rawValue }
  var title: String {
    switch self { case .axial: "Axial"; case .coronal: "Coronal"; case .sagittal: "Sagittal" }
  }
  var explanation: String {
    switch self {
    case .axial: "Travel from the bottom to the top of the scan."
    case .coronal: "Travel from the back to the front of the body."
    case .sagittal: "Travel from the left to the right of the body."
    }
  }
  var horizontalAxis: Int { self == .sagittal ? 1 : 0 }
  var verticalAxis: Int { self == .axial ? 1 : 2 }
  var leftLabel: String { self == .sagittal ? "A" : "R" }
  var topLabel: String { self == .axial ? "A" : "S" }
  var rightLabel: String { self == .sagittal ? "P" : "L" }
  var bottomLabel: String { self == .axial ? "P" : "I" }
  var overviewAxis: ScanAxis { self == .coronal ? .sagittal : .coronal }
}

enum ScanWindow: String, CaseIterable, Identifiable, Sendable {
  case tissue = "Soft tissue", lung = "Lung", bone = "Bone"
  var id: String { rawValue }
  var level: Float {
    switch self { case .tissue: 40; case .lung: -600; case .bone: 300 }
  }
  var width: Float {
    switch self { case .tissue: 400; case .lung: 1500; case .bone: 1500 }
  }
}
