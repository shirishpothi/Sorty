//
//  OpenAIClient.swift
//  Sorty
//
//  OpenAI-Compatible API Client with Streaming Support
//

import Foundation

public final class OpenAIClient: AIClientProtocol, @unchecked Sendable {
    
    /// Helper to construct the full endpoint URL from a base URL
    static func constructEndpoint(from apiURL: String) -> String {
        var base = apiURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Prepend https:// if no scheme is present
        if !base.contains("://") && !base.isEmpty {
            base = "https://" + base
        }
        
        if base.hasSuffix("/v1/chat/completions") {
             return base
        } else if base.hasSuffix("/v1") {
             return "\(base)/chat/completions"
        } else if base.hasSuffix("/v1/") {
             return "\(base)chat/completions"
        } else if base.hasSuffix("/") {
             return "\(base)v1/chat/completions"
        } else {
             return "\(base)/v1/chat/completions"
        }
    }
    public let config: AIConfig
    @MainActor public weak var streamingDelegate: StreamingDelegate?
    
    public init(config: AIConfig) {
        self.config = config
    }
    
    private func getSession() async -> URLSession {
        return await AISessionManager.shared.session(for: config.provider, config: config)
    }
    
    public func analyze(files: [FileItem], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        guard let apiURL = config.apiURL else {
            throw AIClientError.missingAPIURL
        }
        
        // API key is now optional - only required if config.requiresAPIKey is true
        if config.requiresAPIKey && (config.apiKey == nil || config.apiKey?.isEmpty == true) {
            throw AIClientError.missingAPIKey
        }
        
        // Use standard OpenAI-compatible endpoint structure for both providers
        // OpenAI: https://api.openai.com/v1/chat/completions
        // Ollama: http://localhost:11434/v1/chat/completions
        let endpoint = OpenAIClient.constructEndpoint(from: apiURL)
        
        guard let url = URL(string: endpoint), url.scheme != nil else {
            throw AIClientError.invalidURL
        }
        
        // Use custom system prompt if provided, otherwise use default
        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(personaInfo: personaPrompt ?? "", maxTopLevelFolders: config.maxTopLevelFolders, mode: config.mode, enableTagging: config.enableFileTagging)
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files, 
            mode: config.mode,
            namingStyle: config.namingStyle,
            customNamingInstructions: config.customNamingInstructions,
            enableReasoning: config.enableReasoning, 
            enableSmartRename: config.enableSmartRename,
            includeContentMetadata: true,
            customInstructions: customInstructions
        )
        
