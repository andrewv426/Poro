struct UnavailableLLMClient: LLMClient {
  let error: Error

  func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor (String) -> Void
  ) async throws {
    throw error
  }
}
