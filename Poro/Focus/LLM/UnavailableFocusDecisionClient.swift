import Foundation

struct UnavailableFocusDecisionClient: FocusDecisionEvaluating, DistractionClassifying {
  let error: Error

  nonisolated func evaluateDecision(
    goal _: String,
    remainingMinutes _: Int,
    activity _: ActivityContext,
    justification _: String,
    nudgesToday _: Int,
    allowedOverrides _: Int
  ) async throws -> FocusDecision {
    throw error
  }

  nonisolated func classifyDistraction(
    goal _: String,
    remainingMinutes _: Int,
    activity _: ActivityContext
  ) async throws -> DistractionClassification {
    throw error
  }
}
