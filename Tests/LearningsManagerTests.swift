//
//  LearningsManagerTests.swift
//  FileOrganizerTests
//
//  Comprehensive tests for The Learnings feature
//

import XCTest
@testable import FileOrganizerLib

@MainActor
final class LearningsManagerTests: XCTestCase {
    
    var manager: LearningsManager!
    
    override func setUp() async throws {
        try await super.setUp()
        manager = LearningsManager()
    }
    
    override func tearDown() async throws {
        manager = nil
        try await super.tearDown()
    }
    
    // MARK: - Project Management Tests
    
    func testCreateProject() {
        manager.createProject(name: "Test Project", rootPaths: ["/test/path"])
        
        XCTAssertNotNil(manager.currentProject)
        XCTAssertEqual(manager.currentProject?.name, "Test Project")
        XCTAssertEqual(manager.currentProject?.rootPaths.count, 1)
        XCTAssertNil(manager.analysisResult)
    }
    
    func testAddExampleFolder() {
        manager.createProject(name: "Photos", rootPaths: [])
        
        manager.addExampleFolder("/Users/test/OrganizedPhotos")
        
        XCTAssertEqual(manager.currentProject?.exampleFolders.count, 1)
        XCTAssertEqual(manager.currentProject?.exampleFolders.first, "/Users/test/OrganizedPhotos")
    }
    
    func testRemoveExampleFolder() {
        manager.createProject(name: "Project", rootPaths: [])
        manager.addExampleFolder("/path1")
        manager.addExampleFolder("/path2")
        
        manager.removeExampleFolder(at: 0)
        
        XCTAssertEqual(manager.currentProject?.exampleFolders.count, 1)
        XCTAssertEqual(manager.currentProject?.exampleFolders.first, "/path2")
    }
    
    func testAddRootPath() {
        manager.createProject(name: "Project", rootPaths: [])
        
        manager.addRootPath("/Users/test/Downloads")
        
        XCTAssertEqual(manager.currentProject?.rootPaths.count, 1)
    }
    
    func testRemoveRootPath() {
        manager.createProject(name: "Project", rootPaths: ["/path1", "/path2"])
        
        manager.removeRootPath(at: 0)
        
        XCTAssertEqual(manager.currentProject?.rootPaths.count, 1)
        XCTAssertEqual(manager.currentProject?.rootPaths.first, "/path2")
    }
    
    // MARK: - Labeled Example Tests
    
    func testAddLabeledExample() {
        manager.createProject(name: "Project", rootPaths: [])
        
        manager.addLabeledExample(
            srcPath: "/Downloads/IMG_001.jpg",
            dstPath: "/Photos/2024/IMG_001.jpg",
            action: .accept
        )
        
        XCTAssertEqual(manager.currentProject?.labeledExamples.count, 1)
        XCTAssertEqual(manager.currentProject?.labeledExamples.first?.srcPath, "/Downloads/IMG_001.jpg")
        XCTAssertEqual(manager.currentProject?.labeledExamples.first?.action, .accept)
    }
    
    func testAcceptMapping() {
        manager.createProject(name: "Project", rootPaths: [])
        
        let mapping = ProposedMapping(
            srcPath: "/test/file.txt",
            proposedDstPath: "/organized/file.txt",
            confidence: 0.9,
            explanation: "Test"
        )
        
        manager.acceptMapping(mapping)
        
        XCTAssertEqual(manager.currentProject?.labeledExamples.count, 1)
        XCTAssertEqual(manager.currentProject?.labeledExamples.first?.action, .accept)
    }
    
    func testRejectMapping() {
        manager.createProject(name: "Project", rootPaths: [])
        
        let mapping = ProposedMapping(
            srcPath: "/test/file.txt",
            proposedDstPath: "/organized/file.txt",
            confidence: 0.3,
            explanation: "Test"
        )
        
        manager.rejectMapping(mapping)
        
        XCTAssertEqual(manager.currentProject?.labeledExamples.count, 1)
        XCTAssertEqual(manager.currentProject?.labeledExamples.first?.action, .reject)
        // Should keep in place
        XCTAssertEqual(manager.currentProject?.labeledExamples.first?.dstPath, "/test/file.txt")
    }
    
    func testEditMapping() {
        manager.createProject(name: "Project", rootPaths: [])
        
        let mapping = ProposedMapping(
            srcPath: "/test/file.txt",
            proposedDstPath: "/organized/file.txt",
            confidence: 0.7,
            explanation: "Test"
        )
        
        manager.editMapping(mapping, newDstPath: "/custom/location/file.txt")
        
        XCTAssertEqual(manager.currentProject?.labeledExamples.count, 1)
        XCTAssertEqual(manager.currentProject?.labeledExamples.first?.action, .edit)
        XCTAssertEqual(manager.currentProject?.labeledExamples.first?.dstPath, "/custom/location/file.txt")
    }
    
