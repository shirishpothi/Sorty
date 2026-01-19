//
//  AIConfig.swift
//  Sorty
//
//  AI Configuration Model
//

import Foundation

public enum AIProvider: String, Codable, CaseIterable, Sendable {
    case openAI = "openai"
    case githubCopilot = "github_copilot"
    case groq = "groq"
    case openAICompatible = "openai_compatible"
    case openRouter = "open_router"
    case ollama = "ollama"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case appleFoundationModel = "apple_foundation_model"
    
    public var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .githubCopilot:
            return "GitHub Copilot"
        case .groq:
            return "Groq"
        case .openAICompatible:
            return "OpenAI-Compatible API"
        case .openRouter:
            return "OpenRouter"
        case .ollama:
            return "Ollama (Local)"
        case .anthropic:
            return "Anthropic (Claude)"
        case .gemini:
            return "Google Gemini"
        case .appleFoundationModel:
            return "Apple Foundation Model"
        }
    }
    
    public var isAvailable: Bool {
        switch self {
        case .openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .ollama, .anthropic, .gemini:
            return true
        case .appleFoundationModel:
            #if canImport(FoundationModels) && os(macOS)
            if #available(macOS 26.0, *) {
                return AppleFoundationModelClient.isAvailable()
            }
            #endif
            return false
        }
    }
    
    public var unavailabilityReason: String? {
        switch self {
        case .openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .ollama, .anthropic, .gemini:
            return nil
        case .appleFoundationModel:
            #if canImport(FoundationModels) && os(macOS)
            if #available(macOS 26.0, *) {
                return AppleFoundationModelClient.unavailabilityReason
            }
            #endif
            return "Apple Intelligence is not supported on this version of macOS."
        }
    }
    
    /// Default API URL for this provider
    public var defaultAPIURL: String? {
        switch self {
        case .openAI:
            return "https://api.openai.com"
        case .githubCopilot:
            return "https://api.githubcopilot.com"
        case .groq:
            return "https://api.groq.com/openai"
        case .openAICompatible:
            return "https://api.openai.com"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .ollama:
            return "http://localhost:11434"
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .appleFoundationModel:
            return nil
        }
    }
    
    /// Default model for this provider
    public var defaultModel: String {
        switch self {
        case .openAI:
            return "gpt-5-mini"
        case .githubCopilot:
            return "gpt-5-mini"
        case .groq:
            return "llama-4-70b-versatile"
        case .openAICompatible:
            return "gpt-5-mini"
        case .openRouter:
            return "anthropic/claude-haiku-4.5"
        case .ollama:
            return "llama4"
        case .anthropic:
            return "claude-haiku-4.5"
        case .gemini:
            return "gemini-3-flash-preview"
        case .appleFoundationModel:
            return "default"
        }
    }
    
    /// Whether this provider typically requires an API key
    public var typicallyRequiresAPIKey: Bool {
        switch self {
        case .openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .anthropic, .gemini:
            return true
        case .ollama:
            return false
        case .appleFoundationModel:
            // CRITICAL: Apple Foundation Model runs strictly on-device via FoundationModels.framework
            // it does NOT use an API key and this must remain 'false'.
            return false
        }
    }
    
    /// Help text for obtaining API keys
    public var apiKeyHelpText: String {
        switch self {
        case .openAI:
            return "Get your API key from platform.openai.com"
        case .githubCopilot:
            return "Use your GitHub Personal Access Token with Copilot enabled"
        case .groq:
            return "Get your API key from console.groq.com"
        case .openAICompatible:
            return "Enter your API key for the compatible provider"
        case .openRouter:
            return "Get your API key from openrouter.ai/keys"
        case .ollama:
            return "API key is optional for local Ollama instances"
        case .anthropic:
            return "Get your API key from console.anthropic.com"
        case .gemini:
            return "Get your API key from aistudio.google.com"
        case .appleFoundationModel:
            return "No API key required"
        }
    }
    
    /// URL where users can get their API key
    public var apiKeyURL: URL? {
        switch self {
        case .openAI:
            return URL(string: "https://platform.openai.com/api-keys")
        case .githubCopilot:
            return URL(string: "https://github.com/settings/tokens")
        case .groq:
            return URL(string: "https://console.groq.com/keys")
        case .openAICompatible:
            return nil // Varies by provider
        case .openRouter:
            return URL(string: "https://openrouter.ai/keys")
        case .ollama:
            return URL(string: "https://ollama.ai/download")
        case .anthropic:
            return URL(string: "https://console.anthropic.com/settings/keys")
        case .gemini:
            return URL(string: "https://aistudio.google.com/app/apikey")
        case .appleFoundationModel:
            return nil
        }
    }
    
    /// Short label for the API key link
    public var apiKeyLinkLabel: String {
        switch self {
        case .openAI:
            return "platform.openai.com"
        case .githubCopilot:
            return "github.com/settings/tokens"
        case .groq:
            return "console.groq.com"
        case .openAICompatible:
            return "your provider's website"
        case .openRouter:
            return "openrouter.ai/keys"
        case .ollama:
            return "ollama.ai"
        case .anthropic:
            return "console.anthropic.com"
        case .gemini:
            return "aistudio.google.com"
        case .appleFoundationModel:
            return ""
        }
    }
    
    /// URL to the provider's model documentation
    public var modelDocumentationURL: URL? {
        switch self {
        case .openAI:
            return URL(string: "https://platform.openai.com/docs/models")
        case .githubCopilot:
            return URL(string: "https://docs.github.com/en/copilot/using-github-copilot/using-claude-sonnet-in-github-copilot")
        case .groq:
            return URL(string: "https://console.groq.com/docs/models")
        case .openAICompatible:
            return nil
        case .openRouter:
            return URL(string: "https://openrouter.ai/models")
        case .ollama:
            return URL(string: "https://ollama.ai/library")
        case .anthropic:
            return URL(string: "https://docs.anthropic.com/en/docs/about-claude/models")
        case .gemini:
            return URL(string: "https://ai.google.dev/gemini-api/docs/models/gemini")
        case .appleFoundationModel:
            return nil
        }
    }
    
    /// Short label for the model documentation link
    public var modelDocsLinkLabel: String {
        switch self {
        case .openAI:
            return "OpenAI Models"
        case .githubCopilot:
            return "Copilot Models"
        case .groq:
            return "Groq Models"
        case .openAICompatible:
            return "provider docs"
        case .openRouter:
            return "OpenRouter Models"
        case .ollama:
            return "Ollama Library"
        case .anthropic:
            return "Claude Models"
        case .gemini:
            return "Gemini Models"
        case .appleFoundationModel:
            return ""
        }
    }
    
    public var logoImageName: String {
        switch self {
        case .openAI: return "ChatGPT"
        case .githubCopilot: return "GitHubCopilot"
        case .groq: return "Groq"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        case .openAICompatible: return "server.rack"
        case .appleFoundationModel: return "apple.logo"
        }
    }

    public var usesSystemImage: Bool {
        switch self {
        case .openAICompatible, .appleFoundationModel: return true
        default: return false
        }
    }
    
    /// Recommended models for this provider
    public var recommendedModels: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo", "o1-preview", "o1-mini"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-haiku-20240307", "claude-3-opus-20240229", "claude-3-5-haiku-20241022"]
        case .gemini:
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-1.0-pro", "gemini-2.0-flash-exp"]
        case .groq:
            return ["llama-3.1-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768", "llama3-groq-70b-8192-tool-use-preview"]
        case .openRouter:
            return ["anthropic/claude-3.5-sonnet", "openai/gpt-4o", "google/gemini-pro-1.5", "meta-llama/llama-3.1-70b-instruct"]
        case .ollama:
            return ["llama3", "mistral", "codellama", "phi3", "gemma2", "qwen2"]
        case .githubCopilot:
            return ["gpt-4o", "gpt-4", "gpt-3.5-turbo", "claude-3.5-sonnet"]
        case .openAICompatible:
            return ["gpt-4", "gpt-3.5-turbo"]
        case .appleFoundationModel:
            return ["default"]
        }
    }
}


