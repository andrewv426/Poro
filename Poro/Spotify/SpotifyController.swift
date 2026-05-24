import AppKit
import CoreServices
import OSLog

private let logger = Logger(subsystem: "andrewvong.Poro", category: "Spotify")

private actor SpotifyPermissionStore {
  private var status: OSStatus?

  func cached() -> OSStatus? {
    status
  }

  func set(_ value: OSStatus) {
    status = value
  }
}

/// Drives Spotify playback via two paths. The Web API path (Spotify Connect) is preferred because
/// it doesn't activate the Spotify desktop window. When credentials are missing, no active device
/// is available, or the API errors out, the AppleScript path takes over — and the caller is told
/// to snap focus back to Poro via `SpotifyOutcome.requiresReactivation`.
struct SpotifyController {
  private static let bundleID = "com.spotify.client"
  private static let permissionStore = SpotifyPermissionStore()
  private static let auth = SpotifyAuth.shared

  func execute(_ command: SpotifyCommand, completion: @escaping @MainActor (SpotifyOutcome) -> Void) {
    Task.detached {
      let outcome = await Self.run(command)
      await MainActor.run {
        completion(outcome)
      }
    }
  }

  private static func run(_ command: SpotifyCommand) async -> SpotifyOutcome {
    if auth.isConfigured {
      if let outcome = await tryWebAPI(command: command) {
        return outcome
      }
      // Otherwise fall through to AppleScript.
    }
    return await runAppleScript(command: command)
  }

  // MARK: - Web API path

  /// Returns a definitive outcome from the Web API path, or `nil` to signal "fall through to
  /// AppleScript" (e.g. no active device, network down, user cancelled auth).
  private static func tryWebAPI(command: SpotifyCommand) async -> SpotifyOutcome? {
    let api = SpotifyWebAPI(auth: auth)

    do {
      switch command {
      case let .play(query):
        return try await webAPIPlay(api: api, query: query)
      case let .playPlaylist(query):
        return try await webAPIPlayPlaylist(api: api, query: query)
      case .pause:
        return try await webAPIPause(api: api)
      case .skip:
        return try await webAPISkip(api: api)
      case let .shuffle(enabled):
        return try await webAPIShuffle(api: api, enabled: enabled)
      case let .pickTrack(uri, displayName):
        return try await webAPIPickTrack(api: api, uri: uri, displayName: displayName)
      case let .pickPlaylist(uri, displayName):
        return try await webAPIPickPlaylist(api: api, uri: uri, displayName: displayName)
      }
    } catch SpotifyAPIError.premiumRequired {
      logger.info("Spotify Web API premiumRequired; falling back to AppleScript")
      return nil
    } catch SpotifyAPIError.notAuthorized {
      return nil
    } catch {
      logger.warning("Spotify Web API error: \(String(describing: error)); falling back to AppleScript")
      return nil
    }
  }

  private static func webAPIPlay(api: SpotifyWebAPI, query: SpotifyPlayQuery?) async throws -> SpotifyOutcome? {
    let activeDevice = await activeDeviceID(api: api)

    guard let query else {
      guard activeDevice != nil else { return nil }
      try await api.resume(deviceID: activeDevice)
      return SpotifyOutcome(result: .resumed, requiresReactivation: false)
    }

    guard let hit = try await api.search(query) else {
      return SpotifyOutcome(
        result: .scriptError(message: "No tracks found for that query"),
        requiresReactivation: false
      )
    }

    guard let device = activeDevice else { return nil }

    try await api.play(trackURI: hit.uri, deviceID: device)
    return SpotifyOutcome(result: .played(query: hit.displayName), requiresReactivation: false)
  }

  /// Bare /play playlist branch — picks the best-matching user playlist (substring match on name,
  /// then falls back to public playlist search). The picker UI emits `.pickPlaylist` for the
  /// explicit-selection case so this fast-path only runs when the user typed a name and skipped
  /// the picker (or no picker was shown).
  private static func webAPIPlayPlaylist(api: SpotifyWebAPI, query: String?) async throws -> SpotifyOutcome? {
    let activeDevice = await activeDeviceID(api: api)
    guard let device = activeDevice else { return nil }

    let candidates: [SpotifyPlaylistHit]
    if let query, !query.isEmpty {
      let userMatches = try await api.userPlaylists().filter {
        $0.name.lowercased().contains(query.lowercased())
      }
      if userMatches.isEmpty {
        candidates = try await api.searchPlaylists(query)
      } else {
        candidates = userMatches
      }
    } else {
      candidates = try await api.userPlaylists(limit: 1)
    }

    guard let hit = candidates.first else {
      return SpotifyOutcome(
        result: .scriptError(message: "No playlists found"),
        requiresReactivation: false
      )
    }

    try await api.playContext(contextURI: hit.uri, deviceID: device)
    return SpotifyOutcome(result: .playlistStarted(name: hit.name), requiresReactivation: false)
  }

