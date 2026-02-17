//
//  GitHubCopilotClient.swift
//  Sorty
//
//  GitHub Copilot API Client
//

import Foundation

public final class GitHubCopilotClient: AIClientProtocol, @unchecked Sendable {
    public let config: AIConfig
    @MainActor public weak var streamingDelegate: StreamingDelegate?
    
    public init(config: AIConfig) {
        self.config = config
    }
    
    private func getSession() async -> URLSession {
        return await AISessionManager.shared.session(for: config.provider, config: config)
    }
    
    private func getHeaders() async throws -> [String: String] {
        let token = try await GitHubCopilotAuthManager.shared.getCopilotToken()
        return [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "Editor-Version": "vscode/1.85.1",
            "Editor-Plugin-Version": "copilot/1.138.0",
            "User-Agent": "GithubCopilot/1.138.0"
        ]
    }
    
    public func analyze(files: [FileItem], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        let url = URL(string: "https://api.githubcopilot.com/chat/completions")!
        
        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(personaInfo: personaPrompt ?? "", maxTopLevelFolders: config.maxTopLevelFolders, mode: config.mode, enableTagging: config.enableFileTagging)
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files,
            mode: config.mode,
            namingStyle: config.namingStyle,
            enableReasoning: config.enableReasoning,
            includeContentMetadata: true,
            customInstructions: customInstructions
        )
        
        var requestBody: [String: Any] = [
            "model": config.model, // Usually gpt-4 or similar supported by Copilot
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature ?? config.temperature,
            // Copilot often requires stream=true for best results, but supports false too.
        ]
        
        if let maxTokens = config.maxTokens {
            requestBody["max_tokens"] = maxTokens
        }
        
        let finalRequestBody = requestBody // Fix mutating warning by assigning to let
        
        if config.enableStreaming {
            return try await analyzeWithStreaming(url: url, requestBody: finalRequestBody, files: files)
        } else {
            return try await analyzeNonStreaming(url: url, requestBody: finalRequestBody, files: files)
        }
    }
    
    public func analyzeWithImages(files: [FileItem], imageData: [String: Data], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        // Check if model supports vision - if not, fall back to text-only
        let supportsVision = await ModelCatalog.shared.supportsVision(modelId: config.model, provider: config.provider)
        
        guard supportsVision, !imageData.isEmpty else {
            return try await analyze(files: files, customInstructions: customInstructions, personaPrompt: personaPrompt, temperature: temperature)
        }
        
        let url = URL(string: "https://api.githubcopilot.com/chat/completions")!
        
        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(personaInfo: personaPrompt ?? "", maxTopLevelFolders: config.maxTopLevelFolders, mode: config.mode, enableTagging: config.enableFileTagging)
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files,
            mode: config.mode,
            namingStyle: config.namingStyle,
            enableReasoning: config.enableReasoning,
            includeContentMetadata: true,
            customInstructions: customInstructions
        )
        
        // Build multimodal content array (OpenAI-compatible format)
        var userContent: [[String: Any]] = [
            ["type": "text", "text": userPrompt]
        ]
        
        // Add images (limit to first 5 to avoid token limits)
        for (filename, data) in imageData.prefix(5) {
            let base64 = data.base64EncodedString()
            let mimeType = filename.lowercased().hasSuffix(".png") ? "image/png" : "image/jpeg"
            userContent.append([
                "type": "image_url",
                "image_url": [
                    "url": "data:\(mimeType);base64,\(base64)",
                    "detail": "low"
                ]
            ])
        }
        
        var requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ],
            "temperature": temperature ?? config.temperature
        ]
        
        if let maxTokens = config.maxTokens {
            requestBody["max_tokens"] = maxTokens
        }
        
        if config.enableStreaming {
            return try await analyzeWithStreaming(url: url, requestBody: requestBody, files: files)
        } else {
            return try await analyzeNonStreaming(url: url, requestBody: requestBody, files: files)
        }
    }
    
    public func fetchAvailableModels() async throws -> [String] {
        let url = URL(string: "https://api.githubcopilot.com/models")!
        DebugLogger.log("Fetching available models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let headers = try await getHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        let session = await getSession()
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                // Fallback models if endpoint fails or not available
                return ["gpt-4", "gpt-3.5-turbo"]
            }
            
            struct ModelsResponse: Decodable {
                let data: [ModelData]
                struct ModelData: Decodable {
                    let id: String
                }
            }
            
            let modelsResponse = try JSONDecoder().decode(ModelsResponse.self, from: data)
            let models = modelsResponse.data.map { $0.id }
            return models.isEmpty ? ["gpt-4", "gpt-3.5-turbo"] : models
            
        } catch {
             // Fallback on error
             DebugLogger.log("Failed to fetch models: \(error), using defaults")
             return ["gpt-4", "gpt-3.5-turbo"]
        }
    }
    
    public func checkHealth() async throws {
        let url = URL(string: "https://api.githubcopilot.com/models")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = min(config.requestTimeout, 60)

        let headers = try await getHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let session = await getSession()
        let (_, response) = try await AIRequestSupport.withTransientRetry {
            try await session.data(for: request)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }

        if !(200...299).contains(httpResponse.statusCode) {
             throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: "Health check failed")
        }
    }
    
    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        let url = URL(string: "https://api.githubcopilot.com/chat/completions")!
        
        let requestBody: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": systemPrompt ?? "You are a helpful assistant."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let headers = try await getHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let session = await getSession()
        let (data, response) = try await AIRequestSupport.withTransientRetry {
            try await session.data(for: request)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            // Token might be expired, force refresh next time (basic handling)
            // Ideally AuthManager handles this, but here we just report error
             throw GitHubAuthError.accessDenied
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
    
    // MARK: - Non-Streaming Implementation
    
    private func analyzeNonStreaming(url: URL, requestBody: [String: Any], files: [FileItem]) async throws -> OrganizationPlan {
        let startTime = Date()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let headers = try await getHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let session = await getSession()
        do {
            let (data, response) = try await AIRequestSupport.withTransientRetry {
                try await session.data(for: request)
            }
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
            let estimatedTokens = content.count / 4
            let tps = duration > 0 ? Double(estimatedTokens) / duration : 0
            
            let stats = GenerationStats(
                duration: duration,
                tps: tps,
                ttft: duration, // approximate
                totalTokens: estimatedTokens,
                model: config.model,
                filesScanned: files.count,
                totalFileSize: files.reduce(0) { $0 + $1.size }
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
        
        let headers = try await getHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: streamingRequestBody)
        
        let startTime = Date()
        var firstTokenTime: Date?
        var accumulatedContentBuffer = "" // Local buffer to avoid Sendable capture issues
        
        let session = await getSession()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AIClientError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                var errorData = Data()
                for try await byte in bytes {
                    errorData.append(byte)
                }
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    let jsonString = String(line.dropFirst(6))
                    
                    if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                        break
                    }
                    
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
                            
                            accumulatedContentBuffer += content
                            
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
            let estimatedTokens = accumulatedContentBuffer.count / 4
            let tps = duration > 0 ? Double(estimatedTokens) / duration : 0
            
            let stats = GenerationStats(
                duration: duration,
                tps: tps,
                ttft: ttft,
                totalTokens: estimatedTokens,
                model: config.model,
                filesScanned: files.count,
                totalFileSize: files.reduce(0) { $0 + $1.size }
            )
            
            // Capture buffer for closure
            let finalContent = accumulatedContentBuffer
            await MainActor.run {
                streamingDelegate?.didComplete(content: finalContent)
            }
            
            var plan = try ResponseParser.parseResponse(accumulatedContentBuffer, originalFiles: files)
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
