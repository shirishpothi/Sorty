//
//  LearningsManagerTests.swift
//  SortyTests
//
//  Comprehensive tests for The Learnings feature
//

import XCTest
@testable import SortyLib

@MainActor
final class LearningsManagerTests: XCTestCase {
    
    var manager: LearningsManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = LearningsManager()
        // Reset to empty profile for tests
        manager.currentProfile = LearningsProfile()
        // Grant consent for tests
        await manager.grantConsent()
    }
    
    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }

    // MARK: - Labeled Example Tests
    
    func testAddLabeledExample() {
        manager.addLabeledExample(
            srcPath: "/Downloads/IMG_001.jpg",
            dstPath: "/Photos/2024/IMG_001.jpg",
            action: .accept
        )
        
        XCTAssertEqual(manager.currentProfile?.positiveExamples.count, 1)
        XCTAssertEqual(manager.currentProfile?.positiveExamples.first?.srcPath, "/Downloads/IMG_001.jpg")
        XCTAssertEqual(manager.currentProfile?.positiveExamples.first?.action, .accept)
    }
    
    func testAcceptMapping() {
        let mapping = ProposedMapping(
            srcPath: "/test/file.txt",
            proposedDstPath: "/organized/file.txt",
            confidence: 0.9,
            explanation: "Test"
        )
        
        manager.acceptMapping(mapping)
        
        // Should go to positiveExamples
        XCTAssertEqual(manager.currentProfile?.positiveExamples.count, 1)
        XCTAssertEqual(manager.currentProfile?.positiveExamples.first?.action, .accept)
    }
    
    func testRejectMapping() {
        let mapping = ProposedMapping(
            srcPath: "/test/file.txt",
            proposedDstPath: "/organized/file.txt",
            confidence: 0.3,
            explanation: "Test"
        )
        
        manager.rejectMapping(mapping)
        
        // Should go to rejections
        XCTAssertEqual(manager.currentProfile?.rejections.count, 1)
        XCTAssertEqual(manager.currentProfile?.rejections.first?.action, .reject)
        // Should keep in place (srcPath as dstPath)
        XCTAssertEqual(manager.currentProfile?.rejections.first?.dstPath, "/test/file.txt")
    }
    
    func testEditMapping() {
        let mapping = ProposedMapping(
            srcPath: "/test/file.txt",
            proposedDstPath: "/organized/file.txt",
            confidence: 0.7,
            explanation: "Test"
        )
        
        manager.editMapping(mapping, newDstPath: "/custom/location/file.txt")
        
        // Should go to corrections
        XCTAssertEqual(manager.currentProfile?.corrections.count, 1)
        XCTAssertEqual(manager.currentProfile?.corrections.first?.action, .edit)
        XCTAssertEqual(manager.currentProfile?.corrections.first?.dstPath, "/custom/location/file.txt")
    }
    
    // MARK: - Analysis Tests
    
    func testAnalyzeWithNoInputs() async {
        // Should error if no inputs
        await manager.analyze(rootPaths: [], examplePaths: [])
        
        // Analyzer throws emptyRootPaths, so manager.error should be set
        XCTAssertNotNil(manager.error)
        XCTAssertEqual(manager.error, "Analysis failed: No root paths provided for analysis")
    }
    // MARK: - Prompt Context Generation Tests
    
    func testGeneratePromptContext() async {
        // 1. Setup Profile
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "Sort by Date")
        ]
        profile.inferredRules = [
            InferredRule(pattern: ".*", template: "{ext}/", priority: 10, explanation: "Group by extension")
        ]
        profile.additionalInstructionsHistory = [
            UserInstruction(instruction: "No folders")
        ]
        profile.postOrganizationChanges = [
            DirectoryChange(originalPath: "/a.txt", newPath: "/b/a.txt", wasAIOrganized: true)
        ]
        
        manager.currentProfile = profile
        
        // 2. Generate Context
        let context = manager.generatePromptContext()
        
        // 3. Verify
        XCTAssertTrue(context.contains("PREFERENCES"))
        XCTAssertTrue(context.contains("Sort by Date"))
        XCTAssertTrue(context.contains("LEARNED PATTERNS"))
        XCTAssertTrue(context.contains("Group by extension"))
        XCTAssertTrue(context.contains("USER INSTRUCTIONS"))
        XCTAssertTrue(context.contains("No folders"))
        XCTAssertTrue(context.contains("RECENT CORRECTIONS"))
        XCTAssertTrue(context.contains("a.txt"))
        
        // 4. Test No Consent (Should respect privacy)
        manager.currentProfile?.consentGranted = false
        XCTAssertTrue(manager.generatePromptContext().isEmpty)
    }
    
    
    func testErrorStateClearing() async {
        manager.error = "Previous error"
        // Perform an action that clears error usually at start
        // manager.analyze clears errors, but we need valid inputs so it doesn't fail again immediately
        await manager.analyze(rootPaths: ["/tmp"], examplePaths: [])
        
        XCTAssertNil(manager.error)
    }
}

