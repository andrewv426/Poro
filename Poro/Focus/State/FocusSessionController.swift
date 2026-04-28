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
  private var isNudgeActive: Bool = false
  private(set) var overrideEndsAt: Date?

  // Callbacks for UI and state updates.
  var onDistractionDetected: ((ActivityContext) -> Void)?
  var onSessionStateChange: (() -> Void)?
  var onStatusItemUpdate: (() -> Void)?
  var onSummaryAvailable: ((SessionSummary) -> Void)?

  // Internal managers and monitors.
  private let decisionClient: FocusDecisionEvaluating
  private let activityMonitor: FrontmostActivityMonitor
  private let driftWatchdog: DriftWatchdog
  private let distractionPolicy: DistractionPolicy
  private let timer = FocusTimer()
  private let logger = SessionActivityLogger()

  // Internal state for activity tracking.
  private var nudgeEvents: [NudgeEvent] = []
  private var lastProductiveActivity: ActivityContext?
  private var lastSeenActivity: ActivityContext?
  private var pendingNudgeActivity: ActivityContext?

  /// Initializes the controller and starts the activity monitor.
  init(
    decisionClient: FocusDecisionEvaluating,
    activityMonitor: FrontmostActivityMonitor,
    driftWatchdog: DriftWatchdog,
    distractionPolicy: DistractionPolicy
  ) {
    self.decisionClient = decisionClient
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

    do {
      let configuration = try LLMConfiguration.loadFromEnvironment()
      decisionClient = CerebrasFocusDecisionClient(configuration: configuration)
    } catch {
      decisionClient = UnavailableFocusDecisionClient(error: error)
    }

    self.init(
      decisionClient: decisionClient,
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
    overrideEndsAt = nil
    nudgeEvents.removeAll()
    logger.reset()
    lastProductiveActivity = nil
    lastSeenActivity = nil
    pendingNudgeActivity = nil
    
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
    clearNudge()
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
    if let distractionHit = distractionPolicy.evaluate(activity: activity, goal: session.goal) {
      if pendingNudgeActivity == activity { return }

      pendingNudgeActivity = activity
      let returnPid = lastProductiveActivity?.processIdentifier

      // Use a watchdog to debounce accidental clicks (fires after 2s of continuous distraction).
      driftWatchdog.schedule { [weak self] in
        guard
          let self,
          self.state == .active,
          !self.isNudgeActive,
          !self.isOverrideActive
        else {
          return
        }

        self.presentNudge(
          for: activity,
          reason: distractionHit.reason,
          returnToProcessIdentifier: returnPid
        )
      }
    } else {
      driftWatchdog.cancel()
      pendingNudgeActivity = nil
      lastProductiveActivity = activity
    }
  }

  /// Fires the distraction callback so the window layer can expand and inject the chat message.
  private func presentNudge(for activity: ActivityContext, reason: String, returnToProcessIdentifier: Int32?) {
    isNudgeActive = true
    pendingNudgeActivity = nil
    nudgeEvents.append(
      NudgeEvent(
        occurredAt: Date(),
        applicationName: activity.distractionLabel,
        justification: nil,
        outcome: .backToWork
      )
    )
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
    case .backToWork: return "back_to_work"
    case .allowed(let minutes): return "allowed_\(minutes)_minutes"
    case .denied: return "denied"
    }
  }
}
