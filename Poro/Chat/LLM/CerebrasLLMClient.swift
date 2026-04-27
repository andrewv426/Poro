import Foundation

struct CerebrasLLMClient: LLMClient, Sendable {
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

  nonisolated func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    if let toolbox, await toolbox.shouldOfferTools(for: messages) {
      let latestUserMessage = messages.reversed().first { message in
        if case .user = message.role {
          return true
        }

        return false
      }?.text ?? ""

      await toolbox.recordToolEvent(
        phase: "tool_mode_selected",
        toolName: nil,
        detail: latestUserMessage
      )
      try await completeWithTools(messages: messages, toolbox: toolbox, onDelta: onDelta)
      return
    }

    try await streamPlainCompletion(
      messages: messages,
      systemPrompt: toolbox?.systemPrompt,
      onDelta: onDelta
    )
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

      if urlError?.code == .cancelled {
        throw CancellationError()
      }

      throw LLMError.networkFailure(
        description: error.localizedDescription,
        code: urlError?.errorCode,
        url: request.url?.absoluteString
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

  private func completeWithTools(
    messages: [ChatMessage],
    toolbox: any AssistantToolbox,
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    var requestMessages = makeRequestMessages(from: messages, systemPrompt: toolbox.systemPrompt)
    var iterationCount = 0

    while iterationCount < 6 {
      iterationCount += 1

      let response = try await complete(messages: requestMessages, toolDefinitions: toolbox.toolDefinitions)

      guard let assistantMessage = response.choices.first?.message else {
        throw LLMError.emptyResponse
      }

      if let toolCalls = assistantMessage.toolCalls, !toolCalls.isEmpty {
        await toolbox.recordToolEvent(
          phase: "structured_tool_calls_received",
          toolName: toolCalls.map(\.function.name).joined(separator: ", "),
          detail: assistantMessage.content ?? ""
        )
        try await appendToolRound(
          toolCalls: toolCalls,
          assistantContent: assistantMessage.content,
          toolbox: toolbox,
          requestMessages: &requestMessages
        )

        continue
      }

      if
        let content = assistantMessage.content,
        let pseudoToolCall = parsePseudoToolCall(from: content, validToolNames: toolbox.toolDefinitions.map(\.name))
      {
        await toolbox.recordToolEvent(
          phase: "pseudo_tool_call_fallback",
          toolName: pseudoToolCall.function.name,
          detail: content
        )
        try await appendToolRound(
          toolCalls: [pseudoToolCall],
          assistantContent: nil,
          toolbox: toolbox,
          requestMessages: &requestMessages
        )
        continue
      }

      if let content = assistantMessage.content?.trimmingCharacters(in: .whitespacesAndNewlines),
        !content.isEmpty
      {
        await toolbox.recordToolEvent(
          phase: "assistant_final_response",
          toolName: nil,
          detail: content
        )
        await MainActor.run {
          onDelta(content)
        }
        return
      }

      throw LLMError.emptyResponse
    }

    throw LLMError.toolExecutionFailure("Too many consecutive tool rounds.")
  }

  private func appendToolRound(
    toolCalls: [ResponseToolCall],
    assistantContent: String?,
    toolbox: any AssistantToolbox,
    requestMessages: inout [RequestMessage]
  ) async throws {
    requestMessages.append(
      RequestMessage(
        role: "assistant",
        content: assistantContent,
        toolCallID: nil,
        toolCalls: toolCalls
      )
    )

    for toolCall in toolCalls {
      let result = try await toolbox.executeTool(
        named: toolCall.function.name,
        argumentsJSON: toolCall.function.arguments
      )

      requestMessages.append(
        RequestMessage(
          role: "tool",
          content: result,
          toolCallID: toolCall.id,
          toolCalls: nil
        )
      )
    }
  }

  private func complete(
    messages: [RequestMessage],
    toolDefinitions: [AssistantToolDefinition]
  ) async throws -> ChatCompletionsResponse {
    let requestBody = ToolChatCompletionsRequest(
      model: configuration.model,
      messages: messages,
      tools: toolDefinitions.map { ToolDefinition(definition: $0) },
      toolChoice: "auto"
    )
    let request = try makeRequest(body: requestBody)

    let data: Data
    let response: URLResponse

    do {
      (data, response) = try await session.data(for: request)
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
        url: request.url?.absoluteString
      )
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMError.invalidResponse
    }

    guard (200...299).contains(httpResponse.statusCode) else {
      let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
      throw LLMError.unexpectedStatusCode(httpResponse.statusCode, errorResponse?.error.message)
    }

    return try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
  }

