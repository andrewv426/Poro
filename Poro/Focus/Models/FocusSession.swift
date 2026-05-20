import Foundation

struct FocusSession: Equatable {
  let id = UUID()
  let goal: String
  let durationMinutes: Int
  let startedAt: Date
}
