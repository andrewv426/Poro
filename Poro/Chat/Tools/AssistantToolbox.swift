import Foundation

struct AssistantToolDefinition: Sendable {
  let name: String
  let description: String
}

protocol AssistantToolbox: Sendable {
  var systemPrompt: String { get }
  var toolDefinitions: [AssistantToolDefinition] { get }

  func shouldOfferTools(for messages: [ChatMessage]) async -> Bool
  func executeTool(named name: String, argumentsJSON: String) async throws -> String
}