    // MARK: - Analysis Tests
    
    func testAnalyzeWithNoProject() async {
        // Don't create a project
        await manager.analyze()
        
        XCTAssertNotNil(manager.error)
        XCTAssertTrue(manager.error!.contains("No project"))
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorStateClearing() async {
        manager.error = "Previous error"
        manager.createProject(name: "New", rootPaths: [])
        
        // Error should persist until cleared by another operation
        XCTAssertNotNil(manager.error)
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

// MARK: - LearningsProject Tests

final class LearningsProjectTests: XCTestCase {
    
    func testProjectCreation() {
        let project = LearningsProject(
            name: "Test Project",
            rootPaths: ["/test"],
            exampleFolders: ["/examples"]
        )
        
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertEqual(project.rootPaths.count, 1)
        XCTAssertEqual(project.exampleFolders.count, 1)
        XCTAssertTrue(project.labeledExamples.isEmpty)
        XCTAssertTrue(project.inferredRules.isEmpty)
        XCTAssertTrue(project.jobHistory.isEmpty)
    }
    
    func testProjectTouch() {
        var project = LearningsProject(name: "Test")
        let originalModified = project.modifiedAt
        
        Thread.sleep(forTimeInterval: 0.01)
        
        project.touch()
        
        XCTAssertGreaterThan(project.modifiedAt, originalModified)
    }
    
    func testAddExample() {
        var project = LearningsProject(name: "Test")
        
        let example = LabeledExample(
            srcPath: "/src/file.txt",
            dstPath: "/dst/file.txt"
        )
        
        project.addExample(example)
        
        XCTAssertEqual(project.labeledExamples.count, 1)
    }
    
    func testUpdateRules() {
        var project = LearningsProject(name: "Test")
        
        let rules = [
            InferredRule(
                pattern: "^test.*",
                template: "{filename}",
                priority: 50,
                explanation: "Test rule"
            )
        ]
        
        project.updateRules(rules)
        
        XCTAssertEqual(project.inferredRules.count, 1)
    }
    
    func testAddJob() {
        var project = LearningsProject(name: "Test")
        
        let job = JobManifest(
            projectName: "Test",
            entries: [],
            backupMode: .none
        )
        
        project.addJob(job)
        
        XCTAssertEqual(project.jobHistory.count, 1)
    }
    
    func testLearningsOptionDefaults() {
        let options = LearningsOptions()
        
        XCTAssertTrue(options.dryRun)
        XCTAssertTrue(options.stagedApply)
        XCTAssertEqual(options.sampleSize, 50)
        XCTAssertEqual(options.backupMode, .copyToBackupDir)
        XCTAssertEqual(options.confidenceThreshold, 0.7)
    }
    
    func testBackupModeDisplayNames() {
        XCTAssertEqual(BackupMode.none.displayName, "No Backup")
        XCTAssertEqual(BackupMode.moveToBackupDir.displayName, "Move to Backup Directory")
        XCTAssertEqual(BackupMode.copyToBackupDir.displayName, "Copy to Backup Directory")
    }
    
    func testJobManifestCreation() {
        let entries = [
            JobManifestEntry(
                originalPath: "/src/file1.txt",
                destinationPath: "/dst/file1.txt"
            ),
            JobManifestEntry(
                originalPath: "/src/file2.txt",
                destinationPath: "/dst/file2.txt"
            )
        ]
        
        let job = JobManifest(
            projectName: "Test",
            entries: entries,
            backupMode: .copyToBackupDir
        )
        
        XCTAssertEqual(job.fileCount, 2)
        XCTAssertEqual(job.successCount, 0) // All pending
    }
    
    func testJobSuccessCount() {
        var entries = [
            JobManifestEntry(
                originalPath: "/src/file1.txt",
                destinationPath: "/dst/file1.txt",
                status: .success
            ),
            JobManifestEntry(
                originalPath: "/src/file2.txt",
                destinationPath: "/dst/file2.txt",
                status: .failed
            ),
            JobManifestEntry(
                originalPath: "/src/file3.txt",
                destinationPath: "/dst/file3.txt",
                status: .success
            )
        ]
        
        let job = JobManifest(
            projectName: "Test",
            entries: entries,
            backupMode: .none
        )
        
        XCTAssertEqual(job.successCount, 2)
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
        
        // Might return nil or a generic pattern
        // Just verify it doesn't crash
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