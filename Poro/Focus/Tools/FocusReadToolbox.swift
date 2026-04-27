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

    When the user has an active focus session, you have access to tools that let you inspect their session state, current activity, activity log, and drift history. Use these tools liberally whenever session context might be relevant.

    - If the user asks how they are doing, how much time is left, what they have been up to, or similar status questions: call get_session_stats and get_focus_session_state.
    - If the user asks about their current activity, what tab they are on, or where they are: call get_current_activity.
    - If the user asks for a summary of their activity, what they have been doing recently, or their session history: call get_activity_log.
    - If the user is reflecting on the session or asking for coaching advice: call get_recent_drift_events to ground your response in what actually happened.
    - If the user asks a general question unrelated to their session, do not call session tools.

    When you receive tool results, synthesize them into a natural response. Do not dump raw data. Speak like a coach: warm, direct, brief.
    Never mention tool names, function syntax, JSON, or parameters to the user. If you decide session context is relevant, call the tool instead of describing the call.
    For current activity questions, never guess a page, tab, site, or title. Only report the app, URL, host, or page title that the tool explicitly returned. If the tool only gives you the app name or reports a page access error, say that directly and do not infer beyond it.
    If there is no active focus session and the user's question implied a session, clarify that there is no session running right now and ask whether they want to start one.
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

    return focusSessionController.hasAssistantContextForTools()
      && ["how", "what", "why"].contains(where: latestUserMessage.contains)
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
      encodedPayload = try encode(focusSessionController.focusSessionStateSnapshot())
    case "get_current_activity":
      encodedPayload = try encode(focusSessionController.currentActivitySnapshot())
    case "get_recent_drift_events":
      encodedPayload = try encode(focusSessionController.recentDriftEventsSnapshot())
    case "get_session_stats":
      encodedPayload = try encode(focusSessionController.sessionStatsSnapshot())
    case "get_activity_log":
      encodedPayload = try encode(ActivityLogToolResult(log: focusSessionController.activityLogSnapshot()))
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
