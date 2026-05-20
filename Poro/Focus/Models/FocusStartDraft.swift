import Foundation

struct FocusStartDraft: Equatable {
  var goal: String
  var durationMinutes: Int

  static let `default` = FocusStartDraft(goal: "", durationMinutes: 45)
}
