import Foundation
import simd

enum ExplorerSubject: String, CaseIterable, Identifiable {
  case patient, sun, circuit

  var id: String { rawValue }
  var title: String {
    switch self {
    case .patient: "Patient CT"
    case .sun: "The Sun"
    case .circuit: "Circuit board"
    }
  }
  var symbol: String {
    switch self {
    case .patient: "lungs"
    case .sun: "sun.max"
    case .circuit: "cpu"
    }
  }
  var headline: String {
    switch self {
    case .patient: "Anatomy,\nilluminated."
    case .sun: "A star.\nFrom the inside."
    case .circuit: "Small layers.\nBig possibilities."
    }
  }
  var subtitle: String {
    switch self {
    case .patient: "Explore a scan, one layer at a time."
    case .sun: "The same lens. A whole new universe."
    case .circuit: "See what connects beneath the surface."
    }
  }
  var source: any VolumeSource {
    switch self {
    case .patient: AnalyticPhantomSource()
    case .sun: SolarVolumeSource()
    case .circuit: CircuitVolumeSource()
    }
  }
  var points: [ExplorerPoint] {
    switch self {
    case .patient:
      return [
        ExplorerPoint(id: "lung", title: "Lung nodule", location: "Right upper lung", measurement: "14 mm", anchor: PatientPhantom.noduleCenter, summary: "A small spot, about the size of a blueberry.", detail: "In this teaching scan, the highlighted spot sits inside the right lung. ‘Nodule’ is a word a report may use for a small, rounded spot. Its appearance alone does not tell us its cause.", question: "What does this finding mean in the context of my history?", layer: .lungs, window: .lung),
        ExplorerPoint(id: "artery", title: "Widened artery", location: "Abdominal aorta", measurement: "4.4 cm", anchor: PatientPhantom.aneurysmCenter, summary: "A wider section of the body's main artery.", detail: "The aorta carries blood from the heart. This synthetic example shows a wider section in the belly. The cut lets you see the blood channel and the surrounding wall.", question: "What follow-up do you recommend for this measurement?", layer: .blood),
        ExplorerPoint(id: "liver", title: "Liver cyst", location: "Liver", measurement: "2.4 cm", anchor: PatientPhantom.cystCenter, summary: "A small pocket of fluid inside the liver.", detail: "A cyst is a pocket that can contain fluid. This teaching example shows why a fluid-filled area can look different from the tissue around it on a scan.", question: "Does the report describe this as a simple cyst?", layer: .organs),
        ExplorerPoint(id: "kidney", title: "Kidney stone", location: "Left kidney", measurement: "9 mm", anchor: PatientPhantom.stoneCenter, summary: "A small, solid deposit inside the kidney.", detail: "The bright point in this synthetic scan represents a kidney stone. Switch to CT to compare its density with the surrounding kidney. This model cannot determine a treatment plan.", question: "Where is the stone, and is it causing any blockage?", layer: .organs)
      ]
    case .sun:
      return [
        ExplorerPoint(id: "core", title: "The core", location: "Center of the Sun", measurement: "Fusion", anchor: SIMD3(0, 0, 288), summary: "The energy source at the heart of a star.", detail: "This simplified model separates the Sun into concentric regions. Slice through its center to see how the core sits beneath the outer layers. Sizes and colors are illustrative.", question: "How does energy reach the surface?", layer: .blood),
        ExplorerPoint(id: "outer", title: "Outer layers", location: "Near the surface", measurement: "Energy", anchor: SIMD3(105, 0, 340), summary: "Energy travels outward from the center.", detail: "The colors distinguish regions of a simplified star. Tilt the plane and move the slice to reveal how a three-dimensional shell appears as a ring in cross-section.", question: "Why does a shell become a ring when sliced?", layer: .skin)
      ]
    case .circuit:
      return [
        ExplorerPoint(id: "chip", title: "Inside the stack", location: "Layer 3", measurement: "4 layers", anchor: SIMD3(0, 0, 339), summary: "A tiny world of stacked connections.", detail: "This exploded teaching model separates four circuit layers so you can see each one. The slice samples the same model you see in the overview; the gaps are enlarged for clarity.", question: "What changes when the cut crosses more than one layer?", layer: .organs),
        ExplorerPoint(id: "base", title: "The foundation", location: "Layer 1", measurement: "Substrate", anchor: SIMD3(0, 0, 112), summary: "A base that holds a circuit's structure.", detail: "Circuit boards bring electrical paths and components together on a supporting base. Here, deliberately separated layers make an otherwise hidden structure visible.", question: "How do hidden layers connect the components?", layer: .muscle)
      ]
    }
  }
}

struct ExplorerPoint: Identifiable {
  var id: String
  var title: String
  var location: String
  var measurement: String
  var anchor: SIMD3<Float>
  var summary: String
  var detail: String
  var question: String
  var layer: TissueLayer
  var window: WindowPreset = .abdomen
}
