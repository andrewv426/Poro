import Foundation
import Observation

@Observable
@MainActor
final class ChatController {
    let session: ChatSession
    private(set) var isResponding = false
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

        guard !trimmedText.isEmpty, !isResponding else {
            return
        }

        session.appendUserMessage(trimmedText)
        let messages = session.messages
        isResponding = true

        Task {
            do {
                let response = try await llmClient.complete(messages: messages)
                session.appendAssistantMessage(response)
            } catch {
                session.appendAssistantMessage("Something went wrong.")
            }

            isResponding = false
        }
    }
}
