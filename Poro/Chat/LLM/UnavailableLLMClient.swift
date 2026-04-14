struct UnavailableLLMClient: LLMClient, Sendable {
  let error: Error

  nonisolated func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    throw error
  }
}
