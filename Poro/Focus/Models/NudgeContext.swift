import Foundation

struct NudgeContext: Identifiable, Equatable, Sendable {
  enum Stage: Equatable, Sendable {
    case prompted
    case arguing
    case evaluating
    case resolved(FocusDecision)
  }

  let id = UUID()
  let activity: ActivityContext
  let prompt: String
  let returnToProcessIdentifier: Int32?
  var stage: Stage
  var justificationDraft: String
}
