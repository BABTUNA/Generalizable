import Foundation

/// A medical word and its plain meaning.
struct GlossaryTerm: Codable, Equatable, Hashable, Identifiable {
  var term: String
  var meaning: String
  var id: String { term.lowercased() }
}
