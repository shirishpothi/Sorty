
//
//  AppleFoundationModelClient.swift
//  Sorty
//
//  Apple Foundation Models Integration for macOS 26+
//  Uses on-device Apple Intelligence for file organization
//

import Foundation

// NOTE: This client uses futuristic/private APIs (FoundationModels).
#if canImport(FoundationModels) && os(macOS)
import FoundationModels

@available(macOS 26.0, *)
public final class AppleFoundationModelClient: AIClientProtocol, @unchecked Sendable {
    public let config: AIConfig
    @MainActor public weak var streamingDelegate: StreamingDelegate?
    
    public init(config: AIConfig) {
        self.config = config
    }
    
    public func analyze(files: [FileItem], customInstructions: String? = nil, personaPrompt: String? = nil, temperature: Double? = nil) async throws -> OrganizationPlan {
        let startTime = Date()
        
        // Verify availability first
        guard Self.isAvailable() else {
            throw AIClientError.apiError(statusCode: 503, message: Self.unavailabilityReason)
        }
        
        // Determine compaction level to fit context window
        let compactionLevel = PromptBuilder.selectCompactionLevel(files: files, maxTokens: 1200)
        
        var systemPrompt: String
        var userPrompt: String
        
        switch compactionLevel {
        case .standard:
            systemPrompt = config.systemPromptOverride ?? PromptBuilder.buildCompactSystemPrompt(enableReasoning: config.enableReasoning, maxTopLevelFolders: config.maxTopLevelFolders)
            userPrompt = PromptBuilder.buildCompactPrompt(files: files, enableReasoning: config.enableReasoning)
        case .ultra:
            let prompts = PromptBuilder.buildUltraCompactPrompt(files: files)
            systemPrompt = prompts.system
            userPrompt = prompts.user
        case .summary:
            let prompts = PromptBuilder.buildSummaryPrompt(files: files)
            systemPrompt = prompts.system
            userPrompt = prompts.user
        }
        
        // Incorporate custom instructions
        if let instructions = customInstructions, !instructions.isEmpty {
            userPrompt = "USER INSTRUCTIONS: \(instructions)\n\n" + userPrompt
        }
        
        // Log strategy for debugging
        DebugLogger.log("AFM Strategy: \(compactionLevel) compaction for \(files.count) files")
        
        do {
            // Create a language model session with the system instructions
            let session = LanguageModelSession(instructions: systemPrompt)
            
            // Generate response from the model
            let response = try await session.respond(to: userPrompt)
            let content = response.content
            
            // Simulate streaming for UI feedback since this API might be synchronous
            let chunkSize = 20
            var currentIndex = content.startIndex
            
            while currentIndex < content.endIndex {
                let nextIndex = content.index(currentIndex, offsetBy: chunkSize, limitedBy: content.endIndex) ?? content.endIndex
                let chunk = String(content[currentIndex..<nextIndex])
                
                await MainActor.run {
                    streamingDelegate?.didReceiveChunk(chunk)
                }
                
                // minimal delay to allow UI updates
                try? await Task.sleep(nanoseconds: 5_000_000) 
                currentIndex = nextIndex
            }
            
            await MainActor.run {
                streamingDelegate?.didComplete(content: content)
            }
            
            // Parse the response into an OrganizationPlan
            var plan = try ResponseParser.parseResponse(content, originalFiles: files)
            
            // Calculate stats
            let duration = Date().timeIntervalSince(startTime)
            let estimatedTokens = content.count / 4
            let tps = duration > 0 ? Double(estimatedTokens) / duration : 0
            
            plan.generationStats = GenerationStats(
                duration: duration,
                tps: tps,
                ttft: 0.1, // Near instant for on-device
                totalTokens: estimatedTokens,
                model: "Apple Foundation Model"
            )
            
            return plan
            
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
    
    public func checkHealth() async throws {
        // Verify availability
        guard Self.isAvailable() else {
            throw AIClientError.apiError(statusCode: 503, message: Self.unavailabilityReason)
        }
    }
    
    public func generateText(prompt: String, systemPrompt: String? = nil) async throws -> String {
        // Verify availability first
        guard Self.isAvailable() else {
            throw AIClientError.apiError(statusCode: 503, message: Self.unavailabilityReason)
        }
        
        do {
            // Create a language model session with the system instructions
            let session = LanguageModelSession(instructions: systemPrompt ?? "You are a helpful assistant.")
            
            // Generate response from the model
            let response = try await session.respond(to: prompt)
            return response.content
            
        } catch let error as LanguageModelSession.GenerationError {
            throw AIClientError.apiError(
                statusCode: 500,
                message: "Apple Intelligence generation error: \(error.localizedDescription)"
            )
        } catch {
            throw error
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
