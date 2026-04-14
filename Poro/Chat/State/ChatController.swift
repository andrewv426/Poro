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
  private var streamTask: Task<Void, Never>?
  private var currentAssistantMessageID: ChatMessage.ID?

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

  var hasConversation: Bool {
    session.hasMessages
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
    let assistantMessageID = session.appendAssistantPlaceholder()
    currentAssistantMessageID = assistantMessageID
    requestState = .sending

    streamTask = Task { [weak self, session, llmClient] in
      guard let self else {
        return
      }

      do {
        try await llmClient.streamCompletion(messages: messages) { [session] delta in
          session.appendText(delta, toMessageWithID: assistantMessageID)
        }
        self.finishStreaming()
      } catch is CancellationError {
        self.handleStreamCancellation(forMessageWithID: assistantMessageID)
      } catch {
        self.handleStreamFailure(error, forMessageWithID: assistantMessageID)
      }
    }
  }

  func stopStreaming() {
    streamTask?.cancel()
  }

  func startNewConversation() {
    streamTask?.cancel()
    streamTask = nil
    currentAssistantMessageID = nil
    requestState = .idle
    session.clear()
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

  private func finishStreaming() {
    streamTask = nil
    currentAssistantMessageID = nil
    requestState = .idle
  }

  private func handleStreamCancellation(forMessageWithID id: ChatMessage.ID) {
    if session.text(forMessageWithID: id)?.isEmpty != false {
      session.removeMessage(withID: id)
    }

    finishStreaming()
  }

  private func handleStreamFailure(_ error: Error, forMessageWithID id: ChatMessage.ID) {
    if session.text(forMessageWithID: id)?.isEmpty != false {
      session.removeMessage(withID: id)
    }

    streamTask = nil
    currentAssistantMessageID = nil
    requestState = .failed(userFacingMessage(for: error))
  }
}
