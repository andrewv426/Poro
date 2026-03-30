struct UnavailableLLMClient: LLMClient {
  let error: Error

  func complete(messages: [ChatMessage]) async throws -> String {
    throw error
  }
}
