import Foundation

/// System prompts for Claude.
enum Prompts {
  static let patientVoice = """
  You explain medical imaging to patients in plain words at an 8th-grade reading level. \
  You never diagnose, never give treatment advice, and never predict outcomes. You say what the report says, \
  what that kind of finding usually means in general, and what the patient could ask their doctor. \
  Gloss any medical word the first time you use it. Keep a calm, warm tone. \
  The viewer shows the body as seven layers: skin, fat, muscle, bone, lungs, organs, and blood.
  """

  static let reportSystem = patientVoice + """

  You will receive the text of a radiology report. Extract every finding the radiologist mentions, \
  including normal-variant and incidental ones only if they are named as findings. \
  Map each finding to the closest body region from the allowed list. \
  Put measurements in millimetres (convert centimetres). Choose tone "reassuring" for things usually harmless, \
  "routine" for things usually watched, and "attention" for things the report says need prompt follow-up. \
  List medical words from the report with plain meanings in the glossary.
  """

  static func ask(question: String, finding: Finding) -> String {
    """
    The report says: "\(finding.clinicalPhrase)" (\(finding.region.displayName)).
    The patient asks: \(question)
    Answer in 3 to 5 short sentences.
    """
  }

  static let reportSchema: [String: Any] = {
    let regions = BodyRegion.allCases.map(\.rawValue)
    let finding: [String: Any] = [
      "type": "object",
      "additionalProperties": false,
      "required": ["title", "clinical_phrase", "region", "size_mm", "plain_summary", "what_it_means", "questions_for_doctor", "tone"],
      "properties": [
        "title": ["type": "string", "description": "2-3 plain words, e.g. 'Lung nodule'"],
        "clinical_phrase": ["type": "string", "description": "the report's own wording, shortened"],
        "region": ["type": "string", "enum": regions],
        "size_mm": ["anyOf": [["type": "number"], ["type": "null"]]],
        "plain_summary": ["type": "string", "description": "one sentence, with an everyday size comparison when a size is given"],
        "what_it_means": ["type": "string", "description": "2-4 sentences, general information, non-diagnostic"],
        "questions_for_doctor": ["type": "array", "items": ["type": "string"]],
        "tone": ["type": "string", "enum": ["reassuring", "routine", "attention"]],
      ],
    ]
    return [
      "type": "object",
      "additionalProperties": false,
      "required": ["title", "plain_summary", "findings", "glossary"],
      "properties": [
        "title": ["type": "string", "description": "e.g. 'CT of the chest, Sept 2026'"],
        "plain_summary": ["type": "string", "description": "2-3 sentences"],
        "findings": ["type": "array", "items": finding],
        "glossary": [
          "type": "array",
          "items": [
            "type": "object",
            "additionalProperties": false,
            "required": ["term", "meaning"],
            "properties": ["term": ["type": "string"], "meaning": ["type": "string"]],
          ],
        ],
      ],
    ]
  }()
}
