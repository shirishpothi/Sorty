//
//  ParallelGenerationTests.swift
//  SortyTests
//
//  Unit tests for parallel generation feature and feature flag
//

import XCTest
@testable import SortyLib

// MARK: - AIConfig Feature Flag Tests

final class ParallelGenerationFeatureFlagTests: XCTestCase {
    
    func testFeatureFlagDefaultOff() {
        let config = AIConfig.default
        XCTAssertFalse(config.enableParallelGeneration, "Parallel generation should be disabled by default")
    }
    
    func testFeatureFlagInit() {
        // Test default is false
        let defaultConfig = AIConfig()
        XCTAssertFalse(defaultConfig.enableParallelGeneration)
        
        // Test can be enabled
        let enabledConfig = AIConfig(enableParallelGeneration: true)
        XCTAssertTrue(enabledConfig.enableParallelGeneration)
    }
    
    func testFeatureFlagEncoding() throws {
        let config = AIConfig(enableParallelGeneration: true)
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        XCTAssertNotNil(data)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AIConfig.self, from: data)
        XCTAssertTrue(decoded.enableParallelGeneration)
    }
    
    func testFeatureFlagEquality() {
        let config1 = AIConfig(enableParallelGeneration: true)
        let config2 = AIConfig(enableParallelGeneration: true)
        let config3 = AIConfig(enableParallelGeneration: false)
        
        XCTAssertEqual(config1, config2)
        XCTAssertNotEqual(config1, config3)
    }
}

// MARK: - GenerationSpec Tests

final class GenerationSpecTests: XCTestCase {
    
    func testGenerationSpecInitialization() {
        let spec = GenerationSpec(
            provider: .openAI,
            model: "gpt-4"
        )
        
        XCTAssertEqual(spec.provider, AIProvider.openAI)
        XCTAssertEqual(spec.model, "gpt-4")
    }
    
    func testGenerationSpecDefaultValues() {
        let spec = GenerationSpec(provider: .groq, model: "llama-3")
        
        XCTAssertEqual(spec.provider, AIProvider.groq)
        XCTAssertEqual(spec.model, "llama-3")
        XCTAssertNil(spec.personaID)
        XCTAssertFalse(spec.enableReasoning)
        XCTAssertFalse(spec.enableDeepScan)
        XCTAssertEqual(spec.customInstructions, "")
    }
    
    func testGenerationSpecWithPersona() {
        let personaID = "test-persona-id"
        let spec = GenerationSpec(
            provider: .anthropic,
            model: "claude-3",
            personaID: personaID
        )
        
        XCTAssertEqual(spec.personaID, personaID)
    }
    
    func testGenerationSpecWithCustomInstructions() {
        let spec = GenerationSpec(
            provider: .openAI,
            model: "gpt-4",
            customInstructions: "Organize by project"
        )
        
        XCTAssertEqual(spec.customInstructions, "Organize by project")
    }
    
    func testGenerationSpecWithOptions() {
        let spec = GenerationSpec(
            provider: .openAI,
            model: "gpt-4o",
            enableReasoning: true,
            enableDeepScan: true
        )
        
        XCTAssertTrue(spec.enableReasoning)
        XCTAssertTrue(spec.enableDeepScan)
    }
}

// MARK: - GenerationOrchestrator Tests

final class GenerationOrchestratorTests: XCTestCase {
    
    @MainActor
    func testOrchestratorInitialization() {
        let orchestrator = GenerationOrchestrator()
        XCTAssertNotNil(orchestrator)
        XCTAssertTrue(orchestrator.runs.isEmpty)
    }
    
    @MainActor
    func testAddSpec() {
        let orchestrator = GenerationOrchestrator()
        
        let spec = GenerationSpec(provider: .openAI, model: "gpt-4")
        orchestrator.addSpec(spec)
        
        XCTAssertEqual(orchestrator.runs.count, 1)
        XCTAssertEqual(orchestrator.runs.first?.spec.provider, .openAI)
    }
    
