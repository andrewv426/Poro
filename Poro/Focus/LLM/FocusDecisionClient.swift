import Foundation

struct FocusDecision: Codable, Equatable, Sendable {
  enum Verdict: String, Codable, Sendable {
    case allow
    case deny
  }

  let verdict: Verdict
  let message: String
  let allowMinutes: Int?
}

protocol FocusDecisionEvaluating: Sendable {
  nonisolated func evaluateDecision(
    goal: String,
    remainingMinutes: Int,
    activity: ActivityContext,
    justification: String,
    nudgesToday: Int,
    allowedOverrides: Int
  ) async throws -> FocusDecision
}
