import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "andrewvong.Poro", category: "SpotifyAuth")

enum SpotifyAuthError: Error, Equatable {
  case notConfigured
  case userCancelled
  case refreshFailed
  case invalidResponse
  case network(String)
}

/// OAuth PKCE flow for the Spotify Web API. Tokens are persisted in the system Keychain so they
/// survive restarts. The first call to `currentToken()` for a fresh install pops the system web
/// view to ask the user to log in; subsequent calls silently refresh as needed.
final class SpotifyAuth: NSObject, @unchecked Sendable {
  static let shared = SpotifyAuth()

  private let redirectURI = "poro://spotify-callback"
  private let scopes = "user-read-playback-state user-modify-playback-state"
  private let authorizeBase = URL(string: "https://accounts.spotify.com/authorize")!
  private let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

  private let tokenStore = SpotifyTokenStore()

  var isConfigured: Bool {
    SpotifyConfig.clientID() != nil
  }

  /// Returns a valid access token, refreshing if needed and prompting for authorization on the
  /// first call. Throws `SpotifyAuthError.notConfigured` if `SPOTIFY_CLIENT_ID` is unset.
  func currentToken() async throws -> String {
    guard let clientID = SpotifyConfig.clientID() else {
      throw SpotifyAuthError.notConfigured
    }

    if let stored = tokenStore.read(), !stored.isExpiringSoon {
      return stored.accessToken
    }

    if let stored = tokenStore.read(), let refresh = stored.refreshToken {
      do {
        let refreshed = try await refreshTokens(clientID: clientID, refreshToken: refresh)
        tokenStore.write(refreshed)
        return refreshed.accessToken
      } catch {
        logger.warning("Spotify refresh failed: \(String(describing: error)); falling back to authorize")
        tokenStore.clear()
      }
    }

    let fresh = try await authorize(clientID: clientID)
    return fresh.accessToken
  }

  /// Clears stored tokens. Forces the next `currentToken()` call to re-authorize.
  func clearTokens() {
    tokenStore.clear()
  }

  // MARK: - Authorize (PKCE)

  private func authorize(clientID: String) async throws -> SpotifyToken {
    let verifier = Self.randomCodeVerifier()
    let challenge = Self.codeChallenge(for: verifier)
    let state = UUID().uuidString

    let authURL = makeAuthorizeURL(clientID: clientID, challenge: challenge, state: state)
    let callback = try await runWebAuthSession(authorize: authURL)

    guard
      let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
      let returnedState = components.queryItems?.first(where: { $0.name == "state" })?.value,
      returnedState == state,
      let code = components.queryItems?.first(where: { $0.name == "code" })?.value
    else {
      throw SpotifyAuthError.invalidResponse
    }

    let token = try await exchangeCode(code, verifier: verifier, clientID: clientID)
    tokenStore.write(token)
    return token
  }

