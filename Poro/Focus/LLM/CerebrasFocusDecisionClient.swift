import Foundation

/// Focus-session decision + distraction classification via the configured chat model (OpenRouter,
/// OpenAI-compatible). Free models vary in structured-output support, so this client does NOT send a
/// `response_format` schema (strict `json_schema` is rejected by many free models). Instead it prompts
/// for an exact JSON shape and parses the reply leniently — tolerating markdown code fences or
/// surrounding prose. On any failure the caller degrades to static rules, so a model that returns
/// malformed output simply disables the LLM path rather than crashing.
struct CerebrasFocusDecisionClient: FocusDecisionEvaluating, DistractionClassifying {
  let configuration: LLMConfiguration
  private let session: URLSession

  init(configuration: LLMConfiguration, session: URLSession = .shared) {
    self.configuration = configuration
    self.session = session
  }

  nonisolated func evaluateDecision(
    goal: String,
    remainingMinutes: Int,
    activity: ActivityContext,
    justification: String,
    nudgesToday: Int,
    allowedOverrides: Int
  ) async throws -> FocusDecision {
    let systemPrompt = """
    You are a strict but fair focus coach.
    Decide whether the user should be allowed to keep using the distracting activity they were just caught on.
    Only allow if the justification is concrete, relevant to the stated goal, and time-bounded.
    Deny vague avoidance, generic breaks, and low-accountability excuses.
    Keep the message short, direct, and user-facing.

    Respond with ONLY a single JSON object — no prose, no markdown, no code fences — in exactly this shape:
    {"verdict": "allow" or "deny", "message": "<short user-facing message>", "allowMinutes": <integer minutes 1-15, or null when denied>}
    """

    let userPrompt = """
    Goal: \(goal)
    Remaining minutes: \(remainingMinutes)
    Current activity: \(activity.applicationName)
    Justification: \(justification)
    Nudges so far: \(nudgesToday)
    Allowed overrides so far: \(allowedOverrides)

    Return only the JSON object.
    """

    let content = try await completion(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: 0.2
    )

    struct DecisionPayload: Decodable {
      let verdict: String
      let message: String
      let allowMinutes: Int?
    }

    guard
      let json = Self.extractJSONObject(from: content),
      let payload = try? JSONDecoder().decode(DecisionPayload.self, from: json)
    else {
      throw LLMError.emptyResponse
    }

    if payload.verdict.lowercased() == "allow" {
      let grantedMinutes = max(1, min(payload.allowMinutes ?? 5, 15))
      return FocusDecision(verdict: .allow, message: payload.message, allowMinutes: grantedMinutes)
    }

    return FocusDecision(verdict: .deny, message: payload.message, allowMinutes: nil)
  }

  nonisolated func classifyDistraction(
    goal: String,
    remainingMinutes: Int,
    activity: ActivityContext
  ) async throws -> DistractionClassification {
    let systemPrompt = """
    You classify whether a browser tab is distracting for the user's current focus session.
    Use the goal, URL, host, and page title. Mark "distract" for unrelated entertainment, social media,
    shopping, news, idle browsing, or obvious avoidance. Mark "allow" for docs, research, work tools,
    educational material, or anything plausibly necessary for the stated goal.
    Be conservative near ambiguity: allow unless the tab is likely unrelated to the goal.

    Respond with ONLY a single JSON object — no prose, no markdown, no code fences — in exactly this shape:
    {"verdict": "allow" or "distract", "score": <number 0.0-1.0, the probability the tab is distracting>, "reason": "<short explanation>"}
    """

    let userPrompt = """
    Goal: \(goal)
    Remaining minutes: \(remainingMinutes)
    Application: \(activity.applicationName)
    URL: \(activity.pageURL?.absoluteString ?? "unknown")
    Host: \(activity.pageHost ?? "unknown")
    Title: \(activity.pageTitle ?? "unknown")

    Return only the JSON object.
    """

    let content = try await completion(
      systemPrompt: systemPrompt,
      userPrompt: userPrompt,
      temperature: 0
    )

    struct ClassificationPayload: Decodable {
      let verdict: String
      let score: Double
      let reason: String
    }

    guard
      let json = Self.extractJSONObject(from: content),
      let payload = try? JSONDecoder().decode(ClassificationPayload.self, from: json)
    else {
      throw LLMError.emptyResponse
    }

    let verdict: DistractionClassification.Verdict =
      if payload.verdict.lowercased() == "distract" { .distract } else { .allow }
    let score = min(1, max(0, payload.score))

    return DistractionClassification(verdict: verdict, score: score, reason: payload.reason)
  }

  // MARK: - Shared chat plumbing

  /// Sends a system + user prompt to the chat model and returns the raw assistant message content.
  private nonisolated func completion(
    systemPrompt: String,
    userPrompt: String,
    temperature: Double
  ) async throws -> String {
    struct RequestMessage: Encodable {
      let role: String
      let content: String
    }

    struct ChatCompletionsRequest: Encodable {
      let model: String
      let messages: [RequestMessage]
      let temperature: Double
    }

    struct ChatCompletionsResponse: Decodable {
      struct Choice: Decodable {
        struct Message: Decodable { let content: String }
        let message: Message
      }

      let choices: [Choice]
    }

    struct ErrorResponse: Decodable {
      struct APIError: Decodable { let message: String? }
      let error: APIError
    }

    let requestURL = configuration.baseURL.appendingPathComponent("chat/completions")
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("Poro", forHTTPHeaderField: "X-Title")

    let body = ChatCompletionsRequest(
      model: configuration.model,
      messages: [
        RequestMessage(role: "system", content: systemPrompt),
        RequestMessage(role: "user", content: userPrompt),
      ],
      temperature: temperature
    )
    request.httpBody = try JSONEncoder().encode(body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      let urlError = error as? URLError
      throw LLMError.networkFailure(
        description: error.localizedDescription,
        code: urlError?.errorCode,
        url: requestURL.absoluteString
      )
    }

    guard let httpResponse = response as? HTTPURLResponse else {
      throw LLMError.invalidResponse
    }

    guard (200 ... 299).contains(httpResponse.statusCode) else {
      let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
      throw LLMError.unexpectedStatusCode(httpResponse.statusCode, errorResponse?.error.message)
    }

    let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
    guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
      throw LLMError.emptyResponse
    }

    return content
  }

  /// Extracts the first balanced JSON object from a model reply that may wrap it in markdown fences
  /// or surrounding prose. Braces inside string literals are ignored. Returns nil if none is found.
  nonisolated static func extractJSONObject(from text: String) -> Data? {
    guard let start = text.firstIndex(of: "{") else { return nil }

    var depth = 0
    var inString = false
    var escaped = false
    var index = start

    while index < text.endIndex {
      let character = text[index]

      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        inString.toggle()
      } else if !inString {
        if character == "{" {
          depth += 1
        } else if character == "}" {
          depth -= 1
          if depth == 0 {
            return String(text[start ... index]).data(using: .utf8)
          }
        }
      }

      index = text.index(after: index)
    }

    return nil
  }
}
