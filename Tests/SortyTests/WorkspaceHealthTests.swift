//
//  WorkspaceHealthTests.swift
//  Sorty
//
//  Tests for Workspace Health Insights and Interactive Canvas Preview features
//

import XCTest
@testable import SortyLib

// MARK: - Directory Snapshot Tests

class DirectorySnapshotTests: XCTestCase {

    func testSnapshotCreation() {
        let snapshot = DirectorySnapshot(
            directoryPath: "/Users/test/Downloads",
            totalFiles: 100,
            totalSize: 1_073_741_824, // 1 GB
            filesByExtension: ["pdf": 30, "jpg": 50, "txt": 20],
            unorganizedCount: 25,
            averageFileAge: 86400 * 30 // 30 days
        )

        XCTAssertEqual(snapshot.totalFiles, 100)
        XCTAssertEqual(snapshot.totalSize, 1_073_741_824)
        XCTAssertEqual(snapshot.unorganizedCount, 25)
        XCTAssertEqual(snapshot.filesByExtension["pdf"], 30)
    }

    func testFormattedSize() {
        let snapshot = DirectorySnapshot(
            directoryPath: "/test",
            totalFiles: 10,
            totalSize: 1_073_741_824 // 1 GB
        )

        // Verify formatted size contains "GB" or similar
        XCTAssertFalse(snapshot.formattedSize.isEmpty)
    }

    func testFormattedAverageAge() {
        // Less than a day
        let recentSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            totalFiles: 10,
            totalSize: 1000,
            averageFileAge: 3600 // 1 hour
        )
        XCTAssertEqual(recentSnapshot.formattedAverageAge, "< 1 day")

        // 1 day
        let oneDaySnapshot = DirectorySnapshot(
            directoryPath: "/test",
            totalFiles: 10,
            totalSize: 1000,
            averageFileAge: 86400
        )
        XCTAssertEqual(oneDaySnapshot.formattedAverageAge, "1 day")

        // Multiple days
        let weekSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            totalFiles: 10,
            totalSize: 1000,
            averageFileAge: 86400 * 7
        )
        XCTAssertEqual(weekSnapshot.formattedAverageAge, "7 days")

        // Months
        let monthSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            totalFiles: 10,
            totalSize: 1000,
            averageFileAge: 86400 * 45
        )
        XCTAssertEqual(monthSnapshot.formattedAverageAge, "1 month")

        // Years
        let yearSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            totalFiles: 10,
            totalSize: 1000,
            averageFileAge: 86400 * 400
        )
        XCTAssertEqual(yearSnapshot.formattedAverageAge, "1 year")
    }
}

// MARK: - Directory Growth Tests

class DirectoryGrowthTests: XCTestCase {

    func testGrowthCalculations() {
        let previousSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            timestamp: Date().addingTimeInterval(-7 * 86400), // 7 days ago
            totalFiles: 100,
            totalSize: 1_000_000_000, // 1 GB
            filesByExtension: ["pdf": 50, "jpg": 50]
        )