// MARK: - LearningsAnalyzer Tests

@MainActor
final class LearningsAnalyzerTests: XCTestCase {
    
    var analyzer: LearningsAnalyzer!
    
    override func setUp() async throws {
        try await super.setUp()
        analyzer = LearningsAnalyzer()
    }
    
    override func tearDown() async throws {
        analyzer = nil
        try await super.tearDown()
    }
    
    func testProposeMappingWithMatchingRule() async {
        let rule = InferredRule(
            pattern: "^IMG_\\d{8}_\\d{6}",
            template: "{year}/{filename}",
            priority: 80,
            explanation: "Photo organization"
        )
        
        let fileURL = URL(fileURLWithPath: "/Downloads/IMG_20240101_123456.jpg")
        
        let mapping = await analyzer.proposeMapping(
            for: fileURL,
            using: [rule],
            rootPath: "/Photos"
        )
        
        XCTAssertEqual(mapping.srcPath, "/Downloads/IMG_20240101_123456.jpg")
        XCTAssertTrue(mapping.proposedDstPath.contains("/Photos/"))
        XCTAssertGreaterThan(mapping.confidence, 0.5)
        XCTAssertNotNil(mapping.ruleId)
    }
    
    func testProposeMappingWithNoMatchingRule() async {
        let fileURL = URL(fileURLWithPath: "/Downloads/random_file.txt")
        
        let mapping = await analyzer.proposeMapping(
            for: fileURL,
            using: [],
            rootPath: "/Documents"
        )
        
        XCTAssertEqual(mapping.srcPath, "/Downloads/random_file.txt")
        XCTAssertTrue(mapping.proposedDstPath.contains("/Documents/"))
        XCTAssertLessThan(mapping.confidence, 0.5) // Low confidence fallback
        XCTAssertNil(mapping.ruleId)
    }
    
    func testProposeMappingWithMultipleRules() async {
        let rule1 = InferredRule(
            pattern: "^IMG_.*",
            template: "{category}/{filename}",
            priority: 50,
            explanation: "Basic photo rule"
        )
        
        let rule2 = InferredRule(
            pattern: "^IMG_\\d{8}.*",
            template: "{year}/{date}/{filename}",
            priority: 90,
            explanation: "Advanced photo rule"
        )
        
        let fileURL = URL(fileURLWithPath: "/Downloads/IMG_20240101_120000.jpg")
        
        let mapping = await analyzer.proposeMapping(
            for: fileURL,
            using: [rule1, rule2],
            rootPath: "/Photos"
        )
        
        // Should use higher priority rule
        XCTAssertEqual(mapping.ruleId, rule2.id)
        XCTAssertFalse(mapping.alternatives.isEmpty)
    }
}

// MARK: - LearningsProfile Tests

final class LearningsProfileTests: XCTestCase {
    
    func testProfileCreation() {
        let profile = LearningsProfile(
            createdAt: Date(),
            honingAnswers: [],
            inferredRules: [],
            corrections: [],
            rejections: [],
            positiveExamples: []
        )
        
        XCTAssertTrue(profile.corrections.isEmpty)
        XCTAssertTrue(profile.inferredRules.isEmpty)
        XCTAssertTrue(profile.honingAnswers.isEmpty)
    }
    
