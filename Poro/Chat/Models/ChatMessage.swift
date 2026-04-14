import Foundation

struct ChatMessage: Identifiable, Sendable {
  enum Role: Sendable {
    case user
    case assistant
  }

  let id = UUID()
  let role: Role
  var text: String
}
