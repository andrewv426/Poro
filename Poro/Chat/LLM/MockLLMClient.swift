struct MockLLMClient: LLMClient, Sendable {
  nonisolated func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    await onDelta("Not connected yet.")
  }
}
