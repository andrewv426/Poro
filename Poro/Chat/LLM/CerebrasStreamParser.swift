import Foundation

struct CerebrasStreamParser: Sendable {
  enum Event: Equatable {
    case delta(String)
    case done
    case ignore
  }

  nonisolated init() {}

  nonisolated func parse(line: String) -> Event {
    struct StreamingChatCompletionsResponse: Decodable, Sendable {
      let choices: [Choice]
    }

    struct Choice: Decodable, Sendable {
      let delta: DeltaMessage
    }

    struct DeltaMessage: Decodable, Sendable {
      let content: String?
    }

    guard line.hasPrefix("data:") else {
      return .ignore
    }

    let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)

    if payload.isEmpty {
      return .ignore
    }

    if payload == "[DONE]" {
      return .done
    }

    guard
      let data = payload.data(using: .utf8),
      let chunk = try? JSONDecoder().decode(StreamingChatCompletionsResponse.self, from: data),
      let text = chunk.choices.first?.delta.content,
      !text.isEmpty
    else {
      return .ignore
    }

    return .delta(text)
  }
}