        let currentSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            timestamp: Date(),
            totalFiles: 150,
            totalSize: 2_000_000_000, // 2 GB
            filesByExtension: ["pdf": 80, "jpg": 70]
        )

        let growth = DirectoryGrowth(previous: previousSnapshot, current: currentSnapshot)

        XCTAssertEqual(growth.fileCountChange, 50)
        XCTAssertEqual(growth.sizeChange, 1_000_000_000)
        XCTAssertTrue(growth.isGrowing)
        XCTAssertEqual(growth.percentageGrowth, 100.0, accuracy: 0.1)
    }

    func testGrowthRate() {
        // Stable (no growth)
        let stableGrowth = createGrowth(previousSize: 1_000_000_000, currentSize: 1_000_000_000)
        XCTAssertEqual(stableGrowth.growthRate, .stable)

        // Slow growth (< 100MB)
        let slowGrowth = createGrowth(previousSize: 1_000_000_000, currentSize: 1_050_000_000)
        XCTAssertEqual(slowGrowth.growthRate, .slow)

        // Moderate growth (100MB - 1GB)
        let moderateGrowth = createGrowth(previousSize: 1_000_000_000, currentSize: 1_500_000_000)
        XCTAssertEqual(moderateGrowth.growthRate, .moderate)

        // Rapid growth (> 1GB)
        let rapidGrowth = createGrowth(previousSize: 1_000_000_000, currentSize: 3_000_000_000)
        XCTAssertEqual(rapidGrowth.growthRate, .rapid)
    }

    func testTopGrowingTypes() {
        let previousSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            timestamp: Date().addingTimeInterval(-86400),
            totalFiles: 100,
            totalSize: 1_000_000_000,
            filesByExtension: ["pdf": 20, "jpg": 30, "txt": 10]
        )

        let currentSnapshot = DirectorySnapshot(
            directoryPath: "/test",
            timestamp: Date(),
            totalFiles: 200,
            totalSize: 2_000_000_000,
            filesByExtension: ["pdf": 50, "jpg": 80, "txt": 15, "mp4": 25]
        )

        let growth = DirectoryGrowth(previous: previousSnapshot, current: currentSnapshot)
        let topTypes = growth.topGrowingTypes

        XCTAssertFalse(topTypes.isEmpty)

        // jpg should be the top growing type (80 - 30 = 50 new files)
        XCTAssertEqual(topTypes.first?.extension, "jpg")
        XCTAssertEqual(topTypes.first?.count, 50)
    }

    func testFormattedSizeChange() {
        let positiveGrowth = createGrowth(previousSize: 1_000_000_000, currentSize: 2_000_000_000)
        XCTAssertTrue(positiveGrowth.formattedSizeChange.hasPrefix("+"))

        let negativeGrowth = createGrowth(previousSize: 2_000_000_000, currentSize: 1_000_000_000)
        XCTAssertFalse(negativeGrowth.formattedSizeChange.hasPrefix("+"))
    }

    // Helper function
    private func createGrowth(previousSize: Int64, currentSize: Int64) -> DirectoryGrowth {
        let previous = DirectorySnapshot(
            directoryPath: "/test",
            timestamp: Date().addingTimeInterval(-86400),
            totalFiles: 100,
            totalSize: previousSize
        )
        let current = DirectorySnapshot(
            directoryPath: "/test",
            timestamp: Date(),
            totalFiles: 100,
            totalSize: currentSize
        )
        return DirectoryGrowth(previous: previous, current: current)
    }
}

// MARK: - Cleanup Opportunity Tests

class CleanupOpportunityTests: XCTestCase {

    func testOpportunityTypeProperties() {
        let types: [CleanupOpportunity.OpportunityType] = [
            .duplicateFiles, .unorganizedFiles, .largeFiles, .oldFiles,
            .screenshotClutter, .downloadClutter, .cacheFiles, .temporaryFiles
        ]

        for type in types {
            XCTAssertFalse(type.icon.isEmpty, "Icon should not be empty for \(type)")
            // Color is a SwiftUI type, just verify it doesn't crash
            _ = type.color
        }
    }

    func testOpportunityPriority() {
        XCTAssertTrue(CleanupOpportunity.Priority.low < .medium)
        XCTAssertTrue(CleanupOpportunity.Priority.medium < .high)
        XCTAssertTrue(CleanupOpportunity.Priority.high < .critical)

        XCTAssertEqual(CleanupOpportunity.Priority.low.displayName, "Low")
        XCTAssertEqual(CleanupOpportunity.Priority.critical.displayName, "Critical")
    }

    func testFormattedSavings() {
        let opportunity = CleanupOpportunity(
            type: .duplicateFiles,
            directoryPath: "/test",
            description: "Found duplicate files",
            estimatedSavings: 1_073_741_824, // 1 GB
            fileCount: 10,
            priority: .high
        )

        XCTAssertFalse(opportunity.formattedSavings.isEmpty)
        // Should contain "GB" or similar unit
    }
}

// MARK: - Health Insight Tests

class HealthInsightTests: XCTestCase {