  private func makeAuthorizeURL(clientID: String, challenge: String, state: String) -> URL {
    var components = URLComponents(url: authorizeBase, resolvingAgainstBaseURL: false)!
    components.queryItems = [
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "response_type", value: "code"),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "code_challenge_method", value: "S256"),
      URLQueryItem(name: "code_challenge", value: challenge),
      URLQueryItem(name: "scope", value: scopes),
      URLQueryItem(name: "state", value: state),
    ]
    return components.url!
  }

  @MainActor
  private func runWebAuthSession(authorize url: URL) async throws -> URL {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
      let handler: (URL?, Error?) -> Void = { callback, error in
        if let error = error as NSError? {
          if error.domain == ASWebAuthenticationSessionErrorDomain,
             error.code == ASWebAuthenticationSessionError.canceledLogin.rawValue
          {
            continuation.resume(throwing: SpotifyAuthError.userCancelled)
          } else {
            continuation.resume(throwing: SpotifyAuthError.network(error.localizedDescription))
          }
          return
        }
        guard let callback else {
          continuation.resume(throwing: SpotifyAuthError.invalidResponse)
          return
        }
        continuation.resume(returning: callback)
      }

      let session = if #available(macOS 14.4, *) {
        ASWebAuthenticationSession(url: url, callback: .customScheme("poro"), completionHandler: handler)
      } else {
        ASWebAuthenticationSession(url: url, callbackURLScheme: "poro", completionHandler: handler)
      }
      session.presentationContextProvider = self
      session.prefersEphemeralWebBrowserSession = false

      if !session.start() {
        continuation.resume(throwing: SpotifyAuthError.invalidResponse)
      }
    }
  }

  // MARK: - Token exchange / refresh

  private func exchangeCode(_ code: String, verifier: String, clientID: String) async throws -> SpotifyToken {
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "grant_type", value: "authorization_code"),
      URLQueryItem(name: "code", value: code),
      URLQueryItem(name: "redirect_uri", value: redirectURI),
      URLQueryItem(name: "client_id", value: clientID),
      URLQueryItem(name: "code_verifier", value: verifier),
    ]
    return try await postForToken(body: components.percentEncodedQuery ?? "")
  }

  private func refreshTokens(clientID: String, refreshToken: String) async throws -> SpotifyToken {
    var components = URLComponents()
    components.queryItems = [
      URLQueryItem(name: "grant_type", value: "refresh_token"),
      URLQueryItem(name: "refresh_token", value: refreshToken),
      URLQueryItem(name: "client_id", value: clientID),
    ]
    let token = try await postForToken(body: components.percentEncodedQuery ?? "")
    if token.refreshToken == nil {
      return SpotifyToken(
        accessToken: token.accessToken,
        refreshToken: refreshToken,
        expiresAt: token.expiresAt
      )
    }
    return token
  }

  private func postForToken(body: String) async throws -> SpotifyToken {
    var request = URLRequest(url: tokenURL)
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    request.httpBody = body.data(using: .utf8)

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw SpotifyAuthError.network(error.localizedDescription)
    }

    guard let http = response as? HTTPURLResponse else {
      throw SpotifyAuthError.invalidResponse
    }
    guard (200 ..< 300).contains(http.statusCode) else {
      throw SpotifyAuthError.refreshFailed
    }

    do {
      let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
      let expiresAt = Date().addingTimeInterval(TimeInterval(decoded.expiresIn))
      return SpotifyToken(
        accessToken: decoded.accessToken,
        refreshToken: decoded.refreshToken,
        expiresAt: expiresAt
      )
    } catch {
      throw SpotifyAuthError.invalidResponse
    }
  }

  // MARK: - PKCE helpers

  private static func randomCodeVerifier() -> String {
    var bytes = [UInt8](repeating: 0, count: 64)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return Data(bytes).base64URLEncodedString()
  }

  private static func codeChallenge(for verifier: String) -> String {
    let digest = SHA256.hash(data: Data(verifier.utf8))
    return Data(digest).base64URLEncodedString()
  }
}

extension SpotifyAuth: ASWebAuthenticationPresentationContextProviding {
  /// ASWebAuthenticationSession documents this as being invoked on the main thread.
  nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
    MainActor.assumeIsolated {
      NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) ?? NSWindow()
    }
  }
}

// MARK: - Token model + Keychain store

struct SpotifyToken: Codable, Equatable {
  let accessToken: String
  let refreshToken: String?
  let expiresAt: Date

  var isExpiringSoon: Bool {
    expiresAt.timeIntervalSinceNow < 60
  }
}

private struct TokenResponse: Decodable {
  let accessToken: String
  let refreshToken: String?
  let expiresIn: Int

  enum CodingKeys: String, CodingKey {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case expiresIn = "expires_in"
  }
}

/// Keychain-backed persistence for the OAuth token blob. Single item, JSON-encoded.
final class SpotifyTokenStore: @unchecked Sendable {
  private let service = "com.poro.spotify"
  private let account = "oauth"

  func read() -> SpotifyToken? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return try? JSONDecoder().decode(SpotifyToken.self, from: data)
  }

  func write(_ token: SpotifyToken) {
    guard let data = try? JSONEncoder().encode(token) else { return }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let attrs: [String: Any] = [kSecValueData as String: data]

    let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
    if status == errSecItemNotFound {
      var insert = query
      insert[kSecValueData as String] = data
      SecItemAdd(insert as CFDictionary, nil)
    }
  }

  func clear() {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

private extension Data {
  func base64URLEncodedString() -> String {
    base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
