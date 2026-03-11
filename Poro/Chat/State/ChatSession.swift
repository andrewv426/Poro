import Foundation
import Observation

@Observable
final class ChatSession {
    private(set) var messages: [ChatMessage] = [
        ChatMessage(role: .assistant, text: "Ready.")
    ]

    func appendUserMessage(_ text: String) {
        messages.append(ChatMessage(role: .user, text: text))
    }

    func appendAssistantMessage(_ text: String) {
        messages.append(ChatMessage(role: .assistant, text: text))
    }
}
