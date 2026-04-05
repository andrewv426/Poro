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

  func appendAssistantPlaceholder() -> ChatMessage.ID {
    let message = ChatMessage(role: .assistant, text: "")
    messages.append(message)
    return message.id
  }

  func appendText(_ text: String, toMessageWithID id: ChatMessage.ID) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else {
      return
    }

    messages[index].text += text
  }
}
