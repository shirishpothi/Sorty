//
//  RuleInducerTests.swift
//  FileOrganizer
//
//  Unit tests for the RuleInducer component of The Learnings feature
//

import XCTest
@testable import FileOrganizerLib

final class RuleInducerTests: XCTestCase {
    
    var ruleInducer: RuleInducer!
    
    override func setUp() async throws {
        ruleInducer = RuleInducer()
    }
    
    // MARK: - Pattern Matching Tests
    
    func testExtractDateFromIMGPattern() {
        let date = PatternMatcher.extractDate(from: "IMG_20240101_123456.jpg")
        XCTAssertNotNil(date)
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: date!), 2024)
        XCTAssertEqual(calendar.component(.month, from: date!), 1)
        XCTAssertEqual(calendar.component(.day, from: date!), 1)
    }
    
    func testExtractDateFromDashPattern() {
        let date = PatternMatcher.extractDate(from: "Document 2024-06-15.pdf")
        XCTAssertNotNil(date)
        
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.year, from: date!), 2024)
        XCTAssertEqual(calendar.component(.month, from: date!), 6)
        XCTAssertEqual(calendar.component(.day, from: date!), 15)
    }
    
    func testExtractYearFromFilename() {
        XCTAssertEqual(PatternMatcher.extractYear(from: "Movie.2010.1080p.mkv"), 2010)
        XCTAssertEqual(PatternMatcher.extractYear(from: "Report 2023.pdf"), 2023)
        XCTAssertNil(PatternMatcher.extractYear(from: "RandomFile.txt"))
    }
    
    func testTokenizeFilename() {
        let tokens = PatternMatcher.tokenize("IMG_20240101_123456.jpg")
        XCTAssertTrue(tokens.contains("IMG"))
        XCTAssertTrue(tokens.contains("20240101"))
        XCTAssertTrue(tokens.contains("123456"))
    }
    
    func testDetectIMGPattern() {
        let patterns = PatternMatcher.detectPatterns(in: "IMG_20240101_123456.jpg")
        XCTAssertTrue(patterns.contains(.imgDate))
    }
    
    func testDetectArtistTitlePattern() {
        let patterns = PatternMatcher.detectPatterns(in: "Artist Name - Song Title.mp3")
        XCTAssertTrue(patterns.contains(.artistTitle))
    }
    
    func testDetectTrackNumberPattern() {
        let patterns = PatternMatcher.detectPatterns(in: "01 - Song Title.mp3")
        XCTAssertTrue(patterns.contains(.trackNumber))
    }
    
    // MARK: - File Category Tests
    
    func testFileCategoryFromExtension() {
        XCTAssertEqual(FileCategory.from(extension: "jpg"), .photo)
        XCTAssertEqual(FileCategory.from(extension: "JPEG"), .photo)
        XCTAssertEqual(FileCategory.from(extension: "mp3"), .music)
        XCTAssertEqual(FileCategory.from(extension: "mp4"), .video)
        XCTAssertEqual(FileCategory.from(extension: "pdf"), .document)
        XCTAssertEqual(FileCategory.from(extension: "swift"), .code)
        XCTAssertEqual(FileCategory.from(extension: "zip"), .archive)
        XCTAssertEqual(FileCategory.from(extension: "xyz"), .other)
    }
    
    // MARK: - Folder Structure Analysis Tests
    
    func testAnalyzeFolderStructureWithYearFolders() {
        let paths = [
            "/Photos/2024/IMG_001.jpg",
            "/Photos/2024/IMG_002.jpg",
            "/Photos/2023/IMG_003.jpg"
        ]
        
        let analysis = PatternMatcher.analyzeFolderStructure(from: paths)
        XCTAssertTrue(analysis.usesYearFolders)
        XCTAssertEqual(analysis.primaryGroupingKey, "year")
    }
    
    func testAnalyzeFolderStructureWithDateFolders() {
        let paths = [
            "/Photos/2024-01-01/IMG_001.jpg",
            "/Photos/2024-01-02/IMG_002.jpg"
        ]
        
        let analysis = PatternMatcher.analyzeFolderStructure(from: paths)
        XCTAssertTrue(analysis.usesDateFolders)
        XCTAssertEqual(analysis.primaryGroupingKey, "date")
    }
    
    // MARK: - Rule Induction Tests
    
    func testInduceRulesFromLabeledExamples() async {
        let examples = [
            LabeledExample(srcPath: "/Downloads/IMG_20240101_120000.jpg", dstPath: "/Photos/2024/IMG_20240101_120000.jpg"),
            LabeledExample(srcPath: "/Downloads/IMG_20240102_130000.jpg", dstPath: "/Photos/2024/IMG_20240102_130000.jpg"),
            LabeledExample(srcPath: "/Downloads/IMG_20240103_140000.jpg", dstPath: "/Photos/2024/IMG_20240103_140000.jpg")
        ]
        
        let rules = await ruleInducer.induceRules(from: examples, exampleFolders: [])
        
        XCTAssertFalse(rules.isEmpty, "Should induce at least one rule from examples")
        
        // Verify rule has expected properties
        if let photoRule = rules.first(where: { $0.pattern.contains("IMG") }) {
            XCTAssertTrue(photoRule.metadataCues.contains("exif:DateTimeOriginal"))
            XCTAssertGreaterThan(photoRule.priority, 0)
        }
    }
    
    func testIncrementalRuleUpdate() async {
        // Start with initial rules
        let initialExamples = [
            LabeledExample(srcPath: "/Downloads/IMG_20240101_120000.jpg", dstPath: "/Photos/2024/IMG_20240101_120000.jpg")
        ]
        
        let initialRules = await ruleInducer.induceRules(from: initialExamples, exampleFolders: [])
        
        // Add new example
        let newExample = LabeledExample(
            srcPath: "/Downloads/IMG_20240201_150000.jpg",
            dstPath: "/Photos/2024/IMG_20240201_150000.jpg"
        )
        
        let updatedRules = await ruleInducer.updateRulesIncrementally(
            existingRules: initialRules,
            newExample: newExample
        )
        
        // Rules should be updated (priority increased or new rule added)
        XCTAssertFalse(updatedRules.isEmpty)
    }
    
    // MARK: - Confidence Level Tests
    
    func testProposedMappingConfidenceLevels() {
        let highConfidence = ProposedMapping(
            srcPath: "/test.jpg",
            proposedDstPath: "/out/test.jpg",
            confidence: 0.85,
            explanation: "Test"
        )
        XCTAssertEqual(highConfidence.confidenceLevel, .high)
        
        let mediumConfidence = ProposedMapping(
            srcPath: "/test.jpg",
            proposedDstPath: "/out/test.jpg",
            confidence: 0.6,
            explanation: "Test"
        )
        XCTAssertEqual(mediumConfidence.confidenceLevel, .medium)
        
        let lowConfidence = ProposedMapping(
            srcPath: "/test.jpg",
            proposedDstPath: "/out/test.jpg",
            confidence: 0.3,
            explanation: "Test"
        )
        XCTAssertEqual(lowConfidence.confidenceLevel, .low)
    }
    
    // MARK: - Models Tests
    

    
    func testAnalysisResultToJSON() throws {
        let result = LearningsAnalysisResult(
            inferredRules: [
                InferredRule(
                    id: "rule-1",
                    pattern: "^IMG_.*",
                    template: "{year}/{filename}",
                    metadataCues: ["exif:DateTimeOriginal"],
                    priority: 50,
                    exampleIds: ["ex-1"],
                    explanation: "Photo organization rule"
                )
            ],
            proposedMappings: [
                ProposedMapping(
                    srcPath: "/Downloads/test.jpg",
                    proposedDstPath: "/Photos/2024/test.jpg",
                    ruleId: "rule-1",
                    confidence: 0.8,
                    explanation: "Matched photo rule"
                )
            ],
            confidenceSummary: ConfidenceSummary(high: 1, medium: 0, low: 0),
            humanSummary: ["Learned 1 rule from examples"]
        )
        
        let jsonData = try result.toJSON()
        XCTAssertNotNil(jsonData)
        
        // Verify it can be decoded back
        let decoded = try JSONDecoder().decode(LearningsAnalysisResult.self, from: jsonData)
        XCTAssertEqual(decoded.inferredRules.count, 1)
        XCTAssertEqual(decoded.proposedMappings.count, 1)
    }
}
