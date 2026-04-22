import Foundation

struct FocusReadToolbox: AssistantToolbox, Sendable {
  private let focusSessionController: FocusSessionController

  init(focusSessionController: FocusSessionController) {
    self.focusSessionController = focusSessionController
  }

  let systemPrompt = """
    You are a focus coach and general assistant integrated into a macOS app called Poro.
    The user invokes you via a hotkey, and you respond to whatever they ask.

    When the user has an active focus session, you have access to tools that let you inspect their session state, current activity, and drift history. Use these tools liberally whenever session context might be relevant.

    - If the user asks how they are doing, how much time is left, what they have been up to, or similar status questions: call get_session_stats and get_focus_session_state.
    - If the user asks about their current activity or where they are: call get_current_activity.
    - If the user is reflecting on the session or asking for coaching advice: call get_recent_drift_events to ground your response in what actually happened.
    - If the user asks a general question unrelated to their session, do not call session tools.

    When you receive tool results, synthesize them into a natural response. Do not dump raw data. Speak like a coach: warm, direct, brief.
    Never mention tool names, function syntax, JSON, or parameters to the user. If you decide session context is relevant, call the tool instead of describing the call.
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
      "where am i",
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
      "where am i",
      "what am i on",
      "coach",
    ]

    if sessionKeywords.contains(where: latestUserMessage.contains) {
      return true
    }

    return focusSessionController.hasAssistantContextForTools()
      && ["how", "what", "why"].contains(where: latestUserMessage.contains)
  }

  func executeTool(named name: String, argumentsJSON: String) async throws -> String {
    _ = argumentsJSON
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
    default:
      throw LLMError.toolExecutionFailure("Unknown tool: \(name)")
    }

    guard let jsonString = String(data: encodedPayload, encoding: .utf8) else {
      throw LLMError.toolExecutionFailure("Failed to encode tool output for \(name).")
    }

    return jsonString
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
