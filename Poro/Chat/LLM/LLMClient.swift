protocol LLMClient {
    func complete(messages: [ChatMessage]) async throws -> String
}
