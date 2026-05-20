import Foundation

/// A parser responsible for identifying and extracting tool calls from LLM responses,
/// supporting both structured tool calls and "pseudo" tool calls represented in text.
struct LLMToolCallParser {
  /// Attempts to parse a tool call from content that may be a JSON object.
  /// - Parameters:
  ///   - content: The raw string content from the assistant.
  ///   - validToolNames: The list of tool names recognized by the current toolbox.
  /// - Returns: A ResponseToolCall if a valid JSON tool call is found, otherwise nil.
  func parseJSONToolCall(
    from content: String,
    validToolNames: [String]
  ) -> ResponseToolCall? {
    guard let data = content.data(using: .utf8) else {
      return nil
    }

    guard
      let jsonObject = try? JSONSerialization.jsonObject(with: data),
      let dictionary = jsonObject as? [String: Any]
    else {
      return nil
    }

    let name = (dictionary["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)

    guard let name, validToolNames.contains(name) else {
      return nil
    }

    let argumentsObject = dictionary["arguments"] ?? [:]
    guard JSONSerialization.isValidJSONObject(argumentsObject) else {
      return nil
    }

    guard
      let argumentsData = try? JSONSerialization.data(withJSONObject: argumentsObject),
      let arguments = String(data: argumentsData, encoding: .utf8)
    else {
      return nil
    }

    return ResponseToolCall(
      id: UUID().uuidString,
      type: "function",
      function: .init(name: name, arguments: arguments)
    )
  }

  /// Attempts to parse a "pseudo" tool call from natural language content (e.g., when the LLM mentions a tool name in
  /// text).
  /// - Parameters:
  ///   - content: The raw string content from the assistant.
  ///   - validToolNames: The list of tool names recognized by the current toolbox.
  /// - Returns: A ResponseToolCall if a pseudo tool call pattern is matched, otherwise nil.
  func parsePseudoToolCall(
    from content: String,
    validToolNames: [String]
  ) -> ResponseToolCall? {
    let normalizedContent = normalizedToolCallContent(from: content)
    let loweredContent = normalizedContent.lowercased()

    if
      let jsonToolCall = parseJSONToolCall(
        from: normalizedContent,
        validToolNames: validToolNames
      )
    {
      return jsonToolCall
    }

    guard loweredContent.contains("function") || loweredContent.contains("tool") else {
      return nil
    }

    guard
      let matchedToolName = validToolNames.first(where: { loweredContent.contains($0.lowercased()) })
    else {
      return nil
    }

    let arguments = if
      let parametersRange = loweredContent.range(of: "parameters"),
      let jsonStart = normalizedContent[parametersRange.upperBound...].firstIndex(of: "{"),
      let jsonEnd = normalizedContent[jsonStart...].lastIndex(of: "}")
    {
      String(normalizedContent[jsonStart ... jsonEnd])
    } else {
      "{}"
    }

    return ResponseToolCall(
      id: UUID().uuidString,
      type: "function",
      function: .init(name: matchedToolName, arguments: arguments)
    )
  }

  /// Cleans up tool call content, specifically removing markdown code block wrappers if present.
  /// - Parameter content: The raw content string.
  /// - Returns: The cleaned content string.
  private func normalizedToolCallContent(from content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

    guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else {
      return trimmed
    }

    let lines = trimmed.components(separatedBy: .newlines)

    guard lines.count >= 3 else {
      return trimmed
    }

    return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(
      in: .whitespacesAndNewlines
    )
  }
}

/// Represents a tool call request from the LLM.
struct ResponseToolCall: Codable {
  struct Function: Codable {
    let name: String
    let arguments: String
  }

  let id: String
  let type: String
  let function: Function
}
