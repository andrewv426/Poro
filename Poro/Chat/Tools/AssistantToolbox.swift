import Foundation

struct AssistantToolDefinition: Sendable {
  let name: String
  let description: String
}

struct AssistantToolLogEntry: Codable, Sendable {
  let occurredAt: Date
  let phase: String
  let toolName: String?
  let detail: String
}

actor AssistantToolLog {
  private let capacity: Int
  private var entries: [AssistantToolLogEntry] = []

  init(capacity: Int = 40) {
    self.capacity = max(1, capacity)
  }

  func append(phase: String, toolName: String?, detail: String) {
    entries.append(
      AssistantToolLogEntry(
        occurredAt: Date(),
        phase: phase,
        toolName: toolName,
        detail: truncated(detail)
      )
    )

    if entries.count > capacity {
      entries.removeFirst(entries.count - capacity)
    }
  }

  func snapshot(limit: Int = 20) -> [AssistantToolLogEntry] {
    Array(entries.suffix(max(1, limit)))
  }

  private func truncated(_ value: String, maxLength: Int = 280) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)

    guard trimmed.count > maxLength else {
      return trimmed
    }

    let endIndex = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
    return String(trimmed[..<endIndex]) + "..."
  }
}

protocol AssistantToolbox: Sendable {
  var systemPrompt: String { get }
  var toolDefinitions: [AssistantToolDefinition] { get }

  func shouldOfferTools(for messages: [ChatMessage]) async -> Bool
  func executeTool(named name: String, argumentsJSON: String) async throws -> String
  func fetchAllContext() async -> String
  func recordToolEvent(phase: String, toolName: String?, detail: String) async
}

extension AssistantToolbox {
  func recordToolEvent(phase: String, toolName: String?, detail: String) async {}
}
