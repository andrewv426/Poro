import Foundation
import Observation

@Observable
final class ChatSession {
  private(set) var messages: [ChatMessage] = []

  var hasMessages: Bool {
    !messages.isEmpty
  }

  func appendUserMessage(_ text: String, images: [ChatImage] = []) {
    messages.append(ChatMessage(role: .user, text: text, images: images))
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

  func text(forMessageWithID id: ChatMessage.ID) -> String? {
    messages.first(where: { $0.id == id })?.text
  }

  func removeMessage(withID id: ChatMessage.ID) {
    messages.removeAll(where: { $0.id == id })
  }

  func clear() {
    messages.removeAll()
  }
}
