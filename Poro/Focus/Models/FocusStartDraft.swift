import Foundation

struct FocusStartDraft: Equatable, Sendable {
  var goal: String
  var durationMinutes: Int

  static let `default` = FocusStartDraft(goal: "", durationMinutes: 50)
}