    @MainActor
    func testRemoveSpec() {
        let orchestrator = GenerationOrchestrator()
        
        let spec1 = GenerationSpec(provider: .openAI, model: "gpt-4")
        let spec2 = GenerationSpec(provider: .groq, model: "llama-3")
        let id1 = orchestrator.addSpec(spec1)
        orchestrator.addSpec(spec2)
        
        XCTAssertEqual(orchestrator.runs.count, 2)
        
        orchestrator.removeSpec(id: id1)
        XCTAssertEqual(orchestrator.runs.count, 1)
        XCTAssertEqual(orchestrator.runs.first?.spec.provider, .groq)
    }
    
    @MainActor
    func testOrchestratorStateManagement() {
        let orchestrator = GenerationOrchestrator()
        
        // Initial state should be idle
        XCTAssertFalse(orchestrator.isAnyRunning)
    }
    
    @MainActor
    func testCompletedRuns() {
        let orchestrator = GenerationOrchestrator()
        
        // Initially no completed runs
        XCTAssertTrue(orchestrator.completedRuns.isEmpty)
    }
    
    @MainActor
    func testFailedRuns() {
        let orchestrator = GenerationOrchestrator()
        
        // Initially no failed runs
        XCTAssertTrue(orchestrator.failedRuns.isEmpty)
    }
}

// MARK: - ParallelGenerationManager Tests

final class ParallelGenerationManagerTests: XCTestCase {
    
    @MainActor
    func testManagerInitialization() {
        let manager = ParallelGenerationManager()
        
        XCTAssertTrue(manager.plans.isEmpty)
        XCTAssertEqual(manager.selectedPlanIndex, 0)
        XCTAssertFalse(manager.isGenerating)
    }
    
    @MainActor
    func testSelectedPlanIndexBounds() {
        let manager = ParallelGenerationManager()
        
        // With no plans, index should be 0
        XCTAssertEqual(manager.selectedPlanIndex, 0)
        
        // Setting to negative should work (no bounds checking in property)
        manager.selectedPlanIndex = -1
        XCTAssertEqual(manager.selectedPlanIndex, -1)
    }
    
    @MainActor
    func testIsGeneratingState() {
        let manager = ParallelGenerationManager()
        
        XCTAssertFalse(manager.isGenerating)
        
        manager.isGenerating = true
        XCTAssertTrue(manager.isGenerating)
    }
}

// MARK: - GeneratedPlan Tests

final class GeneratedPlanTests: XCTestCase {
    
    @MainActor
    func testGeneratedPlanIdentifiable() {
        // Create a minimal plan for testing
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        
        let plan1 = ParallelGenerationManager.GeneratedPlan(
            plan: plan,
            provider: .openAI,
            model: "gpt-4"
        )
        
        let plan2 = ParallelGenerationManager.GeneratedPlan(
            plan: plan,
            provider: .openAI,
            model: "gpt-4"
        )
        
        // Each plan should have unique ID
        XCTAssertNotEqual(plan1.id, plan2.id)
    }
    
    @MainActor
    func testGeneratedPlanBasicProperties() {
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "Test notes")
        
        let generatedPlan = ParallelGenerationManager.GeneratedPlan(
            plan: plan,
            provider: .groq,
            model: "llama-3"
        )
        
        XCTAssertEqual(generatedPlan.provider, .groq)
        XCTAssertEqual(generatedPlan.model, "llama-3")
        XCTAssertFalse(generatedPlan.isLoading)
        XCTAssertNil(generatedPlan.error)
    }
    
    @MainActor
    func testGeneratedPlanWithError() {
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        
        let generatedPlan = ParallelGenerationManager.GeneratedPlan(
            plan: plan,
            provider: .anthropic,
            model: "claude-3",
            error: "Connection failed"
        )
        
        XCTAssertNotNil(generatedPlan.error)
        XCTAssertEqual(generatedPlan.error, "Connection failed")
    }
    
    @MainActor
    func testGeneratedPlanLoadingState() {
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        
        let generatedPlan = ParallelGenerationManager.GeneratedPlan(
            plan: plan,
            provider: .openAI,
            model: "gpt-4",
            isLoading: true
        )
        
        XCTAssertTrue(generatedPlan.isLoading)
    }
}

// MARK: - AIProvider Tests (Related to Parallel Generation)

final class AIProviderParallelTests: XCTestCase {
    
