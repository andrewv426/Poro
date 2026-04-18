import Foundation

struct SessionSummary: Equatable, Sendable {
  let goal: String
  let startedAt: Date
  let endedAt: Date
  let plannedDurationMinutes: Int
  let completedMinutes: Int
  let nudgeCount: Int
  let allowedOverrideCount: Int
  let deniedOverrideCount: Int
  let topDistractions: [String]
  let memorableArguments: [String]
}