  private static func webAPIPause(api: SpotifyWebAPI) async throws -> SpotifyOutcome? {
    let device = await activeDeviceID(api: api)
    guard device != nil else {
      return SpotifyOutcome(result: .nothingPlaying, requiresReactivation: false)
    }
    try await api.pause(deviceID: device)
    return SpotifyOutcome(result: .paused, requiresReactivation: false)
  }

  private static func webAPISkip(api: SpotifyWebAPI) async throws -> SpotifyOutcome? {
    let device = await activeDeviceID(api: api)
    guard device != nil else {
      return SpotifyOutcome(result: .nothingPlaying, requiresReactivation: false)
    }
    try await api.skipNext(deviceID: device)
    return SpotifyOutcome(result: .skipped, requiresReactivation: false)
  }

  /// `/shuffle off` always toggles plain shuffle off.
  ///
  /// `/shuffle on`:
  ///   - If playback is inside a playlist/album/artist context, set shuffle on that context
  ///     (vanilla Spotify shuffle).
  ///   - If playback has no context (a one-off track), switch the playback context to the
  ///     current artist's URI with shuffle on — Spotify shuffles the artist's catalog
  ///     server-side. This avoids `/v1/artists/{id}/top-tracks`, which Spotify removed from
  ///     Development Mode in their Feb 2026 changes.
  ///
  /// Falls back to vanilla shuffle-on if neither context nor artist URI is available, so the
  /// verb still does *something* useful.
  private static func webAPIShuffle(api: SpotifyWebAPI, enabled: Bool) async throws -> SpotifyOutcome? {
    guard let device = await activeDeviceID(api: api) else {
      return SpotifyOutcome(result: .nothingPlaying, requiresReactivation: false)
    }

    if !enabled {
      try await api.setShuffle(enabled: false, deviceID: device)
      return SpotifyOutcome(result: .shuffleSet(enabled: false), requiresReactivation: false)
    }

    guard let state = try await api.currentlyPlaying() else {
      return SpotifyOutcome(result: .nothingPlaying, requiresReactivation: false)
    }

    logger
      .info(
        "/shuffle on: contextURI=\(state.contextURI ?? "nil", privacy: .public) artistURI=\(state.currentTrackPrimaryArtistURI ?? "nil", privacy: .public)"
      )

    if state.contextURI != nil {
      logger.info("/shuffle: vanilla on existing context")
      try await api.setShuffle(enabled: true, deviceID: device)
      return SpotifyOutcome(result: .shuffleSet(enabled: true), requiresReactivation: false)
    }

    guard let artistURI = state.currentTrackPrimaryArtistURI else {
      logger.info("/shuffle: no context and no artist URI; vanilla shuffle on")
      try await api.setShuffle(enabled: true, deviceID: device)
      return SpotifyOutcome(result: .shuffleSet(enabled: true), requiresReactivation: false)
    }

    // Set shuffle BEFORE starting the artist context so Spotify shuffles from the first track,
    // not the artist's canonical "first" song.
    logger.info("/shuffle: switching context to artist \(artistURI, privacy: .public)")
    try await api.setShuffle(enabled: true, deviceID: device)
    do {
      try await api.playContext(contextURI: artistURI, deviceID: device)
    } catch {
      // If Spotify Connect rejects the artist context (rare; some accounts), at least the
      // shuffle flag is set on the existing single-track queue.
      logger.warning("playContext(artist) failed: \(String(describing: error)); leaving shuffle on existing queue")
    }
    return SpotifyOutcome(result: .shuffleSet(enabled: true), requiresReactivation: false)
  }

  private static func webAPIPickTrack(api: SpotifyWebAPI, uri: String,
                                      displayName: String) async throws -> SpotifyOutcome?
  {
    let activeDevice = await activeDeviceID(api: api)
    guard let device = activeDevice else { return nil }
    try await api.play(trackURI: uri, deviceID: device)
    return SpotifyOutcome(result: .played(query: displayName), requiresReactivation: false)
  }

  private static func webAPIPickPlaylist(api: SpotifyWebAPI, uri: String,
                                         displayName: String) async throws -> SpotifyOutcome?
  {
    let activeDevice = await activeDeviceID(api: api)
    guard let device = activeDevice else { return nil }
    try await api.playContext(contextURI: uri, deviceID: device)
    return SpotifyOutcome(result: .playlistStarted(name: displayName), requiresReactivation: false)
  }

  private static func activeDeviceID(api: SpotifyWebAPI) async -> String? {
    let devices = await (try? api.devices()) ?? []
    return devices.first(where: \.isActive)?.id ?? nil
  }

  // MARK: - AppleScript path

  private static func runAppleScript(command: SpotifyCommand) async -> SpotifyOutcome {
    if let launchFailure = await ensureRunning() {
      return SpotifyOutcome(result: launchFailure, requiresReactivation: false)
    }

    let permission = await automationPermissionStatus()
    if permission == OSStatus(errAEEventNotPermitted) {
      return SpotifyOutcome(result: .notAuthorized, requiresReactivation: false)
    }

    return await withCheckedContinuation { continuation in
      Thread.detachNewThread {
        continuation.resume(returning: executeScript(for: command))
      }
    }
  }

