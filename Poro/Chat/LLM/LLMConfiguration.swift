import Foundation

struct LLMConfiguration {
  let apiKey: String
  let model: String
  let baseURL: URL

  static func loadFromEnvironment(
    environment: [String: String] = EnvFileLoader.mergedEnvironment()
  ) throws -> LLMConfiguration {
    guard
      let rawAPIKey = environment["OPENROUTER_API_KEY"]?.trimmingCharacters(
        in: .whitespacesAndNewlines
      ),
      !rawAPIKey.isEmpty
    else {
      throw LLMError.missingAPIKey(environmentVariable: "OPENROUTER_API_KEY")
    }

    let resolvedModel = nonEmpty(environment["OPENROUTER_MODEL"]) ?? "nvidia/nemotron-nano-12b-v2-vl:free"
    let resolvedBaseURLString = nonEmpty(environment["OPENROUTER_BASE_URL"]) ?? "https://openrouter.ai/api/v1"

    guard let baseURL = URL(string: resolvedBaseURLString) else {
      throw LLMError.invalidBaseURL(resolvedBaseURLString)
    }

    return LLMConfiguration(
      apiKey: rawAPIKey,
      model: resolvedModel,
      baseURL: baseURL
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
