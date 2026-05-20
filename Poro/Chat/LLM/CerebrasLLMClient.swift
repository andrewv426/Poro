import Foundation

/// A client for interacting with the Cerebras LLM API, supporting streaming and eager context injection.
struct CerebrasLLMClient: LLMClient {
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

  /// Streams a completion from the LLM. If a toolbox is available and the query warrants context,
  /// relevant system state is eagerly injected into the system prompt.
  /// - Parameters:
  ///   - messages: The conversation history.
  ///   - onDelta: A callback invoked on the main thread whenever a new text delta is received.
  nonisolated func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    var systemPrompt = baseSystemPrompt

    // Eagerly fetch and inject context if tools are offered for this turn.
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

  private var baseSystemPrompt: String {
    """
    You are Poro, a macOS assistant that is actively backed by an LLM.
    The chat completion provider is Cerebras.
    The configured model for this request is \(configuration.model).
    If the user asks whether you are running an LLM or what model you use, answer directly using this information.
    """
  }

  /// Performs a standard streaming chat completion.
  /// - Parameters:
  ///   - messages: The conversation history.
  ///   - systemPrompt: Optional system prompt to prepend (may contain injected context).
  ///   - onDelta: Callback for text deltas.
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

    let parser = CerebrasStreamParser()

    for try await line in bytes.lines {
      try Task.checkCancellation()

      switch parser.parse(line: line) {
      case .ignore:
        continue
      case .done:
        return
      case let .delta(deltaText):
        await MainActor.run {
          onDelta(deltaText)
        }
      }
    }

    throw LLMError.emptyResponse
  }

  /// Constructs a URLRequest for the Cerebras API.
  /// - Parameter body: The encodable request body.
  /// - Returns: A configured URLRequest.
  private func makeRequest(body: some Encodable) throws -> URLRequest {
    let requestURL = configuration.baseURL.appendingPathComponent("chat/completions")
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

    if let versionPatch = configuration.versionPatch {
      request.setValue(versionPatch, forHTTPHeaderField: "X-Cerebras-Version-Patch")
    }

    request.httpBody = try JSONEncoder().encode(body)
    return request
  }

  /// Maps internal ChatMessage models to API-compatible RequestMessage models.
  /// - Parameters:
  ///   - messages: Internal message list.
  ///   - systemPrompt: Optional system prompt text.
  /// - Returns: A list of RequestMessage objects.
  private func makeRequestMessages(
    from messages: [ChatMessage],
    systemPrompt: String? = nil
  ) -> [RequestMessage] {
    var requestMessages = [RequestMessage]()

    if let systemPrompt, !systemPrompt.isEmpty {
      requestMessages.append(
        RequestMessage(
          role: "system",
          content: systemPrompt,
          tool_call_id: nil,
          tool_calls: nil
        )
      )
    }

    requestMessages.append(
      contentsOf: messages.map { message in
        RequestMessage(
          role: message.role == .user ? "user" : "assistant",
          content: message.text,
          tool_call_id: nil,
          tool_calls: nil
        )
      }
    )

    return requestMessages
  }

  /// Collects all bytes from an AsyncBytes stream into a single Data object.
  /// - Parameter bytes: The byte stream.
  /// - Returns: The fully collected data.
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
  let content: String?
  let tool_call_id: String?
  let tool_calls: [ResponseToolCall]?
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
