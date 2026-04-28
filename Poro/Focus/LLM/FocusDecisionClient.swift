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

struct DistractionClassification: Codable, Equatable, Sendable {
  enum Verdict: String, Codable, Sendable {
    case allow
    case distract
  }

  let verdict: Verdict
  let score: Double
  let reason: String
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

protocol DistractionClassifying: Sendable {
  nonisolated func classifyDistraction(
    goal: String,
    remainingMinutes: Int,
    activity: ActivityContext
  ) async throws -> DistractionClassification
}
