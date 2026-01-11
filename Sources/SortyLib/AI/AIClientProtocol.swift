//
//  AIClientProtocol.swift
//  Sorty
//
//  Protocol defining AI client interface
//

import Foundation

/// Delegate protocol for streaming updates
@MainActor
public protocol StreamingDelegate: AnyObject {
    func didReceiveChunk(_ chunk: String)
    func didComplete(content: String)
    func didFail(error: Error)
}

public protocol AIClientProtocol: Sendable {
    func analyze(files: [FileItem], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan
    func generateText(prompt: String, systemPrompt: String?) async throws -> String
    var config: AIConfig { get }
    @MainActor var streamingDelegate: StreamingDelegate? { get set }
}

public enum AIClientError: LocalizedError, Sendable {
    case missingAPIURL
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case invalidResponseFormat
    case apiError(statusCode: Int, message: String)
    case networkError(Error)
    
    public var errorDescription: String? {
        switch self {
        case .missingAPIURL:
            return "API URL is required"
        case .missingAPIKey:
            return "API key is required"
        case .invalidURL:
            return "Invalid API URL"
        case .invalidResponse:
            return "Invalid response from AI provider"
        case .invalidResponseFormat:
            return "Invalid response format (JSON mode might be unsupported)"
        case .apiError(let statusCode, _):
            return "API Error (\(statusCode)): \(getStatusExplanation(statusCode))"
        case .networkError(let error):
            return "Connection Failed: \(error.localizedDescription)"
        }
    }
    
    public var failureReason: String? {
        switch self {
        case .apiError(_, let message):
            let parsed = parseErrorMessage(message)
            let redactedRaw = redactPotentialKeys(message)
            
            // If the message was successfully parsed from JSON, show both.
            // If parsing failed or was unnecessary, just show the redacted raw message.
            if parsed != message && !message.isEmpty {
                return "Error: \(redactPotentialKeys(parsed))\n\nRaw Response:\n\(redactedRaw)"
            }
            return redactedRaw
        case .networkError(let error):
            return error.localizedDescription
        case .missingAPIKey:
            return "Please enter an API key in the settings or disable 'Requires API Key' for local models."
        case .invalidURL:
            return "The URL format is incorrect. Ensure it starts with http:// or https://."
        default:
            return nil
        }
    }
    
    private func redactPotentialKeys(_ text: String) -> String {
        // Redact standard API key patterns: e.g. sk-..., ant-api-..., or any 32+ char alpha-numeric string
        let patterns = [
            "sk-[a-zA-Z0-9]{20,}",
            "ant-api-[a-zA-Z0-9-]{20,}",
            "[a-zA-Z0-9]{32,}"
        ]
        
        var redacted = text
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(location: 0, length: redacted.utf16.count)
                redacted = regex.stringByReplacingMatches(in: redacted, options: [], range: range, withTemplate: "[REDACTED KEY]")
            }
        }
        return redacted
    }
    
    private func getStatusExplanation(_ code: Int) -> String {
        switch code {
        case 401: return "Authentication failed. Your API key may be invalid or expired. Please check your credentials."
        case 403: return "Access denied. Your API key doesn't have permissions for this model or feature."
        case 404: return "Model or endpoint not found. Please verify the model name and API URL in settings."
        case 429: return "Rate limit exceeded. You've sent too many requests. Please wait a moment before trying again."
        case 500: return "Internal server error. The AI provider is experiencing technical difficulties."
        case 501: return "Not supported. This provider or feature is not available in your current environment."
        case 503: return "Service unavailable. The AI provider's servers are overloaded or undergoing maintenance."
        default: return "The request failed with an unexpected status code."
        }
    }
    
    private func parseErrorMessage(_ message: String) -> String {
        guard let data = message.data(using: .utf8) else { return message }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // OpenAI / Standard format: { "error": { "message": "..." } }
                if let error = json["error"] as? [String: Any],
                   let msg = error["message"] as? String {
                    return msg
                }
                // Anthropic format: { "type": "error", "error": { "message": "..." } }
                // (Handled by the above if it's nested similarly)
                
                // Simple format: { "message": "..." }
                if let msg = json["message"] as? String {
                    return msg
                }
                
                // Ollama/Other: { "error": "..." }
                if let msg = json["error"] as? String {
                    return msg
                }
            }
        } catch {
            // Not JSON or parsing failed, return raw message truncated if too long
        }
        
        // If it's HTML (common for proxy errors), strip it or just return a snippet
        if message.contains("<html>") {
            return "The server returned an HTML error page instead of JSON. This often happens with proxy or DNS issues."
        }
        
        return message.count > 300 ? String(message.prefix(300)) + "..." : message
    }
}



