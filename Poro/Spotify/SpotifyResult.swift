import Foundation

enum SpotifyResult: Equatable {
  case played(query: String)
  case resumed
  case launchFailed(reason: String)
  case notAuthorized
  case scriptError(message: String)
  case authNeeded
  case premiumRequired
  case networkError(reason: String)
}

/// The result plus whether Poro needs to snap focus back. The AppleScript path always returns
/// `requiresReactivation = true` on success (since Spotify activates itself on `play track`); the
/// Web API path always returns `false` because Spotify Connect plays without touching focus.
struct SpotifyOutcome: Equatable {
  let result: SpotifyResult
  let requiresReactivation: Bool
}
