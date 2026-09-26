import Foundation

/// Errors from the Claude client. Kinds mirror ClaudeForFoundationModels Sources/ClaudeAPI/APIError.swift.
enum AnthropicError: LocalizedError {
  case missingKey
  case http(status: Int, type: String?, message: String?)
  case refused
  case truncated
  case badResponse

  var errorDescription: String? {
    switch self {
    case .missingKey: "Add an Anthropic API key in Settings to use Claude."
    case .http(let status, _, let message): message ?? "Claude returned an error (\(status))."
    case .refused: "Claude declined to answer this one."
    case .truncated: "The answer was cut off. Try again."
    case .badResponse: "Claude's answer couldn't be read."
    }
  }
}
