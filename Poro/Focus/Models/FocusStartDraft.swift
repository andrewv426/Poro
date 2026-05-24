import Foundation

struct FocusStartDraft: Equatable {
  var goal: String
  var music: String = ""
  var durationMinutes: Int

  static let `default` = FocusStartDraft(goal: "", music: "", durationMinutes: 45)
}
