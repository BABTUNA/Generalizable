import Foundation
import FoundationModels
import Observation

/// Streams an answer to a patient's question about a finding.
/// Uses Claude when a key is saved, then Apple's on-device model, then says how to enable answers.
/// The streaming view-model shape follows SwiftAnthropic's Examples/.../MessageDemoObservable.swift.
@MainActor
@Observable
final class AskModel {
  var question = ""
  var answer = ""
  var source: String?
  var isStreaming = false
  var errorMessage: String?
  private var task: Task<Void, Never>?

  func ask(about finding: Finding, model: ClaudeModel) {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return }
    task?.cancel()
    answer = ""
    errorMessage = nil
    let prompt = Prompts.ask(question: q, finding: finding)
    task = Task {
      isStreaming = true
      defer { isStreaming = false }
      do {
        if let key = APIKeyStore.shared.read() {
          source = "Claude"
          for try await snapshot in AnthropicClient(apiKey: key, model: model).streamText(system: Prompts.patientVoice, user: prompt) {
            answer = snapshot
          }
        } else if case .available = SystemLanguageModel.default.availability {
          source = "On-device"
          let session = LanguageModelSession(instructions: Prompts.patientVoice)
          for try await snapshot in session.streamResponse(to: prompt) {
            answer = snapshot.content
          }
        } else {
          source = nil
          errorMessage = "Add an Anthropic API key in Settings to ask questions."
        }
      } catch is CancellationError {
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  func cancel() {
    task?.cancel()
  }
}
