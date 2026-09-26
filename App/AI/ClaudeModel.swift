import Foundation

/// Claude models the app can use for explanations.
enum ClaudeModel: String, CaseIterable, Codable, Identifiable {
  case opus = "claude-opus-5-5"
  case sonnet = "claude-sonnet-5"
  case fable = "claude-fable-5-1"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .opus: "Opus 5.5"
    case .sonnet: "Sonnet 5 (faster)"
    case .fable: "Fable 5.1 (most capable)"
    }
  }
}
