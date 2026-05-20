struct MockLLMClient: LLMClient {
  nonisolated func streamCompletion(
    messages _: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws {
    await onDelta("Not connected yet.")
  }
}