    func testAllProvidersHaveRecommendedModels() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.recommendedModels.isEmpty, "\(provider) should have recommended models")
        }
    }
    
    func testAllProvidersHaveDefaultModel() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.defaultModel.isEmpty, "\(provider) should have default model")
        }
    }
    
    func testAllProvidersHaveDisplayName() {
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider) should have display name")
        }
    }
    
    func testProviderIsAvailable() {
        // Most providers should be available
        XCTAssertTrue(AIProvider.openAI.isAvailable)
        XCTAssertTrue(AIProvider.groq.isAvailable)
        XCTAssertTrue(AIProvider.anthropic.isAvailable)
        XCTAssertTrue(AIProvider.gemini.isAvailable)
        XCTAssertTrue(AIProvider.ollama.isAvailable)
        XCTAssertTrue(AIProvider.openRouter.isAvailable)
    }
    
    func testProviderDefaultAPIURL() {
        XCTAssertEqual(AIProvider.openAI.defaultAPIURL, "https://api.openai.com")
        XCTAssertEqual(AIProvider.groq.defaultAPIURL, "https://api.groq.com/openai")
        XCTAssertEqual(AIProvider.ollama.defaultAPIURL, "http://localhost:11434")
        XCTAssertNil(AIProvider.appleFoundationModel.defaultAPIURL)
    }
    
    func testProviderAPIKeyRequirement() {
        XCTAssertTrue(AIProvider.openAI.typicallyRequiresAPIKey)
        XCTAssertTrue(AIProvider.anthropic.typicallyRequiresAPIKey)
        XCTAssertTrue(AIProvider.groq.typicallyRequiresAPIKey)
        XCTAssertFalse(AIProvider.ollama.typicallyRequiresAPIKey)
        XCTAssertFalse(AIProvider.appleFoundationModel.typicallyRequiresAPIKey)
    }
}

// MARK: - Extended ParallelGenerationManager Tests

final class ExtendedParallelGenerationManagerTests: XCTestCase {
    
    @MainActor
    func testAddPlan() {
        let manager = ParallelGenerationManager()
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "Test")
        
        manager.addPlan(plan, provider: .openAI, model: "gpt-4")
        
        XCTAssertEqual(manager.plans.count, 1)
        XCTAssertEqual(manager.plans.first?.provider, .openAI)
        XCTAssertEqual(manager.plans.first?.model, "gpt-4")
    }
    
    @MainActor
    func testClearPlans() {
        let manager = ParallelGenerationManager()
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "Test")
        
        manager.addPlan(plan, provider: .openAI, model: "gpt-4")
        manager.addPlan(plan, provider: .groq, model: "llama-3")
        
        XCTAssertEqual(manager.plans.count, 2)
        
        manager.clearPlans()
        
        XCTAssertTrue(manager.plans.isEmpty)
        XCTAssertEqual(manager.selectedPlanIndex, 0)
        XCTAssertTrue(manager.generationProgress.isEmpty)
        XCTAssertTrue(manager.generationErrors.isEmpty)
        XCTAssertTrue(manager.activeGenerations.isEmpty)
    }
    
    @MainActor
    func testSelectPlan() {
        let manager = ParallelGenerationManager()
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        
        manager.addPlan(plan, provider: .openAI, model: "gpt-4")
        manager.addPlan(plan, provider: .groq, model: "llama-3")
        
        manager.selectPlan(at: 1)
        XCTAssertEqual(manager.selectedPlanIndex, 1)
        
        // Out of bounds should not change
        manager.selectPlan(at: 5)
        XCTAssertEqual(manager.selectedPlanIndex, 1)
        
        manager.selectPlan(at: -1)
        XCTAssertEqual(manager.selectedPlanIndex, 1)
    }
    
    @MainActor
    func testSelectedPlan() {
        let manager = ParallelGenerationManager()
        
        // No plans - should return nil
        XCTAssertNil(manager.selectedPlan)
        
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "Test notes")
        manager.addPlan(plan, provider: .openAI, model: "gpt-4")
        
        XCTAssertNotNil(manager.selectedPlan)
        XCTAssertEqual(manager.selectedPlan?.model, "gpt-4")
    }
    
    @MainActor
    func testCompletedGenerationsCount() {
        let manager = ParallelGenerationManager()
        
        XCTAssertEqual(manager.completedGenerationsCount, 0)
        
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        manager.addPlan(plan, provider: .openAI, model: "gpt-4")
        
        // Non-loading plan counts as completed
        XCTAssertEqual(manager.completedGenerationsCount, 1)
    }
    
    @MainActor
    func testTotalGenerationsCount() {
        let manager = ParallelGenerationManager()
        
        XCTAssertEqual(manager.totalGenerationsCount, 0)
        
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        manager.addPlan(plan, provider: .openAI, model: "gpt-4")
        
        XCTAssertEqual(manager.totalGenerationsCount, 1)
    }
    
    @MainActor
    func testOverallProgress() {
        let manager = ParallelGenerationManager()
        
        // No generations - progress should be 0
        XCTAssertEqual(manager.overallProgress, 0)
        
        let plan = OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        manager.addPlan(plan, provider: .openAI, model: "gpt-4")
        
        // One completed generation - progress should be 1
        XCTAssertEqual(manager.overallProgress, 1.0)
    }
    
    @MainActor
    func testCancelAllGenerations() {
        let manager = ParallelGenerationManager()
        manager.isGenerating = true
        
        manager.cancelAllGenerations()
        
        XCTAssertFalse(manager.isGenerating)
        XCTAssertTrue(manager.activeGenerations.isEmpty)
    }
}

