import simd

/// Tissue classes in the synthetic body. Colours are verbatim from 3D Slicer's
/// Base/Logic/Resources/ColorFiles/GenericAnatomyColors.txt. Hounsfield means come from Radiopaedia's
/// "Hounsfield unit" article and Wikipedia's Hounsfield scale table (see docs/research-phantom.md §3).
enum TissueLabel: UInt8, CaseIterable, Codable {
  case air = 0, skin = 1, fat = 2, muscle = 3, boneCortical = 4, boneTrabecular = 5
  case lungRight = 6, lungLeft = 7, heart = 8, liver = 9, spleen = 10, kidneyRight = 11, kidneyLeft = 12
  case aorta = 13, trachea = 14, spinalCanal = 15
  case noduleLung = 20, aneurysmLumen = 21, aneurysmThrombus = 22, cystLiver = 23, calculusKidney = 24

  var isFinding: Bool { rawValue >= 20 }

  var displayName: String {
    switch self {
    case .air: "Air"
    case .skin: "Skin"
    case .fat: "Fat"
    case .muscle: "Muscle"
    case .boneCortical, .boneTrabecular: "Bone"
    case .lungRight: "Right lung"
    case .lungLeft: "Left lung"
    case .heart: "Heart"
    case .liver: "Liver"
    case .spleen: "Spleen"
    case .kidneyRight: "Right kidney"
    case .kidneyLeft: "Left kidney"
    case .aorta: "Aorta"
    case .trachea: "Windpipe"
    case .spinalCanal: "Spinal canal"
    case .noduleLung: "Lung nodule"
    case .aneurysmLumen, .aneurysmThrombus: "Widened aorta"
    case .cystLiver: "Liver cyst"
    case .calculusKidney: "Kidney stone"
    }
  }

  var layer: TissueLayer? {
    switch self {
    case .air: nil
    case .skin: .skin
    case .fat: .fat
    case .muscle, .spinalCanal: .muscle
    case .boneCortical, .boneTrabecular: .bone
    case .lungRight, .lungLeft, .trachea, .noduleLung: .lungs
    case .liver, .spleen, .kidneyRight, .kidneyLeft, .cystLiver, .calculusKidney: .organs
    case .heart, .aorta, .aneurysmLumen, .aneurysmThrombus: .blood
    }
  }

  /// Slicer GenericAnatomyColors RGB. One deliberate deviation: lungs use Slicer's `trachea` blue
  /// (182,228,255) instead of its tan lung colour, which is unreadable next to skin and muscle.
  /// Findings without a Slicer entry use a high-contrast marker colour.
  var color: SIMD4<UInt8> {
    switch self {
    case .air: SIMD4(0, 0, 0, 0)
    case .skin: SIMD4(177, 122, 101, 255)
    case .fat: SIMD4(230, 220, 70, 255)
    case .muscle: SIMD4(192, 104, 88, 255)
    case .boneCortical: SIMD4(241, 214, 145, 255)
    case .boneTrabecular: SIMD4(226, 202, 134, 255)
    case .lungRight, .lungLeft: SIMD4(182, 228, 255, 255)
    case .trachea: SIMD4(150, 205, 245, 255)
    case .heart: SIMD4(206, 110, 84, 255)
    case .liver: SIMD4(221, 130, 101, 255)
    case .spleen: SIMD4(157, 108, 162, 255)
    case .kidneyRight, .kidneyLeft: SIMD4(185, 102, 83, 255)
    case .aorta, .aneurysmLumen: SIMD4(224, 97, 76, 255)
    case .spinalCanal: SIMD4(244, 214, 49, 255)
    case .noduleLung: SIMD4(144, 238, 144, 255)
    case .aneurysmThrombus: SIMD4(255, 170, 60, 255)
    case .cystLiver: SIMD4(205, 205, 100, 255)
    case .calculusKidney: SIMD4(255, 255, 255, 255)
    }
  }

  var huMean: Float {
    switch self {
    case .air, .trachea: -1000
    case .skin: 45
    case .fat: -100
    case .muscle: 45
    case .boneCortical: 1000
    case .boneTrabecular: 350
    case .lungRight, .lungLeft: -780
    case .heart: 200
    case .liver: 55
    case .spleen: 42
    case .kidneyRight, .kidneyLeft: 32
    case .aorta, .aneurysmLumen: 250
    case .spinalCanal: 15
    case .noduleLung: 40
    case .aneurysmThrombus: 60
    case .cystLiver: 5
    case .calculusKidney: 500
    }
  }

  var huSigma: Float {
    switch self {
    case .air, .trachea, .spinalCanal, .cystLiver: 8
    case .boneCortical: 80
    case .boneTrabecular, .calculusKidney: 60
    case .lungRight, .lungLeft: 45
    case .heart, .aorta, .aneurysmLumen: 18
    case .skin: 15
    default: 12
    }
  }
}
