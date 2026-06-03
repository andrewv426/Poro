import Foundation

/// Streaming chat client for OpenRouter (OpenAI-compatible). Supports multimodal user messages:
/// any `ChatMessage` carrying images is encoded with the OpenAI `image_url` content-part format so
/// a vision model can see them. When a toolbox is available and the query warrants it, relevant
/// system state is eagerly injected into the system prompt.
struct OpenRouterLLMClient: LLMClient {
  let configuration: LLMConfiguration
  private let session: URLSession
  private let toolbox: (any AssistantToolbox)?

  init(
    configuration: LLMConfiguration,
    session: URLSession = .shared,
    toolbox: (any AssistantToolbox)? = nil
  ) {
    self.configuration = configuration
    self.session = session
    self.toolbox = toolbox
  }

  /// Streams a completion. If a toolbox is available and the query warrants context, relevant
  /// system state is eagerly injected into the system prompt.
  /// - Parameters:
  ///   - messages: The conversation history (user messages may carry images).
  ///   - onDelta: A callback invoked on the main thread whenever a new text delta is received.
  nonisolated func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    var systemPrompt = baseSystemPrompt

    if let toolbox {
      var toolboxPrompt = toolbox.systemPrompt

      if await toolbox.shouldOfferTools(for: messages) {
        let context = await toolbox.fetchAllContext()
        toolboxPrompt = toolboxPrompt.replacingOccurrences(of: "{{CONTEXT}}", with: context)

        await toolbox.recordToolEvent(
          phase: "eager_context_injected",
          toolName: nil,
          detail: "Context size: \(context.count) chars"
        )
      }

      systemPrompt += "\n\n" + toolboxPrompt
    }

    try await streamPlainCompletion(
      messages: messages,
      systemPrompt: systemPrompt,
      onDelta: onDelta
    )
  }

  /// Pre-opens the pooled TLS connection so the user's first prompt skips the DNS/TCP/TLS handshake.
  /// Uses a cheap authenticated `GET /key` (account metadata, not an inference call, so it doesn't
  /// consume the model quota). Best-effort: every error is ignored.
  nonisolated func warmUp() async {
    let url = configuration.baseURL.appendingPathComponent("key")
    var request = URLRequest(url: url)
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    _ = try? await session.data(for: request)
  }

  private var baseSystemPrompt: String {
    """
    You are Poro, a macOS assistant that is actively backed by an LLM.
    The chat completion provider is OpenRouter.
    The configured model for this request is \(configuration.model).
    You can see images the user attaches to a message — read them and answer questions about them.
    If the user asks whether you are running an LLM or what model you use, answer directly using this information.
    """
  }

  private func streamPlainCompletion(
    messages: [ChatMessage],
    systemPrompt: String? = nil,
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    let requestMessages = makeRequestMessages(from: messages, systemPrompt: systemPrompt)
    let requestBody = StreamChatCompletionsRequest(
      model: configuration.model,
      messages: requestMessages,
      stream: true
    )
    let request = try makeRequest(body: requestBody)

    let bytes: URLSession.AsyncBytes
    let response: URLResponse

    do {
      (bytes, response) = try await session.bytes(for: request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      let urlError = error as? URLError
      if urlError?.code == .cancelled { throw CancellationError() }

      throw LLMError.networkFailure(
        description: error.localizedDescription,
        code: urlError?.errorCode,
        url: request.url?.absoluteString
      )
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMError.invalidResponse
    }

    guard (200 ... 299).contains(httpResponse.statusCode) else {
      let responseBody = try await collectResponseBody(from: bytes)
      let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: responseBody)
      throw LLMError.unexpectedStatusCode(httpResponse.statusCode, errorResponse?.error.message)
    }

    let parser = OpenAISSEStreamParser()
    var receivedDelta = false

    for try await line in bytes.lines {
      try Task.checkCancellation()

      switch parser.parse(line: line) {
      case .ignore:
        continue
      case .done:
        return
      case let .delta(deltaText):
        receivedDelta = true
        await MainActor.run {
          onDelta(deltaText)
        }
      }
    }

    // The stream can end without an explicit `[DONE]` (provider disconnect, proxy truncation).
    // If content was already delivered, treat that as a successful completion, not an error.
    guard receivedDelta else {
      throw LLMError.emptyResponse
    }
  }

  private func makeRequest(body: some Encodable) throws -> URLRequest {
    let requestURL = configuration.baseURL.appendingPathComponent("chat/completions")
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    // Optional OpenRouter attribution headers (harmless if the route ignores them).
    request.setValue("Poro", forHTTPHeaderField: "X-Title")

    request.httpBody = try JSONEncoder().encode(body)
    return request
  }

  /// Maps internal `ChatMessage` models to API messages. Text-only messages encode `content` as a
  /// plain string; messages with images encode `content` as an array of typed parts.
  private func makeRequestMessages(
    from messages: [ChatMessage],
    systemPrompt: String? = nil
  ) -> [RequestMessage] {
    var requestMessages = [RequestMessage]()

    if let systemPrompt, !systemPrompt.isEmpty {
      requestMessages.append(RequestMessage(role: "system", content: .text(systemPrompt)))
    }

    for message in messages {
      let role = message.role == .user ? "user" : "assistant"

      if message.images.isEmpty {
        requestMessages.append(RequestMessage(role: role, content: .text(message.text)))
      } else {
        var parts = [ContentPart]()
        if !message.text.isEmpty {
          parts.append(ContentPart(text: message.text))
        }
        for image in message.images {
          parts.append(ContentPart(imageURL: image.dataURL))
        }
        requestMessages.append(RequestMessage(role: role, content: .multipart(parts)))
      }
    }

    return requestMessages
  }

  private func collectResponseBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
    }
    return data
  }
}

// MARK: - Internal API Request Models

private struct RequestMessage: Encodable {
  let role: String
  let content: MessageContent
}

/// OpenAI/OpenRouter message content: either a bare string, or an array of typed parts (used when
/// the message carries images).
private enum MessageContent: Encodable {
  case text(String)
  case multipart([ContentPart])

  func encode(to encoder: Encoder) throws {
    switch self {
    case let .text(string):
      var container = encoder.singleValueContainer()
      try container.encode(string)
    case let .multipart(parts):
      var container = encoder.unkeyedContainer()
      for part in parts {
        try container.encode(part)
      }
    }
  }
}

/// A single content part. Optional fields are omitted from JSON when nil (synthesized
/// `encodeIfPresent`), so a text part emits only `{type,text}` and an image part only
/// `{type,image_url}`.
private struct ContentPart: Encodable {
  let type: String
  let text: String?
  let imageURL: ImageURL?

  enum CodingKeys: String, CodingKey {
    case type
    case text
    case imageURL = "image_url"
  }

  init(text: String) {
    type = "text"
    self.text = text
    imageURL = nil
  }

  init(imageURL url: String) {
    type = "image_url"
    text = nil
    imageURL = ImageURL(url: url)
  }
}

private struct ImageURL: Encodable {
  let url: String
}

private struct StreamChatCompletionsRequest: Encodable {
  let model: String
  let messages: [RequestMessage]
  let stream: Bool
}

private struct ErrorResponse: Decodable {
  let error: APIError
}

private struct APIError: Decodable {
  let message: String?
}
