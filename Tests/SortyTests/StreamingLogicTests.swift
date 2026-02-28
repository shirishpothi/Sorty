//
//  StreamingLogicTests.swift
//  SortyTests
//
//  Tests for FolderOrganizer streaming logic, insight extraction, and progress estimation
//

import XCTest
@testable import SortyLib

@MainActor
final class StreamingLogicTests: XCTestCase {
    
    var organizer: FolderOrganizer!
    
    override func setUp() async throws {
        organizer = FolderOrganizer()
    }
    
    override func tearDown() async throws {
        organizer = nil
    }
    
    // MARK: - didReceiveChunk Basic Tests
    
    func testFirstChunkSetsStreamingState() async {
        organizer.didReceiveChunk("Hello streaming")
        
        // Allow MainActor task to execute
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertTrue(organizer.isStreaming)
        XCTAssertEqual(organizer.streamingContent, "Hello streaming")
        XCTAssertGreaterThanOrEqual(organizer.progress, 0.30)
        XCTAssertLessThanOrEqual(organizer.progress, 0.32)
    }
    
    func testMultipleChunksAccumulate() async {
        organizer.didReceiveChunk("chunk1 ")
        try? await Task.sleep(nanoseconds: 50_000_000)
        organizer.didReceiveChunk("chunk2 ")
        try? await Task.sleep(nanoseconds: 50_000_000)
        organizer.didReceiveChunk("chunk3")
        
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(organizer.streamingContent, "chunk1 chunk2 chunk3")
    }

    func testLiveInsightsToggleDisablesInsightAndPreviewUpdates() async {
        organizer.setLiveInsightsEnabled(false)
        organizer.didReceiveChunk("creating folder: 'Receipts' for report.pdf")
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(organizer.isStreaming)
        XCTAssertEqual(organizer.streamingContent, "creating folder: 'Receipts' for report.pdf")
        XCTAssertTrue(organizer.currentInsight.isEmpty)
        XCTAssertTrue(organizer.insightHistory.isEmpty)
        XCTAssertTrue(organizer.truncatedDisplayStreamingContent.isEmpty)
    }

    func testLiveInsightsToggleReEnablesBackfillFromCurrentStream() async {
        organizer.setLiveInsightsEnabled(false)
        organizer.didReceiveChunk("creating folder: 'Receipts' for report.pdf")
        try? await Task.sleep(nanoseconds: 200_000_000)

        organizer.setLiveInsightsEnabled(true)
        try? await Task.sleep(nanoseconds: 400_000_000)

        XCTAssertFalse(organizer.truncatedDisplayStreamingContent.isEmpty)
    }
    
    func testProgressIncreasesWithContentLength() async {
        organizer.scannedFileCount = 10
        
        organizer.didReceiveChunk("x")
        try? await Task.sleep(nanoseconds: 150_000_000)
        let initialProgress = organizer.progress
        
        let longContent = String(repeating: "analyzing files and sorting them into folders. ", count: 50)
        organizer.didReceiveChunk(longContent)
        try? await Task.sleep(nanoseconds: 300_000_000)
        let laterProgress = organizer.progress
        
        XCTAssertGreaterThanOrEqual(laterProgress, initialProgress)
    }
    
    func testProgressDoesNotExceedCap() async {
        organizer.scannedFileCount = 1
        
        let hugeContent = String(repeating: "A", count: 50000)
        organizer.didReceiveChunk(hugeContent)
        try? await Task.sleep(nanoseconds: 300_000_000)
        
        XCTAssertLessThanOrEqual(organizer.progress, 0.82)
    }
    
    func testDidCompleteSetsStreamingFalse() async {
        organizer.didReceiveChunk("some content")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(organizer.isStreaming)
        
        organizer.didComplete(content: "some content")
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(organizer.isStreaming)
    }

    func testChunkAfterCompletedStreamStartsFreshSession() async {
        organizer.didReceiveChunk("first stream")
        try? await Task.sleep(nanoseconds: 100_000_000)
        organizer.didComplete(content: "first stream")
        try? await Task.sleep(nanoseconds: 100_000_000)

        organizer.progress = 0.87
        organizer.organizationStage = "Too many folders, retrying..."

        organizer.didReceiveChunk("retry stream")
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertTrue(organizer.isStreaming)
        XCTAssertEqual(organizer.organizationStage, "AI is analyzing your files...")
        XCTAssertEqual(organizer.streamingContent, "retry stream")
        XCTAssertLessThan(organizer.progress, 0.5)
    }
    
    // MARK: - Insight Extraction via Streaming
    