public struct AIConfig: Codable, Sendable, Equatable {
    public var provider: AIProvider
    public var apiURL: String?
    public var apiKey: String?
    public var model: String
    public var temperature: Double
    
    // Advanced Settings
    public var requestTimeout: TimeInterval
    public var resourceTimeout: TimeInterval
    public var systemPromptOverride: String?
    public var maxTokens: Int?
    public var enableStreaming: Bool
    /// Whether the current provider requires an API key. 
    /// NOTE: For .appleFoundationModel and .ollama (usually), this should be false.
    public var requiresAPIKey: Bool
    public var enableReasoning: Bool  // Ask AI to explain organization decisions
    
    // Deep Scanning & Duplicate Detection
    public var enableDeepScan: Bool   // Analyze file content (PDF text, EXIF, etc.)
    public var detectDuplicates: Bool // Find duplicate files by hash
    public var enableFileTagging: Bool // Apply Finder tags to files
    public var showStatsForNerds: Bool // Show detailed stats about generation
    public var storeDuplicateMetadata: Bool // Save original metadata for duplicates (opt-in)
    public var strictExclusions: Bool // Higher-level screening for exclusions
    
    // Organization limits (user-configurable)
    public var maxTopLevelFolders: Int // Maximum number of top-level folders AI can create (3-20)
    
