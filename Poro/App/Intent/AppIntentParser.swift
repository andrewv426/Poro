import Foundation

/// A dedicated parser for extracting focus session parameters and user intents from natural language strings.
struct AppIntentParser {
  private let durationPattern = try! NSRegularExpression(
    pattern: #"(?i)\b(\d{1,3})\s*(min|mins|minute|minutes|hr|hrs|hour|hours)\b"#
  )

  /// Parses a string to determine if the user wants to start a focus session.
  /// - Parameter text: The user's input text.
  /// - Returns: A FocusStartDraft if a focus intent is detected, otherwise nil.
  func parseFocusStart(from text: String) -> FocusStartDraft? {
    let lowercased = text.lowercased()
    let duration = parseDuration(from: text)
    
    // Check for verbs or phrases that indicate starting a focus session.
    let hasSessionVerb =
      lowercased.contains("start focus")
      || lowercased.contains("focus session")
      || lowercased.contains("lock in")
      || lowercased.contains("keep me focused")
      || lowercased.contains("stay off")
      || (lowercased.hasPrefix("focus ") && duration != nil)
      || lowercased.hasPrefix("focus for ")

    guard hasSessionVerb else {
      return nil
    }

    let durationMinutes = duration ?? 50
    let goal = parseFocusGoal(from: text)

    // Ensure there is enough context to justify transitioning to the focus setup screen.
    guard duration != nil || lowercased.contains("session") || lowercased.contains("lock in")
      || lowercased.contains("stay off") || lowercased.contains("keep me focused")
      || lowercased.contains("start focus")
    else {
      return nil
    }

    return FocusStartDraft(
      goal: goal,
      durationMinutes: durationMinutes
    )
  }

  /// Parses a string to identify session control commands (pause, resume, end, status).
  /// - Parameter text: The user's input text.
  /// - Returns: A SessionCommand if identified, otherwise nil.
  func parseSessionCommand(from text: String) -> SessionCommand? {
    let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    if ["pause", "pause session", "hold focus"].contains(lowercased) {
      return .pause
    }

    if ["resume", "resume session", "continue"].contains(lowercased) {
      return .resume
    }

    if ["end", "stop", "end session", "stop session", "finish session"].contains(lowercased) {
      return .end
    }

    if lowercased == "status" || lowercased == "how much left" || lowercased == "time left"
      || lowercased == "how much time left" || lowercased == "how much time is left"
    {
      return .status
    }

    return nil
  }

  /// Extracts duration in minutes from a string (e.g., "20 mins", "1 hour").
  /// - Parameter text: The user's input text.
  /// - Returns: The parsed duration in minutes, or nil if not found.
  func parseDuration(from text: String) -> Int? {
    let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)

    guard
      let match = durationPattern.firstMatch(in: text, options: [], range: nsRange),
      let valueRange = Range(match.range(at: 1), in: text),
      let unitRange = Range(match.range(at: 2), in: text),
      let rawValue = Int(text[valueRange])
    else {
      return nil
    }

    let unit = text[unitRange].lowercased()

    if unit.hasPrefix("h") {
      return rawValue * 60
    }

    return rawValue
  }

  /// Extracts the focus goal by stripping out session-related verbs and duration patterns.
  /// - Parameter text: The user's input text.
  /// - Returns: A cleaned string representing the user's intended focus goal.
  func parseFocusGoal(from text: String) -> String {
    var goal = text
    let lowercased = text.lowercased()

    // Identify the goal portion using common separators.
    if let range = lowercased.range(of: " on ") {
      goal = String(text[range.upperBound...])
    } else if let range = lowercased.range(of: " for ") {
      goal = String(text[range.upperBound...])

      // If "for" is followed by a duration, the goal might be empty or come before it.
      if parseDuration(from: goal) != nil {
        goal = ""
      }
    }

    // Strip out the duration pattern.
    goal = durationPattern.stringByReplacingMatches(
      in: goal,
      options: [],
      range: NSRange(goal.startIndex..<goal.endIndex, in: goal),
      withTemplate: ""
    )

    // Clean up residual command verbs.
    let strippedPhrases = [
      "start focus session",
      "focus session",
      "focus",
      "lock in",
      "keep me focused",
      "stay off",
      "for the next",
      "for"
    ]

    let cleaned = strippedPhrases.reduce(goal) { partial, phrase in
      partial.replacingOccurrences(of: phrase, with: "", options: .caseInsensitive)
    }

    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