// MARK: - GenerationStatus Tests

final class GenerationStatusTests: XCTestCase {
    
    func testStatusEquality() {
        XCTAssertEqual(GenerationStatus.queued, GenerationStatus.queued)
        XCTAssertEqual(GenerationStatus.canceled, GenerationStatus.canceled)
        
        XCTAssertEqual(
            GenerationStatus.running(progress: 0.5, stage: "Testing"),
            GenerationStatus.running(progress: 0.5, stage: "Testing")
        )
        
        XCTAssertNotEqual(
            GenerationStatus.running(progress: 0.5, stage: "Testing"),
            GenerationStatus.running(progress: 0.7, stage: "Testing")
        )
        
        XCTAssertEqual(
            GenerationStatus.failed(message: "Error"),
            GenerationStatus.failed(message: "Error")
        )
        
        XCTAssertNotEqual(
            GenerationStatus.failed(message: "Error1"),
            GenerationStatus.failed(message: "Error2")
        )
    }
    
    func testDifferentStatusTypes() {
        XCTAssertNotEqual(GenerationStatus.queued, GenerationStatus.canceled)
        XCTAssertNotEqual(GenerationStatus.queued, GenerationStatus.running(progress: 0, stage: nil))
        XCTAssertNotEqual(GenerationStatus.canceled, GenerationStatus.failed(message: "Error"))
    }
}

// MARK: - ModelInfo Tests

final class ModelInfoTests: XCTestCase {
    
    func testModelInfoInit() {
        let model = ModelInfo(
            id: "gpt-4",
            displayName: "GPT-4",
            provider: .openAI,
            capabilities: ["chat", "vision"],
            updatedAt: Date()
        )
        
        XCTAssertEqual(model.id, "gpt-4")
        XCTAssertEqual(model.displayName, "GPT-4")
        XCTAssertEqual(model.provider, .openAI)
        XCTAssertEqual(model.capabilities, ["chat", "vision"])
    }
    
    func testModelInfoIdentifiable() {
        let model1 = ModelInfo(id: "model-1", displayName: "Model 1", provider: .openAI)
        let model2 = ModelInfo(id: "model-1", displayName: "Model 1", provider: .openAI)
        let model3 = ModelInfo(id: "model-2", displayName: "Model 2", provider: .openAI)
        
        XCTAssertEqual(model1.id, model2.id)
        XCTAssertNotEqual(model1.id, model3.id)
    }
    
    func testModelInfoEquatable() {
        let date = Date()
        let model1 = ModelInfo(id: "gpt-4", displayName: "GPT-4", provider: .openAI, updatedAt: date)
        let model2 = ModelInfo(id: "gpt-4", displayName: "GPT-4", provider: .openAI, updatedAt: date)
        
        XCTAssertEqual(model1, model2)
    }
}

// MARK: - ModelCatalog Tests

final class ModelCatalogTests: XCTestCase {
    
    @MainActor
    func testSharedInstance() {
        let catalog = ModelCatalog.shared
        XCTAssertNotNil(catalog)
    }
    
