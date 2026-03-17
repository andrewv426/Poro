import Foundation
import Observation

@Observable
@MainActor
final class ChatController {
    enum RequestState {
        case idle
        case sending
        case failed(String)

        var isSending: Bool {
            if case .sending = self {
                return true
            }

            return false
        }
    }

    let session: ChatSession
    private(set) var requestState: RequestState = .idle
    private let llmClient: LLMClient

    init(session: ChatSession, llmClient: LLMClient) {
        self.session = session
        self.llmClient = llmClient
    }

    convenience init() {
        self.init(session: ChatSession(), llmClient: MockLLMClient())
    }

    func send(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty, !requestState.isSending else {
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
                let errorMessage = "Something went wrong."
                session.appendAssistantMessage(errorMessage)
                requestState = .failed(errorMessage)
            }
        }
    }
}
