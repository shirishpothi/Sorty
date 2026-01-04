//
//  LLMRuleInducerTests.swift
//  FileOrganizerTests
//
//  Tests for LLMRuleInducer using MockAIClient
//

import XCTest
@testable import FileOrganizerLib

@MainActor
final class LLMRuleInducerTests: XCTestCase {
    
    // Mock Client
    final class MockAIClient: AIClientProtocol, @unchecked Sendable {
        var config: AIConfig = AIConfig()
        var generateTextResponse: String = ""
        var streamingDelegate: StreamingDelegate?
        
        func analyze(files: [FileItem], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan {
            fatalError("Not implemented for this test")
        }
        
        func generateText(prompt: String, systemPrompt: String?) async throws -> String {
            return generateTextResponse
        }
    }
    
    var inducer: LLMRuleInducer!
    var mockClient: MockAIClient!
    
    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockAIClient()
        inducer = LLMRuleInducer(aiClient: mockClient)
    }
    
    override func tearDown() async throws {
        inducer = nil
        mockClient = nil
        try await super.tearDown()
    }
    
    func testInduceRulesFromExamples() async {
        // Setup mock response
        let jsonResponse = """
        [
            {
                "pattern": "Invoice.*",
                "template": "Finance/{year}/Invoices/{filename}",
                "priority": 80,
                "explanation": "Organize invoices by year"
            }
        ]
        """
        mockClient.generateTextResponse = jsonResponse
        
        let examples = [
            LabeledExample(srcPath: "Invoice.pdf", dstPath: "Finance/2024/Invoices/Invoice.pdf")
        ]
        
        let rules = await inducer.induceRules(from: examples, exampleFolders: [])
        
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.pattern, "Invoice.*")
        XCTAssertEqual(rules.first?.template, "Finance/{year}/Invoices/{filename}")
        XCTAssertEqual(rules.first?.explanation, "Organize invoices by year")
    }
    
    func testInduceRulesWithMarkdownJSON() async {
        // LLM often wraps JSON in markdown blocks
        let jsonResponse = """
        Here are the rules:
        ```json
        [
            {
                "pattern": ".*\\\\.jpg$",
                "template": "Photos/{date}/{filename}",
                "priority": 50,
                "explanation": "Photos by date"
            }
        ]
        ```
        """
        mockClient.generateTextResponse = jsonResponse
        
        let examples = [
            LabeledExample(srcPath: "photo.jpg", dstPath: "Photos/2024/photo.jpg")
        ]
        
        let rules = await inducer.induceRules(from: examples, exampleFolders: [])
        
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.pattern, ".*\\.jpg$")
    }
    
    func testInduceRulesWithInvalidJSON() async {
        mockClient.generateTextResponse = "This is not JSON"
        
        let examples = [LabeledExample(srcPath: "a", dstPath: "b")]
        let rules = await inducer.induceRules(from: examples, exampleFolders: [])
        
        XCTAssertTrue(rules.isEmpty)
    }
}
