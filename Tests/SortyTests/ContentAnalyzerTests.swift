//
//  ContentAnalyzerTests.swift
//  SortyTests
//
//  Comprehensive tests for ContentAnalyzer and ContentMetadata
//

import XCTest
@testable import SortyLib

// MARK: - ContentMetadata Tests (Additional Coverage)

final class ContentMetadataExtendedTests: XCTestCase {
    
    // MARK: - Initialization Tests
    
    func testDefaultInitialization() {
        let metadata = ContentMetadata()
        
        XCTAssertNil(metadata.textPreview)
        XCTAssertNil(metadata.documentTitle)
        XCTAssertNil(metadata.exifData)
        XCTAssertNil(metadata.pageCount)
        XCTAssertNil(metadata.author)
        XCTAssertNil(metadata.creationDate)
        XCTAssertNil(metadata.keywords)
        XCTAssertNil(metadata.ocrText)
        XCTAssertNil(metadata.ocrConfidence)
        XCTAssertNil(metadata.detectedKeywords)
    }
    
    func testCustomInitialization() {
        let date = Date()
        let metadata = ContentMetadata(
            textPreview: "This is a preview",
            documentTitle: "Test Document",
            exifData: ["camera": "iPhone 15", "dateTime": "2024-01-01"],
            pageCount: 5,
            author: "Test Author",
            creationDate: date,
            keywords: ["test", "document"],
            ocrText: "OCR extracted text",
            ocrConfidence: 0.95,
            detectedKeywords: ["invoice", "receipt"]
        )
        
        XCTAssertEqual(metadata.textPreview, "This is a preview")
        XCTAssertEqual(metadata.documentTitle, "Test Document")
        XCTAssertEqual(metadata.exifData?["camera"], "iPhone 15")
        XCTAssertEqual(metadata.pageCount, 5)
        XCTAssertEqual(metadata.author, "Test Author")
        XCTAssertEqual(metadata.creationDate, date)
        XCTAssertEqual(metadata.keywords, ["test", "document"])
        XCTAssertEqual(metadata.ocrText, "OCR extracted text")
        XCTAssertEqual(metadata.ocrConfidence, 0.95)
        XCTAssertEqual(metadata.detectedKeywords, ["invoice", "receipt"])
    }
    
    // MARK: - isEmpty Tests
    
    func testIsEmptyWhenAllNil() {
        let metadata = ContentMetadata()
        XCTAssertTrue(metadata.isEmpty)
    }
    
    func testIsEmptyWithTextPreview() {
        let metadata = ContentMetadata(textPreview: "Some text")
        XCTAssertFalse(metadata.isEmpty)
    }
    
    func testIsEmptyWithDocumentTitle() {
        let metadata = ContentMetadata(documentTitle: "Title")
        XCTAssertFalse(metadata.isEmpty)
    }
    
    func testIsEmptyWithExifData() {
        let metadata = ContentMetadata(exifData: ["camera": "iPhone"])
        XCTAssertFalse(metadata.isEmpty)
    }
    
    func testIsEmptyWithOCRText() {
        let metadata = ContentMetadata(ocrText: "OCR text")
        XCTAssertFalse(metadata.isEmpty)
    }
    
    func testIsEmptyIgnoresOtherFields() {
        // These fields alone should not make isEmpty false
        let metadata = ContentMetadata(
            pageCount: 10,
            author: "Author",
            keywords: ["test"]
        )
        XCTAssertTrue(metadata.isEmpty)
    }
    
    // MARK: - allTextContent Tests
    
    func testAllTextContentWhenEmpty() {
        let metadata = ContentMetadata()
        XCTAssertNil(metadata.allTextContent)
    }
    
    func testAllTextContentWithTextPreviewOnly() {
        let metadata = ContentMetadata(textPreview: "Preview text")
        XCTAssertEqual(metadata.allTextContent, "Preview text")
    }
    
    func testAllTextContentWithOCROnly() {
        let metadata = ContentMetadata(ocrText: "OCR text")
        XCTAssertEqual(metadata.allTextContent, "OCR text")
    }
    
    func testAllTextContentWithBoth() {
        let metadata = ContentMetadata(
            textPreview: "Preview text",
            ocrText: "OCR text"
        )
        XCTAssertEqual(metadata.allTextContent, "Preview text OCR text")
    }
    
    // MARK: - summary Tests
    
    func testSummaryWhenEmpty() {
        let metadata = ContentMetadata()
        XCTAssertEqual(metadata.summary, "")
    }
    
    func testSummaryWithTitle() {
        let metadata = ContentMetadata(documentTitle: "My Document")
        XCTAssertTrue(metadata.summary.contains("Title: \"My Document\""))
    }
    
    func testSummaryWithTextPreview() {
        let metadata = ContentMetadata(textPreview: "This is the content preview")
        XCTAssertTrue(metadata.summary.contains("Content:"))
        XCTAssertTrue(metadata.summary.contains("content preview"))
    }
    
