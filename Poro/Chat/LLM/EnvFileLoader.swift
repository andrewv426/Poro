import Foundation

/// Loads simple KEY=VALUE pairs from a dotenv-style file. The format is:
///
///   # comments start with #
///   KEY=value
///   QUOTED="value with spaces"
///
/// Returns an empty dictionary if the file doesn't exist — callers can layer this onto
/// `ProcessInfo.processInfo.environment` so Xcode scheme env vars still win when set.
enum EnvFileLoader {
  /// The app is sandboxed, so it cannot read `~/.config/poro/env` directly. A build-phase
  /// script copies that file into the app bundle as `Poro.env` so this loader can find it
  /// at runtime via `Bundle.main`. Falls back to the user-global path for non-sandboxed
  /// contexts (CLI builds, future tests).
  static func load() -> [String: String] {
    if let bundled = Bundle.main.url(forResource: "Poro", withExtension: "env"),
       let contents = try? String(contentsOf: bundled, encoding: .utf8)
    {
      return parse(contents)
    }

    let home = FileManager.default.homeDirectoryForCurrentUser
    let fallback = home.appendingPathComponent(".config/poro/env")
    if let contents = try? String(contentsOf: fallback, encoding: .utf8) {
      return parse(contents)
    }

    return [:]
  }

  /// Reads the file at the given URL and parses dotenv-style entries. Exposed for tests.
  /// Missing file → empty dictionary. Malformed lines are silently skipped.
  static func load(from url: URL) -> [String: String] {
    guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
      return [:]
    }
    return parse(contents)
  }

  /// Parses dotenv-style text. Exposed for testing and for callers that already have the contents.
  static func parse(_ contents: String) -> [String: String] {
    var result: [String: String] = [:]

    for rawLine in contents.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty || line.hasPrefix("#") { continue }

      guard let eq = line.firstIndex(of: "=") else { continue }
      let key = line[..<eq].trimmingCharacters(in: .whitespaces)
      let rawValue = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
      guard !key.isEmpty else { continue }

      result[key] = stripSurroundingQuotes(rawValue)
    }

    return result
  }

  /// Overlays values from the bundled env file underneath the process environment so Xcode scheme
  /// env vars still win when set, but worktrees without scheme vars fall back to the user-global
  /// file. Empty process-env values do NOT override the file — Xcode schemes ship with placeholder
  /// entries like `KEY=""` for discoverability, and we want the file to win in that case.
  static func mergedEnvironment() -> [String: String] {
    var merged = load()
    for (key, value) in ProcessInfo.processInfo.environment where !value.isEmpty {
      merged[key] = value
    }
    return merged
  }

  private static func stripSurroundingQuotes(_ value: String) -> String {
    guard value.count >= 2 else { return value }
    let first = value.first
    let last = value.last
    if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
      return String(value.dropFirst().dropLast())
    }
    return value
  }
}
