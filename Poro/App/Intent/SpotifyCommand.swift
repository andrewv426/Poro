import Foundation

enum SpotifyCommand: Equatable {
  case play(query: SpotifyPlayQuery?)
  case playPlaylist(query: String?)
  case pause
  case skip
  case shuffle(enabled: Bool)
  case pickTrack(uri: String, displayName: String)
  case pickPlaylist(uri: String, displayName: String)
}

enum SpotifyPlayQuery: Equatable {
  case freeform(String)
  case trackByArtist(track: String, artist: String)
}
