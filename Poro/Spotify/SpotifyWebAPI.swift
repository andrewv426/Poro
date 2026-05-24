import Foundation
import OSLog

private let logger = Logger(subsystem: "andrewvong.Poro", category: "SpotifyWebAPI")

enum SpotifyAPIError: Error, Equatable, LocalizedError {
  case notAuthorized // 401 after refresh
  case premiumRequired // 403 from /v1/me/player/play (or scope-insufficient endpoints)
  case noDevice // 404 device-not-found
  case network(String)
  case decoding

  var errorDescription: String? {
    switch self {
    case .notAuthorized:
      "Not authorized. Re-link Poro to Spotify."
    case .premiumRequired:
      "Spotify rejected the request (Premium or missing scope). Try re-linking Poro."
    case .noDevice:
      "No active Spotify device. Open Spotify on your phone, desktop, or web player and play something briefly so it becomes the active device."
    case let .network(reason):
      "Network error: \(reason)"
    case .decoding:
      "Spotify returned an unexpected response format."
    }
  }
}

struct SpotifyTrackHit: Equatable {
  let uri: String
  let displayName: String
}

struct SpotifyPlaylistHit: Equatable, Identifiable {
  let id: String
  let uri: String
  let name: String
  let ownerName: String?
}

struct SpotifyPlaybackState: Equatable {
  let isPlaying: Bool
  let deviceID: String?
  let shuffleState: Bool
  /// `spotify:playlist:...` / `spotify:album:...` / `spotify:artist:...` when playback was started
  /// from such a context. `nil` when listening to a one-off track or queue.
  let contextURI: String?
  /// Primary-artist URI of the currently playing item (e.g. `spotify:artist:abc123`). Used by the
  /// context-aware shuffle path to fall back to artist-top-tracks when no context exists.
  let currentTrackPrimaryArtistURI: String?
}

struct SpotifyDevice: Equatable, Decodable {
  let id: String?
  let isActive: Bool
  let name: String

  enum CodingKeys: String, CodingKey {
    case id
    case isActive = "is_active"
    case name
  }
}

/// Lightweight client for the Spotify Web API. Covers the endpoints needed for /play, /stop, /skip,
/// /shuffle, and the option-picker flow: search (track + playlist), devices, transport controls,
/// user playlists, current playback state. Auth tokens come from `SpotifyAuth`.
struct SpotifyWebAPI {
  let auth: SpotifyAuth
  /// When `false`, the client refuses to trigger the interactive OAuth web view — token
  /// fetches that would otherwise re-authorize surface `.notAuthorized` instead. Background
  /// pollers should pass `false`; user-initiated commands keep the default `true`.
  let interactiveAuth: Bool

  init(auth: SpotifyAuth, interactiveAuth: Bool = true) {
    self.auth = auth
    self.interactiveAuth = interactiveAuth
  }

  private let apiBase = URL(string: "https://api.spotify.com/v1")!

  // MARK: - Search

  func search(_ query: SpotifyPlayQuery) async throws -> SpotifyTrackHit? {
    try await searchTracks(query, limit: 1).first
  }

  func searchTracks(_ query: SpotifyPlayQuery, limit: Int = 5) async throws -> [SpotifyTrackHit] {
    let q: String = switch query {
    case let .freeform(text): text
    case let .trackByArtist(track, artist): "track:\"\(track)\" artist:\"\(artist)\""
    }

    // Over-fetch so the dedupe step still has room to surface `limit` distinct results.
    // Spotify's top hits for a song usually include explicit + clean and single + album
    // variants — same display string, different URIs — which we collapse below.
    let fetchLimit = min(50, limit * 2)
    var components = URLComponents(url: apiBase.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "q", value: q),
      URLQueryItem(name: "type", value: "track"),
      URLQueryItem(name: "limit", value: String(fetchLimit)),
    ]

    let data = try await send(method: "GET", url: components.url!)

