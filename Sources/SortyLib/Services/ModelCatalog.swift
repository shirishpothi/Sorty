//
//  ModelCatalog.swift
//  Sorty
//
//  Dynamic model catalog with caching for AI providers.
//

import Foundation

public struct ModelInfo: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let provider: AIProvider
    public let capabilities: [String]?
    public let updatedAt: Date
    
    public init(id: String, displayName: String, provider: AIProvider, capabilities: [String]? = nil, updatedAt: Date = Date()) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.capabilities = capabilities
        self.updatedAt = updatedAt
    }
}

@MainActor
public final class ModelCatalog: ObservableObject {
    public static let shared = ModelCatalog()
    
    @Published public var modelsByProvider: [AIProvider: [ModelInfo]] = [:]
    @Published public var isFetching: [AIProvider: Bool] = [:]
    @Published public var lastError: [AIProvider: Error?] = [:]
    @Published public var searchResults: [(provider: AIProvider, models: [ModelInfo])] = []
    @Published public var usingFallback: [AIProvider: Bool] = [:]
    
    private var cacheTimestamps: [AIProvider: Date] = [:]
    private let session: URLSession
    private var searchTask: Task<Void, Never>?
    
    private static let cloudTTL: TimeInterval = 24 * 60 * 60
    private static let ollamaTTL: TimeInterval = 10 * 60
    
