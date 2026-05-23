import Foundation

enum ComposerMode: Equatable {
  case normal
  case slashMenu(prefix: String, matches: [SlashCommandDescriptor])
  case spotifyPlay(query: String)
}
