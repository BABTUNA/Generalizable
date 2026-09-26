import simd

/// Where a report sentence points in the body. Anchors sit inside the matching organ of PatientPhantom (mm, LPS).
enum BodyRegion: String, CaseIterable, Codable {
  case rightLungUpperLobe, rightLungLowerLobe, leftLungUpperLobe, leftLungLowerLobe
  case heart, thoracicAorta, abdominalAorta
  case liver, spleen, rightKidney, leftKidney, gallbladder, pancreas
  case spine, ribs, pelvis
  case skin, unknown

  var displayName: String {
    switch self {
    case .rightLungUpperLobe: "Top of the right lung"
    case .rightLungLowerLobe: "Bottom of the right lung"
    case .leftLungUpperLobe: "Top of the left lung"
    case .leftLungLowerLobe: "Bottom of the left lung"
    case .heart: "Heart"
    case .thoracicAorta: "Aorta in the chest"
    case .abdominalAorta: "Aorta in the belly"
    case .liver: "Liver"
    case .spleen: "Spleen"
    case .rightKidney: "Right kidney"
    case .leftKidney: "Left kidney"
    case .gallbladder: "Gallbladder"
    case .pancreas: "Pancreas"
    case .spine: "Spine"
    case .ribs: "Ribs"
    case .pelvis: "Hips and pelvis"
    case .skin: "Skin"
    case .unknown: "Chest and belly"
    }
  }

  var anchorMM: SIMD3<Float> {
    switch self {
    case .rightLungUpperLobe: PatientPhantom.noduleCenter
    case .rightLungLowerLobe: SIMD3(-70, 10, 350)
    case .leftLungUpperLobe: SIMD3(70, -10, 490)
    case .leftLungLowerLobe: SIMD3(70, 15, 350)
    case .heart: SIMD3(22, -22, 390)
    case .thoracicAorta: SIMD3(12, 20, 360)
    case .abdominalAorta: PatientPhantom.aneurysmCenter
    case .liver: PatientPhantom.cystCenter
    case .spleen: SIMD3(100, 38, 290)
    case .rightKidney: SIMD3(-62, 50, 195)
    case .leftKidney: PatientPhantom.stoneCenter
    case .gallbladder: SIMD3(-40, -30, 230)
    case .pancreas: SIMD3(20, 20, 240)
    case .spine: SIMD3(0, 64, 300)
    case .ribs: SIMD3(-130, 0, 420)
    case .pelvis: SIMD3(-78, 25, 60)
    case .skin: SIMD3(0, -108, 300)
    case .unknown: SIMD3(0, 0, 300)
    }
  }

  var layer: TissueLayer {
    switch self {
    case .rightLungUpperLobe, .rightLungLowerLobe, .leftLungUpperLobe, .leftLungLowerLobe: .lungs
    case .heart, .thoracicAorta, .abdominalAorta: .blood
    case .liver, .spleen, .rightKidney, .leftKidney, .gallbladder, .pancreas, .unknown: .organs
    case .spine, .ribs, .pelvis: .bone
    case .skin: .skin
    }
  }

  var windowPreset: WindowPreset {
    switch layer {
    case .lungs: .lung
    case .bone: .bone
    default: .abdomen
    }
  }

  /// Layers to peel so this region is visible: everything outside it.
  var layersToPeel: Set<TissueLayer> {
    switch layer {
    case .skin: []
    case .bone: [.skin, .fat, .muscle]
    default: [.skin, .fat, .muscle]
    }
  }
}