    func testSummaryWithOCR() {
        let metadata = ContentMetadata(ocrText: "OCR extracted text")
        XCTAssertTrue(metadata.summary.contains("OCR:"))
    }
    
    func testSummaryWithDetectedKeywords() {
        let metadata = ContentMetadata(detectedKeywords: ["invoice", "receipt"])
        XCTAssertTrue(metadata.summary.contains("Detected:"))
        XCTAssertTrue(metadata.summary.contains("invoice"))
    }
    
    func testSummaryWithCameraInfo() {
        let metadata = ContentMetadata(exifData: ["camera": "iPhone 15 Pro"])
        XCTAssertTrue(metadata.summary.contains("Camera: iPhone 15 Pro"))
    }
    
    func testSummaryWithDateTime() {
        let metadata = ContentMetadata(exifData: ["dateTime": "2024-01-15 10:30:00"])
        XCTAssertTrue(metadata.summary.contains("Taken:"))
    }
    
    func testSummaryWithPageCount() {
        let metadata = ContentMetadata(pageCount: 42)
        XCTAssertTrue(metadata.summary.contains("42 pages"))
    }
    
    func testSummaryWithMultipleFields() {
        let metadata = ContentMetadata(
            textPreview: "Preview",
            documentTitle: "Title",
            pageCount: 5
        )
        
        let summary = metadata.summary
        XCTAssertTrue(summary.hasPrefix("["))
        XCTAssertTrue(summary.hasSuffix("]"))
        XCTAssertTrue(summary.contains(","))
    }
    
    // MARK: - Codable Tests
    
    func testCodable() throws {
        let original = ContentMetadata(
            textPreview: "Preview",
            documentTitle: "Title",
            exifData: ["camera": "iPhone"],
            pageCount: 10,
            author: "Author",
            creationDate: Date(),
            keywords: ["test"],
            ocrText: "OCR",
            ocrConfidence: 0.9,
            detectedKeywords: ["keyword"]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ContentMetadata.self, from: data)
        
        XCTAssertEqual(decoded.textPreview, original.textPreview)
        XCTAssertEqual(decoded.documentTitle, original.documentTitle)
        XCTAssertEqual(decoded.exifData, original.exifData)
        XCTAssertEqual(decoded.pageCount, original.pageCount)
        XCTAssertEqual(decoded.author, original.author)
        XCTAssertEqual(decoded.keywords, original.keywords)
        XCTAssertEqual(decoded.ocrText, original.ocrText)
        XCTAssertEqual(decoded.ocrConfidence, original.ocrConfidence)
        XCTAssertEqual(decoded.detectedKeywords, original.detectedKeywords)
    }
    
    // MARK: - Hashable Tests
    
    func testHashable() {
        let metadata1 = ContentMetadata(textPreview: "Same", documentTitle: "Same")
        let metadata2 = ContentMetadata(textPreview: "Same", documentTitle: "Same")
        let metadata3 = ContentMetadata(textPreview: "Different", documentTitle: "Different")
        
        XCTAssertEqual(metadata1.hashValue, metadata2.hashValue)
        XCTAssertNotEqual(metadata1.hashValue, metadata3.hashValue)
    }
    
    func testHashableInSet() {
        var set = Set<ContentMetadata>()
        
        let metadata1 = ContentMetadata(textPreview: "Test")
        let metadata2 = ContentMetadata(textPreview: "Test")
        let metadata3 = ContentMetadata(textPreview: "Other")
        
        set.insert(metadata1)
        set.insert(metadata2)
        set.insert(metadata3)
        
        XCTAssertEqual(set.count, 2) // metadata1 and metadata2 are equal
    }
    
    // MARK: - Sendable Conformance
    
    func testSendableConformance() {
        let metadata = ContentMetadata(textPreview: "Test")
        
        Task {
            let _ = metadata.textPreview
        }
        
        XCTAssertTrue(true) // If we got here, Sendable works
    }
}

// MARK: - ContentAnalyzer Tests

