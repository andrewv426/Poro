import Foundation

struct LLMConfiguration {
  let apiKey: String
  let model: String
  let baseURL: URL
  let versionPatch: String?

  static func loadFromEnvironment(
    environment: [String: String] = EnvFileLoader.mergedEnvironment()
  ) throws -> LLMConfiguration {
    guard
      let rawAPIKey = environment["CEREBRAS_API_KEY"]?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      !rawAPIKey.isEmpty
    else {
      throw LLMError.missingAPIKey(environmentVariable: "CEREBRAS_API_KEY")
    }

    let resolvedModel = nonEmpty(environment["CEREBRAS_MODEL"]) ?? "llama3.1-8b"
    let resolvedBaseURLString = nonEmpty(environment["CEREBRAS_BASE_URL"]) ?? "https://api.cerebras.ai/v1"

    guard let baseURL = URL(string: resolvedBaseURLString) else {
      throw LLMError.invalidBaseURL(resolvedBaseURLString)
    }

    return LLMConfiguration(
      apiKey: rawAPIKey,
      model: resolvedModel,
      baseURL: baseURL,
      versionPatch: nonEmpty(environment["CEREBRAS_VERSION_PATCH"])
    )
  }

  /// Trims `value` and returns nil if the result is empty. Lets `??` provide defaults cleanly.
  private static func nonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
      return nil
    }
    return trimmed
  }
}
