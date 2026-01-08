import XCTest
@testable import SortyLib

final class EdgeCaseTests: XCTestCase {
    var fileManager: FileManager!
    var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        fileManager = FileManager.default
        tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? fileManager.removeItem(at: tempDir)
        super.tearDown()
    }
    
    func testEmptyDirectoryScanning() async throws {
        let scanner = DirectoryScanner()
        let files = try await scanner.scanDirectory(at: tempDir)
        XCTAssertTrue(files.isEmpty, "Scanning an empty directory should return no files")
    }
    
    func testSpecialCharactersInFilenames() async throws {
        let specialName = "File !@#$%^&()_+ {}-=[] ;',. ~ .txt"
        let fileURL = tempDir.appendingPathComponent(specialName)
        try "test content".write(to: fileURL, atomically: true, encoding: .utf8)
        
        let scanner = DirectoryScanner()
        let files = try await scanner.scanDirectory(at: tempDir)
        
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.name, "File !@#$%^&()_+ {}-=[] ;',. ~ ")
        XCTAssertEqual(files.first?.extension, "txt")
    }
    
    func testLargeFileMetadata() async throws {
        let largeFileName = "large_file.dat"
        let fileURL = tempDir.appendingPathComponent(largeFileName)
        
        // Create a 10MB file
        let data = Data(count: 10 * 1024 * 1024)
        try data.write(to: fileURL)
        
        let scanner = DirectoryScanner()
        let files = try await scanner.scanDirectory(at: tempDir)
        
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.size, Int64(10 * 1024 * 1024))
    }
    
    func testNestedEmptyDirectories() async throws {
        let nestedDir = tempDir.appendingPathComponent("folder1/folder2/folder3")
        try fileManager.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        
        let scanner = DirectoryScanner()
        let files = try await scanner.scanDirectory(at: tempDir)
        
        XCTAssertTrue(files.isEmpty, "Deep scanning empty nested folders should return no files")
    }
}
