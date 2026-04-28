import Foundation

/// Defines the outcome of an intent preview calculation.
struct IntentPreview {
  let intent: AppIntent?
  let hint: ComposerHint?
}

/// Orchestrates the routing of user input strings to specific application intents.
struct AppIntentRouter {
  private let parser = AppIntentParser()

  /// Calculates a preview of the intent that would be resolved if the current text were submitted.
  /// - Parameters:
  ///   - text: The current composer draft text.
  ///   - hasActiveSession: Whether a focus session is currently active.
  /// - Returns: An IntentPreview containing the potential intent and a visual hint for the user.
  func preview(for text: String, hasActiveSession: Bool) -> IntentPreview {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !trimmed.isEmpty else {
      return IntentPreview(intent: nil, hint: nil)
    }

    // High priority: Session control commands take precedence during an active session.
    if hasActiveSession, let command = parser.parseSessionCommand(from: trimmed) {
      return IntentPreview(
        intent: .sessionCommand(command),
        hint: ComposerHint(title: sessionCommandHint(for: command))
      )
    }

    // Normal priority: Detect intent to start a new focus session.
    if !hasActiveSession, let draft = parser.parseFocusStart(from: trimmed) {
      return IntentPreview(
        intent: .startFocus(draft),
        hint: ComposerHint(title: "↵ Start focus session")
      )
    }

    // Fallback: Default to a standard chat exchange.
    return IntentPreview(intent: .chat(trimmed), hint: nil)
  }

  /// Resolves the final intent for a submitted string.
  /// - Parameters:
  ///   - text: The submitted text.
  ///   - hasActiveSession: Whether a focus session is currently active.
  /// - Returns: The resolved AppIntent.
  func resolveSubmission(for text: String, hasActiveSession: Bool) -> AppIntent {
    let preview = preview(for: text, hasActiveSession: hasActiveSession)
    return preview.intent ?? .chat(text.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  /// Generates a localized hint string for session commands.
  /// - Parameter command: The command type.
  /// - Returns: A user-facing string describing the action.
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
}
