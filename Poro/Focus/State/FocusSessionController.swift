import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class FocusSessionController {
  enum State: Equatable {
    case idle
    case active
    case paused
    case completed
  }

  private(set) var state: State = .idle
  private(set) var activeSession: FocusSession?
  private(set) var remainingSeconds: Int = 0
  private(set) var currentNudge: NudgeContext?
  private(set) var latestSummary: SessionSummary?
  private(set) var overrideEndsAt: Date?

  var onNudgeChange: ((NudgeContext?) -> Void)?
  var onSessionStateChange: (() -> Void)?
  var onSummaryAvailable: ((SessionSummary) -> Void)?

  private let decisionClient: FocusDecisionEvaluating
  private let activityMonitor: FrontmostActivityMonitor
  private let driftWatchdog: DriftWatchdog
  private let distractionPolicy: DistractionPolicy

  private var countdownTimer: Timer?
  private var nudgeEvents: [NudgeEvent] = []
  private var lastProductiveActivity: ActivityContext?
  private var lastSeenActivity: ActivityContext?
  private var pendingNudgeActivity: ActivityContext?

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

    activityMonitor.onActivityChange = { [weak self] activity in
      self?.handleActivityChange(activity)
    }
  }

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

  var hasActiveSession: Bool {
    activeSession != nil && state != .completed
  }

  var isPaused: Bool {
    state == .paused
  }

  var isOverrideActive: Bool {
    guard let overrideEndsAt else {
      return false
    }

    return overrideEndsAt > Date()
  }

  var statusLine: String? {
    guard let session = activeSession else {
      return nil
    }

    switch state {
    case .paused:
      return "Paused • \(remainingTimeText) left"
    case .active:
      if isOverrideActive, let overrideEndsAt {
        return "Override until \(timeString(for: overrideEndsAt)) • \(remainingTimeText) left"
      }

      return "\(remainingTimeText) left • \(session.goal)"
    case .completed:
      return "Session complete"
    case .idle:
      return nil
    }
  }

  var remainingTimeText: String {
    guard remainingSeconds > 0 else {
      return "0m"
    }

    let hours = remainingSeconds / 3600
    let minutes = (remainingSeconds % 3600) / 60

    if hours > 0 {
      return "\(hours)h \(minutes)m"
    }

    return "\(max(1, minutes))m"
  }

  var statusItemText: String? {
    guard hasActiveSession else {
      return nil
    }

    let prefix = isPaused ? "⏸" : "◔"
    return "\(prefix) \(remainingTimeText)"
  }

  func startSession(goal: String, durationMinutes: Int) {
    let trimmedGoal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedGoal = trimmedGoal.isEmpty ? "your work" : trimmedGoal
    let resolvedDuration = max(1, durationMinutes)

    activeSession = FocusSession(
      goal: resolvedGoal,
      durationMinutes: resolvedDuration,
      startedAt: Date()
    )
    remainingSeconds = resolvedDuration * 60
    state = .active
    latestSummary = nil
    overrideEndsAt = nil
    nudgeEvents.removeAll()
    lastProductiveActivity = nil
    lastSeenActivity = nil
    pendingNudgeActivity = nil
    clearNudge()
    startCountdownTimer()
    activityMonitor.start()
    notifySessionStateChange()
  }

  func pauseSession() {
    guard state == .active else {
      return
    }

    state = .paused
    driftWatchdog.cancel()
    clearNudge()
    notifySessionStateChange()
  }

  func resumeSession() {
    guard state == .paused else {
      return
    }

    state = .active
    notifySessionStateChange()
  }

  func endSession() {
    guard let session = activeSession else {
      return
    }

    finishSession(session: session)
  }

  func dismissSummary() {
    latestSummary = nil
    if state == .completed {
      state = .idle
    }
    notifySessionStateChange()
  }

  func beginArguing() {
    guard var nudge = currentNudge else {
      return
    }

    nudge.stage = .arguing
    currentNudge = nudge
    notifyNudgeChange()
  }

  func updateJustificationDraft(_ text: String) {
    guard var nudge = currentNudge else {
      return
    }

    nudge.justificationDraft = text
    currentNudge = nudge
    notifyNudgeChange()
  }

  func backToWork() {
    guard let nudge = currentNudge else {
      return
    }

    nudgeEvents.append(
      NudgeEvent(
        occurredAt: Date(),
        applicationName: nudge.activity.distractionLabel,
        justification: nil,
        outcome: .backToWork
      )
    )
    refocusPreviousApp(for: nudge)
    clearNudge()
  }

  func submitArgument() {
    guard
      var nudge = currentNudge,
      let session = activeSession
    else {
      return
    }

    let justification = nudge.justificationDraft.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !justification.isEmpty else {
      return
    }

    nudge.stage = .evaluating
    currentNudge = nudge
    notifyNudgeChange()

    let nudgesToday = nudgeEvents.count
    let allowedOverrides = nudgeEvents.filter {
      if case .allowed = $0.outcome {
        return true
      }
      return false
    }.count

    Task { [weak self] in
      guard let self else {
        return
      }

      do {
        let decision = try await decisionClient.evaluateDecision(
          goal: session.goal,
          remainingMinutes: max(1, remainingSeconds / 60),
          activity: nudge.activity,
          justification: justification,
          nudgesToday: nudgesToday,
          allowedOverrides: allowedOverrides
        )
        self.applyDecision(decision, justification: justification)
      } catch {
        self.applyDecision(
          FocusDecision(
            verdict: .deny,
            message: (error as? LocalizedError)?.errorDescription ?? "Couldn't verify that. Back to work.",
            allowMinutes: nil
          ),
          justification: justification
        )
      }
    }
  }

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
      guard let session = activeSession else {
        return "There isn't an active focus session right now."
      }
      return "You have \(remainingTimeText) left on '\(session.goal)'."
    }
  }

  private func applyDecision(_ decision: FocusDecision, justification: String) {
    guard var nudge = currentNudge else {
      return
    }

    nudge.stage = .resolved(decision)
    currentNudge = nudge

    switch decision.verdict {
    case .allow:
      let grantedMinutes = decision.allowMinutes ?? 5
      overrideEndsAt = Date().addingTimeInterval(TimeInterval(grantedMinutes * 60))
      nudgeEvents.append(
        NudgeEvent(
          occurredAt: Date(),
          applicationName: nudge.activity.distractionLabel,
          justification: justification,
          outcome: .allowed(grantedMinutes)
        )
      )
    case .deny:
      nudgeEvents.append(
        NudgeEvent(
          occurredAt: Date(),
          applicationName: nudge.activity.distractionLabel,
          justification: justification,
          outcome: .denied
        )
      )
    }

    notifyNudgeChange()

    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      try? await Task.sleep(nanoseconds: 1_400_000_000)

      guard let currentNudge = self.currentNudge, currentNudge.id == nudge.id else {
        return
      }

      if decision.verdict == .deny {
        self.refocusPreviousApp(for: currentNudge)
      }

      self.clearNudge()
      self.notifySessionStateChange()
    }
  }

  private func handleActivityChange(_ activity: ActivityContext) {
    lastSeenActivity = activity

    guard activity.bundleIdentifier != Bundle.main.bundleIdentifier else {
      return
    }

    guard let session = activeSession, state == .active else {
      return
    }

    if isOverrideActive {
      return
    }

    guard currentNudge == nil else {
      return
    }

    if let distractionHit = distractionPolicy.evaluate(activity: activity, goal: session.goal) {
      if pendingNudgeActivity == activity {
        return
      }

      pendingNudgeActivity = activity
      let returnPid = lastProductiveActivity?.processIdentifier

      driftWatchdog.schedule { [weak self] in
        guard
          let self,
          self.state == .active,
          self.currentNudge == nil,
          self.lastSeenActivity == activity,
          self.pendingNudgeActivity == activity,
          self.overrideEndsAt.map({ $0 > Date() }) != true
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

  private func presentNudge(
    for activity: ActivityContext,
    reason: String,
    returnToProcessIdentifier: Int32?
  ) {
    guard let session = activeSession else {
      return
    }

    currentNudge = NudgeContext(
      activity: activity,
      prompt: "You're on \(activity.distractionLabel). This isn't part of '\(session.goal)'. Keep going?",
      returnToProcessIdentifier: returnToProcessIdentifier,
      stage: .prompted,
      justificationDraft: ""
    )
    pendingNudgeActivity = nil
    notifyNudgeChange()
  }

  private func startCountdownTimer() {
    countdownTimer?.invalidate()
    countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.tick()
      }
    }
  }

  private func tick() {
    if let overrideEndsAt, overrideEndsAt <= Date() {
      self.overrideEndsAt = nil
    }

    guard state == .active, activeSession != nil else {
      notifySessionStateChange()
      return
    }

    remainingSeconds = max(0, remainingSeconds - 1)

    if remainingSeconds == 0, let session = activeSession {
      finishSession(session: session)
      return
    }

    notifySessionStateChange()
  }

  private func finishSession(session: FocusSession) {
    countdownTimer?.invalidate()
    countdownTimer = nil
    driftWatchdog.cancel()
    activityMonitor.stop()
    clearNudge()

    let summary = SessionSummary(
      goal: session.goal,
      startedAt: session.startedAt,
      endedAt: Date(),
      plannedDurationMinutes: session.durationMinutes,
      completedMinutes: session.durationMinutes - (remainingSeconds / 60),
      nudgeCount: nudgeEvents.count,
      allowedOverrideCount: nudgeEvents.filter {
        if case .allowed = $0.outcome { return true }
        return false
      }.count,
      deniedOverrideCount: nudgeEvents.filter { $0.outcome == .denied }.count,
      topDistractions: topDistractions(from: nudgeEvents),
      memorableArguments: memorableArguments(from: nudgeEvents)
    )

    latestSummary = summary
    activeSession = nil
    remainingSeconds = 0
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
    events
      .compactMap(\.justification)
      .sorted { $0.count > $1.count }
      .prefix(3)
      .map { $0 }
  }

  private func refocusPreviousApp(for nudge: NudgeContext) {
    guard let pid = nudge.returnToProcessIdentifier else {
      return
    }

    NSWorkspace.shared.runningApplications
      .first(where: { $0.processIdentifier == pid })?
      .activate(options: [])
  }

  private func clearNudge() {
    currentNudge = nil
    pendingNudgeActivity = nil
    driftWatchdog.cancel()
    notifyNudgeChange()
  }

  private func notifyNudgeChange() {
    onNudgeChange?(currentNudge)
  }

  private func notifySessionStateChange() {
    onSessionStateChange?()
  }

  private func timeString(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.timeStyle = .short
    formatter.dateStyle = .none
    return formatter.string(from: date)
  }
}