  private func makeRequest<T: Encodable>(body: T) throws -> URLRequest {
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
          toolCallID: nil,
          toolCalls: nil
        )
      )
    }

    requestMessages.append(
      contentsOf: messages.map { message in
        RequestMessage(
          role: message.role == .user ? "user" : "assistant",
          content: message.text,
          toolCallID: nil,
          toolCalls: nil
        )
      }
    )

    return requestMessages
  }

  private func collectResponseBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
    var data = Data()

    for try await byte in bytes {
      data.append(byte)
    }

    return data
  }

  private func parsePseudoToolCall(
    from content: String,
    validToolNames: [String]
  ) -> ResponseToolCall? {
    let normalizedContent = normalizedToolCallContent(from: content)
    let loweredContent = normalizedContent.lowercased()

    if
      let jsonToolCall = parseJSONToolCall(
        from: normalizedContent,
        validToolNames: validToolNames
      )
    {
      return jsonToolCall
    }

    guard loweredContent.contains("function") || loweredContent.contains("tool") else {
      return nil
    }

    guard
      let matchedToolName = validToolNames.first(where: { loweredContent.contains($0.lowercased()) })
    else {
      return nil
    }

    let arguments: String

    if
      let parametersRange = loweredContent.range(of: "parameters"),
      let jsonStart = normalizedContent[parametersRange.upperBound...].firstIndex(of: "{"),
      let jsonEnd = normalizedContent[jsonStart...].lastIndex(of: "}")
    {
      arguments = String(normalizedContent[jsonStart...jsonEnd])
    } else {
      arguments = "{}"
    }

    return ResponseToolCall(
      id: UUID().uuidString,
      type: "function",
      function: .init(name: matchedToolName, arguments: arguments)
    )
  }

  private func normalizedToolCallContent(from content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
      return trimmed
    }

    let lines = trimmed.components(separatedBy: .newlines)

    guard lines.count >= 3 else {
      return trimmed
    }

    return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(
      in: .whitespacesAndNewlines
    )
  }

  private func parseJSONToolCall(
    from content: String,
    validToolNames: [String]
  ) -> ResponseToolCall? {
    guard let data = content.data(using: .utf8) else {
      return nil
    }

    guard
      let jsonObject = try? JSONSerialization.jsonObject(with: data),
      let dictionary = jsonObject as? [String: Any]
    else {
      return nil
    }

    let name = (dictionary["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let name, validToolNames.contains(name) else {
      return nil
    }

    let argumentsObject = dictionary["arguments"] ?? [:]
    guard JSONSerialization.isValidJSONObject(argumentsObject) else {
      return nil
    }

    guard
      let argumentsData = try? JSONSerialization.data(withJSONObject: argumentsObject),
      let arguments = String(data: argumentsData, encoding: .utf8)
    else {
      return nil
    }

    return ResponseToolCall(
      id: UUID().uuidString,
      type: "function",
      function: .init(name: name, arguments: arguments)
    )
  }
}

private struct RequestMessage: Encodable, Sendable {
  let role: String
  let content: String?
  let toolCallID: String?
  let toolCalls: [ResponseToolCall]?

  enum CodingKeys: String, CodingKey {
    case role
    case content
    case toolCallID = "tool_call_id"
    case toolCalls = "tool_calls"
  }
}

private struct StreamChatCompletionsRequest: Encodable, Sendable {
  let model: String
  let messages: [RequestMessage]
  let stream: Bool
}

private struct ToolChatCompletionsRequest: Encodable, Sendable {
  let model: String
  let messages: [RequestMessage]
  let tools: [ToolDefinition]
  let toolChoice: String

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case tools
    case toolChoice = "tool_choice"
  }
}

private struct ToolDefinition: Encodable, Sendable {
  struct FunctionDefinition: Encodable, Sendable {
    struct Parameters: Encodable, Sendable {
      let type = "object"
      let properties = [String: ParameterProperty]()
      let required = [String]()
      let additionalProperties = false
    }

    struct ParameterProperty: Encodable, Sendable {}

    let name: String
    let description: String
    let parameters = Parameters()
  }

  let type = "function"
  let function: FunctionDefinition

  init(definition: AssistantToolDefinition) {
    self.function = FunctionDefinition(
      name: definition.name,
      description: definition.description
    )
  }
}

private struct ChatCompletionsResponse: Decodable, Sendable {
  struct Choice: Decodable, Sendable {
    let message: ResponseMessage
  }

  let choices: [Choice]
}

private struct ResponseMessage: Decodable, Sendable {
  let content: String?
  let toolCalls: [ResponseToolCall]?

  enum CodingKeys: String, CodingKey {
    case content
    case toolCalls = "tool_calls"
  }
}

private struct ResponseToolCall: Codable, Sendable {
  struct Function: Codable, Sendable {
    let name: String
    let arguments: String
  }

  let id: String
  let type: String
  let function: Function
}

private struct ErrorResponse: Decodable, Sendable {
  let error: APIError
}

private struct APIError: Decodable, Sendable {
  let message: String?
}
