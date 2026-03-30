struct MockLLMClient: LLMClient {
  func complete(messages: [ChatMessage]) async throws -> String {
    "Not connected yet."
  }
}
