import AppKit
import Foundation
import Observation

/// The primary coordinator for focus session state, activity monitoring, and distraction handling.
@Observable
@MainActor
final class FocusSessionController {
  /// Possible states for a focus session.
  enum State: Equatable {
    case idle
    case active
    case paused
    case completed
  }

  private(set) var state: State = .idle
  private(set) var activeSession: FocusSession?
  private(set) var latestSummary: SessionSummary?
  private(set) var pendingDistraction: PendingDistraction?
  private var isNudgeActive: Bool = false
  private(set) var overrideEndsAt: Date?

  // Callbacks for UI and state updates.
  var onDistractionDetected: ((ActivityContext) -> Void)?
  var onDistractionResolved: (() -> Void)?
  var onSessionStateChange: (() -> Void)?
  var onStatusItemUpdate: (() -> Void)?
  var onSummaryAvailable: ((SessionSummary) -> Void)?

  // Internal managers and monitors.
  private let decisionClient: FocusDecisionEvaluating
  private let classificationClient: DistractionClassifying
  private let activityMonitor: FrontmostActivityMonitor
  private let driftWatchdog: DriftWatchdog
  private let distractionPolicy: DistractionPolicy
  private let timer = FocusTimer()
  private let logger = SessionActivityLogger()
  private let browserContextProvider = BrowserTabContextProvider()
  private var pendingDistractionTask: Task<Void, Never>?
  private var classificationTask: Task<Void, Never>?
  private let classificationThreshold = 0.72

  // Internal state for activity tracking.
  private var nudgeEvents: [NudgeEvent] = []
  private var lastProductiveActivity: ActivityContext?
  private var lastSeenActivity: ActivityContext?
  private var pendingNudgeActivity: ActivityContext?

  /// Initializes the controller and starts the activity monitor.
  init(
    decisionClient: FocusDecisionEvaluating,
    classificationClient: DistractionClassifying,
    activityMonitor: FrontmostActivityMonitor,
    driftWatchdog: DriftWatchdog,
    distractionPolicy: DistractionPolicy
  ) {
    self.decisionClient = decisionClient
    self.classificationClient = classificationClient
    self.activityMonitor = activityMonitor
    self.driftWatchdog = driftWatchdog
    self.distractionPolicy = distractionPolicy

    // Wire up activity monitoring.
    activityMonitor.onActivityChange = { [weak self] activity in
      self?.handleActivityChange(activity)
    }

    // Wire up timer events.
    timer.onTick = { [weak self] _ in
      self?.tick()
    }
    timer.onComplete = { [weak self] in
      if let session = self?.activeSession {
        self?.finishSession(session: session)
      }
    }

    // Begin monitoring frontmost app activity immediately.
    activityMonitor.start()
  }

  /// Convenience initializer with standard dependencies.
  convenience init() {
    let decisionClient: FocusDecisionEvaluating
    let classificationClient: DistractionClassifying

    do {
      let configuration = try LLMConfiguration.loadFromEnvironment()
      let cerebrasClient = CerebrasFocusDecisionClient(configuration: configuration)
      decisionClient = cerebrasClient
      classificationClient = cerebrasClient
    } catch {
      let unavailableClient = UnavailableFocusDecisionClient(error: error)
      decisionClient = unavailableClient
      classificationClient = unavailableClient
    }

    self.init(
      decisionClient: decisionClient,
      classificationClient: classificationClient,
      activityMonitor: FrontmostActivityMonitor(),
      driftWatchdog: DriftWatchdog(),
      distractionPolicy: DistractionPolicy()
    )
  }

  // MARK: - Computed Properties

  /// Whether a focus session is currently running and not yet finished.
  var hasActiveSession: Bool {
    activeSession != nil && state != .completed
  }

  /// Whether the current session is paused.
  var isPaused: Bool {
    state == .paused
  }

  /// Whether a temporary override (granted distraction) is currently in effect.
  var isOverrideActive: Bool {
    guard let overrideEndsAt else {
      return false
    }
    return overrideEndsAt > Date()
  }

