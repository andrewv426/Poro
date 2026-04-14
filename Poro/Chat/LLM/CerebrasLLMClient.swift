import Foundation

struct CerebrasLLMClient: LLMClient, Sendable {
  let configuration: LLMConfiguration
  private let session: URLSession

  init(configuration: LLMConfiguration, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
  }

  nonisolated func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    struct RequestMessage: Encodable, Sendable {
      let role: String
      let content: String
    }

    struct ChatCompletionsRequest: Encodable, Sendable {
      let model: String
      let messages: [RequestMessage]
      let stream: Bool
    }

    struct ErrorResponse: Decodable, Sendable {
      let error: APIError
    }

    struct APIError: Decodable, Sendable {
      let message: String?
    }

    let requestURL = configuration.baseURL.appendingPathComponent("chat/completions")
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

    if let versionPatch = configuration.versionPatch {
      request.setValue(versionPatch, forHTTPHeaderField: "X-Cerebras-Version-Patch")
    }

    let requestMessages = messages.map { message in
      let role: String

      switch message.role {
      case .user:
        role = "user"
      case .assistant:
        role = "assistant"
      }

      return RequestMessage(
        role: role,
        content: message.text
      )
    }
    let requestBody = ChatCompletionsRequest(
      model: configuration.model,
      messages: requestMessages,
      stream: true
    )
    request.httpBody = try JSONEncoder().encode(requestBody)

    let bytes: URLSession.AsyncBytes
    let response: URLResponse

    do {
      (bytes, response) = try await session.bytes(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let urlError = error as? URLError

      if urlError?.code == .cancelled {
        throw CancellationError()
      }

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

    let parser = CerebrasStreamParser()

    for try await line in bytes.lines {
      try Task.checkCancellation()

      switch parser.parse(line: line) {
      case .ignore:
        continue
      case .done:
        return
      case .delta(let deltaText):
        await MainActor.run {
          onDelta(deltaText)
        }
      }
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
