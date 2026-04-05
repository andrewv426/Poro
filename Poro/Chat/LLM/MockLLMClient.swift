struct MockLLMClient: LLMClient {
    func streamCompletion(
        messages: [ChatMessage],
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        await onDelta("Not connected yet.")
    }
}
