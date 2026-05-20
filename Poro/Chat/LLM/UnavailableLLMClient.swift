struct UnavailableLLMClient: LLMClient {
  let error: Error

  nonisolated func streamCompletion(
    messages _: [ChatMessage],
    onDelta _: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    throw error
  }
}
