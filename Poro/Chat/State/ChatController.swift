import Foundation
import Observation

@Observable
@MainActor
final class ChatController {
  enum RequestState {
    case idle
    case sending
    case failed(String)
  }

  let session: ChatSession
  private(set) var requestState: RequestState = .idle
  private let llmClient: LLMClient

  init(session: ChatSession, llmClient: LLMClient) {
    self.session = session
    self.llmClient = llmClient
  }

  convenience init() {
    let llmClient: LLMClient

    do {
      let configuration = try LLMConfiguration.loadFromEnvironment()
      llmClient = CerebrasLLMClient(configuration: configuration)
    } catch {
      llmClient = UnavailableLLMClient(error: error)
    }

    self.init(session: ChatSession(), llmClient: llmClient)
  }

  var messages: [ChatMessage] {
    session.messages
  }

  var isSending: Bool {
    if case .sending = requestState {
      return true
    }

    return false
  }

  var errorMessage: String? {
    if case .failed(let message) = requestState {
      return message
    }

    return nil
  }

  var canSendMessage: Bool {
    !isSending
  }

  func send(_ text: String) {
    let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedText.isEmpty, canSendMessage else {
      return
    }

    requestState = .idle
    session.appendUserMessage(trimmedText)
    let messages = session.messages
    requestState = .sending

    Task {
      do {
        let response = try await llmClient.complete(messages: messages)
        session.appendAssistantMessage(response)
        requestState = .idle
      } catch {
        let errorMessage = userFacingMessage(for: error)
        requestState = .failed(errorMessage)
      }
    }
  }

  private func userFacingMessage(for error: Error) -> String {
    if let localizedError = error as? LocalizedError,
      let description = localizedError.errorDescription,
      !description.isEmpty
    {
      return description
    }

    return "Something went wrong."
  }
}