  private static func ensureRunning() async -> SpotifyResult? {
    if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
      return nil
    }

    guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      logger.error("Spotify not found by bundle ID \(bundleID)")
      return .launchFailed(reason: "Spotify is not installed")
    }

    let config = NSWorkspace.OpenConfiguration()
    config.activates = false

    do {
      _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    } catch {
      logger.error("Failed to launch Spotify: \(error.localizedDescription)")
      return .launchFailed(reason: error.localizedDescription)
    }

    for _ in 0 ..< 5 {
      try? await Task.sleep(nanoseconds: 500_000_000)
      if !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
        return nil
      }
    }

    logger.warning("Spotify launched but did not register within 2.5s")
    return .launchFailed(reason: "Spotify didn't finish launching")
  }

  private static func automationPermissionStatus() async -> OSStatus {
    if let cached = await permissionStore.cached() {
      return cached
    }

    let status = await withCheckedContinuation { continuation in
      Thread.detachNewThread {
        continuation.resume(returning: determineAutomationPermissionStatus())
      }
    }

    await permissionStore.set(status)
    return status
  }

  private static func determineAutomationPermissionStatus() -> OSStatus {
    var addressDesc = AEDesc()

    guard let ptr = (bundleID as NSString).utf8String else {
      return OSStatus(paramErr)
    }

    let createStatus = OSStatus(
      AECreateDesc(typeApplicationBundleID, ptr, bundleID.utf8.count, &addressDesc)
    )

    guard createStatus == noErr else {
      logger.error("AECreateDesc failed for \(bundleID): \(createStatus)")
      return createStatus
    }

    let permissionStatus = AEDeterminePermissionToAutomateTarget(
      &addressDesc,
      typeWildCard,
      typeWildCard,
      true
    )
    AEDisposeDesc(&addressDesc)

    return permissionStatus
  }

  private static func executeScript(for command: SpotifyCommand) -> SpotifyOutcome {
    switch command {
    case let .play(query):
      guard let query else {
        let result = runScript(source: SpotifyAppleScript.resumeSource(), success: .resumed)
        return SpotifyOutcome(result: result, requiresReactivation: false)
      }
      let result = runScript(
        source: SpotifyAppleScript.playSource(query),
        success: .played(query: displayString(for: query))
      )
      let needsReactivation = if case .played = result { true } else { false }
      return SpotifyOutcome(result: result, requiresReactivation: needsReactivation)
    case .playPlaylist:
      // Playlists require user-playlist resolution, which the Web API owns. Surface a hint
      // rather than guessing at an AppleScript URI search.
      return SpotifyOutcome(
        result: .scriptError(message: "Playlists require Spotify Connect. Set SPOTIFY_CLIENT_ID."),
        requiresReactivation: false
      )
    case .pause:
      let result = runScript(source: SpotifyAppleScript.pauseSource(), success: .paused)
      return SpotifyOutcome(result: result, requiresReactivation: false)
    case .skip:
      let result = runScript(source: SpotifyAppleScript.nextTrackSource(), success: .skipped)
      let needsReactivation = if case .skipped = result { true } else { false }
      return SpotifyOutcome(result: result, requiresReactivation: needsReactivation)
    case let .shuffle(enabled):
      let result = runScript(
        source: SpotifyAppleScript.shuffleSource(enabled: enabled),
        success: .shuffleSet(enabled: enabled)
      )
      return SpotifyOutcome(result: result, requiresReactivation: false)
    case let .pickTrack(uri, displayName):
      let result = runScript(
        source: SpotifyAppleScript.playURISource(uri),
        success: .played(query: displayName)
      )
      let needsReactivation = if case .played = result { true } else { false }
      return SpotifyOutcome(result: result, requiresReactivation: needsReactivation)
    case let .pickPlaylist(uri, displayName):
      let result = runScript(
        source: SpotifyAppleScript.playURISource(uri),
        success: .playlistStarted(name: displayName)
      )
      let needsReactivation = if case .playlistStarted = result { true } else { false }
      return SpotifyOutcome(result: result, requiresReactivation: needsReactivation)
    }
  }

  private static func displayString(for query: SpotifyPlayQuery) -> String {
    switch query {
    case let .freeform(text): text
    case let .trackByArtist(track, artist): "\(track) by \(artist)"
    }
  }

  private static func runScript(source: String, success: SpotifyResult) -> SpotifyResult {
    var errorInfo: NSDictionary?
    let script = NSAppleScript(source: source)
    _ = script?.executeAndReturnError(&errorInfo)

    if let errorInfo {
      let raw = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
      let truncated = String(raw.prefix(120))
      logger.error("Spotify AppleScript error: \(String(describing: errorInfo))")
      return .scriptError(message: truncated)
    }

    return success
  }
}