  /// Human-readable text for the main status display.
  var statusLine: String? {
    guard let session = activeSession else {
      return nil
    }

    switch state {
    case .paused:
      return "Paused • \(timer.remainingTimeText) left"
    case .active:
      if isOverrideActive, let overrideEndsAt {
        return "Override until \(timeString(for: overrideEndsAt)) • \(timer.remainingTimeText) left"
      }
      return "\(timer.remainingTimeText) left • \(session.goal)"
    case .completed:
      return "Session complete"
    case .idle:
      return nil
    }
  }

  /// Text for the menu bar status item.
  var statusItemText: String? {
    guard hasActiveSession else {
      return nil
    }
    let prefix = isPaused ? "⏸" : "◔"
    return "\(prefix) \(timer.remainingTimeText)"
  }

  // MARK: - Session Control

  /// Starts a new focus session.
  /// - Parameters:
  ///   - goal: The user's goal for the session.
  ///   - durationMinutes: How long the session should last.
  func startSession(goal: String, durationMinutes: Int) {
    let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedGoal = trimmedGoal.isEmpty ? "your work" : trimmedGoal
    let resolvedDuration = max(1, durationMinutes)

    activeSession = FocusSession(
      goal: resolvedGoal,
      durationMinutes: resolvedDuration,
      startedAt: Date()
    )

    state = .active
    latestSummary = nil
    pendingDistraction = nil
    overrideEndsAt = nil
    nudgeEvents.removeAll()
    logger.reset()
    lastProductiveActivity = nil
    lastSeenActivity = nil
    pendingNudgeActivity = nil
    classificationTask?.cancel()
    classificationTask = nil

    clearNudge()
    timer.start(minutes: resolvedDuration)
    notifySessionStateChange()
  }

  /// Pauses the current session.
  func pauseSession() {
    guard state == .active else { return }
    state = .paused
    timer.stop()
    driftWatchdog.cancel()
    classificationTask?.cancel()
    classificationTask = nil
    pendingDistractionTask?.cancel()
    clearNudge()
    notifySessionStateChange()
  }

  /// Resumes the current paused session.
  func resumeSession() {
    guard state == .paused, activeSession != nil else { return }
    state = .active
    timer.start(minutes: timer.remainingSeconds / 60)
    notifySessionStateChange()
  }

  /// Force-ends the current session.
  func endSession() {
    guard let session = activeSession else { return }
    finishSession(session: session)
  }

  /// Dismisses the session completion summary and returns to idle state.
  func dismissSummary() {
    latestSummary = nil
    pendingDistraction = nil
    if state == .completed {
      state = .idle
    }
    notifySessionStateChange()
  }

  /// Handles various textual session control commands.
  /// - Parameter command: The command type.
  /// - Returns: A localized response message for the assistant.
  func handleSessionCommand(_ command: SessionCommand) -> String {
    switch command {
    case .pause:
      pauseSession()
      return "Paused the focus session. Say resume when you want to continue."
    case .resume:
      resumeSession()
      return "Focus session resumed."
    case .end:
      endSession()
      return "Ended the focus session."
    case .status:
      guard let _ = activeSession else {
        return "There isn't an active focus session right now."
      }
      return "You have \(timer.remainingTimeText) left on '\(activeSession?.goal ?? "your goal")'."
    }
  }

  // MARK: - Nudge & Distraction Management

  /// Clears the active distraction/nudge state, allowing new distractions to be detected.
  func clearDistractionState() {
    guard pendingDistraction == nil else { return }
    clearNudge()
  }

  func beginExplainingPendingDistraction() {
    guard pendingDistraction?.resolution == .pending else { return }
    pendingDistractionTask?.cancel()
    pendingDistractionTask = nil
    pendingDistraction?.isExplaining = true
    pendingDistraction?.remainingSeconds = 0
  }

  func updatePendingDistractionJustification(_ text: String) {
    pendingDistraction?.justificationDraft = text
  }

