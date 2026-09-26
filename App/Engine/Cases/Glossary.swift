import Foundation

/// Plain meanings for words common in chest and belly CT reports. Written for this app at a middle-school
/// reading level; no open glossary with a compatible licence was verified, so these are authored, not copied.
enum Glossary {
  static let all: [GlossaryTerm] = [
    GlossaryTerm(term: "Nodule", meaning: "A small round spot, usually under 3 centimetres."),
    GlossaryTerm(term: "Mass", meaning: "A spot larger than 3 centimetres."),
    GlossaryTerm(term: "Lesion", meaning: "Any area that looks different from the tissue around it."),
    GlossaryTerm(term: "Lobe", meaning: "One section of an organ. The right lung has three, the left has two."),
    GlossaryTerm(term: "Pulmonary", meaning: "Having to do with the lungs."),
    GlossaryTerm(term: "Hepatic", meaning: "Having to do with the liver."),
    GlossaryTerm(term: "Renal", meaning: "Having to do with the kidneys."),
    GlossaryTerm(term: "Aorta", meaning: "The body's main artery, running from the heart down through the chest and belly."),
    GlossaryTerm(term: "Aneurysm", meaning: "A section of an artery that has widened like a balloon."),
    GlossaryTerm(term: "Cyst", meaning: "A pocket filled with fluid. Simple cysts are almost always harmless."),
    GlossaryTerm(term: "Calculus", meaning: "A stone, such as a kidney stone."),
    GlossaryTerm(term: "Attenuation", meaning: "How bright or dark something looks on CT, which depends on how dense it is."),
    GlossaryTerm(term: "Hypodense", meaning: "Darker than the tissue around it on CT, often fluid or fat."),
    GlossaryTerm(term: "Hyperdense", meaning: "Brighter than the tissue around it on CT, such as calcium or contrast dye."),
    GlossaryTerm(term: "Contrast", meaning: "A dye given before the scan so blood vessels and organs show up more clearly."),
    GlossaryTerm(term: "Benign", meaning: "Not cancer."),
    GlossaryTerm(term: "Malignant", meaning: "Cancer."),
    GlossaryTerm(term: "Incidental", meaning: "Found by chance while looking for something else."),
    GlossaryTerm(term: "Unremarkable", meaning: "Looks normal."),
    GlossaryTerm(term: "Atelectasis", meaning: "A small area of lung that is partly collapsed, often from shallow breathing."),
    GlossaryTerm(term: "Effusion", meaning: "Extra fluid collected in a space where it normally isn't."),
    GlossaryTerm(term: "Consolidation", meaning: "Lung tissue filled with fluid or pus instead of air, as in pneumonia."),
    GlossaryTerm(term: "Ground-glass", meaning: "A hazy area in the lung that is lighter than solid tissue."),
    GlossaryTerm(term: "Emphysema", meaning: "Damage to the tiny air sacs in the lungs, often from smoking."),
    GlossaryTerm(term: "Steatosis", meaning: "Extra fat stored in the liver."),
    GlossaryTerm(term: "Hydronephrosis", meaning: "A kidney swollen with urine that can't drain normally."),
    GlossaryTerm(term: "Lymph node", meaning: "A small bean-shaped filter that is part of the immune system."),
    GlossaryTerm(term: "Lymphadenopathy", meaning: "Lymph nodes that are larger than usual."),
    GlossaryTerm(term: "Degenerative", meaning: "Wear and tear from age or use."),
    GlossaryTerm(term: "Osteophyte", meaning: "A bone spur, a small extra growth of bone at a joint."),
    GlossaryTerm(term: "Calcification", meaning: "A small deposit of calcium, which shows up bright on CT."),
    GlossaryTerm(term: "Follow-up", meaning: "Another check, often a repeat scan, to see whether something changes."),
    GlossaryTerm(term: "Stable", meaning: "Has not changed since an earlier scan."),
    GlossaryTerm(term: "Impression", meaning: "The radiologist's summary of the most important points."),
  ]

  /// Terms whose word appears in `text`, in glossary order.
  static func terms(in text: String) -> [GlossaryTerm] {
    let lower = text.lowercased()
    return all.filter { lower.contains($0.term.lowercased()) }
  }
}
