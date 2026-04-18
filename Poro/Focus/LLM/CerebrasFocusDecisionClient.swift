import Foundation

struct CerebrasFocusDecisionClient: FocusDecisionEvaluating, Sendable {
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
    struct RequestMessage: Encodable, Sendable {
      let role: String
      let content: String
    }

    struct ChatCompletionsRequest: Encodable, Sendable {
      struct ResponseFormat: Encodable, Sendable {
        struct JSONSchemaConfiguration: Encodable, Sendable {
          let name: String
          let strict: Bool
          let schema: Schema
        }

        struct Schema: Encodable, Sendable {
          let type: String
          let properties: [String: Property]
          let required: [String]
          let additionalProperties: Bool
        }

        struct Property: Encodable, Sendable {
          let type: String?
          let enumValues: [String]?
          let anyOf: [AnyOfProperty]?

          enum CodingKeys: String, CodingKey {
            case type
            case enumValues = "enum"
            case anyOf
          }
        }

        struct AnyOfProperty: Encodable, Sendable {
          let type: String
        }

        let type: String
        let jsonSchema: JSONSchemaConfiguration

        enum CodingKeys: String, CodingKey {
          case type
          case jsonSchema = "json_schema"
        }
      }

      let model: String
      let messages: [RequestMessage]
      let responseFormat: ResponseFormat
      let temperature: Double

      enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case temperature
      }
    }

    struct ChatCompletionsResponse: Decodable, Sendable {
      struct Choice: Decodable, Sendable {
        struct Message: Decodable, Sendable {
          let content: String
        }

        let message: Message
      }

      let choices: [Choice]
    }

    struct DecisionPayload: Decodable, Sendable {
      let verdict: String
      let message: String
      let allowMinutes: Int?
    }

    struct ErrorResponse: Decodable, Sendable {
      let error: APIError
    }

    struct APIError: Decodable, Sendable {
      let message: String?
    }

    let requestURL = configuration.baseURL.appendingPathComponent("chat/completions")
    var request = URLRequest(url: requestURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

    let responseFormat = ChatCompletionsRequest.ResponseFormat(
      type: "json_schema",
      jsonSchema: .init(
        name: "focus_decision",
        strict: true,
        schema: .init(
          type: "object",
          properties: [
            "verdict": .init(type: "string", enumValues: ["allow", "deny"], anyOf: nil),
            "message": .init(type: "string", enumValues: nil, anyOf: nil),
            "allowMinutes": .init(
              type: nil,
              enumValues: nil,
              anyOf: [.init(type: "integer"), .init(type: "null")]
            ),
          ],
          required: ["verdict", "message", "allowMinutes"],
          additionalProperties: false
        )
      )
    )

    let systemPrompt = """
      You are a strict but fair focus coach.
      Decide whether the user should be allowed to keep using the distracting activity they were just caught on.
      Only allow if the justification is concrete, relevant to the stated goal, and time-bounded.
      Deny vague avoidance, generic breaks, and low-accountability excuses.
      Keep the message short, direct, and user-facing.
      """

    let userPrompt = """
      Goal: \(goal)
      Remaining minutes: \(remainingMinutes)
      Current activity: \(activity.applicationName)
      Justification: \(justification)
      Nudges so far: \(nudgesToday)
      Allowed overrides so far: \(allowedOverrides)

      Return JSON only.
      """

    let requestBody = ChatCompletionsRequest(
      model: configuration.model,
      messages: [
        .init(role: "system", content: systemPrompt),
        .init(role: "user", content: userPrompt),
      ],
      responseFormat: responseFormat,
      temperature: 0.2
    )
    request.httpBody = try JSONEncoder().encode(requestBody)

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

    guard (200...299).contains(httpResponse.statusCode) else {
      let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
      throw LLMError.unexpectedStatusCode(httpResponse.statusCode, errorResponse?.error.message)
    }

    let completion = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)

    guard
      let content = completion.choices.first?.message.content.data(using: .utf8)
    else {
      throw LLMError.emptyResponse
    }

    let payload = try JSONDecoder().decode(DecisionPayload.self, from: content)
    let verdict = payload.verdict.lowercased() == "allow" ? FocusDecision.Verdict.allow : .deny

    if verdict == .allow {
      let grantedMinutes = max(1, min(payload.allowMinutes ?? 5, 15))
      return FocusDecision(
        verdict: .allow,
        message: payload.message,
        allowMinutes: grantedMinutes
      )
    }

    return FocusDecision(
      verdict: .deny,
      message: payload.message,
      allowMinutes: nil
    )
  }
}
