import Foundation

struct FocusSession: Equatable {
  let id = UUID()
  let goal: String
  let durationMinutes: Int
  let startedAt: Date
  // TODO: wire to Spotify when integration lands
  let musicPreference: String
}