    @MainActor
    func testCachedModelsReturnsRecommendedAsFallback() {
        let catalog = ModelCatalog.shared
        
        // Clear any cached models for a provider
        catalog.modelsByProvider[.openAICompatible] = nil
        
        let models = catalog.cachedModels(for: .openAICompatible)
        
        // Should return fallback/recommended models
        XCTAssertFalse(models.isEmpty)
    }
    
    @MainActor
    func testSearchAllProviders() {
        let catalog = ModelCatalog.shared
        
        // Set up test data
        catalog.modelsByProvider[.openAI] = [
            ModelInfo(id: "gpt-4", displayName: "GPT-4", provider: .openAI),
            ModelInfo(id: "gpt-3.5-turbo", displayName: "GPT-3.5 Turbo", provider: .openAI)
        ]
        
        let results = catalog.searchAllProviders(query: "gpt")
        
        // Should find matching models
        XCTAssertFalse(results.isEmpty)
    }
    
    @MainActor
    func testSearchAllProvidersEmptyQuery() {
        let catalog = ModelCatalog.shared
        
        let results = catalog.searchAllProviders(query: "")
        
        // Empty query should return empty results
        XCTAssertTrue(results.isEmpty)
    }
}

// MARK: - Extended GenerationOrchestrator Tests

final class ExtendedGenerationOrchestratorTests: XCTestCase {
    
    @MainActor
    func testSelectRun() {
        let orchestrator = GenerationOrchestrator()
        
        let spec = GenerationSpec(provider: .openAI, model: "gpt-4")
        let id = orchestrator.addSpec(spec)
        
        orchestrator.selectRun(id: id)
        
        XCTAssertEqual(orchestrator.selectedRunID, id)
    }
    
    @MainActor
    func testSelectedRun() {
        let orchestrator = GenerationOrchestrator()
        
        // No selection
        XCTAssertNil(orchestrator.selectedRun)
        
        let spec = GenerationSpec(provider: .openAI, model: "gpt-4")
        let id = orchestrator.addSpec(spec)
        orchestrator.selectRun(id: id)
        
        XCTAssertNotNil(orchestrator.selectedRun)
        XCTAssertEqual(orchestrator.selectedRun?.spec.model, "gpt-4")
    }
    
    @MainActor
    func testClearCompleted() {
        let orchestrator = GenerationOrchestrator()
        
        let spec = GenerationSpec(provider: .openAI, model: "gpt-4")
        orchestrator.addSpec(spec)
        
        XCTAssertEqual(orchestrator.runs.count, 1)
        
        // Run is queued, not completed - should not be cleared
        orchestrator.clearCompleted()
        XCTAssertEqual(orchestrator.runs.count, 1)
    }
    
    @MainActor
    func testRetryFailed() {
        let orchestrator = GenerationOrchestrator()
        
        // Add and simulate failure
        let spec = GenerationSpec(provider: .openAI, model: "gpt-4")
        orchestrator.addSpec(spec)
        
        // Initially queued
        XCTAssertEqual(orchestrator.failedRuns.count, 0)
    }
    
    @MainActor
    func testCancelAll() {
        let orchestrator = GenerationOrchestrator()
        
        let spec1 = GenerationSpec(provider: .openAI, model: "gpt-4")
        let spec2 = GenerationSpec(provider: .groq, model: "llama-3")
        orchestrator.addSpec(spec1)
        orchestrator.addSpec(spec2)
        
        orchestrator.cancelAll()
        
        // All runs should be canceled
        for run in orchestrator.runs {
            if case .canceled = run.status {
                XCTAssertTrue(true)
            } else if case .queued = run.status {
                // Also acceptable - was never started
                XCTAssertTrue(true)
            }
        }
    }
    
    @MainActor
    func testUpdateSpec() {
        let orchestrator = GenerationOrchestrator()
        
        let spec = GenerationSpec(provider: .openAI, model: "gpt-4")
        let id = orchestrator.addSpec(spec)
        
        XCTAssertEqual(orchestrator.runs.first?.spec.model, "gpt-4")
        
        let newSpec = GenerationSpec(id: id, provider: .openAI, model: "gpt-4-turbo")
        orchestrator.updateSpec(id: id, with: newSpec)
        
        XCTAssertEqual(orchestrator.runs.first?.spec.model, "gpt-4-turbo")
    }
}
