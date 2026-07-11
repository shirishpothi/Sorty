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
        UserDefaults.standard.removeObject(forKey: "learningsModelDirectories")
        UserDefaults.standard.removeObject(forKey: "learningsModelSelection")
        manager = LearningsManager()
        // Reset to empty profile for tests
        manager.currentProfile = LearningsProfile()
        // Clear any persisted model directories from prior runs
        manager.modelDirectories = []
        // Grant consent for tests
        await manager.grantConsent()
    }
    
    override func tearDown() async throws {
        // Clean up persisted model directories
        manager.modelDirectories = []
        UserDefaults.standard.removeObject(forKey: "learningsModelDirectories")
        UserDefaults.standard.removeObject(forKey: "learningsModelSelection")
        manager = nil
        
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
    
    func testAnalyzeWithNoInputsUsesExistingLearningSignals() async {
        manager.addLabeledExample(
            srcPath: "/Downloads/Invoice_001.pdf",
            dstPath: "/Finance/Invoice_001.pdf",
            action: .accept
        )
        manager.addLabeledExample(
            srcPath: "/Downloads/Invoice_002.pdf",
            dstPath: "/Finance/Invoice_002.pdf",
            action: .accept
        )

        await manager.analyze(rootPaths: [], examplePaths: [])

        XCTAssertNil(manager.error)
        XCTAssertNotNil(manager.analysisResult)
        XCTAssertFalse(manager.analysisResult?.inferredRules.isEmpty ?? true)
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
        
        // 3. Verify - check for key sections (format may vary based on rule confidence)
        XCTAssertFalse(context.isEmpty, "Context should not be empty")
        XCTAssertTrue(context.contains("CRITICAL PREFERENCES") || context.contains("PREFERENCES"), "Missing Preferences section")
        XCTAssertTrue(context.contains("Sort by Date"), "Missing actual preference 'Sort by Date'")
        // Rules are split by confidence level - check for either high-confidence or learned patterns
        XCTAssertTrue(context.contains("LEARNED PATTERNS") || context.contains("HIGH-CONFIDENCE RULES") || context.contains("Group by extension"), "Missing Rules section")
        XCTAssertTrue(context.contains("USER INSTRUCTIONS") || context.contains("FEEDBACK"), "Missing Instructions section")
        XCTAssertTrue(context.contains("No folders"), "Missing instruction 'No folders'")
        XCTAssertTrue(context.contains("CORRECTIONS"), "Missing Corrections section")
        // Corrections are now grouped by extension pattern
        XCTAssertTrue(context.contains("txt") || context.contains(".txt"), "Missing extension pattern 'txt'")
        
        // 4. Test No Consent (Should respect privacy)
        // Set both bits of consent to false
        if var p = manager.currentProfile {
            p.consentGranted = false
            manager.currentProfile = p
        }

        // Revoke consent on the same manager instance to avoid global UserDefaults
        // races when tests run in parallel.
        await manager.withdrawConsent()

        XCTAssertTrue(manager.generatePromptContext().isEmpty, "Context should be empty when no consent is granted")
    }

    func testPromptContextRespectsLearningStrengthAndPreservesRuleAttribution() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.inferredRules = (0..<6).map { index in
            InferredRule(
                id: "rule-\(index)",
                pattern: ".*\\.\(index)$",
                template: "Folder\(index)/{filename}",
                priority: index * 10,
                explanation: "Learned rule \(index)",
                status: .active
            )
        }
        manager.currentProfile = profile
        manager.learningStrength = 0

        let context = manager.generatePromptContext()

        XCTAssertTrue(context.contains("[rule_id: rule-5]"))
        XCTAssertTrue(context.contains("Learned rule 5"))
        XCTAssertFalse(context.contains("Learned rule 4"))
    }
    
    
    func testErrorStateClearing() async {
       manager.error = "Previous error"
       // Perform an action that clears error usually at start
       // manager.analyze clears errors, but we need valid inputs so it doesn't fail again immediately
       await manager.analyze(rootPaths: ["/tmp"], examplePaths: [])
       
       XCTAssertNil(manager.error)
    }
    
    // MARK: - Model Directory Tests
    
    func testAddModelDirectory() {
       let tempPath = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyTestModelDir-\(UUID().uuidString)").path
       try? FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
       defer { try? FileManager.default.removeItem(atPath: tempPath) }
       
       let added = manager.addModelDirectory(path: tempPath)
       XCTAssertTrue(added)
       XCTAssertEqual(manager.modelDirectories.count, 1)
       XCTAssertEqual(manager.modelDirectories.first?.path, tempPath)
    }
    
    func testAddDuplicateModelDirectory() {
       let tempPath = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyTestModelDir-\(UUID().uuidString)").path
       try? FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
       defer { try? FileManager.default.removeItem(atPath: tempPath) }
       
       let added1 = manager.addModelDirectory(path: tempPath)
       let added2 = manager.addModelDirectory(path: tempPath)
       
       XCTAssertTrue(added1)
       XCTAssertFalse(added2, "Duplicate canonical path should be rejected")
       XCTAssertEqual(manager.modelDirectories.count, 1)
    }
    
    func testRemoveModelDirectory() {
       let tempPath = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyTestModelDir-\(UUID().uuidString)").path
       try? FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
       defer { try? FileManager.default.removeItem(atPath: tempPath) }
       
       _ = manager.addModelDirectory(path: tempPath)
       let id = manager.modelDirectories.first!.id
       manager.removeModelDirectory(id: id)
       
       XCTAssertTrue(manager.modelDirectories.isEmpty)
    }
    
    func testToggleModelDirectory() {
       let tempPath = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyTestModelDir-\(UUID().uuidString)").path
       try? FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
       defer { try? FileManager.default.removeItem(atPath: tempPath) }
       
       _ = manager.addModelDirectory(path: tempPath)
       let id = manager.modelDirectories.first!.id
       
       XCTAssertTrue(manager.modelDirectories.first!.isEnabled)
       manager.toggleModelDirectory(id: id)
       XCTAssertFalse(manager.modelDirectories.first!.isEnabled)
       manager.toggleModelDirectory(id: id)
       XCTAssertTrue(manager.modelDirectories.first!.isEnabled)
    }
    
    func testEnabledModelDirectoryPaths() {
       let path1 = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyTestModelDir1-\(UUID().uuidString)").path
       let path2 = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyTestModelDir2-\(UUID().uuidString)").path
       try? FileManager.default.createDirectory(atPath: path1, withIntermediateDirectories: true)
       try? FileManager.default.createDirectory(atPath: path2, withIntermediateDirectories: true)
       defer {
           try? FileManager.default.removeItem(atPath: path1)
           try? FileManager.default.removeItem(atPath: path2)
       }
       
       _ = manager.addModelDirectory(path: path1)
       _ = manager.addModelDirectory(path: path2)
       
       // Both enabled
       XCTAssertEqual(manager.enabledModelDirectoryPaths().count, 2)
       
       // Disable one
       let id = manager.modelDirectories.first!.id
       manager.toggleModelDirectory(id: id)
       XCTAssertEqual(manager.enabledModelDirectoryPaths().count, 1)
    }
    
    func testModelDirectoryContextGeneration() {
       let tempPath = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyTestModelDir-\(UUID().uuidString)")
       try? FileManager.default.createDirectory(
           at: tempPath.appendingPathComponent("Projects"),
           withIntermediateDirectories: true
       )
       defer { try? FileManager.default.removeItem(at: tempPath) }
       
       _ = manager.addModelDirectory(path: tempPath.path)
       let context = manager.generateModelDirectoryContext()
       
       XCTAssertTrue(context.contains("REFERENCE MODEL DIRECTORIES"))
       XCTAssertTrue(context.contains("Projects"))
    }
    
    func testModelDirectoryContextEmptyWhenNoneConfigured() {
       let context = manager.generateModelDirectoryContext()
       XCTAssertTrue(context.isEmpty)
    }

    func testFailedModelDirectoryRescanPreservesLastGoodSnapshot() async throws {
       let directory = FileManager.default.temporaryDirectory
           .appendingPathComponent("SortyModelSnapshot-\(UUID().uuidString)", isDirectory: true)
       try FileManager.default.createDirectory(
           at: directory.appendingPathComponent("Projects", isDirectory: true),
           withIntermediateDirectories: true
       )
       _ = manager.addModelDirectory(path: directory.path)
       let id = try XCTUnwrap(manager.modelDirectories.first?.id)
       await manager.rescanModelDirectory(id: id)
       let snapshot = try XCTUnwrap(manager.modelDirectories.first?.scanSnapshot)
       try FileManager.default.removeItem(at: directory)

       await manager.rescanModelDirectory(id: id)

       XCTAssertEqual(manager.modelDirectories.first?.scanSnapshot, snapshot)
       XCTAssertEqual(manager.modelDirectories.first?.lastScannedAt, snapshot.scannedAt)
    }

    func testLearningsModelOverrideUsesDedicatedModelForAnalysis() {
       manager.setLearningsModelOverride(provider: .openAI, model: "gpt-5-mini")

       var baseConfig = AIConfig.default
       baseConfig.provider = .openAI
       baseConfig.model = "gpt-5"

       let effectiveConfig = manager.effectiveAIConfig(from: baseConfig)

       XCTAssertEqual(effectiveConfig.provider, .openAI)
       XCTAssertEqual(effectiveConfig.model, "gpt-5-mini")
    }

    func testLearningsModelOverrideFallsBackWhenProviderChanges() {
       manager.setLearningsModelOverride(provider: .openAI, model: "gpt-5-mini")

       var baseConfig = AIConfig.default
       baseConfig.provider = .anthropic
       baseConfig.model = "claude-sonnet-4-20250514"

       let effectiveConfig = manager.effectiveAIConfig(from: baseConfig)

       XCTAssertEqual(effectiveConfig.provider, .anthropic)
       XCTAssertEqual(effectiveConfig.model, "claude-sonnet-4-20250514")
    }
}

