import Foundation

struct IntentPreview {
  let intent: AppIntent?
  let hint: ComposerHint?
}

struct AppIntentRouter {
  private let durationPattern = try! NSRegularExpression(
    pattern: #"(?i)\b(\d{1,3})\s*(min|mins|minute|minutes|hr|hrs|hour|hours)\b"#
  )

  func preview(for text: String, hasActiveSession: Bool) -> IntentPreview {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return IntentPreview(intent: nil, hint: nil)
    }

    if hasActiveSession, let command = parseSessionCommand(from: trimmed) {
      return IntentPreview(
        intent: .sessionCommand(command),
        hint: ComposerHint(title: sessionCommandHint(for: command))
      )
    }

    if !hasActiveSession, let draft = parseFocusStart(from: trimmed) {
      return IntentPreview(
        intent: .startFocus(draft),
        hint: ComposerHint(title: "↵ Start focus session")
      )
    }

    return IntentPreview(intent: .chat(trimmed), hint: nil)
  }

  func resolveSubmission(for text: String, hasActiveSession: Bool) -> AppIntent {
    let preview = preview(for: text, hasActiveSession: hasActiveSession)
    return preview.intent ?? .chat(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  private func parseFocusStart(from text: String) -> FocusStartDraft? {
    let lowercased = text.lowercased()
    let duration = parseDuration(from: text)
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

  private func parseSessionCommand(from text: String) -> SessionCommand? {
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

  private func sessionCommandHint(for command: SessionCommand) -> String {
    switch command {
    case .pause:
      return "↵ Pause focus session"
    case .resume:
      return "↵ Resume focus session"
    case .end:
      return "↵ End focus session"
    case .status:
      return "↵ Show session status"
    }
  }

  private func parseDuration(from text: String) -> Int? {
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

  private func parseFocusGoal(from text: String) -> String {
    var goal = text
    let lowercased = text.lowercased()

    if let range = lowercased.range(of: " on ") {
      goal = String(text[range.upperBound...])
    } else if let range = lowercased.range(of: " for ") {
      goal = String(text[range.upperBound...])

      if parseDuration(from: goal) != nil {
        goal = ""
      }
    } else {
      goal = text
    }

    goal = durationPattern.stringByReplacingMatches(
      in: goal,
      options: [],
      range: NSRange(goal.startIndex..<goal.endIndex, in: goal),
      withTemplate: ""
    )

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
