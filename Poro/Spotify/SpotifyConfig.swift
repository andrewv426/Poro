import Foundation

enum SpotifyConfig {
  static func clientID() -> String? {
    let merged = EnvFileLoader.mergedEnvironment()
    guard let raw = merged["SPOTIFY_CLIENT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty
    else {
      return nil
    }
    return raw
  }
}