// MARK: - LearningsAnalyzer Tests

@MainActor
final class LearningsAnalyzerTests: XCTestCase {
    
    var analyzer: LearningsAnalyzer!
    
    override func setUp() async throws {
        
        analyzer = LearningsAnalyzer()
    }
    
    override func tearDown() async throws {
        analyzer = nil
        
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

// MARK: - Enhanced Learnings Tests

@MainActor
final class EnhancedLearningsTests: XCTestCase {
    
    var manager: LearningsManager!
    
    override func setUp() async throws {
        manager = LearningsManager()
        manager.currentProfile = LearningsProfile()
        await manager.grantConsent()
    }
    
    override func tearDown() async throws {
        manager = nil
    }
    
    // MARK: - Scoped Rule Tests
    
    func testScopedRuleFilteringByFolder() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.inferredRules = [
            InferredRule(pattern: ".*\\.pdf$", template: "Documents/{filename}", priority: 80, explanation: "PDFs to Documents", scope: .global, status: .active),
            InferredRule(pattern: ".*\\.pdf$", template: "Work/Reports/{filename}", priority: 90, explanation: "Work PDFs to Reports", scope: .folder("/Users/test/Work"), status: .active),
            InferredRule(pattern: ".*\\.jpg$", template: "Photos/{filename}", priority: 70, explanation: "Photos to Photos folder", scope: .folder("/Users/test/Personal"), status: .active)
        ]
        manager.currentProfile = profile
        
        let workRules = manager.getActiveRules(forFolder: "/Users/test/Work")
        XCTAssertTrue(workRules.contains(where: { $0.explanation == "PDFs to Documents" }), "Global rule should be included")
        XCTAssertTrue(workRules.contains(where: { $0.explanation == "Work PDFs to Reports" }), "Work-scoped rule should be included")
        XCTAssertFalse(workRules.contains(where: { $0.explanation == "Photos to Photos folder" }), "Personal-scoped rule should NOT be included for Work folder")
    }
    
    func testGlobalRulesAlwaysIncluded() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.inferredRules = [
            InferredRule(pattern: ".*", template: "{category}/{filename}", priority: 50, explanation: "Global catch-all", scope: .global, status: .active)
        ]
        manager.currentProfile = profile
        
        let rules = manager.getActiveRules(forFolder: "/any/path")
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.explanation, "Global catch-all")
    }
    
    // MARK: - Pending Approval Tests
    
    func testPendingRulesNotIncludedInActiveRules() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.inferredRules = [
            InferredRule(pattern: ".*\\.txt$", template: "Text/{filename}", priority: 60, explanation: "Text files rule", scope: .global, status: .active),
            InferredRule(pattern: ".*\\.csv$", template: "Data/{filename}", priority: 50, explanation: "CSV files rule", scope: .global, status: .pendingApproval)
        ]
        manager.currentProfile = profile
        
        let activeRules = manager.getActiveRules()
        XCTAssertTrue(activeRules.contains(where: { $0.explanation == "Text files rule" }), "Active rule should be included")
        XCTAssertFalse(activeRules.contains(where: { $0.explanation == "CSV files rule" }), "Pending rule should NOT be in active rules")
    }
    
    func testGetPendingRules() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.inferredRules = [
            InferredRule(pattern: ".*\\.txt$", template: "Text/{filename}", priority: 60, explanation: "Text rule", scope: .global, status: .active),
            InferredRule(pattern: ".*\\.csv$", template: "Data/{filename}", priority: 50, explanation: "CSV rule", scope: .global, status: .pendingApproval),
            InferredRule(pattern: ".*\\.json$", template: "Config/{filename}", priority: 40, explanation: "JSON rule", scope: .global, status: .pendingApproval)
        ]
        manager.currentProfile = profile
        
        let pending = manager.getPendingRules()
        XCTAssertEqual(pending.count, 2)
        XCTAssertTrue(pending.allSatisfy { $0.status == .pendingApproval })
    }
    
    func testApproveRule() async {
        var profile = LearningsProfile()
        profile.consentGranted = true
        let ruleId = UUID().uuidString
        profile.inferredRules = [
            InferredRule(id: ruleId, pattern: ".*\\.csv$", template: "Data/{filename}", priority: 50, explanation: "CSV rule", scope: .global, status: .pendingApproval)
        ]
        manager.currentProfile = profile
        
        await manager.approveRule(ruleId: ruleId)
        
        let rule = manager.currentProfile?.inferredRules.first(where: { $0.id == ruleId })
        XCTAssertEqual(rule?.status, .active)
    }
    
    func testRejectRuleWithCooldown() async {
        var profile = LearningsProfile()
        profile.consentGranted = true
        let ruleId = UUID().uuidString
        profile.inferredRules = [
            InferredRule(id: ruleId, pattern: ".*\\.csv$", template: "Data/{filename}", priority: 50, explanation: "CSV rule", scope: .global, status: .pendingApproval)
        ]
        manager.currentProfile = profile
        
        await manager.rejectRule(ruleId: ruleId, cooldownDays: 7)
        
        let rule = manager.currentProfile?.inferredRules.first(where: { $0.id == ruleId })
        XCTAssertEqual(rule?.status, .rejected)
        XCTAssertNotNil(rule?.rejectedAt)
        XCTAssertNotNil(rule?.cooldownUntil)
        XCTAssertFalse(rule?.isEnabled ?? true)
        
        XCTAssertTrue(manager.isRuleInCooldown(pattern: ".*\\.csv$"))
    }
    
    // MARK: - Learning Exclusion Tests
    
    func testAddAndRemoveLearningExclusion() async {
        await manager.addLearningExclusion("Temp")
        
        XCTAssertTrue(manager.currentProfile?.learningExclusionPatterns.contains("Temp") ?? false)
        XCTAssertTrue(manager.isPathExcludedFromLearning("/Users/test/Temp/file.txt"))
        
        await manager.removeLearningExclusion("Temp")
        
        XCTAssertFalse(manager.currentProfile?.learningExclusionPatterns.contains("Temp") ?? true)
        XCTAssertFalse(manager.isPathExcludedFromLearning("/Users/test/Temp/file.txt"))
    }
    
    func testPathExclusionChecking() async {
        await manager.addLearningExclusion("Temp")
        await manager.addLearningExclusion("Downloads/Cache")
        
        XCTAssertTrue(manager.isPathExcludedFromLearning("/Users/test/Temp/file.pdf"))
        XCTAssertTrue(manager.isPathExcludedFromLearning("/Users/test/Downloads/Cache/data.json"))
        XCTAssertFalse(manager.isPathExcludedFromLearning("/Users/test/Documents/report.pdf"))
    }

    func testLearningExclusionStorageNormalizationPreservesReadablePath() async {
        await manager.addLearningExclusion("  ./Downloads//Cache/  ")

        XCTAssertEqual(manager.currentProfile?.learningExclusionPatterns, ["Downloads/Cache"])
    }

    func testLearningExclusionDeduplicatesCaseInsensitivePatterns() async {
        await manager.addLearningExclusion("Downloads/Cache")
        await manager.addLearningExclusion("downloads/cache")

        XCTAssertEqual(manager.currentProfile?.learningExclusionPatterns.count, 1)
        XCTAssertEqual(manager.currentProfile?.learningExclusionPatterns.first, "Downloads/Cache")
    }

    func testExcludedPathsAreIgnoredWhenRecordingLearnings() async {
        await manager.addLearningExclusion("Temp")

        manager.addLabeledExample(
            srcPath: "/Users/test/Temp/file.txt",
            dstPath: "/Users/test/Documents/file.txt",
            action: .accept
        )
        manager.recordCorrection(
            originalPath: "/Users/test/Temp/file.txt",
            newPath: "/Users/test/Documents/file.txt"
        )
        manager.recordDirectoryChange(
            from: "/Users/test/Temp/file.txt",
            to: "/Users/test/Documents/file.txt",
            wasAIOrganized: true
        )

        XCTAssertTrue(manager.currentProfile?.positiveExamples.isEmpty ?? false)
        XCTAssertTrue(manager.currentProfile?.corrections.isEmpty ?? false)
        XCTAssertTrue(manager.currentProfile?.postOrganizationChanges.isEmpty ?? false)
    }

    func testAddingExclusionPrunesExistingLearningsAndRules() async {
        let excludedExample = LabeledExample(
            id: "excluded-example",
            srcPath: "/Users/test/Temp/file.txt",
            dstPath: "/Users/test/Archive/file.txt",
            action: .accept
        )
        let keptExample = LabeledExample(
            id: "kept-example",
            srcPath: "/Users/test/Documents/report.txt",
            dstPath: "/Users/test/Reports/report.txt",
            action: .accept
        )

        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.positiveExamples = [excludedExample, keptExample]
        profile.corrections = [
            LabeledExample(
                srcPath: "/Users/test/Temp/correct.txt",
                dstPath: "/Users/test/Archive/correct.txt",
                action: .edit
            )
        ]
        profile.additionalInstructionsHistory = [
            UserInstruction(instruction: "Ignore temp work", folderPath: "/Users/test/Temp")
        ]
        profile.inferredRules = [
            InferredRule(
                pattern: ".*\\.txt$",
                template: "Archive/{filename}",
                priority: 80,
                exampleIds: ["excluded-example"],
                explanation: "Temp text files go to Archive"
            )
        ]
        manager.currentProfile = profile

        await manager.addLearningExclusion("Temp")

        XCTAssertEqual(manager.currentProfile?.positiveExamples.count, 1)
        XCTAssertEqual(manager.currentProfile?.positiveExamples.first?.id, "kept-example")
        XCTAssertTrue(manager.currentProfile?.corrections.isEmpty ?? false)
        XCTAssertTrue(manager.currentProfile?.additionalInstructionsHistory.isEmpty ?? false)
        XCTAssertTrue(manager.currentProfile?.inferredRules.isEmpty ?? false)
    }
    
    // MARK: - Rule Evidence Tests
    
    func testRuleEvidenceTracking() {
        let rule = InferredRule(
            pattern: "Invoice.*\\.pdf$",
            template: "Finance/{year}/Invoices/{filename}",
            priority: 85,
            explanation: "Organize invoices by year",
            scope: .global,
            status: .active,
            evidenceIds: ["example-1", "steering-2"],
            evidenceDescription: "Rule created because you moved 5 invoice PDFs to Finance/Invoices last week."
        )
        
        XCTAssertEqual(rule.evidenceIds.count, 2)
        XCTAssertNotNil(rule.evidenceDescription)
        XCTAssertTrue(rule.evidenceDescription!.contains("invoice"))
    }
    
    // MARK: - Session Learning Tests
    
    func testSessionLearningPause() {
        XCTAssertFalse(manager.sessionLearningPaused)
        
        manager.sessionLearningPaused = true
        XCTAssertTrue(manager.sessionLearningPaused)
        
        manager.sessionLearningPaused = false
        XCTAssertFalse(manager.sessionLearningPaused)
    }

    func testSummaryReflectsNoConsentState() async {
        await manager.withdrawConsent()

        let summary = manager.summary
        XCTAssertEqual(summary.state, .noConsent)
        XCTAssertFalse(summary.shouldShowBadge)
        XCTAssertFalse(summary.canProvideFeedback)
    }

    func testSummaryPausedRetainsActiveRuleCounts() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.sessions = [OrganizationSession(folderPath: "/Users/test/Work")]
        profile.inferredRules = [
            InferredRule(
                pattern: ".*\\.pdf$",
                template: "Documents/{filename}",
                priority: 80,
                explanation: "PDF rule",
                scope: .global,
                status: .active
            )
        ]
        manager.currentProfile = profile
        manager.sessionLearningPaused = true

        let summary = manager.summary
        XCTAssertEqual(summary.state, .paused)
        XCTAssertEqual(summary.activeRuleCount, 1)
        XCTAssertTrue(summary.hasActiveRules)
        XCTAssertFalse(summary.canProvideFeedback)
    }

    func testSummaryEstablishedUsesSessionAndRuleMaturity() {
        var sessions: [OrganizationSession] = []
        for index in 0..<12 {
            sessions.append(
                OrganizationSession(
                    id: "session-\(index)",
                    timestamp: Date().addingTimeInterval(TimeInterval(-index * 3600)),
                    folderPath: "/Users/test/Projects"
                )
            )
        }

        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.sessions = sessions
        profile.inferredRules = [
            InferredRule(
                pattern: ".*",
                template: "General/{filename}",
                priority: 90,
                explanation: "General rule",
                scope: .global,
                status: .active
            )
        ]
        manager.currentProfile = profile

        let summary = manager.summary
        XCTAssertEqual(summary.state, .established)
        XCTAssertEqual(summary.maturity, .established)
        XCTAssertTrue(summary.isActive)
    }

    func testSessionOutcomeFeedbackResolvesByHistoryEntryId() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.sessions = [
            OrganizationSession(
                id: "session-1",
                folderPath: "/Users/test/Work",
                historyEntryId: "history-1",
                reaction: .inProgress
            )
        ]
        manager.currentProfile = profile

        manager.recordSessionOutcomeFeedback(
            sessionId: "history-1",
            outcome: .useful,
            folderPath: "/Users/test/Work"
        )

        let updatedSession = manager.currentProfile?.sessions.first(where: { $0.id == "session-1" })
        XCTAssertEqual(updatedSession?.reaction, .accepted)
        XCTAssertTrue(updatedSession?.events.contains(where: { $0.kind == .feedback }) ?? false)
    }

    func testSessionOutcomeFeedbackIgnoredWhenPaused() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.sessions = [
            OrganizationSession(
                id: "session-1",
                folderPath: "/Users/test/Work",
                reaction: .inProgress
            )
        ]
        manager.currentProfile = profile
        manager.sessionLearningPaused = true

        manager.recordSessionOutcomeFeedback(
            sessionId: "session-1",
            outcome: .useful,
            folderPath: "/Users/test/Work"
        )

        let pausedSession = manager.currentProfile?.sessions.first(where: { $0.id == "session-1" })
        XCTAssertEqual(pausedSession?.reaction, .inProgress)
        XCTAssertFalse(pausedSession?.events.contains(where: { $0.kind == .feedback }) ?? false)
    }
    
    // MARK: - Scope Display Names
    
    func testRuleScopeDisplayNames() {
        XCTAssertEqual(RuleScope.global.displayName, "Global")
        
        let folderScope = RuleScope.folder("/Users/test/Documents")
        XCTAssertEqual(folderScope.displayName, "Folder: Documents")
        
        let personaScope = RuleScope.activePersona(UUID())
        XCTAssertTrue(personaScope.displayName.hasPrefix("Persona:"))
    }
}

