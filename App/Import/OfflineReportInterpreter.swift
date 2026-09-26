import Foundation

/// Reads a radiology report without a network connection by matching common finding words to body regions.
/// It is deliberately conservative: it quotes the report's sentence and gives general, non-diagnostic copy.
enum OfflineReportInterpreter {
  private struct Rule {
    var keywords: [String]
    var title: String
    var tone: Finding.Tone
    var summary: String
    var meaning: String
    var questions: [String]
  }

  private static let rules: [Rule] = [
    Rule(keywords: ["aneurysm", "ectatic", "dilated aorta"], title: "Widened artery", tone: .attention,
         summary: "A section of an artery is wider than normal.",
         meaning: "When an artery widens like a balloon it's called an aneurysm. Doctors usually measure it again over time, and the size decides whether anything needs to be done.",
         questions: ["How often should we measure it?", "Which symptoms should send me to the emergency room?"]),
    Rule(keywords: ["nodule", "opacity", "mass"], title: "Spot", tone: .routine,
         summary: "A small round spot was seen.",
         meaning: "Small spots are common and most are harmless, such as scars from old infections. Doctors often check them again with a follow-up scan to make sure they don't change.",
         questions: ["Do I need a follow-up scan, and when?", "Is there an older scan to compare with?"]),
    Rule(keywords: ["cyst"], title: "Cyst", tone: .reassuring,
         summary: "A small pocket of fluid was seen.",
         meaning: "Simple cysts are very common, are not cancer, and usually never cause problems.",
         questions: ["Does this cyst need any follow-up?"]),
    Rule(keywords: ["calculus", "calculi", "stone", "nephrolithiasis", "urolithiasis"], title: "Stone", tone: .routine,
         summary: "A small stone was seen.",
         meaning: "Stones show up bright on CT because they contain calcium. Small stones often pass on their own; larger ones or ones that block flow may need treatment.",
         questions: ["Is this likely to pass on its own?", "How can I prevent more stones?"]),
    Rule(keywords: ["effusion"], title: "Extra fluid", tone: .routine,
         summary: "Some extra fluid has collected where there is normally very little.",
         meaning: "Fluid can build up for many reasons, from infection to heart or kidney conditions. Your doctor will look at the cause.",
         questions: ["What might be causing the fluid?"]),
    Rule(keywords: ["consolidation", "pneumonia", "infiltrate"], title: "Lung infection signs", tone: .attention,
         summary: "Part of a lung looks filled with fluid instead of air.",
         meaning: "This pattern is often seen with pneumonia. Your doctor will match it with your symptoms.",
         questions: ["Do I need treatment for an infection?"]),
    Rule(keywords: ["atelectasis"], title: "Partly collapsed lung area", tone: .reassuring,
         summary: "A small area of lung isn't fully inflated.",
         meaning: "This is common, often from shallow breathing while lying still, and usually improves on its own.",
         questions: ["Should I do breathing exercises?"]),
    Rule(keywords: ["steatosis", "fatty liver", "fatty infiltration"], title: "Fatty liver", tone: .routine,
         summary: "The liver is storing extra fat.",
         meaning: "Fatty liver is very common. Weight, diet, alcohol, and blood sugar all play a part, and it can often improve.",
         questions: ["Should I have liver blood tests?"]),
    Rule(keywords: ["hydronephrosis"], title: "Swollen kidney", tone: .attention,
         summary: "A kidney is swollen with urine that isn't draining normally.",
         meaning: "Something may be slowing urine flow, such as a stone. Your doctor will want to find the cause.",
         questions: ["What is blocking the flow, and how soon should it be treated?"]),
    Rule(keywords: ["emphysema"], title: "Emphysema", tone: .routine,
         summary: "Some of the tiny air sacs in the lungs are damaged.",
         meaning: "This is often related to smoking. Breathing tests help show how much it affects you.",
         questions: ["Should I have breathing tests?"]),
    Rule(keywords: ["lymphadenopathy", "enlarged lymph node"], title: "Enlarged lymph nodes", tone: .routine,
         summary: "Some of the body's small immune filters are larger than usual.",
         meaning: "Lymph nodes grow with infections and many other conditions. Your doctor may compare with other tests.",
         questions: ["Do these need another look?"]),
    Rule(keywords: ["fracture"], title: "Broken bone", tone: .attention,
         summary: "A break in a bone was seen.",
         meaning: "Your doctor will explain whether it is new or old and whether it needs care.",
         questions: ["Is this break new, and does it need treatment?"]),
    Rule(keywords: ["degenerative", "osteophyte", "spondylosis"], title: "Wear and tear", tone: .reassuring,
         summary: "The bones show normal signs of wear with age.",
         meaning: "These changes are very common and often cause no symptoms.",
         questions: ["Could this explain any back pain I have?"]),
  ]