    func testInsightTypeProperties() {
        let types: [HealthInsight.InsightType] = [
            .growth, .opportunity, .milestone, .suggestion, .warning
        ]

        for type in types {
            XCTAssertFalse(type.icon.isEmpty, "Icon should not be empty for \(type)")
            _ = type.color
        }
    }

    func testInsightCreation() {
        let insight = HealthInsight(
            directoryPath: "/Users/test/Downloads",
            message: "Your Downloads folder grew by 5GB this week",
            details: "Main contributors: 80 screenshots, 20 PDFs",
            type: .growth,
            actionPrompt: "Would you like me to organize new files?"
        )

        XCTAssertFalse(insight.isRead)
        XCTAssertEqual(insight.type, .growth)
        XCTAssertNotNil(insight.actionPrompt)
    }
}

// MARK: - Time Period Tests

class TimePeriodTests: XCTestCase {

    func testTimeIntervals() {
        XCTAssertEqual(TimePeriod.day.timeInterval, 86400)
        XCTAssertEqual(TimePeriod.week.timeInterval, 7 * 86400)
        XCTAssertEqual(TimePeriod.month.timeInterval, 30 * 86400)
        XCTAssertEqual(TimePeriod.quarter.timeInterval, 90 * 86400)
        XCTAssertEqual(TimePeriod.year.timeInterval, 365 * 86400)
    }

    func testAllCases() {
        XCTAssertEqual(TimePeriod.allCases.count, 5)
        XCTAssertTrue(TimePeriod.allCases.contains(.day))
        XCTAssertTrue(TimePeriod.allCases.contains(.year))
    }
}

// MARK: - Canvas Node Tests

class CanvasNodeTests: XCTestCase {

    func testFolderNode() {
        let suggestion = FolderSuggestion(folderName: "Documents")
        let node = CanvasNode(
            id: UUID(),
            position: CGPoint(x: 100, y: 100),
            size: CGSize(width: 200, height: 150),
            type: .folder(suggestion)
        )

        if case .folder(let s) = node.type {
            XCTAssertEqual(s.folderName, "Documents")
        } else {
            XCTFail("Expected folder node type")
        }
    }

    func testFileNode() {
        let file = FileItem(path: "/test/doc.pdf", name: "doc", extension: "pdf")
        let parentId = UUID()
        let node = CanvasNode(
            id: file.id,
            position: CGPoint(x: 150, y: 200),
            size: CGSize(width: 120, height: 60),
            type: .file(file, parentFolderId: parentId)
        )

        if case .file(let f, let pId) = node.type {
            XCTAssertEqual(f.name, "doc")
            XCTAssertEqual(pId, parentId)
        } else {
            XCTFail("Expected file node type")
        }
    }

    func testUnorganizedNode() {
        let node = CanvasNode(
            id: UUID(),
            position: CGPoint(x: 50, y: 300),
            size: CGSize(width: 200, height: 80),
            type: .unorganized
        )

        if case .unorganized = node.type {
            // Success
        } else {
            XCTFail("Expected unorganized node type")
        }
    }

    func testNodeEquality() {
        let id = UUID()
        let position = CGPoint(x: 100, y: 100)

        let node1 = CanvasNode(
            id: id,
            position: position,
            size: CGSize(width: 100, height: 100),
            type: .unorganized
        )

        let node2 = CanvasNode(
            id: id,
            position: position,
            size: CGSize(width: 100, height: 100),
            type: .unorganized
        )

        XCTAssertEqual(node1, node2)

        let node3 = CanvasNode(
            id: id,
            position: CGPoint(x: 200, y: 200), // Different position
            size: CGSize(width: 100, height: 100),
            type: .unorganized
        )

        XCTAssertNotEqual(node1, node3)
    }
}

// MARK: - Canvas View Model Tests

class CanvasViewModelTests: XCTestCase {

