import Foundation

enum SpotifyCommand: Equatable {
  case play(query: SpotifyPlayQuery?)
}

enum SpotifyPlayQuery: Equatable {
  case freeform(String)
  case trackByArtist(track: String, artist: String)
}
