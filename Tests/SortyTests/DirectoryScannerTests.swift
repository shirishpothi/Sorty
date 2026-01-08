
import XCTest
@testable import SortyLib

class DirectoryScannerTests: XCTestCase {
    
    var scanner: DirectoryScanner!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        scanner = DirectoryScanner()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        scanner = nil
        try await super.tearDown()
    }
    
    func testBasicScanning() async throws {
        // Create some test files
        let file1 = tempDirectory.appendingPathComponent("test1.txt")
        let file2 = tempDirectory.appendingPathComponent("test2.md")
        try "Content 1".write(to: file1, atomically: true, encoding: .utf8)
        try "Content 2".write(to: file2, atomically: true, encoding: .utf8)
        
        let files = try await scanner.scanDirectory(at: tempDirectory)
        
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains(where: { $0.name == "test1" && $0.extension == "txt" }))
        XCTAssertTrue(files.contains(where: { $0.name == "test2" && $0.extension == "md" }))
    }
    
    func testHiddenFileExclusion() async throws {
        let visibleFile = tempDirectory.appendingPathComponent("visible.txt")
        let hiddenFile = tempDirectory.appendingPathComponent(".hidden.txt")
        try "Visible".write(to: visibleFile, atomically: true, encoding: .utf8)
        try "Hidden".write(to: hiddenFile, atomically: true, encoding: .utf8)
        
        // Scan without hidden files
        let files = try await scanner.scanDirectory(at: tempDirectory, includeHidden: false)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.name, "visible")
        
        // Scan with hidden files
        let filesWithHidden = try await scanner.scanDirectory(at: tempDirectory, includeHidden: true)
        XCTAssertEqual(filesWithHidden.count, 2)
    }
    
    func testDeepScan() async throws {
        let textFile = tempDirectory.appendingPathComponent("sample.txt")
        let content = "This is a sample text file for deep scanning."
        try content.write(to: textFile, atomically: true, encoding: .utf8)
        
        let files = try await scanner.scanDirectory(at: tempDirectory, deepScan: true)
        
        XCTAssertEqual(files.count, 1)
        XCTAssertNotNil(files.first?.contentMetadata)
        XCTAssertEqual(files.first?.contentMetadata?.textPreview, content)
    }
    
    func testHashComputation() async throws {
        let file = tempDirectory.appendingPathComponent("hash_test.txt")
        let content = "hash me"
        try content.write(to: file, atomically: true, encoding: .utf8)
        
        let files = try await scanner.scanDirectory(at: tempDirectory, computeHashes: true)
        
        XCTAssertEqual(files.count, 1)
        XCTAssertNotNil(files.first?.sha256Hash)
        // Verify hash if possible, or just check it's non-empty
        XCTAssertFalse(files.first?.sha256Hash?.isEmpty ?? true)
    }
    
    func testRecursiveScanning() async throws {
        let subDir = tempDirectory.appendingPathComponent("SubDir")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let subFile = subDir.appendingPathComponent("sub.txt")
        try "sub content".write(to: subFile, atomically: true, encoding: .utf8)
        
        let files = try await scanner.scanDirectory(at: tempDirectory)
        
        XCTAssertTrue(files.contains(where: { $0.name == "sub" }))
    }
}