    private var cacheDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Sorty/ModelCache")
    }
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        loadCacheFromDisk()
    }
    
    public func cachedModels(for provider: AIProvider) -> [ModelInfo] {
        let cached = modelsByProvider[provider] ?? []
        if cached.isEmpty {
            return fallbackModels(for: provider)
        }
        return cached
    }
    
    public func refresh(provider: AIProvider, force: Bool = false) async {
        if !force, let timestamp = cacheTimestamps[provider] {
            let ttl = provider == .ollama ? Self.ollamaTTL : Self.cloudTTL
            if Date().timeIntervalSince(timestamp) < ttl {
                return
            }
        }
        
        isFetching[provider] = true
        lastError[provider] = nil
        
        do {
            let result = try await fetchModels(for: provider)
            let sortedModels = result.models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            modelsByProvider[provider] = sortedModels
            usingFallback[provider] = result.isFallback
            
            // Only update cache and timestamp if NOT using fallback
            if !result.isFallback {
                cacheTimestamps[provider] = Date()
                saveCacheToDisk(provider: provider, models: sortedModels)
            }
        } catch {
            await MainActor.run {
                lastError[provider] = error
            }
        }
        
        isFetching[provider] = false
    }
    
    public func refreshAllAvailable(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for provider in AIProvider.allCases where provider.isAvailable {
                group.addTask {
                    await self.refresh(provider: provider, force: force)
                }
            }
        }
    }
    
    public func searchAllProviders(query: String) -> [(provider: AIProvider, models: [ModelInfo])] {
        let lowercased = query.lowercased()
        var results: [(provider: AIProvider, models: [ModelInfo])] = []
        
        for (provider, models) in modelsByProvider {
            let matching = models.filter {
                $0.id.lowercased().contains(lowercased) ||
                $0.displayName.lowercased().contains(lowercased)
            }
            if !matching.isEmpty {
                results.append((provider, matching))
            }
        }
        
        return results.sorted { $0.provider.displayName < $1.provider.displayName }
    }
    
    public func performDebouncedSearch(query: String) {
        searchTask?.cancel()
        
        if query.isEmpty {
            searchResults = []
            return
        }
        
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 150_000_000)
            } catch {
                return
            }
            
            guard !Task.isCancelled else { return }
            
            let capturedModels = modelsByProvider
            let lowercased = query.lowercased()
            
            let results: [(provider: AIProvider, models: [ModelInfo])] = await Task.detached {
                var searchResults: [(provider: AIProvider, models: [ModelInfo])] = []
                for (provider, models) in capturedModels {
                    let matching = models.filter {
                        $0.id.lowercased().contains(lowercased) ||
                        $0.displayName.lowercased().contains(lowercased)
                    }
                    if !matching.isEmpty {
                        searchResults.append((provider, matching))
                    }
                }
                return searchResults.sorted { $0.provider.displayName < $1.provider.displayName }
            }.value
            
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }
    
    private func fetchModels(for provider: AIProvider) async throws -> (models: [ModelInfo], isFallback: Bool) {
        switch provider {
        case .openAI:
            return (try await fetchOpenAIModels(), false)
        case .anthropic:
            return try await fetchAnthropicModels()
        case .gemini:
            return try await fetchGeminiModels()
        case .groq:
            return (try await fetchGroqModels(), false)
        case .openRouter:
            return (try await fetchOpenRouterModels(), false)
        case .ollama:
            return (try await fetchOllamaModels(), false)
        case .githubCopilot:
            return try await fetchGitHubCopilotModels()
        case .appleFoundationModel:
            return (appleFoundationModels(), false)
        case .openAICompatible:
            return try await fetchOpenAICompatibleModels()
        }
    }
    
    private func fetchOpenAIModels() async throws -> [ModelInfo] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        guard let openAIAPIKey = KeychainManager.get(key: AIProvider.openAI.keychainKey), !openAIAPIKey.isEmpty else {
            throw ModelCatalogError.fetchFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(openAIAPIKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelCatalogError.fetchFailed
        }
        
        struct OpenAIModelsResponse: Decodable {
            let data: [OpenAIModel]
        }
        struct OpenAIModel: Decodable {
            let id: String
            let created: Int?
        }
        
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data.map { model in
            ModelInfo(
                id: model.id,
                displayName: model.id,
                provider: .openAI,
                updatedAt: model.created.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
            )
        }
    }
    
    private func fetchGroqModels() async throws -> [ModelInfo] {
        guard let url = URL(string: "https://api.groq.com/openai/v1/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        guard let groqAPIKey = KeychainManager.get(key: AIProvider.groq.keychainKey), !groqAPIKey.isEmpty else {
            throw ModelCatalogError.fetchFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(groqAPIKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelCatalogError.fetchFailed
        }
        
        struct GroqModelsResponse: Decodable {
            let data: [GroqModel]
        }
        struct GroqModel: Decodable {
            let id: String
            let created: Int?
        }
        
        let decoded = try JSONDecoder().decode(GroqModelsResponse.self, from: data)
        return decoded.data.map { model in
            ModelInfo(
                id: model.id,
                displayName: model.id,
                provider: .groq,
                updatedAt: model.created.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date()
            )
        }
    }
    
    private func fetchOpenRouterModels() async throws -> [ModelInfo] {
        guard let url = URL(string: "https://openrouter.ai/api/v1/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        if let apiKey = KeychainManager.get(key: AIProvider.openRouter.keychainKey), !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelCatalogError.fetchFailed
        }
        
        struct OpenRouterModelsResponse: Decodable {
            let data: [OpenRouterModel]
        }
        struct OpenRouterModel: Decodable {
            let id: String
            let name: String?
        }
        
        let decoded = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return decoded.data.map { model in
            ModelInfo(
                id: model.id,
                displayName: model.name ?? model.id,
                provider: .openRouter,
                updatedAt: Date()
            )
        }
    }
    
    private func fetchOllamaModels() async throws -> [ModelInfo] {
        guard let url = URL(string: "http://localhost:11434/api/tags") else {
            throw ModelCatalogError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelCatalogError.fetchFailed
        }
        
        struct OllamaTagsResponse: Decodable {
            let models: [OllamaModel]
        }
        struct OllamaModel: Decodable {
            let name: String
            let modified_at: String?
        }
        
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        return decoded.models.map { model in
            let updatedAt = model.modified_at.flatMap { dateFormatter.date(from: $0) } ?? Date()
            return ModelInfo(
                id: model.name,
                displayName: model.name,
                provider: .ollama,
                updatedAt: updatedAt
            )
        }
    }
    
    private func fetchAnthropicModels() async throws -> (models: [ModelInfo], isFallback: Bool) {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        guard let anthropicAPIKey = KeychainManager.get(key: AIProvider.anthropic.keychainKey), !anthropicAPIKey.isEmpty else {
            return (anthropicFallbackModels(), true)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(anthropicAPIKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (anthropicFallbackModels(), true)
            }
            
            struct AnthropicModelsResponse: Decodable {
                let data: [AnthropicModel]
            }
            struct AnthropicModel: Decodable {
                let id: String
                let display_name: String?
            }
            
            let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            if decoded.data.isEmpty {
                return (anthropicFallbackModels(), true)
            }
            
            let models = decoded.data.map { model in
                ModelInfo(
                    id: model.id,
                    displayName: model.display_name ?? model.id,
                    provider: .anthropic,
                    updatedAt: Date()
                )
            }
            return (models, false)
        } catch {
            return (anthropicFallbackModels(), true)
        }
    }

    private func fetchOpenAICompatibleModels() async throws -> (models: [ModelInfo], isFallback: Bool) {
        // We need to get the URL from the current config
        // This is a bit tricky as ModelCatalog is a singleton and doesn't know about SettingsViewModel
        // However, we can try to use the stored URL in UserDefaults or just fallback
        
        let userDefaults = UserDefaults.standard
        let configKey = "aiConfig"
        
        var apiURL = "https://api.openai.com"
        var apiKey: String?
        
        if let data = userDefaults.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(AIConfig.self, from: data) {
            if decoded.provider == .openAICompatible {
                apiURL = decoded.apiURL ?? apiURL
            }
        }
        
        apiKey = KeychainManager.get(key: AIProvider.openAICompatible.keychainKey)
        
        // Ensure URL ends with /v1/models or similar if it's just a base URL
        var urlString = apiURL
        if !urlString.hasSuffix("/models") {
            if urlString.hasSuffix("/") {
                urlString += "v1/models"
            } else {
                urlString += "/v1/models"
            }
        }
        
        guard let url = URL(string: urlString) else {
            return (openAICompatibleFallback(), true)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let key = apiKey, !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (openAICompatibleFallback(), true)
            }
            
            struct OpenAIModelsResponse: Decodable {
                let data: [OpenAIModel]
            }
            struct OpenAIModel: Decodable {
                let id: String
            }
            
            let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
            let models = decoded.data.map { model in
                ModelInfo(
                    id: model.id,
                    displayName: model.id,
                    provider: .openAICompatible,
                    updatedAt: Date()
                )
            }
            return (models, false)
        } catch {
            return (openAICompatibleFallback(), true)
        }
    }
    
    private func fetchGitHubCopilotModels() async throws -> (models: [ModelInfo], isFallback: Bool) {
        guard let url = URL(string: "https://api.githubcopilot.com/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        let token = try await GitHubCopilotAuthManager.shared.getCopilotToken()
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("vscode/1.85.1", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot/1.138.0", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("Sorty/1.0", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                throw ModelCatalogError.fetchFailed
            }
            
            struct ModelsResponse: Decodable {
                let data: [ModelData]
                struct ModelData: Decodable {
                    let id: String
                }
            }
            
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            if decoded.data.isEmpty {
                throw ModelCatalogError.fetchFailed
            }
            
            let models = decoded.data.map { model in
                ModelInfo(
                    id: model.id,
                    displayName: model.id,
                    provider: .githubCopilot,
                    updatedAt: Date()
                )
            }
            return (models, false)
        } catch {
            throw error
        }
    }
    
    private func fetchGeminiModels() async throws -> (models: [ModelInfo], isFallback: Bool) {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        guard let geminiAPIKey = KeychainManager.get(key: AIProvider.gemini.keychainKey), !geminiAPIKey.isEmpty else {
             return (geminiFallbackModels(), true)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(geminiAPIKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return (geminiFallbackModels(), true)
            }
            
            struct GeminiModelsResponse: Decodable {
                let models: [GeminiModel]
            }
            struct GeminiModel: Decodable {
                let name: String
                let displayName: String?
            }
            
            let decoded = try JSONDecoder().decode(GeminiModelsResponse.self, from: data)
            if decoded.models.isEmpty {
                return (geminiFallbackModels(), true)
            }
            
            let models = decoded.models.map { model in
                let id = model.name.replacingOccurrences(of: "models/", with: "")
                return ModelInfo(
                    id: id,
                    displayName: model.displayName ?? id,
                    provider: .gemini,
                    updatedAt: Date()
                )
            }
            return (models, false)
        } catch {
            return (geminiFallbackModels(), true)
        }
    }
    
    private func anthropicFallbackModels() -> [ModelInfo] {
        let models = [
            "claude-3-5-sonnet-20241022",
            "claude-3-5-sonnet-latest",
            "claude-3-5-haiku-20241022",
            "claude-3-5-haiku-latest",
            "claude-3-opus-20240229",
            "claude-3-opus-latest",
            "claude-3-sonnet-20240229",
            "claude-3-haiku-20240307"
        ]
        return models.map { ModelInfo(id: $0, displayName: $0, provider: .anthropic) }
    }
    
    private func geminiFallbackModels() -> [ModelInfo] {
        let models = [
            "gemini-2.0-flash-exp",
            "gemini-1.5-pro",
            "gemini-1.5-pro-latest",
            "gemini-1.5-flash",
            "gemini-1.5-flash-latest",
            "gemini-1.5-flash-8b",
            "gemini-1.0-pro"
        ]
        return models.map { ModelInfo(id: $0, displayName: $0, provider: .gemini) }
    }
    
    private func appleFoundationModels() -> [ModelInfo] {
        [ModelInfo(id: "default", displayName: "Default", provider: .appleFoundationModel)]
    }
    
    private func openAICompatibleFallback() -> [ModelInfo] {
        [ModelInfo(id: "gpt-4", displayName: "GPT-4", provider: .openAICompatible)]
    }
    
    private func fallbackModels(for provider: AIProvider) -> [ModelInfo] {
        provider.recommendedModels.map { ModelInfo(id: $0, displayName: $0, provider: provider) }
    }
    
    private func loadCacheFromDisk() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cacheDirectory.path) else { return }
        
        for provider in AIProvider.allCases {
            let cacheFile = cacheDirectory.appendingPathComponent("\(provider.rawValue).json")
            guard fm.fileExists(atPath: cacheFile.path) else { continue }
            
            do {
                let data = try Data(contentsOf: cacheFile)
                let wrapper = try JSONDecoder().decode(CacheWrapper.self, from: data)
                modelsByProvider[provider] = wrapper.models
                cacheTimestamps[provider] = wrapper.timestamp
            } catch {
                continue
            }
        }
    }
    
    private func saveCacheToDisk(provider: AIProvider, models: [ModelInfo]) {
        let fm = FileManager.default
        
        if !fm.fileExists(atPath: cacheDirectory.path) {
            try? fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
        
        let cacheFile = cacheDirectory.appendingPathComponent("\(provider.rawValue).json")
        let wrapper = CacheWrapper(models: models, timestamp: Date())
        
        do {
            let data = try JSONEncoder().encode(wrapper)
            try data.write(to: cacheFile)
        } catch {
            return
        }
    }

    // MARK: - Vision Support

    /// Known models that support vision (multimodal)
    private static let knownVisionModels: Set<String> = [
        // OpenAI
        "gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4-vision-preview",
        // Anthropic
        "claude-3-5-sonnet-20241022", "claude-3-5-sonnet-latest", "claude-3-5-haiku-20241022",
        "claude-3-opus-20240229", "claude-3-sonnet-20240229", "claude-3-haiku-20240307",
        // Gemini
        "gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.5-flash-8b", "gemini-2.0-flash-exp",
        // Groq
        "llama-3.2-11b-vision-preview", "llama-3.2-90b-vision-preview"
    ]

    /// Check if a specific model supports vision capabilities
    public func supportsVision(modelId: String, provider: AIProvider) -> Bool {
        // First check explicitly known models
        if Self.knownVisionModels.contains(modelId) {
            return true
        }

        // Provider-specific heuristics
        switch provider {
        case .ollama:
            // Ollama often uses models like 'llava', 'bakllava' for vision
            let visionKeywords = ["llava", "vision", "moondream", "minicpm"]
            return visionKeywords.contains { modelId.lowercased().contains($0) }
        case .openRouter:
            // OpenRouter often includes vision in the name or we can check the ID
            return modelId.lowercased().contains("vision") || modelId.lowercased().contains("vl")
        default:
            return modelId.lowercased().contains("vision") || modelId.lowercased().contains("flash")
        }
    }
}

private struct CacheWrapper: Codable {
    let models: [ModelInfo]
    let timestamp: Date
}

public enum ModelCatalogError: Error, LocalizedError {
    case invalidURL
    case fetchFailed
    case decodingFailed
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL for model API"
        case .fetchFailed: return "Failed to fetch models from provider"
        case .decodingFailed: return "Failed to decode model response"
        }
    }
}
