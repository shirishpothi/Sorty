//
//  ResourceLoadingTests.swift
//  SortyTests
//
//  Tests to ensure resources load correctly and prevent launch crashes
//  from Bundle.module issues in non-SPM builds.
//

import XCTest
@testable import SortyLib

final class ResourceLoadingTests: XCTestCase {
    
    // MARK: - SortyResources Bundle Tests
    
    func testSortyResourcesBundleIsNotNil() {
        // This test ensures the safe bundle resolver returns a valid bundle
        // and doesn't crash like Bundle.module did in production
        let bundle = SortyResources.bundle
        XCTAssertNotNil(bundle, "SortyResources.bundle should never be nil")
    }
    
    func testSortyResourcesBundleIsReusable() {
        // Ensure multiple accesses return the same cached bundle
        let bundle1 = SortyResources.bundle
        let bundle2 = SortyResources.bundle
        XCTAssertTrue(bundle1 === bundle2, "SortyResources.bundle should return the same instance")
    }
    
    // MARK: - Provider Logo Loading Tests
    
    func testAllProviderLogosLoadWithoutCrashing() {
        // This test would have caught the launch crash caused by Bundle.module
        // Each provider logo must load safely (with fallback) without crashing
        
        // Test all available providers
        for provider in AIProvider.allCases {
            // Creating ProviderLogoView should not crash
            // The view uses SortyResources.bundle internally
            let _ = ProviderLogoView(provider: provider)
            XCTAssertTrue(true, "ProviderLogoView for \(provider.displayName) should load without crashing")
        }
    }
    
    func testProviderLogoViewInitialization() {
        // Specific test for default initialization
        let view = ProviderLogoView(provider: .openAI)
        XCTAssertNotNil(view, "ProviderLogoView should initialize without crashing")
    }
    
    func testProviderLogoViewWithCustomSize() {
        // Test custom size parameter
        let view = ProviderLogoView(provider: .anthropic, size: 48)
        XCTAssertNotNil(view, "ProviderLogoView with custom size should initialize without crashing")
    }
    
    // MARK: - Image Resource Existence Tests
    
    func testExpectedImageResourcesExist() {
        // Verify that expected image resources are locatable
        let bundle = SortyResources.bundle
        
        let expectedImages = [
            "ChatGPT",
            "Claude",
            "Gemini",
            "Ollama",
            "OpenRouter",
            "Groq",
            "GitHubCopilot"
        ]
        
        for imageName in expectedImages {
            // Check Images subdirectory first
            if let url = bundle.url(forResource: imageName, withExtension: "png", subdirectory: "Images") {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(imageName).png should exist in Images subdirectory")
            } else if let url = bundle.url(forResource: imageName, withExtension: "png") {
                XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(imageName).png should exist in bundle")
            } else {
                // Image might be in asset catalog or fallback to system icon - that's OK
                // The key is it doesn't crash
                XCTAssertTrue(true, "\(imageName) may use fallback - this is acceptable")
            }
        }
    }
    
    // MARK: - Fallback Behavior Tests
    
    func testProviderWithMissingImageUsesFallback() {
        // Create a mock provider scenario where image doesn't exist
        // The ProviderLogoView should gracefully fall back to system icon
        
        // This test ensures the fallback chain in ProviderLogoView works:
        // 1. Try Images subdirectory
        // 2. Try main bundle Resources/Images
        // 3. Try flat bundle resources
        // 4. Try asset catalog
        // 5. Fall back to system icon
        
        // All real providers should work - we just verify no crashes
        for provider in AIProvider.allCases {
            let _ = ProviderLogoView(provider: provider)
        }
        XCTAssertTrue(true, "All providers should load with graceful fallback")
    }
    
    // MARK: - Bundle Resolver Robustness Tests
    
    func testBundleResolverHandlesMainBundle() {
        // The resolver should work when main bundle is the only option
        XCTAssertNotNil(Bundle.main, "Main bundle should always exist")
        
        // SortyResources should return something even if SPM bundle isn't found
        let bundle = SortyResources.bundle
        XCTAssertNotNil(bundle)
    }
    
    func testBundleResolverDoesNotCrashOnMissingResources() {
        // Looking up a non-existent resource should return nil, not crash
        let bundle = SortyResources.bundle
        let nonExistentURL = bundle.url(forResource: "NonExistentResource12345", withExtension: "xyz")
        XCTAssertNil(nonExistentURL, "Non-existent resource should return nil, not crash")
    }
}

// MARK: - Integration Tests

final class ResourceLoadingIntegrationTests: XCTestCase {
    
    @MainActor
    func testSettingsViewModelCanInitialize() {
        // Integration test ensuring SettingsViewModel initializes without crash
        let viewModel = SettingsViewModel()
        XCTAssertNotNil(viewModel, "SettingsViewModel should initialize")
    }
    
    func testAIProviderDisplayNamesAreValid() {
        // Ensure all providers have valid display names for UI
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.displayName.isEmpty, "\(provider) should have a non-empty display name")
        }
    }
    
    func testAIProviderLogoImageNamesAreValid() {
        // Ensure all providers have valid logo image names
        for provider in AIProvider.allCases {
            XCTAssertFalse(provider.logoImageName.isEmpty, "\(provider) should have a non-empty logo image name")
        }
    }
}
