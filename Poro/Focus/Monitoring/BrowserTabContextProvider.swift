import AppKit
import CoreServices

actor BrowserAutomationPermissionStore {
  private var statuses: [String: OSStatus] = [:]

  func status(for bundleIdentifier: String) -> OSStatus? {
    statuses[bundleIdentifier]
  }

  func setStatus(_ status: OSStatus, for bundleIdentifier: String) {
    statuses[bundleIdentifier] = status
  }
}

struct BrowserTabContextProvider {
  private static let permissionStore = BrowserAutomationPermissionStore()

  struct TabSnapshot {
    let url: URL?
    let title: String?
    let errorDescription: String?
  }

  enum BrowserApp: Equatable {
    case chrome
    case safari
    case arc
    case brave

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

    var urlScript: String {
      switch self {
      case .safari:
        return "tell application id \"\(bundleIdentifier)\" to get URL of current tab of front window"
      case .chrome, .arc, .brave:
        return
          "tell application id \"\(bundleIdentifier)\" to get URL of active tab of front window"
      }
    }

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

  func browser(for bundleIdentifier: String?) -> BrowserApp? {
    BrowserApp(bundleIdentifier: bundleIdentifier)
  }

  // NSAppleScript.executeAndReturnError() is synchronous and blocks the calling
  // thread. When called on the main thread it prevents the run loop from pumping,
  // which stops macOS from displaying the Automation permission dialog. Running it
  // on a background thread lets the system show the prompt and keeps the main
  // thread responsive.
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

  func activeTabURL(for browser: BrowserApp, processIdentifier: Int32? = nil) async -> URL? {
    await activeTabSnapshot(for: browser, processIdentifier: processIdentifier).url
  }

  // MARK: - Private synchronous helpers (must only be called off the main thread)

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
      print("[Poro] AECreateDesc failed for \(bundleIdentifier) (pid: \(processIdentifier ?? -1)): \(createStatus)")
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
      print("[Poro] Automation permission granted for \(bundleIdentifier)")
    case OSStatus(errAEEventNotPermitted):
      print("[Poro] Automation permission denied for \(bundleIdentifier)")
    default:
      print("[Poro] Automation permission status \(permissionStatus) for \(bundleIdentifier) (pid: \(processIdentifier ?? -1))")
    }

    return permissionStatus
  }

  private static func fetchTabSnapshot(browser: BrowserApp) -> TabSnapshot {
    let scriptSource = browser.urlScript
    print("[Poro] fetchTabSnapshot for \(browser.applescriptApplicationName), thread=\(Thread.current.isMainThread ? "MAIN" : "background")")
    print("[Poro] Executing script: \(scriptSource)")
    var errorInfo: NSDictionary?
    let script = NSAppleScript(source: scriptSource)
    let result = script?.executeAndReturnError(&errorInfo)

    if let errorInfo {
      let message = errorInfo[NSAppleScript.errorMessage] as? String
      print("[Poro] AppleScript error for \(browser.applescriptApplicationName): \(errorInfo)")
      return TabSnapshot(url: nil, title: nil, errorDescription: message)
    }

    print("[Poro] AppleScript result for \(browser.applescriptApplicationName): \(result?.stringValue ?? "(nil)")")

    let urlString = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = fetchTabTitle(browser: browser)

    guard let urlString, !urlString.isEmpty else {
      return TabSnapshot(url: nil, title: title, errorDescription: nil)
    }

    return TabSnapshot(url: URL(string: urlString), title: title, errorDescription: nil)
  }

  private static func fetchTabTitle(browser: BrowserApp) -> String? {
    let scriptSource = browser.titleScript
    print("[Poro] Executing script: \(scriptSource)")
    var errorInfo: NSDictionary?
    let script = NSAppleScript(source: scriptSource)
    let result = script?.executeAndReturnError(&errorInfo)

    guard errorInfo == nil else {
      print("[Poro] AppleScript error for title (\(browser.applescriptApplicationName)): \(errorInfo!)")
      return nil
    }

    let title = result?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (title?.isEmpty == false) ? title : nil
  }
}
