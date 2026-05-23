import Foundation

enum SpotifyAppleScript {
  /// Builds the AppleScript source to play the top track for `query`. Uses the `track:` scope so
  /// Spotify ranks tracks ahead of playlists/podcasts.
  static func playSource(_ query: SpotifyPlayQuery) -> String {
    let inner: String = switch query {
    case let .freeform(text):
      percentEncode(text)
    case let .trackByArtist(track, artist):
      quotedTerm("track", track) + "%20" + quotedTerm("artist", artist)
    }
    return "tell application id \"com.spotify.client\" to play track \"spotify:search:track:\(inner)\""
  }

  /// Builds the AppleScript source to resume current playback.
  static func resumeSource() -> String {
    "tell application id \"com.spotify.client\" to play"
  }

  /// Wraps a search term in `field:"value"` form. `%22` is the encoded double-quote so the term is
  /// safe inside the surrounding AppleScript string literal.
  private static func quotedTerm(_ field: String, _ value: String) -> String {
    "\(field):%22\(percentEncode(value))%22"
  }

  /// Percent-encodes a query so it can sit safely inside a `spotify:search:` URI embedded in
  /// AppleScript. We restrict the allowed set tightly because the URI itself is wrapped in
  /// AppleScript double quotes.
  private static func percentEncode(_ query: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "\"\\")
    return query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
  }
}