    do {
      let response = try JSONDecoder().decode(SearchResponse.self, from: data)
      var seen = Set<String>()
      let unique = response.tracks.items.compactMap { track -> SpotifyTrackHit? in
        let primaryArtist = track.artists.first?.name ?? ""
        let key = "\(track.name.lowercased())\u{1F}\(primaryArtist.lowercased())"
        guard seen.insert(key).inserted else { return nil }
        let artists = track.artists.map(\.name).joined(separator: ", ")
        return SpotifyTrackHit(uri: track.uri, displayName: "\(track.name) by \(artists)")
      }
      return Array(unique.prefix(limit))
    } catch {
      throw SpotifyAPIError.decoding
    }
  }

  func searchPlaylists(_ query: String, limit: Int = 5) async throws -> [SpotifyPlaylistHit] {
    var components = URLComponents(url: apiBase.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "q", value: query),
      URLQueryItem(name: "type", value: "playlist"),
      URLQueryItem(name: "limit", value: String(limit)),
    ]

    let data = try await send(method: "GET", url: components.url!)

    do {
      let response = try JSONDecoder().decode(PlaylistSearchResponse.self, from: data)
      return response.playlists.items.compactMap(Self.toPlaylistHit)
    } catch {
      throw SpotifyAPIError.decoding
    }
  }

  // MARK: - User playlists

  func userPlaylists(limit: Int = 50) async throws -> [SpotifyPlaylistHit] {
    var components = URLComponents(url: apiBase.appendingPathComponent("me/playlists"), resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

    let data = try await send(method: "GET", url: components.url!)

    do {
      let response = try JSONDecoder().decode(UserPlaylistsResponse.self, from: data)
      return response.items.compactMap(Self.toPlaylistHit)
    } catch {
      throw SpotifyAPIError.decoding
    }
  }

  // MARK: - Devices

  func devices() async throws -> [SpotifyDevice] {
    let url = apiBase.appendingPathComponent("me/player/devices")
    let data = try await send(method: "GET", url: url)
    do {
      let response = try JSONDecoder().decode(DevicesResponse.self, from: data)
      return response.devices
    } catch {
      throw SpotifyAPIError.decoding
    }
  }

  // MARK: - Playback state

  /// Returns the current playback state, or `nil` when Spotify reports 204 (nothing playing /
  /// no active device). 404 is also mapped to `nil` so callers can short-circuit cleanly.
  func currentlyPlaying() async throws -> SpotifyPlaybackState? {
    let url = apiBase.appendingPathComponent("me/player")
    do {
      let data = try await send(method: "GET", url: url)
      if data.isEmpty { return nil }
      let response = try JSONDecoder().decode(PlayerStateResponse.self, from: data)
      return SpotifyPlaybackState(
        isPlaying: response.isPlaying,
        deviceID: response.device?.id ?? nil,
        shuffleState: response.shuffleState ?? false,
        contextURI: response.context?.uri,
        currentTrackPrimaryArtistURI: response.item?.artists?.first?.resolvedURI
      )
    } catch SpotifyAPIError.noDevice {
      return nil
    } catch SpotifyAPIError.decoding {
      throw SpotifyAPIError.decoding
    }
  }

  // MARK: - Play (track URI)

  func play(trackURI: String, deviceID: String?) async throws {
    let body = try JSONSerialization.data(withJSONObject: ["uris": [trackURI]])
    _ = try await send(method: "PUT", url: playURL(deviceID: deviceID), body: body)
  }

  /// Start playback in the context of a playlist/album/artist URI (`spotify:playlist:...`,
  /// `spotify:album:...`, or `spotify:artist:...`).
  func playContext(contextURI: String, deviceID: String?) async throws {
    let body = try JSONSerialization.data(withJSONObject: ["context_uri": contextURI])
    _ = try await send(method: "PUT", url: playURL(deviceID: deviceID), body: body)
  }

  /// Resume current playback (no body). Used when the user types `/play` with no query.
  func resume(deviceID: String?) async throws {
    _ = try await send(method: "PUT", url: playURL(deviceID: deviceID))
  }

  // MARK: - Transport controls

  func pause(deviceID: String?) async throws {
    let url = transportURL(path: "me/player/pause", deviceID: deviceID)
    _ = try await send(method: "PUT", url: url)
  }

  func skipNext(deviceID: String?) async throws {
    let url = transportURL(path: "me/player/next", deviceID: deviceID)
    _ = try await send(method: "POST", url: url)
  }

  func setShuffle(enabled: Bool, deviceID: String?) async throws {
    var components = URLComponents(
      url: apiBase.appendingPathComponent("me/player/shuffle"),
      resolvingAgainstBaseURL: false
    )!
    var items = [URLQueryItem(name: "state", value: enabled ? "true" : "false")]
    if let deviceID {
      items.append(URLQueryItem(name: "device_id", value: deviceID))
    }
    components.queryItems = items
    _ = try await send(method: "PUT", url: components.url!)
  }

  // MARK: - Internals

  private func playURL(deviceID: String?) -> URL {
    transportURL(path: "me/player/play", deviceID: deviceID)
  }

  private func transportURL(path: String, deviceID: String?) -> URL {
    var components = URLComponents(url: apiBase.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
    if let deviceID {
      components.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
    }
    return components.url!
  }

  private static func toPlaylistHit(_ item: PlaylistItem?) -> SpotifyPlaylistHit? {
    // Spotify's /me/playlists and /search?type=playlist responses can include nulls in the items
    // array when a playlist is unavailable to the current user — drop those.
    guard let item, let id = item.id, let uri = item.uri, let name = item.name else { return nil }
    return SpotifyPlaylistHit(id: id, uri: uri, name: name, ownerName: item.owner?.displayName)
  }

  private func send(method: String, url: URL, body: Data? = nil) async throws -> Data {
    try await performRequest(method: method, url: url, body: body, retryOn401: true)
  }

  private func performRequest(
    method: String,
    url: URL,
    body: Data?,
    retryOn401: Bool
  ) async throws -> Data {
    let token: String
    if interactiveAuth {
      do {
        token = try await auth.currentToken()
      } catch let error as SpotifyAuthError {
        throw mapAuthError(error)
      } catch {
        throw SpotifyAPIError.network(error.localizedDescription)
      }
    } else {
      guard let cached = await auth.cachedToken() else {
        throw SpotifyAPIError.notAuthorized
      }
      token = cached
    }

    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if body != nil {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = body
    }

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw SpotifyAPIError.network(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw SpotifyAPIError.network("Invalid response")
    }

    switch http.statusCode {
    case 200 ..< 300:
      return data
    case 401:
      if retryOn401 {
        auth.clearTokens()
        return try await performRequest(method: method, url: url, body: body, retryOn401: false)
      }
      throw SpotifyAPIError.notAuthorized
    case 403:
      throw SpotifyAPIError.premiumRequired
    case 404:
      throw SpotifyAPIError.noDevice
    default:
      logger.warning("Spotify API \(http.statusCode) for \(url.path)")
      throw SpotifyAPIError.network("HTTP \(http.statusCode)")
    }
  }

  private func mapAuthError(_ error: SpotifyAuthError) -> SpotifyAPIError {
    switch error {
    case .notConfigured, .userCancelled, .refreshFailed, .invalidResponse:
      .notAuthorized
    case let .network(reason):
      .network(reason)
    }
  }
}

// MARK: - Response models

private struct SearchResponse: Decodable {
  let tracks: SearchTracks
}

private struct SearchTracks: Decodable {
  let items: [SearchTrack]
}

private struct SearchTrack: Decodable {
  let uri: String
  let name: String
  let artists: [SearchArtist]
}

private struct SearchArtist: Decodable {
  let name: String
}

private struct PlaylistSearchResponse: Decodable {
  let playlists: PlaylistItems
}

private struct UserPlaylistsResponse: Decodable {
  let items: [PlaylistItem?]
}

private struct PlaylistItems: Decodable {
  let items: [PlaylistItem?]
}

private struct PlaylistItem: Decodable {
  let id: String?
  let uri: String?
  let name: String?
  let owner: PlaylistOwner?
}

private struct PlaylistOwner: Decodable {
  let displayName: String?

  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
  }
}

private struct PlayerStateResponse: Decodable {
  let isPlaying: Bool
  let device: PlayerStateDevice?
  let shuffleState: Bool?
  let context: PlayerStateContext?
  let item: PlayerStateItem?

  enum CodingKeys: String, CodingKey {
    case isPlaying = "is_playing"
    case device
    case shuffleState = "shuffle_state"
    case context
    case item
  }
}

private struct PlayerStateDevice: Decodable {
  let id: String?
}

private struct PlayerStateContext: Decodable {
  let uri: String?
}

private struct PlayerStateItem: Decodable {
  let artists: [PlayerStateArtist]?
}

private struct PlayerStateArtist: Decodable {
  let uri: String?
  let id: String?

  /// Spotify's `/me/player` payload sometimes returns `uri` and sometimes only `id`. Normalize so
  /// callers can rely on a single resolved URI regardless of which the API gave us.
  var resolvedURI: String? {
    if let uri { return uri }
    if let id { return "spotify:artist:\(id)" }
    return nil
  }
}

private struct DevicesResponse: Decodable {
  let devices: [SpotifyDevice]
}
