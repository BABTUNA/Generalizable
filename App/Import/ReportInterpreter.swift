import Foundation

/// Turns report text into a case: Claude when a key is set, otherwise the on-device keyword reader.
enum ReportInterpreter {
  private struct Payload: Decodable {
    struct Item: Decodable {
      var title: String
      var clinical_phrase: String
      var region: String
      var size_mm: Float?
      var plain_summary: String
      var what_it_means: String
      var questions_for_doctor: [String]
      var tone: String
    }

    var title: String
    var plain_summary: String
    var findings: [Item]
    var glossary: [GlossaryTerm]
  }

  static func interpret(text: String, fileName: String?, model: ClaudeModel) async -> (ScanCase, String?) {
    guard let key = APIKeyStore.shared.read() else {
      return (OfflineReportInterpreter.interpret(text: text, fileName: fileName), nil)
    }
    do {
      let client = AnthropicClient(apiKey: key, model: model)
      let data = try await client.structured(
        system: Prompts.reportSystem,
        userContent: [["type": "text", "text": "Radiology report:\n\n\(text.prefix(60_000))"]],
        schema: Prompts.reportSchema
      )
      let payload = try JSONDecoder().decode(Payload.self, from: data)
      let findings = payload.findings.map { item in
        Finding(
          title: item.title,
          clinicalPhrase: item.clinical_phrase,
          region: BodyRegion(rawValue: item.region) ?? .unknown,
          sizeMM: item.size_mm,
          plainSummary: item.plain_summary,
          whatItMeans: item.what_it_means,
          questionsForDoctor: item.questions_for_doctor,
          tone: Finding.Tone(rawValue: item.tone) ?? .routine
        )
      }
      let scanCase = ScanCase(
        title: payload.title,
        subtitle: "Explained by Claude",
        kind: .imported,
        findings: findings,
        plainSummary: payload.plain_summary,
        glossary: payload.glossary,
        sourceFileName: fileName,
        interpretedBy: "Claude \(model.displayName)"
      )
      return (scanCase, nil)
    } catch {
      let fallback = OfflineReportInterpreter.interpret(text: text, fileName: fileName)
      return (fallback, "Claude wasn't reachable (\(error.localizedDescription)). Read on this device instead.")
    }
  }
}
