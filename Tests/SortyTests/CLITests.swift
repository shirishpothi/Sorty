//
//  CLITests.swift
//  SortyTests
//
//  Tests for CLI tools: fileorg script and learnings CLI
//  These tests verify deeplink handling that maps to CLI commands
//

import XCTest
@testable import SortyLib

final class CLITests: XCTestCase {
    
    // MARK: - fileorg Script Tests
    // Note: Script existence and syntax are verified in GitHub Actions CI
    
    // MARK: - Deeplink Handler CLI Command Mapping Tests
    
    @MainActor
    func testDeeplinkHandlerParsesStatusCommand() throws {
        // CLI "status" command maps to health deeplink
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://health")!
        
        handler.handle(url: url)
        
        if case .health = handler.pendingDestination {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .health destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkHandlerParsesListCommand() throws {
        // CLI "list" command maps to watched deeplink
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://watched")!
        
        handler.handle(url: url)
        
        if case .watched = handler.pendingDestination {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .watched destination")
        }
        
        handler.clearPending()
    }
}
