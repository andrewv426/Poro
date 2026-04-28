import AppKit
import CoreServices
import OSLog

private let logger = Logger(subsystem: "andrewvong.Poro", category: "BrowserAutomation")

actor BrowserAutomationPermissionStore {
  private var statuses: [String: OSStatus] = [:]

  /// Retrieves the cached automation permission status for a browser.
  /// - Parameter bundleIdentifier: The bundle ID of the browser.
  /// - Returns: The OSStatus if cached, otherwise nil.
  func status(for bundleIdentifier: String) -> OSStatus? {
    statuses[bundleIdentifier]
  }

  /// Caches the automation permission status for a browser.
  /// - Parameters:
  ///   - status: The OSStatus to cache.
  ///   - bundleIdentifier: The bundle ID of the browser.
  func setStatus(_ status: OSStatus, for bundleIdentifier: String) {
    statuses[bundleIdentifier] = status
  }
}

/// Provides context about the active tab in supported web browsers via AppleScript.
struct BrowserTabContextProvider {
  private static let permissionStore = BrowserAutomationPermissionStore()

  /// A snapshot of the state of a browser tab.
  struct TabSnapshot {
    let url: URL?
    let title: String?
    let errorDescription: String?
  }

  /// Supported browser applications.
  enum BrowserApp: Equatable {
    case chrome
    case safari
    case arc
    case brave

    /// Initializes a BrowserApp from a bundle identifier.
    /// - Parameter bundleIdentifier: The bundle ID to match.
    init?(bundleIdentifier: String?) {
      switch bundleIdentifier {
      case "com.google.Chrome":
        self = .chrome
      case "com.apple.Safari":
        self = .safari
      case "company.thebrowser.Browser":
        self = .arc
      case "com.brave.Browser":
        self = .brave
      default:
        return nil
      }
    }

    /// The name used when logging or displaying the browser.
    var applescriptApplicationName: String {
      switch self {
      case .chrome:
        return "Google Chrome"
      case .safari:
        return "Safari"
      case .arc:
        return "Arc"
      case .brave:
        return "Brave Browser"
      }
    }

    /// The official bundle identifier for the browser.
    var bundleIdentifier: String {
      switch self {
      case .chrome:
        return "com.google.Chrome"
      case .safari:
        return "com.apple.Safari"
      case .arc:
        return "company.thebrowser.Browser"
      case .brave:
        return "com.brave.Browser"
      }
    }

    /// AppleScript source to retrieve the URL of the active tab.
    var urlScript: String {
      switch self {
      case .safari:
        return "tell application id \"\(bundleIdentifier)\" to get URL of current tab of front window"
      case .chrome, .arc, .brave:
        return
          "tell application id \"\(bundleIdentifier)\" to get URL of active tab of front window"
      }
    }

    /// AppleScript source to retrieve the title of the active tab.
    var titleScript: String {
      switch self {
      case .safari:
        return "tell application id \"\(bundleIdentifier)\" to get name of current tab of front window"
      case .chrome, .arc, .brave:
        return
          "tell application id \"\(bundleIdentifier)\" to get title of active tab of front window"
      }
    }
  }

  /// Maps a bundle identifier to a supported BrowserApp.
  /// - Parameter bundleIdentifier: The bundle ID to check.
  /// - Returns: A BrowserApp if supported, otherwise nil.
  func browser(for bundleIdentifier: String?) -> BrowserApp? {
    BrowserApp(bundleIdentifier: bundleIdentifier)
  }

  /// Retrieves a snapshot of the active tab in the specified browser.
  /// - Parameters:
  ///   - browser: The target browser application.
  ///   - processIdentifier: Optional PID to use for precise permission verification.
  /// - Returns: A TabSnapshot containing the URL and title, or an error description.
  /// - Note: NSAppleScript execution is moved to a background thread to prevent UI hangs and allow permission dialogs.
  func activeTabSnapshot(for browser: BrowserApp, processIdentifier: Int32? = nil) async -> TabSnapshot {
    let permissionStatus = await Self.automationPermissionStatus(for: browser, processIdentifier: processIdentifier)

    if permissionStatus == OSStatus(errAEEventNotPermitted) {
      return TabSnapshot(
        url: nil,
        title: nil,
        errorDescription: "Automation permission denied for \(browser.applescriptApplicationName). Enable Poro -> \(browser.applescriptApplicationName) in System Settings > Privacy & Security > Automation."
      )
    }

    return await withCheckedContinuation { continuation in
      Thread.detachNewThread {
        let snapshot = Self.fetchTabSnapshot(browser: browser)
        continuation.resume(returning: snapshot)
      }
    }
  }

  /// Helper to retrieve only the URL of the active tab.
  /// - Parameters:
  ///   - browser: The target browser application.
  ///   - processIdentifier: Optional PID for permission checks.
  /// - Returns: The URL if successfully retrieved, otherwise nil.
  func activeTabURL(for browser: BrowserApp, processIdentifier: Int32? = nil) async -> URL? {
    await activeTabSnapshot(for: browser, processIdentifier: processIdentifier).url
  }

