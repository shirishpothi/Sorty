//
//  OpenAIClient.swift
//  Sorty
//
//  OpenAI-Compatible API Client with Streaming Support
//

import Foundation

public final class OpenAIClient: AIClientProtocol, Sendable {
    public let config: AIConfig
    @MainActor public weak var streamingDelegate: StreamingDelegate?
    
    public init(config: AIConfig) {
        self.config = config
    }
    
    public func analyze(files: [FileItem], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        let apiURL = try AIRequestSupport.requireAPIURL(from: config)
        try AIRequestSupport.requireAPIKeyIfNeeded(from: config)
        let url = try AIRequestSupport.openAIChatCompletionsURL(from: apiURL)
        
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
        let apiURL = try AIRequestSupport.requireAPIURL(from: config)
        try AIRequestSupport.requireAPIKeyIfNeeded(from: config)
        let url = try AIRequestSupport.openAIChatCompletionsURL(from: apiURL)
        
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
        let apiURL = try AIRequestSupport.requireAPIURL(from: config)
        try AIRequestSupport.requireAPIKeyIfNeeded(from: config)
        let url = try AIRequestSupport.openAIChatCompletionsURL(from: apiURL)
        
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
        
        var headers: [String: String] = [:]
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        let request = try AIRequestSupport.makeJSONRequest(url: url, headers: headers, body: requestBody)

        let session = await AIRequestSupport.session(for: config)
        let (data, response) = try await AIRequestSupport.withTransientRetry {
            try await session.data(for: request)
        }

        _ = try AIRequestSupport.validateHTTPResponse(data: data, response: response)
        
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
        let apiURL = try AIRequestSupport.requireAPIURL(from: config)
        let url = try AIRequestSupport.openAIModelsURL(from: apiURL)

        var headers: [String: String] = [:]
        if config.requiresAPIKey, let apiKey = config.apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

        var request = try AIRequestSupport.makeJSONRequest(url: url, method: "GET", headers: headers)
        request.timeoutInterval = min(config.requestTimeout, 60)

        let session = await AIRequestSupport.session(for: config)
        let (data, response) = try await AIRequestSupport.withTransientRetry {
            try await session.data(for: request)
        }
        _ = try AIRequestSupport.validateHTTPResponse(data: data, response: response)
    }
    
    // MARK: - Non-Streaming Implementation
    
    private func analyzeNonStreaming(url: URL, requestBody: [String: Any], files: [FileItem], systemPrompt: String, userPrompt: String) async throws -> OrganizationPlan {
        let startTime = Date()
        var headers: [String: String] = [:]
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

        let request = try AIRequestSupport.makeJSONRequest(url: url, headers: headers, body: requestBody)

        let session = await AIRequestSupport.session(for: config)
        do {
            let (data, response) = try await AIRequestSupport.withTransientRetry {
                try await session.data(for: request)
            }
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)

            _ = try AIRequestSupport.validateHTTPResponse(data: data, response: response)
            
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
        
        var headers: [String: String] = [:]
        if let apiKey = config.apiKey, !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

        let request = try AIRequestSupport.makeJSONRequest(url: url, headers: headers, body: streamingRequestBody)
        
        let startTime = Date()
        var firstTokenTime: Date?
        var accumulatedContent = ""
        var tokenCountEstimate = 0
        
        let session = await AIRequestSupport.session(for: config)
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


