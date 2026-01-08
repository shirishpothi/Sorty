//
//  BuildInfoTests.swift
//  SortyTests
//
//  Tests for build information utility
//

import XCTest
@testable import SortyLib

final class BuildInfoTests: XCTestCase {
    
    func testVersionIsNotEmpty() {
        let version = BuildInfo.version
        XCTAssertFalse(version.isEmpty)
        // Should have at least one digit
        XCTAssertTrue(version.contains(where: { $0.isNumber }))
    }
    
    func testBuildIsNotEmpty() {
        let build = BuildInfo.build
        XCTAssertFalse(build.isEmpty)
    }
    
    func testFullVersionFormat() {
        let fullVersion = BuildInfo.fullVersion
        XCTAssertFalse(fullVersion.isEmpty)
        // Should contain version and build
        XCTAssertTrue(fullVersion.contains("("))
        XCTAssertTrue(fullVersion.contains(")"))
    }
    
    func testCommitIsString() {
        let commit = BuildInfo.commit
        XCTAssertFalse(commit.isEmpty)
        // Should either be "unknown" or a valid commit hash
        XCTAssertTrue(commit == "unknown" || commit.count >= 7)
    }
    
    func testShortCommitLength() {
        let shortCommit = BuildInfo.shortCommit
        XCTAssertFalse(shortCommit.isEmpty)
        
        if shortCommit != "unknown" {
            // Should be truncated to 9 characters max
            XCTAssertLessThanOrEqual(shortCommit.count, 9)
        }
    }
    
    func testHasValidCommitConsistency() {
        let hasValid = BuildInfo.hasValidCommit
        let commit = BuildInfo.commit
        
        if hasValid {
            XCTAssertNotEqual(commit, "unknown")
            XCTAssertGreaterThanOrEqual(commit.count, 7)
        } else {
            XCTAssertTrue(commit == "unknown" || commit.count < 7)
        }
    }
    
    func testCommitMethodsConsistency() {
        let commit = BuildInfo.commit
        let shortCommit = BuildInfo.shortCommit
        
        if commit == "unknown" {
            XCTAssertEqual(shortCommit, "unknown")
        } else if commit.count > 9 {
            XCTAssertEqual(shortCommit, String(commit.prefix(9)))
        } else {
            XCTAssertEqual(shortCommit, commit)
        }
    }
}