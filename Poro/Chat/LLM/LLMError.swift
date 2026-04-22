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
    case .missingAPIKey(let environmentVariable):
      return "Missing API key. Set \(environmentVariable) in your Xcode scheme environment."
    case .invalidBaseURL(let baseURL):
      return "Invalid Cerebras base URL: \(baseURL)"
    case .networkFailure(let description, let code, let url):
      var parts = ["Network request failed: \(description)"]

      if let code {
        parts.append("code \(code)")
      }

      if let url, !url.isEmpty {
        parts.append(url)
      }

      return parts.joined(separator: " | ")
    case .invalidResponse:
      return "Received an invalid response from Cerebras."
    case .unexpectedStatusCode(let statusCode, let message):
      if let message, !message.isEmpty {
        return "Cerebras request failed (\(statusCode)): \(message)"
      }

      return "Cerebras request failed with status code \(statusCode)."
    case .emptyResponse:
      return "Cerebras returned an empty response."
    case .toolExecutionFailure(let message):
      return "Tool execution failed: \(message)"
    }
  }
}
