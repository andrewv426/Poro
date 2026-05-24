import Foundation

enum ComposerMode: Equatable {
  case normal
  case slashMenu(prefix: String, matches: [SlashCommandDescriptor])
  case spotifyPlay(query: String)
  case spotifyPlaylistChip(query: String)
  case spotifyOptionPicker(state: SpotifyPickerState)
  case focusStart(args: String)
}

enum SpotifyPickerKind: Equatable {
  case track
  case playlist
}

struct SpotifyPickerState: Equatable {
  let kind: SpotifyPickerKind
  let query: String
  let options: [SpotifyPickerOption]
  var selectedIndex: Int
}

struct SpotifyPickerOption: Equatable, Identifiable {
  let id: String
  let uri: String
  let title: String
  let subtitle: String?
}
