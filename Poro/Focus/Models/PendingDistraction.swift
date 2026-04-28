import Foundation

struct PendingDistraction: Identifiable, Equatable, Sendable {
  enum Resolution: Equatable, Sendable {
    case pending
    case closing
    case closed
    case allowed
    case failed(String)
  }

  let id = UUID()
  let activity: ActivityContext
  let reason: String
  let detectedAt: Date
  let deadline: Date
  var remainingSeconds: Int
  var justificationDraft: String = ""
  var isExplaining = false
  var resolution: Resolution = .pending

  var label: String {
    activity.distractionLabel
  }

  var targetURL: URL? {
    activity.pageURL
  }
}
