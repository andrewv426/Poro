import Foundation

struct NudgeEvent: Identifiable, Equatable, Sendable {
  enum Outcome: Equatable, Sendable {
    case backToWork
    case allowed(Int)
    case denied
  }

  let id = UUID()
  let occurredAt: Date
  let applicationName: String
  let justification: String?
  let outcome: Outcome
}
