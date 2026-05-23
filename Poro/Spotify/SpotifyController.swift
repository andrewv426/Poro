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

    switch command {
    case let .play(query):
      do {
        let devices = await (try? api.devices()) ?? []
        let activeDevice = devices.first(where: \.isActive)?.id

        guard let query else {
          guard activeDevice != nil else { return nil }
          try await api.resume(deviceID: activeDevice)
          return SpotifyOutcome(result: .resumed, requiresReactivation: false)
        }

        guard let hit = try await api.search(query) else {
          // Search succeeded but no tracks — surface as a real error rather than falling through.
          return SpotifyOutcome(
            result: .scriptError(message: "No tracks found for that query"),
            requiresReactivation: false
          )
        }

        guard let device = activeDevice else { return nil }

        try await api.play(trackURI: hit.uri, deviceID: device)
        return SpotifyOutcome(
          result: .played(query: hit.displayName),
          requiresReactivation: false
        )
      } catch SpotifyAPIError.premiumRequired {
        // Free-tier user — fall through to AppleScript silently so /play still works.
        logger.info("Spotify Web API premiumRequired; falling back to AppleScript")
        return nil
      } catch SpotifyAPIError.notAuthorized {
        // Auth flow failed or was cancelled; fall through silently rather than blocking the user.
        return nil
      } catch {
        logger.warning("Spotify Web API error: \(String(describing: error)); falling back to AppleScript")
        return nil
      }
    }
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
        // Resume doesn't trigger Spotify activation in practice, but it's harmless to reactivate.
        return SpotifyOutcome(result: result, requiresReactivation: false)
      }
      let result = runScript(
        source: SpotifyAppleScript.playSource(query),
        success: .played(query: displayString(for: query))
      )
      let needsReactivation = if case .played = result { true } else { false }
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
