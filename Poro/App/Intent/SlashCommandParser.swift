import Foundation

enum SlashCommandParser {
  static func parse(_ trimmed: String) -> AppIntent? {
    guard trimmed.hasPrefix("/") else { return nil }

    let body = trimmed.dropFirst()
    let (verb, rest) = splitVerb(from: String(body))
    let args = rest.trimmingCharacters(in: .whitespacesAndNewlines)

    switch verb.lowercased() {
    case "play":
      // /play playlist [name] — explicit playlist subcommand, scoped to the user's playlists.
      if let playlistArgs = stripPlaylistSubverb(args) {
        return .spotify(.playPlaylist(query: playlistArgs.isEmpty ? nil : playlistArgs))
      }
      guard !args.isEmpty else { return .spotify(.play(query: nil)) }
      return .spotify(.play(query: parsePlayQuery(args)))
    case "stop", "pause":
      return .spotify(.pause)
    case "skip", "next":
      return .spotify(.skip)
    case "shuffle":
      return .spotify(.shuffle(enabled: parseShuffleState(args)))
    case "focus":
      let parser = AppIntentParser()
      let duration = parser.parseDuration(from: args) ?? 45
      // Prepend a space so goal-extraction's " on "/" for " matchers find clauses
      // that start at the beginning of the trimmed args (e.g. "/focus on writing").
      let goal = parser.parseFocusGoal(from: " " + args)
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

  /// If the args to `/play` begin with the literal token "playlist", return the remainder. Returns
  /// nil otherwise so the caller can treat the whole string as a freeform track query.
  private static func stripPlaylistSubverb(_ args: String) -> String? {
    let lower = args.lowercased()
    if lower == "playlist" { return "" }
    if lower.hasPrefix("playlist ") {
      let idx = args.index(args.startIndex, offsetBy: "playlist ".count)
      return String(args[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return nil
  }

  /// `/shuffle off` (and aliases) → false, anything else (including bare `/shuffle`) → true.
  private static func parseShuffleState(_ args: String) -> Bool {
    switch args.lowercased() {
    case "off", "false", "no", "disable", "stop":
      false
    default:
      true
    }
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