  // MARK: - Private synchronous helpers (must only be called off the main thread)

  /// Orchestrates automation permission checking, utilizing a cache to avoid redundant system calls.
  /// - Parameters:
  ///   - browser: The browser to check.
  ///   - processIdentifier: Optional PID for targeted checking.
  /// - Returns: The OSStatus result of the permission check.
  private static func automationPermissionStatus(for browser: BrowserApp, processIdentifier: Int32?) async -> OSStatus {
    if let cachedStatus = await permissionStore.status(for: browser.bundleIdentifier) {
      return cachedStatus
    }

    let status = await withCheckedContinuation { continuation in
      Thread.detachNewThread {
        let resolvedStatus = determineAutomationPermissionStatus(
          forBundleIdentifier: browser.bundleIdentifier,
          processIdentifier: processIdentifier
        )
        continuation.resume(returning: resolvedStatus)
      }
    }

    await permissionStore.setStatus(status, for: browser.bundleIdentifier)
    return status
  }

  /// Performs the low-level Apple Event permission check using AEDesc and system APIs.
  /// - Parameters:
  ///   - bundleIdentifier: The target application's bundle ID.
  ///   - processIdentifier: Optional PID for kernel-level process identification.
  /// - Returns: The OSStatus from the system permission check.
  private static func determineAutomationPermissionStatus(
    forBundleIdentifier bundleIdentifier: String,
    processIdentifier: Int32?
  ) -> OSStatus {
    var addressDesc = AEDesc()
    let createStatus: OSStatus

    if let pid = processIdentifier {
      var targetPid = pid
      createStatus = OSStatus(AECreateDesc(typeKernelProcessID, &targetPid, MemoryLayout<pid_t>.size, &addressDesc))
    } else {
      guard let ptr = (bundleIdentifier as NSString).utf8String else {
        return OSStatus(paramErr)
      }
      createStatus = OSStatus(AECreateDesc(typeApplicationBundleID, ptr, bundleIdentifier.utf8.count, &addressDesc))
    }

    guard createStatus == noErr else {
      logger.error("AECreateDesc failed for \(bundleIdentifier) (pid: \(processIdentifier ?? -1)): \(createStatus)")
      return OSStatus(createStatus)
    }

    let permissionStatus = AEDeterminePermissionToAutomateTarget(
      &addressDesc,
      typeWildCard,
      typeWildCard,
      true
    )
    AEDisposeDesc(&addressDesc)

    switch permissionStatus {
    case noErr:
      logger.debug("Automation permission granted for \(bundleIdentifier)")
    case OSStatus(errAEEventNotPermitted):
      logger.warning("Automation permission denied for \(bundleIdentifier)")
    default:
      logger.error("Automation permission status \(permissionStatus) for \(bundleIdentifier) (pid: \(processIdentifier ?? -1))")
    }

    return permissionStatus
  }

  /// Executes AppleScript to retrieve URL and Title from the browser.
  /// - Parameter browser: The target browser application.
  /// - Returns: A TabSnapshot containing the retrieved data or error info.
  private static func fetchTabSnapshot(browser: BrowserApp) -> TabSnapshot {
    let scriptSource = browser.urlScript
    logger.debug("Fetching tab snapshot for \(browser.applescriptApplicationName) on background thread")
    
    var errorInfo: NSDictionary?
    let script = NSAppleScript(source: scriptSource)
    let result = script?.executeAndReturnError(&errorInfo)

    if let errorInfo {
      let message = errorInfo[NSAppleScript.errorMessage] as? String
      logger.error("AppleScript error for URL (\(browser.applescriptApplicationName)): \(String(describing: errorInfo))")
      return TabSnapshot(url: nil, title: nil, errorDescription: message)
    }

    let urlString = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = fetchTabTitle(browser: browser)

    guard let urlString, !urlString.isEmpty else {
      return TabSnapshot(url: nil, title: title, errorDescription: nil)
    }

    return TabSnapshot(url: URL(string: urlString), title: title, errorDescription: nil)
  }

  /// Executes AppleScript to retrieve the active tab's title.
  /// - Parameter browser: The target browser application.
  /// - Returns: The title string if successful, otherwise nil.
  private static func fetchTabTitle(browser: BrowserApp) -> String? {
    let scriptSource = browser.titleScript
    var errorInfo: NSDictionary?
    let script = NSAppleScript(source: scriptSource)
    let result = script?.executeAndReturnError(&errorInfo)

    guard errorInfo == nil else {
      logger.error("AppleScript error for title (\(browser.applescriptApplicationName)): \(String(describing: errorInfo!))")
      return nil
    }

    let title = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (title?.isEmpty == false) ? title : nil
  }
}

