protocol LLMClient: Sendable {
  nonisolated func streamCompletion(
    messages: [ChatMessage],
    onDelta: @escaping @MainActor @Sendable (String) -> Void
  ) async throws

  /// Optionally pre-open the network connection before the first real request. Best-effort; the
  /// default is a no-op for clients that don't need it.
  nonisolated func warmUp() async
}

extension LLMClient {
  nonisolated func warmUp() async {}
}
