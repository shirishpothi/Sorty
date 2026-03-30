//
//  PromptBuilderTests.swift
//  SortyTests
//
//  Tests for PromptBuilder reference-directory context generation
//

import XCTest
@testable import SortyLib

final class PromptBuilderTests: XCTestCase {
    
    private var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBuilderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }
    
    // MARK: - Empty Input
    
    func testEmptyPathsReturnsEmpty() {
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [])
        XCTAssertTrue(result.isEmpty)
    }
    
    func testMissingDirectorySkipped() {
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: ["/nonexistent/path/\(UUID().uuidString)"])
        XCTAssertTrue(result.isEmpty)
    }
    
    // MARK: - Single Directory
    
    func testSingleDirectoryWithSubfolders() throws {
        let sub1 = tempDir.appendingPathComponent("Photos")
        let sub2 = tempDir.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: sub1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: true)
        
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [tempDir.path])
        
        XCTAssertTrue(result.contains("REFERENCE MODEL DIRECTORIES"))
        XCTAssertTrue(result.contains("Documents"))
        XCTAssertTrue(result.contains("Photos"))
        XCTAssertTrue(result.contains("reference examples only"))
    }
    
    func testSingleDirectoryEmpty() throws {
        // tempDir exists but has no subdirectories
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [tempDir.path])
        XCTAssertTrue(result.isEmpty, "Empty directory should produce empty context")
    }
    
    // MARK: - Multi-Directory
    
    func testMultipleDirectories() throws {
        let dir1 = tempDir.appendingPathComponent("Reference1")
        let dir2 = tempDir.appendingPathComponent("Reference2")
        try FileManager.default.createDirectory(at: dir1.appendingPathComponent("Work"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2.appendingPathComponent("Personal"), withIntermediateDirectories: true)
        
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [dir1.path, dir2.path])
        
        XCTAssertTrue(result.contains("Reference1"))
        XCTAssertTrue(result.contains("Reference2"))
        XCTAssertTrue(result.contains("Work"))
        XCTAssertTrue(result.contains("Personal"))
    }
    
    // MARK: - Truncation
    
    func testTruncationAtMaxEntries() throws {
        // Create more subfolders than the cap
        let maxEntries = 5
        for i in 0..<10 {
            let sub = tempDir.appendingPathComponent("Folder\(String(format: "%02d", i))")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        
        let result = PromptBuilder.buildReferenceDirectoryContext(
            paths: [tempDir.path],
            maxEntriesPerDirectory: maxEntries
        )
        
        XCTAssertTrue(result.contains("truncated"))
        // Count the number of "  - " entries
        let entryCount = result.components(separatedBy: "  - ").count - 1
        XCTAssertEqual(entryCount, maxEntries)
    }
    
    // MARK: - Depth Limit
    
    func testDepthLimit() throws {
        let deep = tempDir
            .appendingPathComponent("L1")
            .appendingPathComponent("L2")
            .appendingPathComponent("L3")
            .appendingPathComponent("L4")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        
        // maxDepth=2 should capture L1, L1/L2 but not L1/L2/L3 or deeper
        let result = PromptBuilder.buildReferenceDirectoryContext(
            paths: [tempDir.path],
            maxDepth: 2
        )
        
        XCTAssertTrue(result.contains("L1"))
        XCTAssertTrue(result.contains("L1/L2"))
        XCTAssertFalse(result.contains("L3"))
        XCTAssertFalse(result.contains("L4"))
    }
    
    func testMixedValidAndInvalidPaths() throws {
        let validDir = tempDir.appendingPathComponent("ValidRef")
        try FileManager.default.createDirectory(at: validDir.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        
        let result = PromptBuilder.buildReferenceDirectoryContext(
            paths: ["/nonexistent/\(UUID().uuidString)", validDir.path]
        )
        
        XCTAssertTrue(result.contains("Projects"))
        XCTAssertTrue(result.contains("REFERENCE MODEL DIRECTORIES"))
    }
}
