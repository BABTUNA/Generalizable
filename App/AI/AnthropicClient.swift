import Foundation

/// A small Messages API client over URLSession.
/// Request shape and error handling follow Anthropic's own Swift client, ClaudeForFoundationModels
/// (Sources/ClaudeAPI/ClaudeClient.swift). Guaranteed JSON uses `output_config.format` like its RequestBuilder.
/// Streaming reads `data:` lines from URLSession.bytes like jamesrochabrun/SwiftAnthropic AnthropicService.fetchStream.
struct AnthropicClient {
  var apiKey: String
  var model: ClaudeModel
  var session: URLSession = .shared

  private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

  private func request(body: [String: Any]) throws -> URLRequest {
    var r = URLRequest(url: endpoint)
    r.httpMethod = "POST"
    r.timeoutInterval = 600
    r.setValue("application/json", forHTTPHeaderField: "content-type")
    r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    r.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    r.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    return r
  }

  private static func apiError(status: Int, data: Data) -> AnthropicError {
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    let err = json?["error"] as? [String: Any]
    return .http(status: status, type: err?["type"] as? String, message: err?["message"] as? String)
  }

  /// Returns schema-valid JSON text from `content[0].text`.
  func structured(system: String, userContent: [[String: Any]], schema: [String: Any]) async throws -> Data {
    let body: [String: Any] = [
      "model": model.rawValue,
      "max_tokens": 16000,
      "system": system,
      "messages": [["role": "user", "content": userContent]],
      "output_config": [
        "effort": "medium",
        "format": ["type": "json_schema", "schema": schema],
      ],
    ]
    let (data, response) = try await session.data(for: request(body: body))
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard status < 400 else { throw Self.apiError(status: status, data: data) }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AnthropicError.badResponse }
    switch json["stop_reason"] as? String {
    case "refusal": throw AnthropicError.refused
    case "max_tokens": throw AnthropicError.truncated
    default: break
    }
    let content = json["content"] as? [[String: Any]] ?? []
    guard let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String else {
      throw AnthropicError.badResponse
    }
    return Data(text.utf8)
  }

  /// Streams cumulative text snapshots.
  func streamText(system: String, user: String) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 8192,
            "stream": true,
            "system": system,
            "messages": [["role": "user", "content": user]],
            "output_config": ["effort": "low"],
          ]
          let (bytes, response) = try await session.bytes(for: request(body: body))
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          if status >= 400 {
            var data = Data()
            for try await b in bytes { data.append(b) }
            throw Self.apiError(status: status, data: data)
          }
          var text = ""
          for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { continue }
            switch obj["type"] as? String {
            case "content_block_delta":
              if let delta = obj["delta"] as? [String: Any], delta["type"] as? String == "text_delta", let t = delta["text"] as? String {
                text += t
                continuation.yield(text)
              }
            case "message_delta":
              if let delta = obj["delta"] as? [String: Any], delta["stop_reason"] as? String == "refusal" {
                throw AnthropicError.refused
              }
            case "error":
              let err = obj["error"] as? [String: Any]
              throw AnthropicError.http(status: 200, type: err?["type"] as? String, message: err?["message"] as? String)
            default:
              break
            }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