  private static let regionKeywords: [(String, BodyRegion)] = [
    ("lung bases", .rightLungLowerLobe), ("both bases", .rightLungLowerLobe), ("bibasilar", .rightLungLowerLobe),
    ("right upper lobe", .rightLungUpperLobe), ("rul", .rightLungUpperLobe),
    ("right middle lobe", .rightLungLowerLobe), ("right lower lobe", .rightLungLowerLobe), ("rll", .rightLungLowerLobe),
    ("left upper lobe", .leftLungUpperLobe), ("lul", .leftLungUpperLobe), ("lingula", .leftLungUpperLobe),
    ("left lower lobe", .leftLungLowerLobe), ("lll", .leftLungLowerLobe),
    ("abdominal aort", .abdominalAorta), ("infrarenal", .abdominalAorta),
    ("thoracic aort", .thoracicAorta), ("ascending aort", .thoracicAorta), ("aort", .abdominalAorta),
    ("heart", .heart), ("cardiac", .heart), ("pericardi", .heart),
    ("hepatic", .liver), ("liver", .liver), ("gallbladder", .gallbladder), ("cholelith", .gallbladder),
    ("splen", .spleen), ("pancrea", .pancreas),
    ("left renal", .leftKidney), ("left kidney", .leftKidney), ("right renal", .rightKidney), ("right kidney", .rightKidney),
    ("renal", .leftKidney), ("kidney", .leftKidney),
    ("rib", .ribs), ("spine", .spine), ("vertebra", .spine), ("lumbar", .spine), ("thoracic spine", .spine),
    ("pelvi", .pelvis), ("hip", .pelvis), ("iliac", .pelvis),
    ("right lung", .rightLungLowerLobe), ("left lung", .leftLungLowerLobe), ("pleura", .rightLungLowerLobe), ("lung", .rightLungUpperLobe),
    ("pulmonary", .rightLungUpperLobe),
  ]

  static func interpret(text: String, fileName: String?) -> ScanCase {
    let sentences = text
      .replacingOccurrences(of: "\n", with: " ")
      .components(separatedBy: CharacterSet(charactersIn: ".;"))
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { $0.count > 8 }

    var findings: [Finding] = []
    var seen = Set<String>()
    for sentence in sentences {
      let lower = sentence.lowercased()
      if lower.contains("no ") && !lower.contains("nodule") && !lower.contains("stone") && !lower.contains("cyst") && !lower.contains("aneurysm") { continue }
      if lower.hasPrefix("no ") || lower.contains("without evidence") || lower.contains("negative for") { continue }
      guard let rule = rules.first(where: { r in r.keywords.contains(where: { lower.contains($0) }) }) else { continue }
      let region = regionKeywords.first(where: { lower.contains($0.0) })?.1 ?? .unknown
      let key = "\(rule.title)-\(region.rawValue)"
      guard !seen.contains(key) else { continue }
      seen.insert(key)
      let size = sizeMM(in: lower)
      var summary = rule.summary
      if let size { summary += " It measures about \(Self.format(size))." }
      findings.append(Finding(
        title: region == .unknown ? rule.title : "\(rule.title), \(region.displayName.lowercased())",
        clinicalPhrase: sentence,
        region: region,
        sizeMM: size,
        plainSummary: summary,
        whatItMeans: rule.meaning,
        questionsForDoctor: rule.questions,
        tone: rule.tone
      ))
    }

    let summary = findings.isEmpty
      ? "No common findings were recognised in this report. Add a Claude key in Settings for a full explanation."
      : "Your report mentions \(findings.count) thing\(findings.count == 1 ? "" : "s") worth understanding. Each one is pinned on the body below."
    return ScanCase(
      title: fileName.map { ($0 as NSString).deletingPathExtension } ?? "Imported report",
      subtitle: "Read on this device",
      kind: .imported,
      findings: findings,
      plainSummary: summary,
      glossary: Glossary.terms(in: text),
      sourceFileName: fileName,
      interpretedBy: "On-device keyword reader"
    )
  }

  static func sizeMM(in text: String) -> Float? {
    guard let regex = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s*(?:x\s*\d+(?:\.\d+)?\s*)?(mm|cm)\b"#) else { return nil }
    let range = NSRange(text.startIndex..., in: text)
    guard let m = regex.firstMatch(in: text, range: range),
          let numRange = Range(m.range(at: 1), in: text),
          let unitRange = Range(m.range(at: 2), in: text),
          let value = Float(text[numRange]) else { return nil }
    return text[unitRange] == "cm" ? value * 10 : value
  }

  static func format(_ mm: Float) -> String {
    mm >= 20 ? String(format: "%.1f cm", mm / 10) : String(format: "%.0f mm", mm)
  }
}
