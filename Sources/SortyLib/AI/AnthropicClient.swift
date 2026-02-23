//
//  AnthropicClient.swift
//  Sorty
//
//  Anthropic API client implementation
//

import Foundation

public final class AnthropicClient: AIClientProtocol, Sendable {
    public let config: AIConfig
    @MainActor public weak var streamingDelegate: StreamingDelegate?

    private static let messagesURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let modelsURL = URL(string: "https://api.anthropic.com/v1/models")!
    
    public init(config: AIConfig) {
        self.config = config
    }
    
    public func analyze(files: [FileItem], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }

        let url = Self.messagesURL
        
        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(personaInfo: "", maxTopLevelFolders: config.maxTopLevelFolders, mode: config.mode, enableTagging: config.enableFileTagging)
        let fullSystemPrompt = personaPrompt != nil ? "\(systemPrompt)\n\nPERSONA INSTRUCTIONS:\n\(personaPrompt!)" : systemPrompt

        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files,
            mode: config.mode,
            namingStyle: config.namingStyle,
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

    public func analyzeWithImages(files: [FileItem], imageData: [String: Data], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }

        let url = Self.messagesURL

        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildSystemPrompt(personaInfo: "", maxTopLevelFolders: config.maxTopLevelFolders, mode: config.mode, enableTagging: config.enableFileTagging)
        let fullSystemPrompt = personaPrompt != nil ? "\(systemPrompt)\n\nPERSONA INSTRUCTIONS:\n\(personaPrompt!)" : systemPrompt
        
        let userPrompt = PromptBuilder.buildOrganizationPrompt(
            files: files, 
            mode: config.mode,
            namingStyle: config.namingStyle,
            enableReasoning: config.enableReasoning, 
            includeContentMetadata: true,
            customInstructions: customInstructions
        )
        
        // Build multimodal content for Claude Vision
        var contentArray: [[String: Any]] = [
            ["type": "text", "text": userPrompt]
        ]
        
        // Add images in Claude's format
        for (_, data) in imageData {
            let base64 = data.base64EncodedString()
            contentArray.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64
                ]
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens ?? 4096,
            "system": fullSystemPrompt,
            "messages": [
                ["role": "user", "content": contentArray]
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
        let request = try AIRequestSupport.makeJSONRequest(
            url: url,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01"
            ],
            body: requestBody
        )

        let session = await AIRequestSupport.session(for: config)
        let (data, response) = try await AIRequestSupport.withTransientRetry {
            try await session.data(for: request)
        }

        _ = try AIRequestSupport.validateHTTPResponse(data: data, response: response)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = AIRequestSupport.extractText(from: json?["content"]),
              !text.isEmpty else {
            throw AIClientError.invalidResponseFormat
        }
        
        return try ResponseParser.parseResponse(text, originalFiles: files)
    }
    
    private func analyzeWithStreaming(url: URL, requestBody: [String: Any], apiKey: String, files: [FileItem]) async throws -> OrganizationPlan {
        var streamingRequestBody = requestBody
        streamingRequestBody["stream"] = true

        let request = try AIRequestSupport.makeJSONRequest(
            url: url,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01"
            ],
            body: streamingRequestBody
        )

        let session = await AIRequestSupport.session(for: config)
        let (bytes, response) = try await session.bytes(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIClientError.invalidResponse
        }
        
        if httpResponse.statusCode != 200 {
            var errorData = Data()
            for try await byte in bytes {
                errorData.append(byte)
            }
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown streaming error"
            throw AIClientError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }
        
        var accumulatedContent = ""
        
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let jsonString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if jsonString == "[DONE]" { break }

            if let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {

                let type = json["type"] as? String
                var chunkText: String?

                if type == "content_block_delta",
                   let delta = json["delta"] as? [String: Any] {
                    chunkText =
                        AIRequestSupport.extractText(from: delta["text"]) ??
                        AIRequestSupport.extractText(from: delta["partial_json"]) ??
                        AIRequestSupport.extractText(from: delta["content"])
                } else if type == "content_block_start",
                          let contentBlock = json["content_block"] as? [String: Any] {
                    chunkText = AIRequestSupport.extractText(from: contentBlock["text"])
                }

                if let chunk = chunkText, !chunk.isEmpty {
                    accumulatedContent += chunk
                    await MainActor.run { [weak self] in
                        self?.streamingDelegate?.didReceiveChunk(chunk)
                    }
                }
            }
        }
        
        let finalContent = accumulatedContent
        await MainActor.run { [weak self] in
            self?.streamingDelegate?.didComplete(content: finalContent)
        }
        
        do {
            return try ResponseParser.parseResponse(accumulatedContent, originalFiles: files)
        } catch {
            if let partialPlan = ResponseParser.extractPartialResults(accumulatedContent, originalFiles: files) {
                return partialPlan
            }
            throw AIClientError.jsonDecodingError(context: error.localizedDescription)
        }
    }
    
    public func checkHealth() async throws {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }

        var request = try AIRequestSupport.makeJSONRequest(
            url: Self.modelsURL,
            method: "GET",
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01"
            ]
        )
        request.timeoutInterval = min(config.requestTimeout, 60)

        let session = await AIRequestSupport.session(for: config)
        let (data, response) = try await AIRequestSupport.withTransientRetry {
            try await session.data(for: request)
        }
        _ = try AIRequestSupport.validateHTTPResponse(data: data, response: response)
    }
    
    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw AIClientError.missingAPIKey
        }
        
        let url = Self.messagesURL
        
        let requestBody: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens ?? 4096,
            "system": systemPrompt ?? "You are a helpful assistant.",
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": config.temperature
        ]
        
        let request = try AIRequestSupport.makeJSONRequest(
            url: url,
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01"
            ],
            body: requestBody
        )

        let session = await AIRequestSupport.session(for: config)
        let (data, response) = try await AIRequestSupport.withTransientRetry {
            try await session.data(for: request)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AIClientError.apiError(statusCode: status, message: errorText)
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = AIRequestSupport.extractText(from: json?["content"]),
              !text.isEmpty else {
            throw AIClientError.invalidResponseFormat
        }
        
        return text
    }
}