final class ContentAnalyzerTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() async {
        let analyzer = ContentAnalyzer()
        // Should initialize without errors
        XCTAssertNotNil(analyzer)
    }
    
    func testConfigurationDefaults() async {
        let analyzer = ContentAnalyzer()
        
        // Access properties to verify they're accessible
        let enableOCR = await analyzer.enableOCR
        let enableDeepScan = await analyzer.enableDeepDocumentScan
        
        XCTAssertTrue(enableOCR)
        XCTAssertTrue(enableDeepScan)
    }
    
    func testConfigurationModification() async {
        let analyzer = ContentAnalyzer()
        
        await analyzer.setEnableOCR(false)
        await analyzer.setEnableDeepDocumentScan(false)
        
        let enableOCR = await analyzer.enableOCR
        let enableDeepScan = await analyzer.enableDeepDocumentScan
        
        XCTAssertFalse(enableOCR)
        XCTAssertFalse(enableDeepScan)
    }
    
    // MARK: - Analyze Non-Existent File
    
    func testAnalyzeNonExistentFile() async {
        let analyzer = ContentAnalyzer()
        let nonExistentURL = URL(fileURLWithPath: "/path/that/does/not/exist.txt")
        
        let result = await analyzer.analyze(fileURL: nonExistentURL)
        
        XCTAssertNil(result)
    }
    
    // MARK: - Analyze Unsupported File Type
    
    func testAnalyzeUnsupportedFileType() async throws {
        let analyzer = ContentAnalyzer()
        
        let unsupportedFile = tempDirectory.appendingPathComponent("test.xyz")
        try "some content".write(to: unsupportedFile, atomically: true, encoding: .utf8)
        
        let result = await analyzer.analyze(fileURL: unsupportedFile)
        
        XCTAssertNil(result)
    }
    
    // MARK: - Text File Analysis
    
    func testAnalyzeTextFile() async throws {
        let analyzer = ContentAnalyzer()
        
        let textFile = tempDirectory.appendingPathComponent("test.txt")
        let content = "This is a test text file with some content for analysis."
        try content.write(to: textFile, atomically: true, encoding: .utf8)
        
        let result = await analyzer.analyze(fileURL: textFile)
        
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.textPreview, content)
    }
    
    func testAnalyzeMarkdownFile() async throws {
        let analyzer = ContentAnalyzer()
        
        let mdFile = tempDirectory.appendingPathComponent("README.md")
        let content = "# Heading\n\nThis is markdown content."
        try content.write(to: mdFile, atomically: true, encoding: .utf8)
        
        let result = await analyzer.analyze(fileURL: mdFile)
        
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.textPreview?.contains("Heading") ?? false)
    }
    
    func testAnalyzeLargeTextFile() async throws {
        let analyzer = ContentAnalyzer()
        
        let textFile = tempDirectory.appendingPathComponent("large.txt")
        // Create content larger than maxBytesToRead (4KB) and maxPreviewLength (800)
        let content = String(repeating: "A", count: 5000)
        try content.write(to: textFile, atomically: true, encoding: .utf8)
        
        let result = await analyzer.analyze(fileURL: textFile)
        
        XCTAssertNotNil(result)
        // Should be truncated to maxPreviewLength
        XCTAssertLessThanOrEqual(result?.textPreview?.count ?? 0, 800)
    }
    
    // MARK: - Batch Analysis
    
    func testAnalyzeFilesEmpty() async {
        let analyzer = ContentAnalyzer()
        
        let results = await analyzer.analyzeFiles([])
        
        XCTAssertTrue(results.isEmpty)
    }
    
    func testAnalyzeFilesWithProgress() async throws {
        let analyzer = ContentAnalyzer()
        
        // Create test files
        let file1 = tempDirectory.appendingPathComponent("file1.txt")
        let file2 = tempDirectory.appendingPathComponent("file2.txt")
        
        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)
        
        var progressUpdates: [(current: Int, total: Int)] = []
        
        let results = await analyzer.analyzeFiles([file1, file2]) { current, total in
            progressUpdates.append((current, total))
        }
        
        XCTAssertEqual(results.count, 2)
        XCTAssertNotNil(results[file1])
        XCTAssertNotNil(results[file2])
        
        // Should have received progress updates
        XCTAssertEqual(progressUpdates.count, 2)
        XCTAssertEqual(progressUpdates.last?.current, 2)
        XCTAssertEqual(progressUpdates.last?.total, 2)
    }
    
    func testAnalyzeFilesMixedTypes() async throws {
        let analyzer = ContentAnalyzer()
        
        let textFile = tempDirectory.appendingPathComponent("test.txt")
        let unsupportedFile = tempDirectory.appendingPathComponent("test.xyz")
        
        try "Text content".write(to: textFile, atomically: true, encoding: .utf8)
        try "Other content".write(to: unsupportedFile, atomically: true, encoding: .utf8)
        
        let results = await analyzer.analyzeFiles([textFile, unsupportedFile])
        
        // Only supported file should have results
        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[textFile])
        XCTAssertNil(results[unsupportedFile])
    }
    
    // MARK: - OCR Flag Tests
    
    func testAnalyzeWithOCRDisabled() async throws {
        let analyzer = ContentAnalyzer()
        
        let textFile = tempDirectory.appendingPathComponent("test.txt")
        try "Content".write(to: textFile, atomically: true, encoding: .utf8)
        
        let result = await analyzer.analyze(fileURL: textFile, enableOCR: false)
        
        // Text files don't use OCR, but verify the parameter is accepted
        XCTAssertNotNil(result)
    }
}

// MARK: - Helper Extension for Tests

extension ContentAnalyzer {
    func setEnableOCR(_ value: Bool) {
        enableOCR = value
    }
    
    func setEnableDeepDocumentScan(_ value: Bool) {
        enableDeepDocumentScan = value
    }
}
