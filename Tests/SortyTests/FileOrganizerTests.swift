import XCTest
@testable import SortyLib

// Mock AI Client for testing
actor MockAIClient: AIClientProtocol, @unchecked Sendable {
    let config: AIConfig
    var analyzeHandler: (([FileItem]) async throws -> OrganizationPlan)?
    @MainActor weak var streamingDelegate: StreamingDelegate?

    init(config: AIConfig) {
        self.config = config
    }

    func analyze(files: [FileItem], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan {
        if let handler = analyzeHandler {
            return try await handler(files)
        }
        return OrganizationPlan(suggestions: [], unorganizedFiles: [], notes: "")
    }

    func setHandler(_ handler: @escaping @Sendable ([FileItem]) async throws -> OrganizationPlan) {
        self.analyzeHandler = handler
    }

    func generateText(prompt: String, systemPrompt: String?) async throws -> String {
        return "Mock response"
    }
}

class SortyTests: XCTestCase {

    var folderOrganizer: FolderOrganizer!
    var mockClient: MockAIClient!
    var tempDirectory: URL!

    @MainActor
    override func setUp() async throws {
        try await super.setUp()
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
        try await super.tearDown()
    }

    @MainActor
    func testOrganizeFlow() async throws {
        // 1. Setup: Create a dummy file to scan
        let dummyFileURL = tempDirectory.appendingPathComponent("test.txt")
        try "content".write(to: dummyFileURL, atomically: true, encoding: .utf8)

        // 2. Setup: Inject mock client
        folderOrganizer.aiClient = mockClient

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
    func testClientNotConfiguredError() async {
        // Ensure client is nil
        folderOrganizer.aiClient = nil

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

        folderOrganizer.aiClient = mockClient

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

        folderOrganizer.aiClient = mockClient
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
}