  func allowPendingDistraction(minutes: Int = 5) {
    guard var pendingDistraction else { return }

    let justification = pendingDistraction.justificationDraft
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !justification.isEmpty else { return }

    pendingDistractionTask?.cancel()
    pendingDistractionTask = nil
    pendingDistraction.resolution = .allowed
    self.pendingDistraction = pendingDistraction
    overrideEndsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))

    nudgeEvents.append(
      NudgeEvent(
        occurredAt: Date(),
        applicationName: pendingDistraction.label,
        justification: justification,
        outcome: .allowed(minutes)
      )
    )

    clearPendingDistraction()
    onDistractionResolved?()
    notifySessionStateChange()
  }

  func closePendingDistraction(manual: Bool) {
    guard var pendingDistraction, pendingDistraction.resolution == .pending else { return }
    pendingDistractionTask?.cancel()
    pendingDistractionTask = nil

    guard
      let targetURL = pendingDistraction.targetURL,
      let browser = browserContextProvider.browser(for: pendingDistraction.activity.bundleIdentifier)
    else {
      pendingDistraction.resolution = .failed("Poro can only close supported browser tabs.")
      self.pendingDistraction = pendingDistraction
      return
    }

    pendingDistraction.resolution = .closing
    self.pendingDistraction = pendingDistraction

    Task { @MainActor [weak self] in
      guard let self else { return }
      let result = await browserContextProvider.closeActiveTabIfMatching(
        for: browser,
        targetURL: targetURL,
        processIdentifier: pendingDistraction.activity.processIdentifier
      )
      handleCloseTabResult(result, for: pendingDistraction, manual: manual)
    }
  }

  // MARK: - Activity Handling

  /// Main entry point for activity change notifications from the ActivityMonitor.
  private func handleActivityChange(_ activity: ActivityContext) {
    // 1. Filter out Poro itself to prevent "meta" activation loops.
    guard activity.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return
    }

    // 2. Persist activity in state and log.
    lastSeenActivity = activity
    logger.recordActivity(activity)

    // 3. Early return if no session logic is needed.
    guard let session = activeSession, state == .active else {
      return
    }

    if isOverrideActive {
      return
    }

    guard !isNudgeActive else {
      return
    }

    // 4. Evaluate distraction policy.
    if let distractionHit = distractionPolicy.staticHit(activity: activity) {
      if pendingNudgeActivity == activity { return }
      classificationTask?.cancel()
      classificationTask = nil
      scheduleDistractionWatchdog(for: activity, reason: distractionHit.reason)
    } else if distractionPolicy.needsLLMClassification(activity: activity) {
      classifyAmbiguousActivity(activity, session: session)
    } else {
      markActivityAllowed(activity)
    }
  }

  private func classifyAmbiguousActivity(_ activity: ActivityContext, session: FocusSession) {
    if pendingNudgeActivity == activity { return }

    driftWatchdog.cancel()
    classificationTask?.cancel()
    pendingNudgeActivity = activity

    let goal = session.goal
    let remainingMinutes = max(1, timer.remainingSeconds / 60)

    classificationTask = Task { @MainActor [weak self] in
      guard let self else { return }

      do {
        let classification = try await classificationClient.classifyDistraction(
          goal: goal,
          remainingMinutes: remainingMinutes,
          activity: activity
        )

        guard
          !Task.isCancelled,
          pendingNudgeActivity == activity,
          state == .active,
          !isNudgeActive,
          !isOverrideActive
        else {
          return
        }

        classificationTask = nil

        if classification.verdict == .distract,
           classification.score >= classificationThreshold
        {
          scheduleDistractionWatchdog(for: activity, reason: classification.reason)
        } else {
          markActivityAllowed(activity)
        }
      } catch {
        guard !Task.isCancelled else { return }
        markActivityAllowed(activity)
      }
    }
  }

  private func scheduleDistractionWatchdog(for activity: ActivityContext, reason: String) {
    pendingNudgeActivity = activity
    let returnPid = lastProductiveActivity?.processIdentifier

    // Use a watchdog to debounce accidental clicks (fires after 2s of continuous distraction).
    driftWatchdog.schedule { [weak self] in
      guard
        let self,
        state == .active,
        !self.isNudgeActive,
        !self.isOverrideActive
      else {
        return
      }

      presentNudge(
        for: activity,
        reason: reason,
        returnToProcessIdentifier: returnPid
      )
    }
  }

  private func markActivityAllowed(_ activity: ActivityContext) {
    driftWatchdog.cancel()
    classificationTask?.cancel()
    classificationTask = nil

    if pendingNudgeActivity == activity {
      pendingNudgeActivity = nil
    }

    lastProductiveActivity = activity
  }

  /// Fires the distraction callback so the window layer can expand and inject the chat message.
  private func presentNudge(for activity: ActivityContext, reason: String, returnToProcessIdentifier _: Int32?) {
    isNudgeActive = true
    pendingNudgeActivity = nil

    if
      activity.pageURL != nil,
      browserContextProvider.browser(for: activity.bundleIdentifier) != nil
    {
      startPendingDistraction(for: activity, reason: reason)
    } else {
      nudgeEvents.append(
        NudgeEvent(
          occurredAt: Date(),
          applicationName: activity.distractionLabel,
          justification: nil,
          outcome: .backToWork
        )
      )
    }

    onDistractionDetected?(activity)
  }

  // MARK: - Private Helpers

  private func tick() {
    if let overrideEndsAt, overrideEndsAt <= Date() {
      self.overrideEndsAt = nil
    }
    notifySessionStateChange()
  }

  private func finishSession(session: FocusSession) {
    timer.stop()
    driftWatchdog.cancel()
    classificationTask?.cancel()
    classificationTask = nil
    clearNudge()

    let summary = SessionSummary(
      goal: session.goal,
      startedAt: session.startedAt,
      endedAt: Date(),
      plannedDurationMinutes: session.durationMinutes,
      completedMinutes: session.durationMinutes - (timer.remainingSeconds / 60),
      nudgeCount: nudgeEvents.count,
      allowedOverrideCount: nudgeEvents.filter { if case .allowed = $0.outcome { return true }; return false }.count,
      deniedOverrideCount: nudgeEvents.filter { $0.outcome == .denied }.count,
      topDistractions: topDistractions(from: nudgeEvents),
      memorableArguments: memorableArguments(from: nudgeEvents)
    )

    latestSummary = summary
    activeSession = nil
    overrideEndsAt = nil
    state = .completed
    notifySessionStateChange()
    onSummaryAvailable?(summary)
  }

  private func topDistractions(from events: [NudgeEvent]) -> [String] {
    Dictionary(grouping: events, by: \.applicationName)
      .sorted { $0.value.count > $1.value.count }
      .prefix(3)
      .map { "\($0.key) (\($0.value.count))" }
  }

  private func memorableArguments(from events: [NudgeEvent]) -> [String] {
    Array(events
      .compactMap(\.justification)
      .sorted { $0.count > $1.count }
      .prefix(3))
  }

  private func clearNudge() {
    isNudgeActive = false
    pendingNudgeActivity = nil
    driftWatchdog.cancel()
    classificationTask?.cancel()
    classificationTask = nil
  }

  private func startPendingDistraction(for activity: ActivityContext, reason: String) {
    let deadline = Date().addingTimeInterval(10)
    pendingDistractionTask?.cancel()
    pendingDistraction = PendingDistraction(
      activity: activity,
      reason: reason,
      detectedAt: Date(),
      deadline: deadline,
      remainingSeconds: 10
    )
    schedulePendingDistractionTimeout(id: pendingDistraction?.id)
  }

  private func schedulePendingDistractionTimeout(id: PendingDistraction.ID?) {
    pendingDistractionTask = Task { @MainActor [weak self] in
      while let self, pendingDistraction?.id == id {
        guard let pendingDistraction else { return }

        if pendingDistraction.isExplaining {
          return
        }

        let remaining = max(0, Int(ceil(pendingDistraction.deadline.timeIntervalSinceNow)))
        self.pendingDistraction?.remainingSeconds = remaining

        if remaining <= 0 {
          closePendingDistraction(manual: false)
          return
        }

        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  private func handleCloseTabResult(
    _ result: BrowserTabContextProvider.CloseTabResult,
    for pendingDistraction: PendingDistraction,
    manual: Bool
  ) {
    guard self.pendingDistraction?.id == pendingDistraction.id else { return }

    switch result {
    case .closed:
      nudgeEvents.append(
        NudgeEvent(
          occurredAt: Date(),
          applicationName: pendingDistraction.label,
          justification: manual ? "Closed manually" : "Closed automatically after timeout",
          outcome: .denied
        )
      )
      self.pendingDistraction?.resolution = .closed
      clearPendingDistraction()
      onDistractionResolved?()
    case .urlMismatch:
      self.pendingDistraction?.resolution = .failed("The active tab changed, so Poro did not close it.")
      clearNudge()
    case let .failed(message):
      self.pendingDistraction?.resolution = .failed(message)
      clearNudge()
    }

    notifySessionStateChange()
  }

  private func clearPendingDistraction() {
    pendingDistractionTask?.cancel()
    pendingDistractionTask = nil
    pendingDistraction = nil
    clearNudge()
  }

  private func notifySessionStateChange() {
    onSessionStateChange?()
    onStatusItemUpdate?()
  }

  private func timeString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
  }

  // MARK: - Tool Snapshot Methods

  func hasAssistantContextForTools() -> Bool {
    hasActiveSession || latestSummary != nil || !nudgeEvents.isEmpty
  }

  func focusSessionStateSnapshot() -> FocusSessionStateToolResult {
    FocusSessionStateToolResult(
      isActive: hasActiveSession,
      isPaused: isPaused,
      goal: activeSession?.goal,
      remainingMinutes: hasActiveSession ? max(1, timer.remainingSeconds / 60) : nil,
      remainingTimeText: hasActiveSession ? timer.remainingTimeText : nil,
      startedAt: activeSession?.startedAt,
      overrideEndsAt: isOverrideActive ? overrideEndsAt : nil
    )
  }

  func currentActivitySnapshot() -> CurrentActivityToolResult {
    CurrentActivityToolResult(
      applicationName: lastSeenActivity?.applicationName,
      bundleIdentifier: lastSeenActivity?.bundleIdentifier,
      pageURL: lastSeenActivity?.pageURL?.absoluteString,
      pageHost: lastSeenActivity?.pageHost,
      pageTitle: lastSeenActivity?.pageTitle,
      pageAccessError: lastSeenActivity?.pageAccessError
    )
  }

  func activityLogSnapshot() -> String {
    logger.snapshot()
  }

  func recentDriftEventsSnapshot(limit: Int = 5) -> RecentDriftEventsToolResult {
    RecentDriftEventsToolResult(
      events: Array(nudgeEvents.suffix(limit)).map { event in
        .init(
          occurredAt: event.occurredAt,
          applicationName: event.applicationName,
          justification: event.justification,
          outcome: describeOutcome(event.outcome)
        )
      }
    )
  }

  func sessionStatsSnapshot() -> SessionStatsToolResult {
    let allowedOverrideCount = nudgeEvents.filter { if case .allowed = $0.outcome { return true }; return false }.count

    return SessionStatsToolResult(
      isActive: hasActiveSession,
      goal: activeSession?.goal,
      elapsedMinutes: activeSession.map { max(0, $0.durationMinutes - (timer.remainingSeconds / 60)) },
      remainingMinutes: hasActiveSession ? max(1, timer.remainingSeconds / 60) : nil,
      remainingTimeText: hasActiveSession ? timer.remainingTimeText : nil,
      nudgeCount: nudgeEvents.count,
      allowedOverrideCount: allowedOverrideCount,
      deniedOverrideCount: nudgeEvents.filter { $0.outcome == .denied }.count,
      topDistractions: topDistractions(from: nudgeEvents)
    )
  }

  private func describeOutcome(_ outcome: NudgeEvent.Outcome) -> String {
    switch outcome {
    case .backToWork: "back_to_work"
    case let .allowed(minutes): "allowed_\(minutes)_minutes"
    case .denied: "denied"
    }
  }
}
