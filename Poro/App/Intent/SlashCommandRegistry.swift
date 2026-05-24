import Foundation

struct SlashCommandDescriptor: Equatable, Identifiable {
  let id: String
  let verb: String
  let title: String
  let subtitle: String
}

/// Single source of truth for the slash-command autocomplete menu. The parser
/// (`SlashCommandParser`) stays the dispatcher for known verbs; this registry just feeds the UI.
enum SlashCommandRegistry {
  static let all: [SlashCommandDescriptor] = [
    SlashCommandDescriptor(
      id: "play",
      verb: "play",
      title: "/play",
      subtitle: "Play a song on Spotify"
    ),
    SlashCommandDescriptor(
      id: "focus",
      verb: "focus",
      title: "/focus",
      subtitle: "Start a focus session"
    ),
  ]

  /// Returns commands whose verb starts with the given (case-insensitive) prefix. An empty prefix
  /// returns every command.
  static func matches(prefix: String) -> [SlashCommandDescriptor] {
    let lower = prefix.lowercased()
    if lower.isEmpty { return all }
    return all.filter { $0.verb.lowercased().hasPrefix(lower) }
  }
}
