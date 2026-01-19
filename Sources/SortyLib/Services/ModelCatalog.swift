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
            let models = try await fetchModels(for: provider)
            let sortedModels = models.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            modelsByProvider[provider] = sortedModels
            cacheTimestamps[provider] = Date()
            saveCacheToDisk(provider: provider, models: sortedModels)
        } catch {
            await MainActor.run {
                lastError[provider] = error
                // Don't fall back to hardcoded models - keep existing cache if available
                // This ensures we always use ModelCatalog data
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
    
    private func fetchModels(for provider: AIProvider) async throws -> [ModelInfo] {
        switch provider {
        case .openAI:
            return try await fetchOpenAIModels()
        case .anthropic:
            return anthropicModels()
        case .gemini:
            return try await fetchGeminiModels()
        case .groq:
            return try await fetchGroqModels()
        case .openRouter:
            return try await fetchOpenRouterModels()
        case .ollama:
            return try await fetchOllamaModels()
        case .githubCopilot:
            return try await fetchGitHubCopilotModels()
        case .appleFoundationModel:
            return appleFoundationModels()
        case .openAICompatible:
            return openAICompatibleFallback()
        }
    }
    
    private func fetchOpenAIModels() async throws -> [ModelInfo] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        guard let openAIAPIKey = UserDefaults.standard.string(forKey: "openAIAPIKey"), !openAIAPIKey.isEmpty else {
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
        
        guard let groqAPIKey = UserDefaults.standard.string(forKey: "groqAPIKey"), !groqAPIKey.isEmpty else {
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
    
    private func fetchGitHubCopilotModels() async throws -> [ModelInfo] {
        // GitHub Copilot requires auth headers, so we fetch via GitHubCopilotClient
        // For now, try the API directly; if it fails, use fallback
        guard let url = URL(string: "https://api.githubcopilot.com/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // API requires auth - return fallback
                return githubCopilotFallbackModels()
            }
            
            struct ModelsResponse: Decodable {
                let data: [ModelData]
                struct ModelData: Decodable {
                    let id: String
                }
            }
            
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            if decoded.data.isEmpty {
                return githubCopilotFallbackModels()
            }
            
            return decoded.data.map { model in
                ModelInfo(
                    id: model.id,
                    displayName: model.id,
                    provider: .githubCopilot,
                    updatedAt: Date()
                )
            }
        } catch {
            // Auth required or network error - return fallback
            return githubCopilotFallbackModels()
        }
    }
    
    private func githubCopilotFallbackModels() -> [ModelInfo] {
        // Known models available via GitHub Copilot
        let models = [
            "gpt-4o",
            "gpt-4o-mini",
            "gpt-4",
            "gpt-4-turbo",
            "gpt-3.5-turbo",
            "claude-3.5-sonnet",
            "claude-3-opus",
            "o1-preview",
            "o1-mini"
        ]
        return models.map { ModelInfo(id: $0, displayName: $0, provider: .githubCopilot) }
    }
    
    private func fetchGeminiModels() async throws -> [ModelInfo] {
        // Google's models list API
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1/models") else {
            throw ModelCatalogError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                // API may require API key - return fallback
                return geminiModels()
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
                return geminiModels()
            }
            
            return decoded.models.compactMap { model in
                // name format is "models/gemini-pro", extract model id
                let id = model.name.replacingOccurrences(of: "models/", with: "")
                guard id.contains("gemini") else { return nil }
                return ModelInfo(
                    id: id,
                    displayName: model.displayName ?? id,
                    provider: .gemini,
                    updatedAt: Date()
                )
            }
        } catch {
            return geminiModels()
        }
    }
    
    private func anthropicModels() -> [ModelInfo] {
        let models = [
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-opus-20240229",
            "claude-3-sonnet-20240229",
            "claude-3-haiku-20240307"
        ]
        return models.map { ModelInfo(id: $0, displayName: $0, provider: .anthropic) }
    }
    
    private func geminiModels() -> [ModelInfo] {
        // Fallback Gemini models when API is unavailable
        let models = [
            "gemini-2.0-flash-exp",
            "gemini-1.5-pro",
            "gemini-1.5-flash",
            "gemini-1.0-pro"
        ]
        return models.map { ModelInfo(id: $0, displayName: $0, provider: .gemini) }
    }
    
    // Kept for backward compatibility but no longer used directly
    private func githubCopilotModels() -> [ModelInfo] {
        return githubCopilotFallbackModels()
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
