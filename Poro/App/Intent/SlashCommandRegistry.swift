import Foundation

struct SlashCommandDescriptor: Equatable, Identifiable {
  let id: String
  let verb: String
  let title: String
  let subtitle: String
}

/// Single source of truth for the slash-command autocomplete menu. The parser
/// (`SlashCommandParser`) stays the dispatcher for known verbs; this registry just feeds the UI.
///
/// `/stop`, `/skip`, and `/shuffle` only surface while Spotify is actively playing — they're noise
/// otherwise. The caller threads `spotifyPlaying` in from `PoroController.spotifyIsPlaying`.
enum SlashCommandRegistry {
  static func all(spotifyPlaying: Bool) -> [SlashCommandDescriptor] {
    var commands: [SlashCommandDescriptor] = [
      SlashCommandDescriptor(
        id: "play",
        verb: "play",
        title: "/play",
        subtitle: "Play a song or playlist on Spotify"
      ),
      SlashCommandDescriptor(
        id: "focus",
        verb: "focus",
        title: "/focus",
        subtitle: "Start a focus session"
      ),
    ]

    if spotifyPlaying {
      commands.append(contentsOf: [
        SlashCommandDescriptor(
          id: "stop",
          verb: "stop",
          title: "/stop",
          subtitle: "Pause Spotify"
        ),
        SlashCommandDescriptor(
          id: "skip",
          verb: "skip",
          title: "/skip",
          subtitle: "Skip to the next track"
        ),
        SlashCommandDescriptor(
          id: "shuffle",
          verb: "shuffle",
          title: "/shuffle",
          subtitle: "Toggle shuffle on or off"
        ),
      ])
    }

    return commands
  }

  /// Returns commands whose verb starts with the given (case-insensitive) prefix. An empty prefix
  /// returns every command available in the current context.
  static func matches(prefix: String, spotifyPlaying: Bool) -> [SlashCommandDescriptor] {
    let lower = prefix.lowercased()
    let everything = all(spotifyPlaying: spotifyPlaying)
    if lower.isEmpty { return everything }
    return everything.filter { $0.verb.lowercased().hasPrefix(lower) }
  }
}
