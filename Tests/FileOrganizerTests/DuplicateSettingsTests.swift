//
//  DuplicateSettingsTests.swift
//  FileOrganizerTests
//
//  Tests for duplicate detection settings
//

import XCTest
@testable import FileOrganizerLib

final class DuplicateSettingsTests: XCTestCase {
    
    // MARK: - DuplicateSettings Tests
    
    func testDefaultSettings() {
        let settings = DuplicateSettings()
        
        XCTAssertEqual(settings.minFileSize, 0)
        XCTAssertEqual(settings.maxScanDepth, -1)
        XCTAssertTrue(settings.includeExtensions.isEmpty)
        XCTAssertFalse(settings.excludeExtensions.isEmpty) // Has defaults
        XCTAssertEqual(settings.defaultKeepStrategy, .newest)
        XCTAssertTrue(settings.enableSafeDeletion)
        XCTAssertFalse(settings.autoStartScan)
        XCTAssertFalse(settings.includeSemanticDuplicates)
        XCTAssertEqual(settings.semanticSimilarityThreshold, 0.9)
    }
    
    func testCustomSettings() {
        let settings = DuplicateSettings(
            minFileSize: 1024 * 1024, // 1 MB
            maxScanDepth: 3,
            includeExtensions: ["jpg", "png"],
            excludeExtensions: [".DS_Store"],
            defaultKeepStrategy: .largest,
            enableSafeDeletion: false,
            autoStartScan: true,
            includeSemanticDuplicates: true,
            semanticSimilarityThreshold: 0.8
        )
        
        XCTAssertEqual(settings.minFileSize, 1024 * 1024)
        XCTAssertEqual(settings.maxScanDepth, 3)
        XCTAssertEqual(settings.includeExtensions, ["jpg", "png"])
        XCTAssertEqual(settings.excludeExtensions, [".DS_Store"])
        XCTAssertEqual(settings.defaultKeepStrategy, .largest)
        XCTAssertFalse(settings.enableSafeDeletion)
        XCTAssertTrue(settings.autoStartScan)
        XCTAssertTrue(settings.includeSemanticDuplicates)
        XCTAssertEqual(settings.semanticSimilarityThreshold, 0.8)
    }
    
    func testSettingsCodable() throws {
        let original = DuplicateSettings(
            minFileSize: 500,
            maxScanDepth: 5,
            includeExtensions: ["pdf"],
            excludeExtensions: [],
            defaultKeepStrategy: .oldest,
            enableSafeDeletion: true,
            autoStartScan: false,
            includeSemanticDuplicates: false,
            semanticSimilarityThreshold: 0.95
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(DuplicateSettings.self, from: data)
        
        XCTAssertEqual(decoded.minFileSize, original.minFileSize)
        XCTAssertEqual(decoded.maxScanDepth, original.maxScanDepth)
        XCTAssertEqual(decoded.includeExtensions, original.includeExtensions)
        XCTAssertEqual(decoded.defaultKeepStrategy, original.defaultKeepStrategy)
        XCTAssertEqual(decoded.semanticSimilarityThreshold, original.semanticSimilarityThreshold)
    }
    
    // MARK: - KeepStrategy Tests
    
    func testKeepStrategyDisplayNames() {
        XCTAssertEqual(KeepStrategy.newest.displayName, "Keep Newest")
        XCTAssertEqual(KeepStrategy.oldest.displayName, "Keep Oldest")
        XCTAssertEqual(KeepStrategy.largest.displayName, "Keep Largest")
        XCTAssertEqual(KeepStrategy.smallest.displayName, "Keep Smallest")
        XCTAssertEqual(KeepStrategy.shortestPath.displayName, "Keep Shortest Path")
    }
    
    func testKeepStrategyDescriptions() {
        XCTAssertFalse(KeepStrategy.newest.description.isEmpty)
        XCTAssertFalse(KeepStrategy.oldest.description.isEmpty)
        XCTAssertFalse(KeepStrategy.largest.description.isEmpty)
    }
    
    func testKeepStrategyCaseIterable() {
        let allCases = KeepStrategy.allCases
        XCTAssertEqual(allCases.count, 5)
        XCTAssertTrue(allCases.contains(.newest))
        XCTAssertTrue(allCases.contains(.shortestPath))
    }
}
