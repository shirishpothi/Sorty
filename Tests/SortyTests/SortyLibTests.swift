import XCTest
import Combine
@testable import SortyLib

// Mock AI Client for testing
actor MockAIClient: AIClientProtocol, @unchecked Sendable {
    let config: AIConfig
    var analyzeHandler: (([FileItem]) async throws -> OrganizationPlan)?
    private(set) var analyzedBatchSizes: [Int] = []
    @MainActor weak var streamingDelegate: StreamingDelegate?

    init(config: AIConfig) {
        self.config = config
    }

    func analyze(files: [FileItem], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan {
        analyzedBatchSizes.append(files.count)
        if let handler = analyzeHandler {
            return try await handler(files)
        }
        return OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
    }

    func setHandler(_ handler: @escaping @Sendable ([FileItem]) async throws -> OrganizationPlan) {
        self.analyzeHandler = handler
    }

    func currentAnalyzedBatchSizes() -> [Int] {
        analyzedBatchSizes
    }

    func generateText(prompt: String, systemPrompt: String?) async throws -> String {
        return "Mock response"
    }
    
    func checkHealth() async throws {
        // Success by default
    }

    func analyzeWithImages(files: [FileItem], imageData: [String: Data], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan {
        return try await analyze(files: files, customInstructions: customInstructions, personaPrompt: personaPrompt, temperature: temperature)
    }
}

class SortyTests: XCTestCase {

    var folderOrganizer: FolderOrganizer!
    var mockClient: MockAIClient!
    var tempDirectory: URL!

    @MainActor
    override func setUp() async throws {
        
        folderOrganizer = FolderOrganizer()
        let config = AIConfig(apiKey: "test-key", model: "test-model")
        mockClient = MockAIClient(config: config)

        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    @MainActor
    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        folderOrganizer = nil
        mockClient = nil
        
    }

    @MainActor
    func testOrganizeFlow() async throws {
        // 1. Setup: Create a dummy file to scan
        let dummyFileURL = tempDirectory.appendingPathComponent("test.txt")
        try "content".write(to: dummyFileURL, atomically: true, encoding: .utf8)

        // 2. Setup: Inject mock client
        folderOrganizer.setAIClientForTesting(mockClient)

        // 3. Setup: Define mock behavior
        await mockClient.setHandler { files in
            // Verify we received the file
            XCTAssertEqual(files.count, 1)
            XCTAssertEqual(files.first?.name, "test")

            return OrganizationPlan(
                suggestions: [
                    FolderSuggestion(folderName: "Docs", description: "Text", files: files, subfolders: [], reasoning: "Text")
                ],
                unorganizedFiles: [],
                notes: "Test Plan"
            )
        }

        // 4. Act
        try await folderOrganizer.organize(directory: tempDirectory)

        // 5. Assert
        XCTAssertEqual(folderOrganizer.state, .ready)
        XCTAssertNotNil(folderOrganizer.currentPlan)
        XCTAssertEqual(folderOrganizer.currentPlan?.suggestions.first?.folderName, "Docs")
    }

    @MainActor
    func testLargeOrganizeFlowUsesBoundedAIBatches() async throws {
        for index in 0..<351 {
            let fileURL = tempDirectory.appendingPathComponent("file-\(index).txt")
            try Data().write(to: fileURL)
        }

        folderOrganizer.setAIClientForTesting(mockClient)
        await mockClient.setHandler { files in
            OrganizationPlan(
                suggestions: [
                    FolderSuggestion(folderName: "Documents", files: files)
                ]
            )
        }

        try await folderOrganizer.organize(directory: tempDirectory)
        let batchSizes = await mockClient.currentAnalyzedBatchSizes()

        XCTAssertEqual(batchSizes, [350, 1])
        XCTAssertEqual(folderOrganizer.currentPlan?.totalFiles, 351)
        XCTAssertEqual(folderOrganizer.currentPlan?.suggestions.count, 1)
    }

    @MainActor
    func testLargeRenameFlowUsesSmallerBoundedAIBatches() async throws {
        for index in 0..<121 {
            let fileURL = tempDirectory.appendingPathComponent("rename-\(index).txt")
            try Data().write(to: fileURL)
        }

        let renameConfig = AIConfig(
            apiKey: "test-key",
            model: "test-model",
            mode: .renameOnly,
            enableDeepScan: false,
            enableVision: false
        )
        let renameClient = MockAIClient(config: renameConfig)
        folderOrganizer.setAIClientForTesting(renameClient)
        await renameClient.setHandler { files in
            OrganizationPlan(
                suggestions: [
                    FolderSuggestion(folderName: "", files: files)
                ]
            )
        }

        try await folderOrganizer.organize(directory: tempDirectory)
        let batchSizes = await renameClient.currentAnalyzedBatchSizes()

        XCTAssertEqual(batchSizes, [120, 1])
        XCTAssertEqual(folderOrganizer.currentPlan?.totalFiles, 121)
    }

    @MainActor
    func testOutputLimitFailureSplitsBatchAndPreservesSuccessfulResults() async throws {
        for index in 0..<16 {
            let fileURL = tempDirectory.appendingPathComponent("adaptive-\(index).txt")
            try Data().write(to: fileURL)
        }

        folderOrganizer.setAIClientForTesting(mockClient)
        await mockClient.setHandler { files in
            if files.count > 8 {
                throw AIClientError.apiError(
                    statusCode: 413,
                    message: "The model reached its output limit."
                )
            }
            return OrganizationPlan(
                suggestions: [
                    FolderSuggestion(folderName: "Documents", files: files)
                ]
            )
        }

        try await folderOrganizer.organize(directory: tempDirectory)
        let batchSizes = await mockClient.currentAnalyzedBatchSizes()

        XCTAssertEqual(batchSizes, [16, 8, 8])
        XCTAssertEqual(folderOrganizer.currentPlan?.totalFiles, 16)
        XCTAssertEqual(folderOrganizer.currentPlan?.suggestions.count, 1)
    }

    @MainActor
    func testTimeoutCanContinueFromLastCompletedBatch() async throws {
        for index in 0..<121 {
            let fileURL = tempDirectory.appendingPathComponent("resume-\(index).txt")
            try Data().write(to: fileURL)
        }

        let renameConfig = AIConfig(
            apiKey: "test-key",
            model: "test-model",
            mode: .renameOnly,
            enableDeepScan: false,
            enableVision: false
        )
        let renameClient = MockAIClient(config: renameConfig)
        let timeoutTracker = ResumeTimeoutTracker()
        folderOrganizer.setAIClientForTesting(renameClient)
        await renameClient.setHandler { files in
            try await timeoutTracker.plan(for: files)
        }

        do {
            try await folderOrganizer.organize(directory: tempDirectory)
            XCTFail("Expected the final batch to time out")
        } catch {
            XCTAssertTrue(folderOrganizer.canResumeOrganization)
        }

        try await folderOrganizer.resumeOrganization()
        let batchSizes = await renameClient.currentAnalyzedBatchSizes()

        XCTAssertEqual(batchSizes, [120, 1, 1])
        XCTAssertEqual(folderOrganizer.currentPlan?.totalFiles, 121)
        XCTAssertEqual(folderOrganizer.state, .ready)
        XCTAssertFalse(folderOrganizer.canResumeOrganization)
    }

    @MainActor
    func testClientNotConfiguredError() async {
        // Ensure client is nil
        folderOrganizer.setAIClientForTesting(nil)

        do {
            try await folderOrganizer.organize(directory: tempDirectory)
            XCTFail("Should throw error")
        } catch {
            XCTAssertEqual(error as? OrganizationError, OrganizationError.clientNotConfigured)
        }
    }

    @MainActor
    func testCancelOrganization() async throws {
        // Setup
        let dummyFileURL = tempDirectory.appendingPathComponent("test.txt")
        try "content".write(to: dummyFileURL, atomically: true, encoding: .utf8)

        folderOrganizer.setAIClientForTesting(mockClient)

        // Setup a slow handler
        await mockClient.setHandler { files in
            try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            return OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
        }

        // Start organization in background
        let task = Task {
            try await folderOrganizer.organize(directory: tempDirectory)
        }

        // Wait a bit then cancel
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        folderOrganizer.cancel()

        // Verify state is idle after cancel
        XCTAssertEqual(folderOrganizer.state, .idle)

        task.cancel()
    }

    @MainActor
    func testResetClearsState() async throws {
        // Setup some state
        let dummyFileURL = tempDirectory.appendingPathComponent("test.txt")
        try "content".write(to: dummyFileURL, atomically: true, encoding: .utf8)

        folderOrganizer.setAIClientForTesting(mockClient)
        await mockClient.setHandler { files in
            return OrganizationPlan(
                suggestions: [FolderSuggestion(folderName: "Test", files: files)],
                unorganizedFiles: [],
                notes: ""
            )
        }

        try await folderOrganizer.organize(directory: tempDirectory)
        XCTAssertEqual(folderOrganizer.state, .ready)
        XCTAssertNotNil(folderOrganizer.currentPlan)

        // Reset
        folderOrganizer.reset()

        // Verify reset
        XCTAssertEqual(folderOrganizer.state, .idle)
        XCTAssertNil(folderOrganizer.currentPlan)
        XCTAssertEqual(folderOrganizer.progress, 0.0)
    }
    
    @MainActor
    func testOrganizeIntoExistingDirectory() async throws {
        // Setup: Create a file and an existing directory
        let dummyFileURL = tempDirectory.appendingPathComponent("test.txt")
        try "content".write(to: dummyFileURL, atomically: true, encoding: .utf8)
        
        let existingDirURL = tempDirectory.appendingPathComponent("ExistingFolder")
        try FileManager.default.createDirectory(at: existingDirURL, withIntermediateDirectories: true)
        
        folderOrganizer.setAIClientForTesting(mockClient)
        
        // Setup: Mock returns a plan with a folder name that already exists
        await mockClient.setHandler { files in
            return OrganizationPlan(
                suggestions: [
                    FolderSuggestion(
                        folderName: "ExistingFolder",
                        description: "Test folder",
                        files: files,
                        subfolders: [],
                        reasoning: "Test"
                    )
                ],
                unorganizedFiles: [],
                notes: "Test Plan"
            )
        }
        
        // Act: This should NOT throw an error even though ExistingFolder already exists
        try await folderOrganizer.organize(directory: tempDirectory)
        
        // Assert: Organization should succeed
        XCTAssertEqual(folderOrganizer.state, .ready)
        XCTAssertNotNil(folderOrganizer.currentPlan)
        XCTAssertEqual(folderOrganizer.currentPlan?.suggestions.first?.folderName, "ExistingFolder")
    }
    
    @MainActor
    func testRejectOrganizingIntoExistingFile() async throws {
        // Setup: Create test files including one that will conflict with the suggested folder name
        let dummyFileURL = tempDirectory.appendingPathComponent("test.txt")
        try "content".write(to: dummyFileURL, atomically: true, encoding: .utf8)
        
        // Create a file (not directory) with the name we'll suggest as a folder
        let existingFileURL = tempDirectory.appendingPathComponent("ConflictingFile")
        try "existing file content".write(to: existingFileURL, atomically: true, encoding: .utf8)
        
        folderOrganizer.setAIClientForTesting(mockClient)
        
        // Setup: Mock returns a plan with a folder name that conflicts with an existing file
        await mockClient.setHandler { files in
            return OrganizationPlan(
                suggestions: [
                    FolderSuggestion(
                        folderName: "ConflictingFile",
                        description: "Test folder",
                        files: files,
                        subfolders: [],
                        reasoning: "Test"
                    )
                ],
                unorganizedFiles: [],
                notes: "Test Plan"
            )
        }
        
        // Act & Assert: This should throw a validation error because ConflictingFile exists as a file
        do {
            try await folderOrganizer.organize(directory: tempDirectory)
            XCTFail("Should have thrown a validation error")
        } catch let error as ValidationError {
            // Verify it's the correct error type
            if case .pathExists(let path) = error {
                XCTAssertTrue(path.contains("ConflictingFile"))
            } else {
                XCTFail("Wrong validation error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}

private actor ResumeTimeoutTracker {
    private var hasTimedOut = false

    func plan(for files: [FileItem]) throws -> OrganizationPlan {
        if files.count == 1, !hasTimedOut {
            hasTimedOut = true
            throw AIClientError.networkError(URLError(.timedOut))
        }
        return OrganizationPlan(
            suggestions: [
                FolderSuggestion(folderName: "", files: files)
            ]
        )
    }
}
