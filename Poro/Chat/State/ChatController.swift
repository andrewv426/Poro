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

  func appendLocalExchange(userText: String, assistantText: String) {
    let trimmedText = userText.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedReply = assistantText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmedText.isEmpty, !trimmedReply.isEmpty else {
      return
    }

    streamTask?.cancel()
    streamTask = nil
    currentAssistantMessageID = nil
    requestState = .idle
    session.appendUserMessage(trimmedText)
    session.appendAssistantMessage(trimmedReply)
  }

  func startNewConversation() {
    streamTask?.cancel()
    streamTask = nil
    currentAssistantMessageID = nil
    requestState = .idle
    session.clear()
  }

  /// Injects a visible user bubble and streams a response using a richer LLM prompt.
  /// The display bubble shows `userText`; the LLM receives `assistantPrompt` instead.
  func injectDistractionExchange(userText: String, assistantPrompt: String) {
    guard canSendMessage else { return }
    requestState = .idle
    session.appendUserMessage(userText)
    let assistantMessageID = session.appendAssistantPlaceholder()
    currentAssistantMessageID = assistantMessageID
    requestState = .sending

    // Build a synthetic message list: history before this exchange, then the richer prompt.
    let historyBeforeInjection = Array(session.messages.dropLast(2))
    let syntheticMessages = historyBeforeInjection + [ChatMessage(role: .user, text: assistantPrompt)]

    streamTask = Task { [weak self, session, llmClient] in
      guard let self else { return }
      do {
        try await llmClient.streamCompletion(messages: syntheticMessages) { delta in
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

  /// Streams an assistant-only response. The LLM receives `assistantPrompt`,
  /// but no synthetic user bubble is added to the visible chat history.
  func injectAssistantPrompt(_ assistantPrompt: String) {
    guard canSendMessage else { return }
    requestState = .idle
    let historyBeforeInjection = session.messages
    let assistantMessageID = session.appendAssistantPlaceholder()
    currentAssistantMessageID = assistantMessageID
    requestState = .sending

    let syntheticMessages = historyBeforeInjection + [ChatMessage(role: .user, text: assistantPrompt)]

    streamTask = Task { [weak self, session, llmClient] in
      guard let self else { return }
      do {
        try await llmClient.streamCompletion(messages: syntheticMessages) { delta in
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
