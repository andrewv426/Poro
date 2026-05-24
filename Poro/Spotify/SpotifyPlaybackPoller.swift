import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "andrewvong.Poro", category: "SpotifyPlaybackPoller")

/// Polls `SpotifyWebAPI.currentlyPlaying()` while observing is active. Exists so the slash-command
/// menu can hide `/stop`, `/skip`, and `/shuffle` when nothing is playing. Polling stops while the
/// normal-chat panel is hidden to save API calls; callers also nudge `refreshNow()` after any
/// Spotify command so the menu reacts faster than the 10-second tick.
@Observable
@MainActor
final class SpotifyPlaybackPoller {
  /// Strict "Spotify is actually playing a music track right now" signal. Drives whether the
  /// slash-command menu surfaces `/stop`, `/skip`, and `/shuffle`. We require all three:
  /// `is_playing == true`, an active `device`, and a current `item` with a primary artist. This
  /// rules out the stale-state shape Spotify returns when a paused session is lingering with no
  /// current track, and the "Spotify is open but nothing is playing" edge case.
  private(set) var isPlayingMusic: Bool = false

  private let auth = SpotifyAuth.shared
  private var pollTask: Task<Void, Never>?
  private var isObserving: Bool = false

  private static let pollInterval: TimeInterval = 10

  func startObserving() {
    guard !isObserving else { return }
    isObserving = true
    logger.info("playback poll: starting")
    guard auth.isConfigured else {
      logger.info("playback poll: auth not configured; skipping schedule")
      return
    }
    schedule()
  }

  func stopObserving() {
    isObserving = false
    pollTask?.cancel()
    pollTask = nil
    logger.info("playback poll: stopped")
  }

  /// Force an immediate refresh — called after Spotify commands so the menu updates without
  /// waiting for the next poll tick.
  func refreshNow() {
    guard auth.isConfigured else {
      isPlayingMusic = false
      return
    }
    Task { @MainActor in
      await self.tick()
    }
  }

  private func schedule() {
    pollTask?.cancel()
    pollTask = Task { @MainActor [weak self] in
      while let self, isObserving, !Task.isCancelled {
        await tick()
        try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
      }
    }
  }

  private func tick() async {
    // Non-interactive so a stale/insufficient token never pops the OAuth web view from a poll.
    // The user gets the consent prompt only when they actually run a command that needs the
    // missing scope (e.g. `/play playlist`).
    let api = SpotifyWebAPI(auth: auth, interactiveAuth: false)
    do {
      let state = try await api.currentlyPlaying()
      let nowPlaying = Self.computeIsPlayingMusic(state: state)
      logger
        .info(
          "playback poll: isPlayingMusic=\(nowPlaying, privacy: .public) isPlaying=\(state?.isPlaying ?? false, privacy: .public) device=\(state?.deviceID ?? "nil", privacy: .public) artist=\(state?.currentTrackPrimaryArtistURI ?? "nil", privacy: .public)"
        )
      if isPlayingMusic != nowPlaying {
        isPlayingMusic = nowPlaying
      }
    } catch {
      // Auth errors are recoverable on the next tick (the auth layer reopens the OAuth flow when
      // the user actually issues a command). Treat as "not playing" to hide controls.
      logger.debug("playback poll failed: \(String(describing: error))")
      if isPlayingMusic {
        isPlayingMusic = false
      }
    }
  }

  /// Stricter than Spotify's raw `is_playing` flag: requires an active device AND a current track
  /// with a primary artist. Filters out the "paused, no track, stale device" shape that
  /// `/me/player` sometimes returns when Spotify is open but nothing is actively playing.
  private static func computeIsPlayingMusic(state: SpotifyPlaybackState?) -> Bool {
    guard let state else { return false }
    return state.isPlaying
      && state.deviceID != nil
      && state.currentTrackPrimaryArtistURI != nil
  }
}
