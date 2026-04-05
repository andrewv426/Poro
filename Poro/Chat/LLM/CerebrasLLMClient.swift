import Foundation

struct CerebrasLLMClient: LLMClient {
  let configuration: LLMConfiguration
  private let session: URLSession

  init(configuration: LLMConfiguration, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
  }

  func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor (String) -> Void
  ) async throws {
    let requestURL = configuration.baseURL.appendingPathComponent("chat/completions")
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

    if let versionPatch = configuration.versionPatch {
      request.setValue(versionPatch, forHTTPHeaderField: "X-Cerebras-Version-Patch")
    }

    let requestBody = ChatCompletionsRequest(
      model: configuration.model,
      messages: messages.map(RequestMessage.init),
      stream: true
    )
    request.httpBody = try JSONEncoder().encode(requestBody)

    let bytes: URLSession.AsyncBytes
    let response: URLResponse

    do {
      (bytes, response) = try await session.bytes(for: request)
    } catch {
      let urlError = error as? URLError
      throw LLMError.networkFailure(
        description: error.localizedDescription,
        code: urlError?.errorCode,
        url: requestURL.absoluteString
      )
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let responseBody = try await collectResponseBody(from: bytes)
      let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: responseBody)
      throw LLMError.unexpectedStatusCode(httpResponse.statusCode, errorResponse?.error.message)
    }

    for try await line in bytes.lines {
      guard line.hasPrefix("data: ") else {
        continue
      }

      let payload = String(line.dropFirst(6))

      if payload == "[DONE]" {
        return
      }

      guard let payloadData = payload.data(using: .utf8) else {
        continue
      }

      let chunk: StreamingChatCompletionsResponse

      do {
        chunk = try JSONDecoder().decode(StreamingChatCompletionsResponse.self, from: payloadData)
      } catch {
        continue
      }

      guard let deltaText = chunk.choices.first?.delta.content, !deltaText.isEmpty else {
        continue
      }

      await onDelta(deltaText)
    }

    throw LLMError.emptyResponse
  }

  private func collectResponseBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()

    for try await byte in bytes {
      data.append(byte)
    }

    return data
  }
}

extension CerebrasLLMClient {
  fileprivate struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
    let stream: Bool
  }

  fileprivate struct RequestMessage: Encodable {
    let role: String
    let content: String

    init(message: ChatMessage) {
      self.role = message.role.apiValue
      self.content = message.text
    }
  }

  fileprivate struct StreamingChatCompletionsResponse: Decodable {
    let choices: [Choice]
  }

  fileprivate struct Choice: Decodable {
    let delta: DeltaMessage
  }

  fileprivate struct DeltaMessage: Decodable {
    let content: String?
  }

  fileprivate struct ErrorResponse: Decodable {
    let error: APIError
  }

  fileprivate struct APIError: Decodable {
    let message: String?
  }
}

extension ChatMessage.Role {
  fileprivate var apiValue: String {
    switch self {
    case .user:
      return "user"
    case .assistant:
      return "assistant"
    }
  }
}
