
//
//  AppleFoundationModelClient.swift
//  FileOrganizer
//
//  Apple Foundation Models Integration for macOS 26+
//  Uses on-device Apple Intelligence for file organization
//

import Foundation

// NOTE: This client uses futuristic/private APIs (FoundationModels).
#if canImport(FoundationModels) && os(macOS)
import FoundationModels

@available(macOS 26.0, *)
final class AppleFoundationModelClient: AIClientProtocol, @unchecked Sendable {
    let config: AIConfig
    
    init(config: AIConfig) {
        self.config = config
    }
    
    func analyze(files: [FileItem], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        // Verify availability first
        guard Self.isAvailable() else {
            throw AIClientError.apiError(statusCode: 503, message: Self.unavailabilityReason)
        }
        
        // Use compact prompts for Apple Intelligence
        let systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildCompactSystemPrompt(enableReasoning: config.enableReasoning)
        
        // Incorporate custom instructions
        var userPrompt = PromptBuilder.buildCompactPrompt(files: files, enableReasoning: config.enableReasoning)
        if let instructions = customInstructions, !instructions.isEmpty {
            userPrompt = "USER INSTRUCTIONS: \(instructions)\n\n" + userPrompt
        }
        
        do {
            // Create a language model session with the system instructions
            let session = LanguageModelSession(instructions: systemPrompt)
            
            // Generate response from the model
            let response = try await session.respond(to: userPrompt)
            let content = response.content
            
            // Parse the response into an OrganizationPlan
            return try ResponseParser.parseResponse(content, originalFiles: files)
            
        } catch let error as LanguageModelSession.GenerationError {
            throw AIClientError.apiError(
                statusCode: 500,
                message: "Apple Intelligence generation error: \(error.localizedDescription)"
            )
        } catch let error as AIClientError {
            throw error
        } catch {
            throw AIClientError.networkError(error)
        }
    }
    
    /// Check if Apple Intelligence is available on this device
    static func isAvailable() -> Bool {
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            return true
        }
        return false
    }
    
    /// Get a user-friendly explanation of why Apple Intelligence is unavailable
    static var unavailabilityReason: String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return "Apple Intelligence is available."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device is not eligible for Apple Intelligence. Requires Apple Silicon Mac with macOS 26 or later."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is not enabled. Enable it in System Settings > Apple Intelligence & Siri."
            case .modelNotReady:
                return "Apple Intelligence model is not ready. It may still be downloading. Please wait and try again."
            @unknown default:
                return "Apple Intelligence is unavailable for an unknown reason."
            }
        }
    }
}

#if canImport(FoundationModels) && os(macOS)
@available(macOS 26.0, *)
extension AIClientError {
    static var appleIntelligenceUnavailable: AIClientError {
        return AIClientError.apiError(
            statusCode: 503,
            message: AppleFoundationModelClient.unavailabilityReason
        )
    }
}
#endif
#endif
