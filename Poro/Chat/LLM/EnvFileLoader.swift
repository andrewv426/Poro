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
  /// Default location: `~/.config/poro/env`. User-global so it's shared across worktrees.
  static var defaultURL: URL {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home.appendingPathComponent(".config/poro/env")
  }

  /// Reads the file at `url` (default: `defaultURL`) and parses dotenv-style entries.
  /// Missing file → empty dictionary. Malformed lines are silently skipped.
  static func load(from url: URL = defaultURL) -> [String: String] {
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