    // Experimental Features
    public var enableParallelGeneration: Bool // Enable multi-model comparison (experimental)

    public init(
        provider: AIProvider = .openAICompatible,
        apiURL: String? = nil,
        apiKey: String? = nil,
        model: String = "gpt-4",
        temperature: Double = 0.7,
        requestTimeout: TimeInterval = 120,
        resourceTimeout: TimeInterval = 600,
        systemPromptOverride: String? = nil,
        maxTokens: Int? = nil,
        enableStreaming: Bool = true,
        requiresAPIKey: Bool = true,
        enableReasoning: Bool = false,
        enableDeepScan: Bool = false,
        detectDuplicates: Bool = false,
        enableFileTagging: Bool = true,
        showStatsForNerds: Bool = false,
        storeDuplicateMetadata: Bool = true,
        strictExclusions: Bool = true,
        maxTopLevelFolders: Int = 10,
        enableParallelGeneration: Bool = false
    ) {
        self.provider = provider
        self.apiURL = apiURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.requestTimeout = requestTimeout
        self.resourceTimeout = resourceTimeout
        self.systemPromptOverride = systemPromptOverride
        self.maxTokens = maxTokens
        self.enableStreaming = enableStreaming
        self.requiresAPIKey = requiresAPIKey
        self.enableReasoning = enableReasoning
        self.enableDeepScan = enableDeepScan
        self.detectDuplicates = detectDuplicates
        self.enableFileTagging = enableFileTagging
        self.showStatsForNerds = showStatsForNerds
        self.storeDuplicateMetadata = storeDuplicateMetadata
        self.strictExclusions = strictExclusions
        self.maxTopLevelFolders = maxTopLevelFolders
        self.enableParallelGeneration = enableParallelGeneration
    }
    
    public static let `default` = AIConfig(
        provider: .openAICompatible,
        apiURL: "https://api.openai.com",
        model: "gpt-4",
        temperature: 0.7,
        requestTimeout: 120,
        resourceTimeout: 600,
        systemPromptOverride: nil,
        maxTokens: nil,
        enableStreaming: true,
        requiresAPIKey: true,
        enableReasoning: false,
        enableDeepScan: false,
        detectDuplicates: false,
        enableFileTagging: true,
        showStatsForNerds: false,
        storeDuplicateMetadata: true,
        strictExclusions: true,
        maxTopLevelFolders: 10,
        enableParallelGeneration: false
    )
}



