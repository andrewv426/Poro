import Foundation

struct FocusReadToolbox: AssistantToolbox, Sendable {
  private let focusSessionController: FocusSessionController
  private let toolLog: AssistantToolLog

  init(
    focusSessionController: FocusSessionController,
    toolLog: AssistantToolLog = AssistantToolLog()
  ) {
    self.focusSessionController = focusSessionController
    self.toolLog = toolLog
  }

  let systemPrompt = """
    You are a focus coach and general assistant integrated into a macOS app called Poro.
    The user invokes you via a hotkey, and you respond to whatever they ask.

    Below is the current [SYSTEM_CONTEXT] from the user's computer. Use this information to answer the user's question accurately.
    Never mention the words 'context', 'tool', 'JSON', or 'system' to the user.
    Synthesize the information into a natural, warm, and direct response. Speak like a coach.

    [SYSTEM_CONTEXT]
    {{CONTEXT}}

    If the [SYSTEM_CONTEXT] reports that there is no active focus session and the user's question implies one, clarify that there is no session running right now and ask whether they want to start one.
    """

  let toolDefinitions: [AssistantToolDefinition] = [
    .init(
      name: "get_focus_session_state",
      description: "Returns whether a focus session is active or paused, its goal, remaining time, and override state."
    ),
    .init(
      name: "get_current_activity",
      description: "Returns the current frontmost app and current browser URL or host when available."
    ),
    .init(
      name: "get_recent_drift_events",
      description: "Returns recent drift and nudge events, including outcomes like back to work, allowed override, or denied override."
    ),
    .init(
      name: "get_session_stats",
      description: "Returns high-level stats for the current focus session, including time spent, time left, and drift totals."
    ),
    .init(
      name: "get_activity_log",
      description: "Returns a compacted chronological log of applications and websites visited during the session."
    ),
    .init(
      name: "get_tool_call_log",
      description: "Returns the recent assistant tool-call log, including structured tool calls, fallbacks, and tool outputs."
    ),
  ]

  func shouldOfferTools(for messages: [ChatMessage]) async -> Bool {
    guard
      let latestUserMessage = messages.last(where: { $0.role == .user })?.text.lowercased()
    else {
      return false
    }

    let directSessionPhrases = [
      "how am i doing",
      "how much time left",
      "how much left",
      "what have i been up to",
      "what am i on",
      "what do i have open",
      "what do i have opened",
      "what do i have up",
      "what tab",
      "what page",
      "what site",
      "which tab",
      "which page",
      "which site",
      "which app",
      "where am i",
      "what have i been up to",
      "what was i doing",
      "history",
      "activity log",
      "how's my session",
      "hows my session",
      "how is my session",
      "session stats",
      "focus session",
      "recent drift",
      "recent nudges",
      "what distracted me",
      "what distracted",
      "how locked in",
      "am i drifting",
      "tool log",
      "tool call log",
      "debug tool",
      "debug tools",
      "how's it going",
      "hows it going",
      "how is it going",
    ]

    if directSessionPhrases.contains(where: latestUserMessage.contains) {
      return true
    }

    let sessionKeywords = [
      "session",
      "drift",
      "distract",
      "nudge",
      "override",
      "paused",
      "resume",
      "status",
      "time left",
      "remaining",
      "activity",
      "history",
      "log",
      "url",
      "title",
      "open",
      "opened",
      "tab",
      "page",
      "site",
      "browser",
      "arc",
      "where am i",
      "what am i on",
      "coach",
      "tool",
      "debug",
      "log",
    ]

    if sessionKeywords.contains(where: latestUserMessage.contains) {
      return true
    }

    return await focusSessionController.hasAssistantContextForTools()
      && ["how", "what", "why"].contains(where: latestUserMessage.contains)
  }

