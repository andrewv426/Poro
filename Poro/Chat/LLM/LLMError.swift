import Foundation

enum LLMError: LocalizedError {
  case missingAPIKey(environmentVariable: String)
  case invalidBaseURL(String)
  case networkFailure(description: String, code: Int?, url: String?)
  case invalidResponse
  case unexpectedStatusCode(Int, String?)
  case emptyResponse
  case toolExecutionFailure(String)

  var errorDescription: String? {
    switch self {
    case let .missingAPIKey(environmentVariable):
      return "Missing API key. Set \(environmentVariable) in your Xcode scheme environment."
    case let .invalidBaseURL(baseURL):
      return "Invalid model provider base URL: \(baseURL)"
    case let .networkFailure(description, code, url):
      var parts = ["Network request failed: \(description)"]

      if let code {
        parts.append("code \(code)")
      }

      if let url, !url.isEmpty {
        parts.append(url)
      }

      return parts.joined(separator: " | ")
    case .invalidResponse:
      return "Received an invalid response from the model provider."
    case let .unexpectedStatusCode(statusCode, message):
      if let message, !message.isEmpty {
        return "Model request failed (\(statusCode)): \(message)"
      }

      return "Model request failed with status code \(statusCode)."
    case .emptyResponse:
      return "The model returned an empty response."
    case let .toolExecutionFailure(message):
      return "Tool execution failed: \(message)"
    }
  }
}