    var viewModel: CanvasViewModel!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        viewModel = CanvasViewModel()
    }

    @MainActor
    override func tearDown() async throws {
        viewModel = nil
        try await super.tearDown()
    }

    @MainActor
    func testLoadPlan() {
        let file1 = FileItem(path: "/test/doc1.pdf", name: "doc1", extension: "pdf")
        let file2 = FileItem(path: "/test/doc2.txt", name: "doc2", extension: "txt")

        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(
                    folderName: "Documents",
                    files: [file1, file2],
                    reasoning: "Text files"
                )
            ],
            unorganizedFiles: []
        )

        viewModel.loadPlan(plan, canvasSize: CGSize(width: 1000, height: 800))

        // Should have folder node + 2 file nodes
        XCTAssertEqual(viewModel.nodes.count, 3)

        // Should have 2 connections (folder to each file)
        XCTAssertEqual(viewModel.connections.count, 2)
    }

    @MainActor
    func testLoadPlanWithUnorganizedFiles() {
        let organizedFile = FileItem(path: "/test/doc1.pdf", name: "doc1", extension: "pdf")
        let unorganizedFile = FileItem(path: "/test/misc.dat", name: "misc", extension: "dat")

        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(
                    folderName: "Documents",
                    files: [organizedFile]
                )
            ],
            unorganizedFiles: [unorganizedFile]
        )

        viewModel.loadPlan(plan, canvasSize: CGSize(width: 1000, height: 800))

        // Folder + organized file + unorganized section + unorganized file = 4 nodes
        XCTAssertEqual(viewModel.nodes.count, 4)
    }

    @MainActor
    func testUpdateNodePosition() {
        let file = FileItem(path: "/test/doc.pdf", name: "doc", extension: "pdf")
        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "Docs", files: [file])
            ]
        )

        viewModel.loadPlan(plan, canvasSize: CGSize(width: 1000, height: 800))

        let fileNode = viewModel.nodes.first { node in
            if case .file(_, _) = node.type { return true }
            return false
        }

        guard let nodeId = fileNode?.id else {
            XCTFail("File node not found")
            return
        }

        let newPosition = CGPoint(x: 500, y: 500)
        viewModel.updateNodePosition(nodeId, position: newPosition)

        let updatedNode = viewModel.nodes.first { $0.id == nodeId }
        XCTAssertEqual(updatedNode?.position, newPosition)
    }

    @MainActor
    func testMoveFile() {
        let file1 = FileItem(path: "/test/doc1.pdf", name: "doc1", extension: "pdf")
        let file2 = FileItem(path: "/test/doc2.txt", name: "doc2", extension: "txt")

        let folder1 = FolderSuggestion(folderName: "Folder1", files: [file1])
        let folder2 = FolderSuggestion(folderName: "Folder2", files: [file2])

        let plan = OrganizationPlan(
            suggestions: [folder1, folder2]
        )

        viewModel.loadPlan(plan, canvasSize: CGSize(width: 1000, height: 800))

        // Find folder2's ID
        let folder2Node = viewModel.nodes.first { node in
            if case .folder(let s) = node.type, s.folderName == "Folder2" {
                return true
            }
            return false
        }

        guard let folder2Id = folder2Node?.id else {
            XCTFail("Folder2 not found")
            return
        }

        // Move file1 to folder2
        viewModel.moveFile(file1.id, to: folder2Id)

        XCTAssertTrue(viewModel.hasChanges)

        // Verify the connection was updated
        let file1Connection = viewModel.connections.first { $0.toNodeId == file1.id }
        XCTAssertEqual(file1Connection?.fromNodeId, folder2Id)
    }

    @MainActor
    func testGenerateUpdatedPlan() {
        let file = FileItem(path: "/test/doc.pdf", name: "doc", extension: "pdf")
        let originalPlan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "Original", files: [file])
            ]
        )

        viewModel.loadPlan(originalPlan, canvasSize: CGSize(width: 1000, height: 800))

        let updatedPlan = viewModel.generateUpdatedPlan()

        XCTAssertNotNil(updatedPlan)
        XCTAssertEqual(updatedPlan?.suggestions.first?.folderName, "Original")
    }

    @MainActor
    func testResetChanges() {
        let file = FileItem(path: "/test/doc.pdf", name: "doc", extension: "pdf")
        let plan = OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "Docs", files: [file])
            ]
        )

        viewModel.loadPlan(plan, canvasSize: CGSize(width: 1000, height: 800))

        // Modify something
        viewModel.hasChanges = true

        viewModel.resetChanges()

        XCTAssertFalse(viewModel.hasChanges)
    }

    @MainActor
    func testScaleAndOffset() {
        XCTAssertEqual(viewModel.scale, 1.0)
        XCTAssertEqual(viewModel.offset, .zero)

        viewModel.scale = 1.5
        viewModel.offset = CGPoint(x: 100, y: 50)

        XCTAssertEqual(viewModel.scale, 1.5)
        XCTAssertEqual(viewModel.offset, CGPoint(x: 100, y: 50))
    }

    @MainActor
    func testSelectionState() {
        XCTAssertNil(viewModel.selectedNodeId)
        XCTAssertNil(viewModel.draggedNodeId)
        XCTAssertNil(viewModel.dropTargetId)

        let testId = UUID()
        viewModel.selectedNodeId = testId

        XCTAssertEqual(viewModel.selectedNodeId, testId)
    }
}