    func testFileInsightExtracted() async {
        let content = String(repeating: " ", count: 100) + "analyzing document: 'report.pdf' for organization"
        organizer.didReceiveChunk(content)
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        organizer.didReceiveChunk(" more content here to trigger throttle window")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let hasFileInsight = organizer.insightHistory.contains { $0.category == .file }
        let currentMentionsFile = organizer.currentInsight.contains("report.pdf")
        
        XCTAssertTrue(hasFileInsight || currentMentionsFile,
                       "Should extract file insight from content mentioning 'report.pdf'")
    }
    
    func testFolderInsightExtracted() async {
        let content = String(repeating: " ", count: 100) + "creating folder: 'Documents' for PDFs"
        organizer.didReceiveChunk(content)
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        organizer.didReceiveChunk(" additional content to pass throttle")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let hasFolderInsight = organizer.insightHistory.contains { $0.category == .folder }
        let currentMentionsFolder = organizer.currentInsight.contains("Documents")
        
        XCTAssertTrue(hasFolderInsight || currentMentionsFolder,
                       "Should extract folder insight from content mentioning 'Documents'")
    }
    
    func testConstraintInsightExtracted() async {
        let content = String(repeating: " ", count: 100) + "considering: the user prefers flat structure for small projects"
        organizer.didReceiveChunk(content)
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        organizer.didReceiveChunk(" more text to allow throttle window to pass")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let hasConstraintInsight = organizer.insightHistory.contains { $0.category == .constraint }
        let currentHasText = organizer.currentInsight.contains("flat structure")
        
        XCTAssertTrue(hasConstraintInsight || currentHasText,
                       "Should extract constraint insight")
    }
    
    func testDecisionInsightExtracted() async {
        let content = String(repeating: " ", count: 100) + "will move these files into the Archives directory for safekeeping"
        organizer.didReceiveChunk(content)
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        organizer.didReceiveChunk(" more text padding to get past throttle limit")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let hasDecisionInsight = organizer.insightHistory.contains { $0.category == .decision }
        let currentHasDecision = organizer.currentInsight.contains("Archives")
        
        XCTAssertTrue(hasDecisionInsight || currentHasDecision,
                       "Should extract decision insight")
    }
    
    func testJSONContentSkippedByGeneralInsight() async {
        let jsonContent = String(repeating: " ", count: 100) +
            """
            {"folders": [{"name": "Images"}]}. This is pure JSON that should be skipped by general insight.
            """
        organizer.didReceiveChunk(jsonContent)
        
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        organizer.didReceiveChunk(" extra padding for throttle")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let generalInsights = organizer.insightHistory.filter { $0.category == .general }
        for insight in generalInsights {
            XCTAssertFalse(insight.text.contains("{"), "General insight should not contain JSON braces")
            XCTAssertFalse(insight.text.contains("}"), "General insight should not contain JSON braces")
        }
    }
    
    // MARK: - Insight History Limit
    
