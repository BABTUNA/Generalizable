import Foundation

/// A set of findings shown on the body. The sample case ships with the app; imported cases come from a patient's report.
struct ScanCase: Identifiable, Codable, Equatable, Hashable {
  enum Kind: String, Codable {
    case sample, imported
  }

  var id: UUID = UUID()
  var title: String
  var subtitle: String
  var kind: Kind
  var findings: [Finding]
  var plainSummary: String
  var glossary: [GlossaryTerm] = []
  var createdAt: Date = .now
  var sourceFileName: String?
  var interpretedBy: String?
}
