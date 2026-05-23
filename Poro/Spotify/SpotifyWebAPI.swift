import Foundation
import OSLog

private let logger = Logger(subsystem: "andrewvong.Poro", category: "SpotifyWebAPI")

enum SpotifyAPIError: Error, Equatable {
  case notAuthorized // 401 after refresh
  case premiumRequired // 403 from /v1/me/player/play
  case noDevice // 404 device-not-found
  case network(String)
  case decoding
}

struct SpotifyTrackHit: Equatable {
  let uri: String
  let displayName: String
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

/// Lightweight client for the Spotify Web API. Covers just enough endpoints to implement /play:
/// search (track scope), devices, and start playback. Auth tokens come from `SpotifyAuth`.
struct SpotifyWebAPI {
  let auth: SpotifyAuth

  private let apiBase = URL(string: "https://api.spotify.com/v1")!

  // MARK: - Search

  func search(_ query: SpotifyPlayQuery) async throws -> SpotifyTrackHit? {
    let q: String = switch query {
    case let .freeform(text): text
    case let .trackByArtist(track, artist): "track:\"\(track)\" artist:\"\(artist)\""
    }

    var components = URLComponents(url: apiBase.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "q", value: q),
      URLQueryItem(name: "type", value: "track"),
      URLQueryItem(name: "limit", value: "1"),
    ]

    let data = try await send(method: "GET", url: components.url!)

    do {
      let response = try JSONDecoder().decode(SearchResponse.self, from: data)
      guard let track = response.tracks.items.first else { return nil }
      let artists = track.artists.map(\.name).joined(separator: ", ")
      return SpotifyTrackHit(uri: track.uri, displayName: "\(track.name) by \(artists)")
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

  // MARK: - Play

  func play(trackURI: String, deviceID: String?) async throws {
    let playURL = apiBase.appendingPathComponent("me/player/play")
    var components = URLComponents(url: playURL, resolvingAgainstBaseURL: false)!
    if let deviceID {
      components.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
    }
    let body = try JSONSerialization.data(withJSONObject: ["uris": [trackURI]])
    _ = try await send(method: "PUT", url: components.url!, body: body)
  }

  /// Resume current playback (no body). Used when the user types `/play` with no query.
  func resume(deviceID: String?) async throws {
    let playURL = apiBase.appendingPathComponent("me/player/play")
    var components = URLComponents(url: playURL, resolvingAgainstBaseURL: false)!
    if let deviceID {
      components.queryItems = [URLQueryItem(name: "device_id", value: deviceID)]
    }
    _ = try await send(method: "PUT", url: components.url!)
  }

  // MARK: - Internals

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
    do {
      token = try await auth.currentToken()
    } catch let error as SpotifyAuthError {
      throw mapAuthError(error)
    } catch {
      throw SpotifyAPIError.network(error.localizedDescription)
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

private struct DevicesResponse: Decodable {
  let devices: [SpotifyDevice]
}
