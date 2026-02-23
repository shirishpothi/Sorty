import Foundation

enum AIRequestSupport {
    static func session(for config: AIConfig) async -> URLSession {
        await AISessionManager.shared.session(for: config.provider, config: config)
    }

    static func requireAPIURL(from config: AIConfig) throws -> String {
        guard let apiURL = config.apiURL?.trimmingCharacters(in: .whitespacesAndNewlines), !apiURL.isEmpty else {
            throw AIClientError.missingAPIURL
        }
        return apiURL
    }

    static func requireAPIKeyIfNeeded(from config: AIConfig) throws {
        if config.requiresAPIKey && (config.apiKey == nil || config.apiKey?.isEmpty == true) {
            throw AIClientError.missingAPIKey
        }
    }

    static func openAIChatCompletionsURL(from apiURL: String) throws -> URL {
        let normalized = normalizeBaseURL(apiURL)

        guard var components = URLComponents(string: normalized), components.scheme != nil else {
            throw AIClientError.invalidURL
        }

        let path = components.path
        if path.hasSuffix("/v1/chat/completions") {
            return try ensureURL(components)
        }

        if path.hasSuffix("/v1") {
            components.path += "/chat/completions"
            return try ensureURL(components)
        }

        if path.hasSuffix("/v1/") {
            components.path += "chat/completions"
            return try ensureURL(components)
        }

        let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        components.path = trimmedPath + "/v1/chat/completions"
        return try ensureURL(components)
    }

    static func openAIModelsURL(from apiURL: String) throws -> URL {
        let normalized = normalizeBaseURL(apiURL)

        guard var components = URLComponents(string: normalized), components.scheme != nil else {
            throw AIClientError.invalidURL
        }

        let path = components.path
        if path.hasSuffix("/chat/completions") {
            components.path = String(path.dropLast("/chat/completions".count)) + "/models"
            return try ensureURL(components)
        }

        if path.hasSuffix("/chat/completions/") {
            components.path = String(path.dropLast("/chat/completions/".count)) + "/models"
            return try ensureURL(components)
        }

        if path.hasSuffix("/v1") {
            components.path += "/models"
            return try ensureURL(components)
        }

        if path.hasSuffix("/v1/") {
            components.path += "models"
            return try ensureURL(components)
        }

        if path.contains("/v1/") || path.contains("/v1beta/") {
            let normalizedPath = path.hasSuffix("/") ? path + "models" : path + "/models"
            components.path = normalizedPath
            return try ensureURL(components)
        }

        let trimmedPath = path.hasSuffix("/") ? String(path.dropLast()) : path
        components.path = trimmedPath + "/v1/models"
        return try ensureURL(components)
    }

    static func makeJSONRequest(
        url: URL,
        method: String = "POST",
        headers: [String: String] = [:],
        body: [String: Any]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method

        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        if body != nil && headers["Content-Type"] == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        return request
    }

    static func validateHTTPResponse(data: Data, response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return httpResponse
    }

    private static func normalizeBaseURL(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.contains("://") {
            normalized = "https://" + normalized
        }
        return normalized
    }

    private static func ensureURL(_ components: URLComponents) throws -> URL {
        guard let url = components.url, url.scheme != nil else {
            throw AIClientError.invalidURL
        }
        return url
    }

    /// Extracts textual content from heterogeneous OpenAI-compatible payloads.
    /// Handles plain strings plus content-part arrays/dictionaries used by newer APIs.
    static func extractText(from value: Any?) -> String? {
        guard let value else { return nil }

        if let text = value as? String {
            return text
        }

        if let parts = value as? [Any] {
            let joined = parts.compactMap { extractText(from: $0) }.joined()
            return joined.isEmpty ? nil : joined
        }

        if let dict = value as? [String: Any] {
            let priorityKeys = ["text", "content", "value", "output_text", "reasoning", "thinking", "analysis", "parts"]
            for key in priorityKeys {
                if let extracted = extractText(from: dict[key]), !extracted.isEmpty {
                    return extracted
                }
            }
        }

        return nil
    }

    /// Best-effort extraction for chat completion message text in non-streaming responses.
    static func extractChatMessageText(from choice: [String: Any]) -> String? {
        let message = choice["message"] as? [String: Any]
        return extractText(from: message?["content"]) ??
            extractText(from: message?["text"]) ??
            extractText(from: choice["text"])
    }

    /// Best-effort extraction for streaming chunk text in OpenAI-compatible responses.
    static func extractChatDeltaText(from choice: [String: Any]) -> String? {
        let delta = choice["delta"] as? [String: Any]
        let message = choice["message"] as? [String: Any]
        return extractText(from: delta?["content"]) ??
            extractText(from: delta?["text"]) ??
            extractText(from: message?["content"]) ??
            extractText(from: choice["text"])
    }

    /// Retries a network operation once on transient HTTP errors (429, 500, 502, 503, 504).
    /// Cancellation-aware: checks Task.isCancelled before retrying.
    /// - Parameter operation: The async throwing closure to retry
    /// - Returns: The result of the operation
    static func withTransientRetry<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        do {
            return try await operation()
        } catch let error as AIClientError {
            guard shouldRetry(error), !Task.isCancelled else {
                throw error
            }
            // Single retry with brief backoff
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            return try await operation()
        } catch {
            // URLSession network errors are worth retrying
            guard !Task.isCancelled else { throw error }
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms
            return try await operation()
        }
    }

    /// Whether a given error is transient and worth retrying
    private static func shouldRetry(_ error: AIClientError) -> Bool {
        switch error {
        case .apiError(let statusCode, _):
            return [429, 500, 502, 503, 504].contains(statusCode)
        case .networkError:
            return true
        default:
            return false
        }
    }
}
