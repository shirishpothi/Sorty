import XCTest
@testable import SortyLib

@MainActor
final class ModelCatalogVisionSupportTests: XCTestCase {
    func testKnownVisionModelsReturnTrue() {
        XCTAssertTrue(ModelCatalog.shared.supportsVision(modelId: "gpt-4o", provider: .openAI))
        XCTAssertTrue(ModelCatalog.shared.supportsVision(modelId: "claude-sonnet-4", provider: .anthropic))
        XCTAssertTrue(ModelCatalog.shared.supportsVision(modelId: "gemini-2.5-flash", provider: .gemini))
    }

    func testKnownNonVisionModelsReturnFalse() {
        XCTAssertFalse(ModelCatalog.shared.supportsVision(modelId: "gemma-flash", provider: .openAICompatible))
        XCTAssertFalse(ModelCatalog.shared.supportsVision(modelId: "gemma-2-flash", provider: .openRouter))
    }

    func testFlashHeuristicDoesNotCreateFalsePositiveForNonGeminiProviders() {
        XCTAssertFalse(ModelCatalog.shared.supportsVision(modelId: "gemma-flash", provider: .openAI))
        XCTAssertFalse(ModelCatalog.shared.supportsVision(modelId: "my-text-flash-model", provider: .openAICompatible))
    }

    func testProviderSpecificHeuristics() {
        XCTAssertTrue(ModelCatalog.shared.supportsVision(modelId: "llava:latest", provider: .ollama))
        XCTAssertTrue(ModelCatalog.shared.supportsVision(modelId: "gpt-4o", provider: .githubCopilot))
        XCTAssertFalse(ModelCatalog.shared.supportsVision(modelId: "gpt-3.5-turbo", provider: .githubCopilot))
    }
}
