import AppKit

@MainActor
final class FrontmostActivityMonitor {
  var onActivityChange: ((ActivityContext) -> Void)?

  private let browserContextProvider = BrowserTabContextProvider()
  private var observer: NSObjectProtocol?
  private var browserPollTimer: Timer?

  func start() {
    guard observer == nil else {
      emitCurrentApplication()
      return
    }

    observer = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard
        let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
        let self
      else {
        return
      }

      Task { @MainActor [weak self] in
        guard let self else {
          return
        }

        self.emit(self.activityFor(app))
      }
    }

    emitCurrentApplication()
  }

  func stop() {
    if let observer {
      NSWorkspace.shared.notificationCenter.removeObserver(observer)
    }

    observer = nil
    browserPollTimer?.invalidate()
    browserPollTimer = nil
  }

  private func emitCurrentApplication() {
    guard let app = NSWorkspace.shared.frontmostApplication else {
      return
    }

    handleActivatedApplication(app)
  }

  private func activityFor(_ application: NSRunningApplication) -> ActivityContext {
    ActivityContext(
      applicationName: application.localizedName ?? "Unknown App",
      bundleIdentifier: application.bundleIdentifier,
      processIdentifier: application.processIdentifier
    )
  }

  private func emit(_ activity: ActivityContext) {
    onActivityChange?(activity)
  }

  private func handleActivatedApplication(_ application: NSRunningApplication) {
    let baseActivity = activityFor(application)

    guard let browser = browserContextProvider.browser(for: baseActivity.bundleIdentifier) else {
      browserPollTimer?.invalidate()
      browserPollTimer = nil
      emit(baseActivity)
      return
    }

    emit(enrichedActivity(from: baseActivity, browser: browser))
    startBrowserPolling(for: browser, processIdentifier: application.processIdentifier)
  }

  private func startBrowserPolling(for browser: BrowserTabContextProvider.BrowserApp, processIdentifier: Int32) {
    browserPollTimer?.invalidate()
    browserPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        guard
          let self,
          let frontmostApplication = NSWorkspace.shared.frontmostApplication,
          frontmostApplication.processIdentifier == processIdentifier
        else {
          self?.browserPollTimer?.invalidate()
          self?.browserPollTimer = nil
          return
        }

        guard let activeBrowser = self.browserContextProvider.browser(for: frontmostApplication.bundleIdentifier),
          activeBrowser == browser
        else {
          self.browserPollTimer?.invalidate()
          self.browserPollTimer = nil
          self.emit(self.activityFor(frontmostApplication))
          return
        }

        self.emit(
          self.enrichedActivity(
            from: self.activityFor(frontmostApplication),
            browser: activeBrowser
          )
        )
      }
    }
  }

  private func enrichedActivity(
    from activity: ActivityContext,
    browser: BrowserTabContextProvider.BrowserApp
  ) -> ActivityContext {
    ActivityContext(
      applicationName: activity.applicationName,
      bundleIdentifier: activity.bundleIdentifier,
      processIdentifier: activity.processIdentifier,
      pageURL: browserContextProvider.activeTabURL(for: browser)
    )
  }
}
