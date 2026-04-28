import Foundation

struct UnavailableFocusDecisionClient: FocusDecisionEvaluating, DistractionClassifying, Sendable {
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

  nonisolated func classifyDistraction(
    goal: String,
    remainingMinutes: Int,
    activity: ActivityContext
  ) async throws -> DistractionClassification {
    throw error
  }
}
