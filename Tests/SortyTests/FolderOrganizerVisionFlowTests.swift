import XCTest
import AppKit
@testable import SortyLib

@MainActor
final class FolderOrganizerVisionFlowTests: XCTestCase {
    private var organizer: FolderOrganizer!
    private var tempDirectory: URL!

    override func setUp() async throws {
        organizer = FolderOrganizer()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        organizer = nil
    }

    func testVisionFlowCallsAnalyzeWithImagesAndRespectsBatchSize() async throws {
        let config = AIConfig(
            provider: .openAI,
            apiURL: "https://api.openai.com",
            apiKey: "test-key",
            model: "gpt-4o",
            enableVision: true,
            visionBatchSize: 1,
            visionBatchStrategy: .firstN
        )
        try await organizer.configure(with: config)

        let mockClient = VisionFlowMockClient(config: config)
        organizer.setAIClientForTesting(mockClient)

        try createPNG(at: tempDirectory.appendingPathComponent("one.png"))
        try createPNG(at: tempDirectory.appendingPathComponent("two.png"))
        try "text".write(to: tempDirectory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        try await organizer.organize(directory: tempDirectory)

        let analyzeWithImagesCalls = await mockClient.analyzeWithImagesCalls
        let analyzeCalls = await mockClient.analyzeCalls
        let lastImageCount = await mockClient.lastImageCount

        XCTAssertEqual(analyzeWithImagesCalls, 1)
        XCTAssertEqual(analyzeCalls, 0)
        XCTAssertEqual(lastImageCount, 1)
        XCTAssertEqual(organizer.visionAnalysisSummary?.analyzedCount, 1)
        XCTAssertEqual(organizer.visionAnalysisSummary?.totalImageCount, 2)
        XCTAssertEqual(organizer.visionAnalysisSummary?.skippedCount, 1)
    }

    func testVisionUnsupportedFallsBackToTextAnalysisAndProvidesWarning() async throws {
        let config = AIConfig(
            provider: .openAI,
            apiURL: "https://api.openai.com",
            apiKey: "test-key",
            model: "gemma-flash",
            enableVision: true
        )
        try await organizer.configure(with: config)

        let mockClient = VisionFlowMockClient(config: config)
        organizer.setAIClientForTesting(mockClient)

        try createPNG(at: tempDirectory.appendingPathComponent("one.png"))

        try await organizer.organize(directory: tempDirectory)

        let analyzeWithImagesCalls = await mockClient.analyzeWithImagesCalls
        let analyzeCalls = await mockClient.analyzeCalls

        XCTAssertEqual(analyzeWithImagesCalls, 0)
        XCTAssertEqual(analyzeCalls, 1)
        XCTAssertEqual(organizer.visionAnalysisSummary?.analyzedCount, 0)
        XCTAssertEqual(organizer.visionAnalysisSummary?.skippedCount, 1)
        XCTAssertNotNil(organizer.visionAnalysisSummary?.warningMessage)
    }

    private func createPNG(at url: URL) throws {
        let size = NSSize(width: 80, height: 80)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            XCTFail("Unable to create bitmap")
            return
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemPink.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Unable to create PNG data")
            return
        }
        try data.write(to: url)
    }
}

actor VisionFlowMockClient: AIClientProtocol {
    let config: AIConfig
    @MainActor weak var streamingDelegate: StreamingDelegate?
    var analyzeCalls = 0
    var analyzeWithImagesCalls = 0
    var lastImageCount = 0

    init(config: AIConfig) {
        self.config = config
    }

    func analyze(files: [FileItem], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan {
        analyzeCalls += 1
        return OrganizationPlan(
            suggestions: [FolderSuggestion(folderName: "Grouped", files: files)],
            unorganizedFiles: [],
            notes: "ok"
        )
    }

    func analyzeWithImages(files: [FileItem], imageData: [String: Data], customInstructions: String?, personaPrompt: String?, temperature: Double?) async throws -> OrganizationPlan {
        analyzeWithImagesCalls += 1
        lastImageCount = imageData.count
        return OrganizationPlan(
            suggestions: [FolderSuggestion(folderName: "Grouped", files: files)],
            unorganizedFiles: [],
            notes: "ok"
        )
    }

    func generateText(prompt: String, systemPrompt: String?) async throws -> String {
        "ok"
    }

    func checkHealth() async throws {}
}
