protocol LLMClient {
  func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor (String) -> Void
  ) async throws
}
