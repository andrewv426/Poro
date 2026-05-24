import Foundation

enum SlashCommandParser {
  static func parse(_ trimmed: String) -> AppIntent? {
    guard trimmed.hasPrefix("/") else { return nil }

    let body = trimmed.dropFirst()
    let (verb, rest) = splitVerb(from: String(body))

    switch verb.lowercased() {
    case "play":
      let query = rest.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !query.isEmpty else { return .spotify(.play(query: nil)) }
      return .spotify(.play(query: parsePlayQuery(query)))
    case "focus":
      let parser = AppIntentParser()
      let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
      let duration = parser.parseDuration(from: trimmed) ?? 45
      // Prepend a space so goal-extraction's " on "/" for " matchers find clauses
      // that start at the beginning of the trimmed args (e.g. "/focus on writing").
      let goal = parser.parseFocusGoal(from: " " + trimmed)
      return .startFocus(FocusStartDraft(goal: goal, durationMinutes: duration))
    default:
      return nil
    }
  }

  private static func splitVerb(from text: String) -> (verb: String, rest: String) {
    guard let spaceIdx = text.firstIndex(where: { $0.isWhitespace }) else {
      return (text, "")
    }
    let verb = String(text[..<spaceIdx])
    let rest = String(text[text.index(after: spaceIdx)...])
    return (verb, rest)
  }

  /// Splits "<song> by <artist>" into a track+artist pair, otherwise returns the raw text as a
  /// freeform query. Uses `.backwards` so "X by Y by Z" treats Z as the artist.
  private static func parsePlayQuery(_ text: String) -> SpotifyPlayQuery {
    if let range = text.range(of: " by ", options: [.caseInsensitive, .backwards]) {
      let track = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
      let artist = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
      if !track.isEmpty, !artist.isEmpty {
        return .trackByArtist(track: track, artist: artist)
      }
    }
    return .freeform(text)
  }
}