// MARK: - Exclusion Parsing Tests

final class ExclusionParsingTests: XCTestCase {
    
    func testParseExclusionFromPrompt() {
        let testCases: [(input: String, expected: String?)] = [
            ("Don't learn from moves in my Temp folder", "Temp"),
            ("Skip learning for Downloads", "Downloads"),
            ("Exclude from learning Cache directory", "Cache"),
            ("This is a regular instruction", nil),
            ("Organize files by date", nil),
        ]
        
        for testCase in testCases {
            let result = parseExclusionPattern(testCase.input)
            XCTAssertEqual(result, testCase.expected, "Failed for input: \(testCase.input)")
        }
    }
    
    private func parseExclusionPattern(_ prompt: String) -> String? {
        let lowered = prompt.lowercased()
        let exclusionPhrases = [
            "don't learn from",
            "dont learn from",
            "skip learning for",
            "exclude from learning",
            "ignore for learning",
            "no learning for",
            "stop learning from"
        ]
        
        for phrase in exclusionPhrases {
            if lowered.contains(phrase) {
                if let range = lowered.range(of: phrase) {
                    let remainder = String(prompt[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let cleaned = remainder
                        .replacingOccurrences(of: "moves in ", with: "")
                        .replacingOccurrences(of: "my ", with: "")
                        .replacingOccurrences(of: " folder", with: "")
                        .replacingOccurrences(of: " directory", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    
                    if !cleaned.isEmpty { return cleaned }
                }
            }
        }
        return nil
    }
}