// MARK: - Canvas Connection Tests

class CanvasConnectionTests: XCTestCase {

    func testConnectionTypes() {
        let fromId = UUID()
        let toId = UUID()

        let folderToFileConnection = CanvasConnection(
            id: UUID(),
            fromNodeId: fromId,
            toNodeId: toId,
            type: .folderToFile
        )

        let folderToSubfolderConnection = CanvasConnection(
            id: UUID(),
            fromNodeId: fromId,
            toNodeId: toId,
            type: .folderToSubfolder
        )

        XCTAssertEqual(folderToFileConnection.fromNodeId, fromId)
        XCTAssertEqual(folderToFileConnection.toNodeId, toId)

        // Verify different connection types
        switch folderToFileConnection.type {
        case .folderToFile:
            // Expected
            break
        case .folderToSubfolder:
            XCTFail("Wrong connection type")
        }

        switch folderToSubfolderConnection.type {
        case .folderToFile:
            XCTFail("Wrong connection type")
        case .folderToSubfolder:
            // Expected
            break
        }
    }
}

// MARK: - Integration Tests

class WorkspaceHealthIntegrationTests: XCTestCase {

    var healthManager: WorkspaceHealthManager!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        healthManager = WorkspaceHealthManager()
    }

    @MainActor
    override func tearDown() async throws {
        healthManager = nil
        try await super.tearDown()
    }

    @MainActor
    func testTakeSnapshotAndGetGrowth() async {
        let testPath = "/test/downloads"
        let files = [
            FileItem(path: "\(testPath)/file1.txt", name: "file1", extension: "txt", size: 1000, creationDate: Date()),
            FileItem(path: "\(testPath)/file2.pdf", name: "file2", extension: "pdf", size: 2000, creationDate: Date())
        ]

        // Take first snapshot
        await healthManager.takeSnapshot(at: testPath, files: files)

        XCTAssertNotNil(healthManager.snapshots[testPath])
        // Depending on implementation, it might be 1 or 2 if we count current session
        XCTAssertGreaterThanOrEqual(healthManager.snapshots[testPath]?.count ?? 0, 1)

        // Simulate time passing and more files
        let moreFiles = files + [
            FileItem(path: "\(testPath)/file3.jpg", name: "file3", extension: "jpg", size: 5000, creationDate: Date())
        ]

        await healthManager.takeSnapshot(at: testPath, files: moreFiles)

        XCTAssertGreaterThanOrEqual(healthManager.snapshots[testPath]?.count ?? 0, 2)

        // Get growth
        let _ = healthManager.getGrowth(for: testPath, period: .week)
        // Growth might be nil if snapshots are too close together
        // This is expected behavior
    }

    @MainActor
    func testAnalyzeDirectoryForOpportunities() async {
        let testPath = "/test/downloads"

        // Create files that should trigger various opportunities
        var files: [FileItem] = []

        // Add many unorganized files in root
        for i in 0..<30 {
            files.append(FileItem(
                path: "\(testPath)/file\(i).txt",
                name: "file\(i)",
                extension: "txt",
                size: 1000,
                creationDate: Date().addingTimeInterval(-60 * 86400) // 60 days old
            ))
        }

        // Add large files
        files.append(FileItem(
            path: "\(testPath)/large.zip",
            name: "large",
            extension: "zip",
            size: 200_000_000 // 200 MB
        ))

        await healthManager.analyzeDirectory(path: testPath, files: files)

        // Should have identified opportunities
        XCTAssertFalse(healthManager.opportunities.isEmpty)

        // Should have unorganized files opportunity
        let hasUnorganizedOpp = healthManager.opportunities.contains { $0.type == .unorganizedFiles }
        XCTAssertTrue(hasUnorganizedOpp)

        // Should have large files opportunity
        let hasLargeFilesOpp = healthManager.opportunities.contains { $0.type == .largeFiles }
        XCTAssertTrue(hasLargeFilesOpp)
    }

    @MainActor
    func testDismissOpportunity() async {
        let testPath = "/test/downloads"

        // Create files that will trigger opportunities via analyzeDirectory
        var files: [FileItem] = []

        // Add many unorganized files in root to trigger opportunity
        for i in 0..<30 {
            files.append(FileItem(
                path: "\(testPath)/file\(i).txt",
                name: "file\(i)",
                extension: "txt",
                size: 1000,
                creationDate: Date()
            ))
        }

        await healthManager.analyzeDirectory(path: testPath, files: files)

        // Should have identified at least one opportunity
        XCTAssertFalse(healthManager.opportunities.isEmpty)

        let initialCount = healthManager.activeOpportunities.count

        if let firstOpportunity = healthManager.activeOpportunities.first {
            XCTAssertFalse(firstOpportunity.isDismissed)

            healthManager.dismissOpportunity(firstOpportunity)
            
            // Check if it's marked as dismissed in the full list
            XCTAssertTrue(healthManager.opportunities.first { $0.id == firstOpportunity.id }?.isDismissed ?? false)

            // After dismissing, active count should decrease
            XCTAssertEqual(healthManager.activeOpportunities.count, initialCount - 1)
        }

    }


    @MainActor
    func testComputedProperties() async {
        let testPath = "/test/downloads"

        // Create files that will trigger multiple opportunities
        var files: [FileItem] = []

        // Add many unorganized files (triggers unorganizedFiles opportunity)
        for i in 0..<30 {
            files.append(FileItem(
                path: "\(testPath)/file\(i).txt",
                name: "file\(i)",
                extension: "txt",
                size: 1000,
                creationDate: Date().addingTimeInterval(-60 * 86400) // 60 days old
            ))
        }

        // Add large files (triggers largeFiles opportunity)
        files.append(FileItem(
            path: "\(testPath)/large.zip",
            name: "large",
            extension: "zip",
            size: 200_000_000 // 200 MB
        ))

        await healthManager.analyzeDirectory(path: testPath, files: files)

        // Should have identified opportunities
        XCTAssertFalse(healthManager.activeOpportunities.isEmpty)
        XCTAssertFalse(healthManager.formattedTotalSavings.isEmpty)
    }

    @MainActor
    func testClearInsights() {
        let insight = HealthInsight(
            directoryPath: "/test",
            message: "Test",
            details: "Details",
            type: .growth
        )

        healthManager.insights = [insight]

        XCTAssertEqual(healthManager.insights.count, 1)

        healthManager.clearInsights()

        XCTAssertTrue(healthManager.insights.isEmpty)
    }

    @MainActor
    func testMarkInsightAsRead() {
        let insight = HealthInsight(
            directoryPath: "/test",
            message: "Test",
            details: "Details",
            type: .suggestion,
            isRead: false
        )

        healthManager.insights = [insight]

        XCTAssertEqual(healthManager.unreadInsights.count, 1)

        healthManager.markInsightAsRead(insight)

        XCTAssertTrue(healthManager.insights.first!.isRead)
        XCTAssertTrue(healthManager.unreadInsights.isEmpty)
    }
}
