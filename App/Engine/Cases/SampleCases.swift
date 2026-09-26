import Foundation

/// The bundled synthetic patient. Size thresholds in the copy come from Radiopaedia's pulmonary nodule,
/// abdominal aortic aneurysm, hepatic cyst and urolithiasis articles (docs/research-phantom.md §9).
enum SampleCases {
  static let patientCT = ScanCase(
    title: "Sample chest and belly CT",
    subtitle: "Synthetic demo patient",
    kind: .sample,
    findings: [lungNodule, aneurysm, liverCyst, kidneyStone],
    plainSummary: "This practice scan shows four things a radiologist would point out: a small spot in the right lung, a widened section of the main artery in the belly, a fluid bubble in the liver, and a small stone in the left kidney.",
    glossary: Glossary.terms(in: "nodule lobe aneurysm aorta cyst calculus renal hepatic pulmonary attenuation"),
    sourceFileName: nil,
    interpretedBy: "Authored"
  )

  static let lungNodule = Finding(
    title: "Lung nodule",
    clinicalPhrase: "Pulmonary nodule, 14 mm, right upper lobe",
    region: .rightLungUpperLobe,
    anchorMM: PatientPhantom.noduleCenter,
    sizeMM: 14,
    plainSummary: "A small round spot about the size of a blueberry near the top of your right lung.",
    whatItMeans: "Lung spots are very common and most are scars from old infections. Spots between 6 and 30 millimetres are usually checked again with a follow-up scan, and the size, shape, and your history decide how soon. A spot that stays the same size for a long time is usually harmless.",
    questionsForDoctor: [
      "When should I have a follow-up scan?",
      "Does my smoking history change the plan?",
      "Is there an older scan we can compare this with?",
    ],
    tone: .routine,
    label: .noduleLung
  )

  static let aneurysm = Finding(
    title: "Widened artery",
    clinicalPhrase: "Abdominal aortic aneurysm, 4.4 cm",
    region: .abdominalAorta,
    anchorMM: PatientPhantom.aneurysmCenter,
    sizeMM: 44,
    plainSummary: "The aorta, the main pipe carrying blood down to your legs, is wider than normal in your belly.",
    whatItMeans: "An aorta wider than 3 centimetres is called an aneurysm. At 4.0 to 4.4 centimetres, doctors usually check it with a scan about once a year. Repair is usually discussed once it reaches about 5.5 centimetres or grows quickly. The orange ring on the scan is old clot lining the wall; the red centre is where blood flows.",
    questionsForDoctor: [
      "How often should we measure it?",
      "What blood pressure should I aim for?",
      "Which symptoms mean I should go to the emergency room?",
    ],
    tone: .attention,
    label: .aneurysmThrombus
  )

  static let liverCyst = Finding(
    title: "Liver cyst",
    clinicalPhrase: "Simple hepatic cyst, 2.4 cm",
    region: .liver,
    anchorMM: PatientPhantom.cystCenter,
    sizeMM: 24,
    plainSummary: "A small bubble of clear fluid inside your liver.",
    whatItMeans: "Simple liver cysts are very common, are not cancer, and almost never cause problems. On the CT view it looks darker than the liver because fluid is less dense than liver tissue. Most people never need treatment for one.",
    questionsForDoctor: [
      "Do I need any follow-up for this cyst?",
    ],
    tone: .reassuring,
    label: .cystLiver
  )

  static let kidneyStone = Finding(
    title: "Kidney stone",
    clinicalPhrase: "Left renal calculus, 9 mm",
    region: .leftKidney,
    anchorMM: PatientPhantom.stoneCenter,
    sizeMM: 9,
    plainSummary: "A hard stone about the size of a pea inside your left kidney.",
    whatItMeans: "Kidney stones show up bright white on CT because they contain calcium. Stones larger than 5 millimetres are less likely to pass on their own, so your doctor may talk about treatment if it causes pain or blocks urine flow.",
    questionsForDoctor: [
      "Is this stone likely to pass on its own?",
      "What can I change in my diet to prevent more stones?",
    ],
    tone: .routine,
    label: .calculusKidney
  )
}
