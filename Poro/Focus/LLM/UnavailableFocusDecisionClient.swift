import Foundation

struct UnavailableFocusDecisionClient: FocusDecisionEvaluating, Sendable {
  let error: Error

  nonisolated func evaluateDecision(
    goal: String,
    remainingMinutes: Int,
    activity: ActivityContext,
    justification: String,
    nudgesToday: Int,
    allowedOverrides: Int
  ) async throws -> FocusDecision {
    throw error
  }
}