    func testInsightHistoryLimitedToFive() async {
        for i in 0..<8 {
            let content = String(repeating: " ", count: 100) +
                "creating folder: 'Folder\(i)' for files number \(i)"
            organizer.streamingContent = ""
            organizer.didReceiveChunk(content)
            try? await Task.sleep(nanoseconds: 900_000_000)
            organizer.didReceiveChunk(" padding \(i)")
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        
        XCTAssertLessThanOrEqual(organizer.insightHistory.count, 5,
                                  "Insight history should be limited to 5 entries")
    }
    
    // MARK: - Insights Cache
    
    func testGetCachedInsightsReturnsData() async {
        let content = String(repeating: " ", count: 100) + "analyzing document: 'test.pdf'"
        organizer.didReceiveChunk(content)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        organizer.didReceiveChunk(" more")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        let cached = organizer.getCachedInsights()
        XCTAssertEqual(cached.current, organizer.currentInsight)
    }
    
    func testInvalidateInsightsCache() {
        organizer.invalidateInsightsCache()
        let cached = organizer.getCachedInsights()
        XCTAssertEqual(cached.current, organizer.currentInsight)
        XCTAssertEqual(cached.history.count, organizer.insightHistory.count)
    }
    
    // MARK: - Organization Stage Updates
    
    func testOrganizationStageSetOnFirstChunk() async {
        organizer.didReceiveChunk("first chunk of streaming data")
        try? await Task.sleep(nanoseconds: 100_000_000)
        
        XCTAssertEqual(organizer.organizationStage, "AI is analyzing your files...")
    }

    func testReadyCueCapturedAsGeneralInsight() async {
        organizer.didReceiveChunk(">> general: Ready to output organization structure.\n")
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertTrue(
            organizer.insightHistory.contains {
                $0.category == .general && $0.text.contains("Ready to output organization structure")
            }
        )
    }

    func testProgressLineSkipsLowSignalAssignmentFolderNames() async {
        organizer.didReceiveChunk(">> file: Assigning assets2.m4a to name\n")
        try? await Task.sleep(nanoseconds: 160_000_000)

        XCTAssertFalse(
            organizer.insightHistory.contains { $0.text.contains("assets2.m4a") && $0.text.contains("to name") }
        )
    }

    // MARK: - OrganizationProgress Struct Tests
    
    func testOrganizationProgressPercentage() {
        let progress = OrganizationProgress(phase: .aiProcessing, current: 50, total: 100, detail: nil)
        XCTAssertEqual(progress.percentage, 0.5)
    }
    
    func testOrganizationProgressZeroTotal() {
        let progress = OrganizationProgress(phase: .scanning, current: 0, total: 0, detail: nil)
        XCTAssertEqual(progress.percentage, 0)
    }
    
    func testOrganizationProgressPhaseWeights() {
        XCTAssertEqual(OrganizationProgress(phase: .scanning, current: 0, total: 1, detail: nil).phaseWeight, 0.15)
        XCTAssertEqual(OrganizationProgress(phase: .aiProcessing, current: 0, total: 1, detail: nil).phaseWeight, 0.50)
        XCTAssertEqual(OrganizationProgress(phase: .complete, current: 0, total: 1, detail: nil).phaseWeight, 1.0)
    }
    
    func testOrganizationProgressPhaseBaseProgress() {
        XCTAssertEqual(OrganizationProgress(phase: .scanning, current: 0, total: 1, detail: nil).phaseBaseProgress, 0.0)
        XCTAssertEqual(OrganizationProgress(phase: .aiProcessing, current: 0, total: 1, detail: nil).phaseBaseProgress, 0.30)
        XCTAssertEqual(OrganizationProgress(phase: .complete, current: 1, total: 1, detail: nil).overallProgress, 1.0)
    }
    
    // MARK: - AIInsight Model Tests
    
    func testAIInsightCreation() {
        let insight = AIInsight(text: "Analyzing report.pdf", category: .file, filePath: "/path/report.pdf")
        XCTAssertEqual(insight.text, "Analyzing report.pdf")
        XCTAssertEqual(insight.category, .file)
        XCTAssertEqual(insight.filePath, "/path/report.pdf")
    }
    
    func testAIInsightCategoryIcons() {
        XCTAssertEqual(AIInsight.Category.file.icon, "doc")
        XCTAssertEqual(AIInsight.Category.folder.icon, "folder")
        XCTAssertEqual(AIInsight.Category.constraint.icon, "exclamationmark.triangle")
        XCTAssertEqual(AIInsight.Category.decision.icon, "arrow.right")
        XCTAssertEqual(AIInsight.Category.general.icon, "brain")
    }
    
    func testAIInsightCategoryColors() {
        XCTAssertEqual(AIInsight.Category.file.color, "blue")
        XCTAssertEqual(AIInsight.Category.folder.color, "orange")
        XCTAssertEqual(AIInsight.Category.constraint.color, "yellow")
        XCTAssertEqual(AIInsight.Category.decision.color, "green")
        XCTAssertEqual(AIInsight.Category.general.color, "secondary")
    }
    
    // MARK: - State Transition Tests
    
    func testValidStateTransitions() {
        XCTAssertTrue(OrganizationState.canTransition(from: .idle, to: .scanning))
        XCTAssertTrue(OrganizationState.canTransition(from: .scanning, to: .organizing))
        XCTAssertTrue(OrganizationState.canTransition(from: .organizing, to: .ready))
        XCTAssertTrue(OrganizationState.canTransition(from: .ready, to: .applying))
        XCTAssertTrue(OrganizationState.canTransition(from: .applying, to: .completed))
    }
    
    func testInvalidStateTransitions() {
        XCTAssertFalse(OrganizationState.canTransition(from: .idle, to: .applying))
        XCTAssertFalse(OrganizationState.canTransition(from: .completed, to: .applying))
        XCTAssertFalse(OrganizationState.canTransition(from: .idle, to: .ready))
    }
    
    func testTransitionMethodUpdatesState() {
        XCTAssertEqual(organizer.state, .idle)
        
        let result = organizer.transition(to: .scanning)
        XCTAssertTrue(result)
        XCTAssertEqual(organizer.state, .scanning)
    }
    
    func testInvalidTransitionDoesNotChangeState() {
        XCTAssertEqual(organizer.state, .idle)
        
        let result = organizer.transition(to: .applying)
        XCTAssertFalse(result)
        XCTAssertEqual(organizer.state, .idle)
    }
    
    func testForceTransitionBypassesValidation() {
        XCTAssertEqual(organizer.state, .idle)
        
        let result = organizer.transition(to: .applying, force: true)
        XCTAssertTrue(result)
        XCTAssertEqual(organizer.state, .applying)
    }
    
    func testResetToIdleState() {
        _ = organizer.transition(to: .scanning)
        XCTAssertEqual(organizer.state, .scanning)
        
        organizer.resetToIdleState()
        XCTAssertEqual(organizer.state, .idle)
    }
}
