import Foundation

struct LLMConfiguration {
  let apiKey: String
  let model: String
  let baseURL: URL
  let versionPatch: String?

  static func loadFromEnvironment(
    environment: [String: String] = ProcessInfo.processInfo.environment
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
}
