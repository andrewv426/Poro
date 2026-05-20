import Foundation

struct LLMConfiguration {
  let apiKey: String
  let model: String
  let baseURL: URL
  let versionPatch: String?

  static func loadFromEnvironment(
    environment: [String: String] = mergedEnvironment()
  ) throws -> LLMConfiguration {
    guard
      let rawAPIKey = environment["CEREBRAS_API_KEY"]?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      !rawAPIKey.isEmpty
    else {
      throw LLMError.missingAPIKey(environmentVariable: "CEREBRAS_API_KEY")
    }

    let model = environment["CEREBRAS_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedModel = (model?.isEmpty == false) ? model! : "llama3.1-8b"

    let baseURLString = environment["CEREBRAS_BASE_URL"]?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let resolvedBaseURLString =
      (baseURLString?.isEmpty == false) ? baseURLString! : "https://api.cerebras.ai/v1"

    guard let baseURL = URL(string: resolvedBaseURLString) else {
      throw LLMError.invalidBaseURL(resolvedBaseURLString)
    }

    let versionPatch = environment["CEREBRAS_VERSION_PATCH"]?.trimmingCharacters(
      in: .whitespacesAndNewlines
    )

    return LLMConfiguration(
      apiKey: rawAPIKey,
      model: resolvedModel,
      baseURL: baseURL,
      versionPatch: versionPatch?.isEmpty == false ? versionPatch : nil
    )
  }

  /// Overlays values from `~/.config/poro/env` underneath the process environment so Xcode scheme
  /// env vars still win when set, but worktrees without scheme vars fall back to the user-global file.
  private static func mergedEnvironment() -> [String: String] {
    var merged = EnvFileLoader.load()
    for (key, value) in ProcessInfo.processInfo.environment {
      merged[key] = value
    }
    return merged
  }
}
