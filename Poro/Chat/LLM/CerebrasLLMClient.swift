import Foundation

struct CerebrasLLMClient: LLMClient {
  let configuration: LLMConfiguration
  private let session: URLSession

  init(configuration: LLMConfiguration, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
  }

  func complete(messages: [ChatMessage]) async throws -> String {
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
      messages: messages.map(RequestMessage.init)
    )
    request.httpBody = try JSONEncoder().encode(requestBody)

    let data: Data
    let response: URLResponse

    do {
      (data, response) = try await session.data(for: request)
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
      let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
      throw LLMError.unexpectedStatusCode(httpResponse.statusCode, errorResponse?.error.message)
    }

    let completionResponse: ChatCompletionsResponse

    do {
      completionResponse = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
    } catch {
      throw LLMError.invalidResponse
    }

    guard let content = completionResponse.choices.first?.message.content.textValue,
      !content.isEmpty
    else {
      throw LLMError.emptyResponse
    }

    return content
  }
}

extension CerebrasLLMClient {
  fileprivate struct ChatCompletionsRequest: Encodable {
    let model: String
    let messages: [RequestMessage]
  }

  fileprivate struct RequestMessage: Encodable {
    let role: String
    let content: String

    init(message: ChatMessage) {
      self.role = message.role.apiValue
      self.content = message.text
    }
  }

  fileprivate struct ChatCompletionsResponse: Decodable {
    let choices: [Choice]
  }

  fileprivate struct Choice: Decodable {
    let message: ResponseMessage
  }

  fileprivate struct ResponseMessage: Decodable {
    let content: MessageContent
  }

  fileprivate struct TextContentPart: Decodable {
    let text: String
  }

  fileprivate enum MessageContent: Decodable {
    case text(String)
    case parts([TextContentPart])
    case empty

    var textValue: String? {
      switch self {
      case .text(let text):
        return text
      case .parts(let parts):
        let joined = parts.map(\.text).joined()
        return joined.isEmpty ? nil : joined
      case .empty:
        return nil
      }
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.singleValueContainer()

      if container.decodeNil() {
        self = .empty
        return
      }

      if let text = try? container.decode(String.self) {
        self = .text(text)
        return
      }

      if let parts = try? container.decode([TextContentPart].self) {
        self = .parts(parts)
        return
      }

      throw DecodingError.typeMismatch(
        MessageContent.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unsupported message content type."
        )
      )
    }
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
