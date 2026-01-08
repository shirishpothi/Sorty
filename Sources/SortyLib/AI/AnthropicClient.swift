//
//  AnthropicClient.swift
//  Sorty
//
//  Anthropic API client implementation
//

import Foundation

final class AnthropicClient: AIClientProtocol, @unchecked Sendable {
    let config: AIConfig
    private let session: URLSession
    @MainActor var streamingDelegate: StreamingDelegate?
    
    init(config: AIConfig) {
        self.config = config
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = config.requestTimeout
        sessionConfig.timeoutIntervalForResource = config.resourceTimeout
        self.session = URLSession(configuration: sessionConfig)
    }
    
    func analyze(files: [FileItem], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }
        
        // Anthropic uses Messages API: https://api.anthropic.com/v1/messages
        let urlString = "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: urlString) else {
            throw AIClientError.invalidURL
        }
        
        let systemPrompt = config.systemPromptOverride ?? "You are a professional file organization assistant. Analyze the provided file metadata and return a JSON plan for organizing them. Use ONLY the specified JSON format. No conversational text."
        let fullSystemPrompt = personaPrompt != nil ? "\(systemPrompt)\n\nPERSONA INSTRUCTIONS:\n\(personaPrompt!)" : systemPrompt
        
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files, 
            enableReasoning: config.enableReasoning, 
            includeContentMetadata: true,
            customInstructions: customInstructions
        )
        
        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens ?? 4096,
            "system": fullSystemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature ?? config.temperature
        ]
        
        if config.enableStreaming {
            return try await analyzeWithStreaming(url: url, requestBody: requestBody, apiKey: apiKey, files: files)
        } else {
            return try await analyzeStandard(url: url, requestBody: requestBody, apiKey: apiKey, files: files)
        }
    }
    
    private func analyzeStandard(url: URL, requestBody: [String: Any], apiKey: String, files: [FileItem]) async throws -> OrganizationPlan {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIClientError.invalidResponseFormat
        }
        
        return try ResponseParser.parseResponse(text, originalFiles: files)
    }
    
    private func analyzeWithStreaming(url: URL, requestBody: [String: Any], apiKey: String, files: [FileItem]) async throws -> OrganizationPlan {
        var streamingRequestBody = requestBody
        streamingRequestBody["stream"] = true
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: streamingRequestBody)
        
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: "Streaming error")
        }
        
        var accumulatedContent = ""
        
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))
                if jsonString == "[DONE]" { break }
                
                if let data = jsonString.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    
                    if let type = json["type"] as? String, type == "content_block_delta",
                       let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        
                        accumulatedContent += text
                        let chunk = text
                        await MainActor.run { [weak self] in
                            self?.streamingDelegate?.didReceiveChunk(chunk)
                        }
                    }
                }
            }
        }
        
        let finalContent = accumulatedContent
        await MainActor.run { [weak self] in
            self?.streamingDelegate?.didComplete(content: finalContent)
        }
        
        return try ResponseParser.parseResponse(accumulatedContent, originalFiles: files)
    }
    
    func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }
        
        let urlString = "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: urlString) else {
            throw AIClientError.invalidURL
        }
        
        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens ?? 4096,
            "system": systemPrompt ?? "You are a helpful assistant.",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": config.temperature
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIClientError.apiError(statusCode: status, message: errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw AIClientError.invalidResponseFormat
        }
        
        return text
    }
}
