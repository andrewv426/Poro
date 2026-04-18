import Foundation

struct FocusSession: Equatable, Sendable {
  let id = UUID()
  let goal: String
  let durationMinutes: Int
  let startedAt: Date
}