        // Build request body
        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature ?? config.temperature,
            "response_format": ["type": "json_object"]
        ]
        
        // Add max_tokens if specified
        if let maxTokens = config.maxTokens {
            requestBody["max_tokens"] = maxTokens
        }
        
        // Use streaming if enabled
        if config.enableStreaming {
            return try await analyzeWithStreaming(url: url, requestBody: requestBody, files: files)
        } else {
            return try await analyzeNonStreaming(url: url, requestBody: requestBody, files: files, systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }
    
    public func analyzeWithImages(files: [FileItem], imageData: [String: Data], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        guard let apiURL = config.apiURL else {
            throw AIClientError.missingAPIURL
        }
        
        if config.requiresAPIKey && (config.apiKey == nil || config.apiKey?.isEmpty == true) {
            throw AIClientError.missingAPIKey
        }
        
        let endpoint = OpenAIClient.constructEndpoint(from: apiURL)
        
        guard let url = URL(string: endpoint), url.scheme != nil else {
            throw AIClientError.invalidURL
        }
        
        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(personaInfo: personaPrompt ?? "", maxTopLevelFolders: config.maxTopLevelFolders, mode: config.mode, enableTagging: config.enableFileTagging)
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files, 
            mode: config.mode,
            namingStyle: config.namingStyle,
            customNamingInstructions: config.customNamingInstructions,
            enableReasoning: config.enableReasoning, 
            enableSmartRename: config.enableSmartRename,
            includeContentMetadata: true,
            customInstructions: customInstructions
        )
        
        // Build multimodal content
        var contentArray: [[String: Any]] = [
            ["type": "text", "text": userPrompt]
        ]
        
        // Add images as base64
        for (_, data) in imageData {
            let base64 = data.base64EncodedString()
            contentArray.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:image/jpeg;base64,\(base64)",
                    "detail": "auto"
                ]
            ])
        }
        
        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": contentArray]
            ],
            "temperature": temperature ?? config.temperature,
            "response_format": ["type": "json_object"]
        ]
        
        if let maxTokens = config.maxTokens {
            requestBody["max_tokens"] = maxTokens
        }
        
        // Multimodal usually doesn't work well with streaming in some implementations, 
        // but we'll follow the config if possible.
        if config.enableStreaming {
            return try await analyzeWithStreaming(url: url, requestBody: requestBody, files: files)
        } else {
            return try await analyzeNonStreaming(url: url, requestBody: requestBody, files: files, systemPrompt: systemPrompt, userPrompt: userPrompt)
        }
    }
    
    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        guard let apiURL = config.apiURL else {
            throw AIClientError.missingAPIURL
        }
        
        if config.requiresAPIKey && (config.apiKey == nil || config.apiKey?.isEmpty == true) {
            throw AIClientError.missingAPIKey
        }
        
        let endpoint = OpenAIClient.constructEndpoint(from: apiURL)
        
        guard let url = URL(string: endpoint), url.scheme != nil else {
            throw AIClientError.invalidURL
        }
        
        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt ?? "You are a helpful assistant."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7
        ]
        
        if let maxTokens = config.maxTokens {
            requestBody["max_tokens"] = maxTokens
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let session = await getSession()
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        
        guard let choices = jsonResponse?["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIClientError.invalidResponseFormat
        }
        
        return content
    }
    
    public func checkHealth() async throws {
        guard let apiURL = config.apiURL else {
            throw AIClientError.missingAPIURL
        }
        
        // Construct the models endpoint URL properly based on the base URL format
        var modelsURL: String
        
        if apiURL.hasSuffix("/chat/completions") {
            // Strip /chat/completions and use /models
            modelsURL = String(apiURL.dropLast("/chat/completions".count)) + "/models"
        } else if apiURL.hasSuffix("/chat/completions/") {
            modelsURL = String(apiURL.dropLast("/chat/completions/".count)) + "/models"
        } else if apiURL.hasSuffix("/v1") {
            // URL ends with /v1, add /models
            modelsURL = apiURL + "/models"
        } else if apiURL.hasSuffix("/v1/") {
            modelsURL = apiURL + "models"
        } else if apiURL.contains("/v1/") || apiURL.contains("/v1beta/") {
            // URL already has versioning path (like OpenRouter or Gemini)
            let baseURL = apiURL.hasSuffix("/") ? apiURL : apiURL + "/"
            modelsURL = baseURL + "models"
        } else {
            // Standard API base URL (like https://api.openai.com), add /v1/models
            let baseURL = apiURL.hasSuffix("/") ? String(apiURL.dropLast()) : apiURL
            modelsURL = baseURL + "/v1/models"
        }
        
        guard let url = URL(string: modelsURL), url.scheme != nil else {
            throw AIClientError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = min(config.requestTimeout, 60)

        if config.requiresAPIKey, let apiKey = config.apiKey, !apiKey.isEmpty {
            request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let session = await getSession()
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
             throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: "Health check failed")
        }
    }
    
    // MARK: - Non-Streaming Implementation
    
    private func analyzeNonStreaming(url: URL, requestBody: [String: Any], files: [FileItem], systemPrompt: String, userPrompt: String) async throws -> OrganizationPlan {
        let startTime = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Only add Authorization header if API key is provided
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let session = await getSession()
        do {
            let (data, response) = try await session.data(for: request)
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIClientError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            

            
            guard let choices = jsonResponse?["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw AIClientError.invalidResponseFormat
            }
            
            // Calculate stats
            // For non-streaming, TTFT is essentially the total duration as we wait for the full response
            // Estimated tokens: ~4 chars per token
            let estimatedTokens = content.count / 4
            let tps = duration > 0 ? Double(estimatedTokens) / duration : 0
            
            let stats = GenerationStats(
                duration: duration,
                tps: tps,
                ttft: duration, // approximate
                totalTokens: estimatedTokens,
                model: config.model,
                filesScanned: files.count,
                totalFileSize: files.reduce(0) { $0 + $1.size },
                promptTokens: PromptBuilder.estimateTokens(systemPrompt + userPrompt)
            )
            
            var plan = try ResponseParser.parseResponse(content, originalFiles: files)
            plan.generationStats = stats
            return plan
        } catch let error as AIClientError {
            throw error
        } catch {
            throw AIClientError.networkError(error)
        }
    }
    
    // MARK: - Streaming Implementation
    
    private func analyzeWithStreaming(url: URL, requestBody: [String: Any], files: [FileItem]) async throws -> OrganizationPlan {
        var streamingRequestBody = requestBody
        streamingRequestBody["stream"] = true
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // Only add Authorization header if API key is provided
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: streamingRequestBody)
        
        let startTime = Date()
        var firstTokenTime: Date?
        var accumulatedContent = ""
        var tokenCountEstimate = 0
        
        let session = await getSession()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIClientError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                // For streaming errors, we need to collect the error message
                var errorData = Data()
                for try await byte in bytes {
                    errorData.append(byte)
                }
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            // Process SSE stream
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    // Check for stream end
                    if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                        break
                    }
                    
                    // Parse the JSON chunk
                    if let jsonData = jsonString.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                        
                        let choices = json["choices"] as? [[String: Any]]
                        let firstChoice = choices?.first
                        let delta = firstChoice?["delta"] as? [String: Any]
                        let deltaContent = delta?["content"] as? String

                        if let content = deltaContent {
                            if firstTokenTime == nil {
                                firstTokenTime = Date()
                            }
                            
                            accumulatedContent += content
                            tokenCountEstimate += 1
                            
                            await MainActor.run {
                                streamingDelegate?.didReceiveChunk(content)
                            }
                        }
                    }
                }
            }
            
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            let ttft = firstTokenTime?.timeIntervalSince(startTime) ?? duration
            
            // improved token estimation: ~4 chars per token
            let estimatedTokens = accumulatedContent.count / 4
            let tps = duration > 0 ? Double(estimatedTokens) / duration : 0
            
            let stats = GenerationStats(
                duration: duration,
                tps: tps,
                ttft: ttft,
                totalTokens: estimatedTokens,
                model: config.model,
                filesScanned: files.count,
                totalFileSize: files.reduce(0) { $0 + $1.size },
                promptTokens: PromptBuilder.estimateTokens(accumulatedContent) // We don't have the exact prompt tokens here easily
            )
            
            // Notify completion
            let finalContent = accumulatedContent
            await MainActor.run {
                streamingDelegate?.didComplete(content: finalContent)
            }
            
            var plan = try ResponseParser.parseResponse(accumulatedContent, originalFiles: files)
            plan.generationStats = stats
            return plan
            
        } catch let error as AIClientError {
            await MainActor.run {
                streamingDelegate?.didFail(error: error)
            }
            throw error
        } catch {
            let clientError = AIClientError.networkError(error)
            await MainActor.run {
                streamingDelegate?.didFail(error: clientError)
            }
            throw clientError
        }
    }
}