    func testAddExample() {
        var profile = LearningsProfile()
        
        let example = LabeledExample(
            srcPath: "/src/file.txt",
            dstPath: "/dst/file.txt",
            action: .accept
        )
        
        profile.positiveExamples.append(example)
        
        XCTAssertEqual(profile.positiveExamples.count, 1)
    }
}

// MARK: - PatternMatcher Additional Tests

final class PatternMatcherAdvancedTests: XCTestCase {
    
    func testBuildPatternFromMultipleFilenames() {
        let filenames = [
            "IMG_20240101_120000.jpg",
            "IMG_20240102_130000.jpg",
            "IMG_20240103_140000.jpg"
        ]
        
        let pattern = PatternMatcher.buildPattern(from: filenames)
        
        XCTAssertNotNil(pattern)
        // Should detect IMG pattern
        XCTAssertTrue(pattern!.contains("IMG"))
    }
    
    func testBuildPatternWithCommonPrefix() {
        let filenames = [
            "report_2024_01.pdf",
            "report_2024_02.pdf",
            "report_2024_03.pdf"
        ]
        
        let pattern = PatternMatcher.buildPattern(from: filenames)
        
        XCTAssertNotNil(pattern)
        XCTAssertTrue(pattern!.contains("report"))
    }
    
    func testBuildPatternWithNoCommonality() {
        let filenames = [
            "random1.txt",
            "another_file.doc",
            "something_else.pdf"
        ]
        
        let pattern = PatternMatcher.buildPattern(from: filenames)
        
        XCTAssertTrue(pattern == nil || !pattern!.isEmpty)
    }
    
    func testBuildTemplateFromExamples() {
        let examples = [
            (src: "/Downloads/IMG_001.jpg", dst: "/Photos/2024/IMG_001.jpg"),
            (src: "/Downloads/IMG_002.jpg", dst: "/Photos/2024/IMG_002.jpg")
        ]
        
        let template = PatternMatcher.buildTemplate(from: examples)
        
        XCTAssertNotNil(template)
        XCTAssertTrue(template!.contains("{filename}"))
    }
}

// MARK: - FolderStructureAnalysis Tests

final class FolderStructureAnalysisTests: XCTestCase {
    
    func testAnalysisInitialState() {
        let analysis = FolderStructureAnalysis()
        
        XCTAssertFalse(analysis.usesYearFolders)
        XCTAssertFalse(analysis.usesMonthFolders)
        XCTAssertFalse(analysis.usesDateFolders)
        XCTAssertFalse(analysis.usesCategoryFolders)
        XCTAssertNil(analysis.primaryGroupingKey)
    }
}

// MARK: - Confidence and Conflict Tests

final class LearningsConfidenceTests: XCTestCase {
    
    func testConfidenceSummaryCalculation() {
        let summary = ConfidenceSummary(high: 10, medium: 5, low: 2)
        
        XCTAssertEqual(summary.total, 17)
        XCTAssertEqual(summary.high, 10)
        XCTAssertEqual(summary.medium, 5)
        XCTAssertEqual(summary.low, 2)
    }
    
    func testConfidenceLevelColors() {
        XCTAssertEqual(ConfidenceLevel.high.color, "green")
        XCTAssertEqual(ConfidenceLevel.medium.color, "orange")
        XCTAssertEqual(ConfidenceLevel.low.color, "red")
    }
    
    func testMappingConflictCreation() {
        let conflict = MappingConflict(
            srcPaths: ["/path1/file.txt", "/path2/file.txt"],
            proposedDstPath: "/dest/file.txt",
            suggestedResolution: .autoSuffix
        )
        
        XCTAssertEqual(conflict.srcPaths.count, 2)
        XCTAssertEqual(conflict.suggestedResolution, .autoSuffix)
    }
    
    func testAlternativeMappingCreation() {
        let alt = AlternativeMapping(
            proposedDstPath: "/alternative/path.txt",
            confidence: 0.6,
            explanation: "Alternative organization"
        )
        
        XCTAssertEqual(alt.confidence, 0.6)
        XCTAssertFalse(alt.explanation.isEmpty)
    }
}