  /// Aggregates all relevant session and activity data into a single string for eager injection.
  func fetchAllContext() async -> String {
    let state = await focusSessionController.focusSessionStateSnapshot()
    let activity = await focusSessionController.currentActivitySnapshot()
    let stats = await focusSessionController.sessionStatsSnapshot()
    let log = await focusSessionController.activityLogSnapshot()

    var context = ""
    context += "Session Active: \(state.isActive)\n"
    if state.isActive {
      context += "Goal: \(state.goal ?? "None")\n"
      context += "Status: \(state.isPaused ? "Paused" : "Running")\n"
      context += "Time Remaining: \(state.remainingTimeText ?? "Unknown")\n"
      context += "Recent Stats: \(stats.nudgeCount) nudges, \(stats.allowedOverrideCount) allowed, \(stats.deniedOverrideCount) denied\n"
    }

    context += "Current App: \(activity.applicationName ?? "Unknown")\n"
    if let title = activity.pageTitle {
      context += "Active Tab Title: \(title)\n"
    }
    if let url = activity.pageURL {
      context += "Active Tab URL: \(url)\n"
    }
    if let error = activity.pageAccessError {
      context += "Browser Access Note: \(error)\n"
    }

    context += "\nActivity Log (Recent):\n\(log)\n"

    return context
  }

  func executeTool(named name: String, argumentsJSON: String) async throws -> String {
    await toolLog.append(
      phase: "tool_requested",
      toolName: name,
      detail: argumentsJSON
    )
    let encodedPayload: Data

    switch name {
    case "get_focus_session_state":
      let snapshot = await focusSessionController.focusSessionStateSnapshot()
      encodedPayload = try encode(snapshot)
    case "get_current_activity":
      let snapshot = await focusSessionController.currentActivitySnapshot()
      encodedPayload = try encode(snapshot)
    case "get_recent_drift_events":
      let snapshot = await focusSessionController.recentDriftEventsSnapshot()
      encodedPayload = try encode(snapshot)
    case "get_session_stats":
      let snapshot = await focusSessionController.sessionStatsSnapshot()
      encodedPayload = try encode(snapshot)
    case "get_activity_log":
      let log = await focusSessionController.activityLogSnapshot()
      encodedPayload = try encode(ActivityLogToolResult(log: log))
    case "get_tool_call_log":
      encodedPayload = try encode(ToolCallLogToolResult(entries: await toolLog.snapshot()))
    default:
      throw LLMError.toolExecutionFailure("Unknown tool: \(name)")
    }

    guard let jsonString = String(data: encodedPayload, encoding: .utf8) else {
      throw LLMError.toolExecutionFailure("Failed to encode tool output for \(name).")
    }

    await toolLog.append(
      phase: "tool_completed",
      toolName: name,
      detail: jsonString
    )

    return jsonString
  }

  func recordToolEvent(phase: String, toolName: String?, detail: String) async {
    await toolLog.append(phase: phase, toolName: toolName, detail: detail)
  }

  private func encode(_ payload: some Encodable) throws -> Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(payload)
  }
}

struct FocusSessionStateToolResult: Codable, Sendable {
  let isActive: Bool
  let isPaused: Bool
  let goal: String?
  let remainingMinutes: Int?
  let remainingTimeText: String?
  let startedAt: Date?
  let overrideEndsAt: Date?
}

struct CurrentActivityToolResult: Codable, Sendable {
  let applicationName: String?
  let bundleIdentifier: String?
  let pageURL: String?
  let pageHost: String?
  let pageTitle: String?
  let pageAccessError: String?
}

struct RecentDriftEventsToolResult: Codable, Sendable {
  struct Event: Codable, Sendable {
    let occurredAt: Date
    let applicationName: String
    let justification: String?
    let outcome: String
  }

  let events: [Event]
}

struct SessionStatsToolResult: Codable, Sendable {
  let isActive: Bool
  let goal: String?
  let elapsedMinutes: Int?
  let remainingMinutes: Int?
  let remainingTimeText: String?
  let nudgeCount: Int
  let allowedOverrideCount: Int
  let deniedOverrideCount: Int
  let topDistractions: [String]
}

struct ActivityLogToolResult: Codable, Sendable {
  let log: String
}

struct ToolCallLogToolResult: Codable, Sendable {
  let entries: [AssistantToolLogEntry]
}
