import simd

/// The seven peelable layers, ordered from the outside in.
enum TissueLayer: String, CaseIterable, Codable, Identifiable, Hashable {
  case skin, fat, muscle, bone, lungs, organs, blood

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .skin: "Skin"
    case .fat: "Fat"
    case .muscle: "Muscle"
    case .bone: "Bone"
    case .lungs: "Lungs"
    case .organs: "Organs"
    case .blood: "Blood"
    }
  }

  var patientDescription: String {
    switch self {
    case .skin: "The thin outer covering of your body."
    case .fat: "A soft cushioning layer under the skin that stores energy."
    case .muscle: "The walls of your chest and belly, and the muscles along your back."
    case .bone: "Your ribs, breastbone, spine, and hips."
    case .lungs: "The air-filled organs that bring oxygen into your blood."
    case .organs: "Your liver, spleen, and kidneys."
    case .blood: "Your heart and the aorta, the main artery that carries blood to your body."
    }
  }

  /// Representative colour (3D Slicer GenericAnatomyColors, see TissueLabel.color).
  var rgba: SIMD4<UInt8> {
    switch self {
    case .skin: TissueLabel.skin.color
    case .fat: TissueLabel.fat.color
    case .muscle: TissueLabel.muscle.color
    case .bone: TissueLabel.boneCortical.color
    case .lungs: TissueLabel.lungRight.color
    case .organs: TissueLabel.liver.color
    case .blood: TissueLabel.aorta.color
    }
  }

  var symbolName: String {
    switch self {
    case .skin: "hand.raised"
    case .fat: "drop"
    case .muscle: "figure.strengthtraining.traditional"
    case .bone: "figure.stand"
    case .lungs: "lungs"
    case .organs: "cross.case"
    case .blood: "heart"
    }
  }
}
