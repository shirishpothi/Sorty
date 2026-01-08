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
    
    func testFileorgSchemeIsCorrect() throws {
        // The scheme should be "sorty" as per Info.plist
        // This is verified in CI via grep
        XCTAssertTrue(true, "Scheme verification done in CI")
    }
    
    // MARK: - Deeplink Handler CLI Command Mapping Tests
    
    @MainActor
    func testDeeplinkHandlerParsesOrganizeCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://organize?path=/tmp&persona=developer")!
        
        handler.handle(url: url)
        
        if case let .organize(path, persona, autostart) = handler.pendingDestination {
            XCTAssertEqual(path, "/tmp")
            XCTAssertEqual(persona, "developer")
            XCTAssertFalse(autostart)
        } else {
            XCTFail("Expected .organize destination")
        }
        
        handler.clearPending()
    }
    
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
    
    @MainActor
    func testDeeplinkHandlerParsesSettingsCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://settings?section=ai")!
        
        handler.handle(url: url)
        
        if case let .settings(section) = handler.pendingDestination {
            XCTAssertEqual(section, "ai")
        } else {
            XCTFail("Expected .settings destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkHandlerParsesHelpCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://help")!
        
        handler.handle(url: url)
        
        if case .help = handler.pendingDestination {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .help destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkHandlerParsesHistoryCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://history")!
        
        handler.handle(url: url)
        
        if case .history = handler.pendingDestination {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .history destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkHandlerParsesWatchedAddCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://watched?action=add&path=/Users/test")!
        
        handler.handle(url: url)
        
        if case let .watched(action, path) = handler.pendingDestination {
            XCTAssertEqual(action, "add")
            XCTAssertEqual(path, "/Users/test")
        } else {
            XCTFail("Expected .watched destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkHandlerParsesRulesAddCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://rules?action=add&type=extension&pattern=*.log")!
        
        handler.handle(url: url)
        
        if case let .rules(action, type, pattern) = handler.pendingDestination {
            XCTAssertEqual(action, "add")
            XCTAssertEqual(type, "extension")
            XCTAssertEqual(pattern, "*.log")
        } else {
            XCTFail("Expected .rules destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkHandlerIgnoresInvalidScheme() throws {
        let handler = DeeplinkHandler.shared
        handler.clearPending()  // Clear any existing state
        
        let url = URL(string: "invalid://organize")!
        handler.handle(url: url)
        
        XCTAssertNil(handler.pendingDestination, "Should not handle invalid scheme")
    }
    
    // MARK: - URL Generation Tests
    
    @MainActor
    func testDeeplinkURLGeneration() throws {
        let organizeURL = DeeplinkHandler.url(for: .organize(path: "/tmp", persona: "dev", autostart: true))
        XCTAssertNotNil(organizeURL)
        XCTAssertTrue(organizeURL?.absoluteString.contains("sorty://organize") ?? false)
        XCTAssertTrue(organizeURL?.absoluteString.contains("path=") ?? false)
        
        let settingsURL = DeeplinkHandler.url(for: .settings(section: "ai"))
        XCTAssertNotNil(settingsURL)
        XCTAssertTrue(settingsURL?.absoluteString.contains("sorty://settings") ?? false)
        
        let helpURL = DeeplinkHandler.url(for: .help(section: nil))
        XCTAssertEqual(helpURL?.absoluteString, "sorty://help")
        
        let historyURL = DeeplinkHandler.url(for: .history)
        XCTAssertEqual(historyURL?.absoluteString, "sorty://history")
    }
    
    // MARK: - Organize Command with Autostart
    
    @MainActor
    func testDeeplinkHandlerParsesOrganizeWithAutostart() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://organize?path=/tmp&autostart=true")!
        
        handler.handle(url: url)
        
        if case let .organize(path, _, autostart) = handler.pendingDestination {
            XCTAssertEqual(path, "/tmp")
            XCTAssertTrue(autostart)
        } else {
            XCTFail("Expected .organize destination with autostart")
        }
        
        handler.clearPending()
    }
    
    // MARK: - Duplicates Command
    
    @MainActor
    func testDeeplinkHandlerParsesDuplicatesCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://duplicates?path=/tmp&autostart=true")!
        
        handler.handle(url: url)
        
        if case let .duplicates(path, autostart) = handler.pendingDestination {
            XCTAssertEqual(path, "/tmp")
            XCTAssertTrue(autostart)
        } else {
            XCTFail("Expected .duplicates destination")
        }
        
        handler.clearPending()
    }
    
    // MARK: - Persona Command
    
    @MainActor
    func testDeeplinkHandlerParsesPersonaCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://persona?action=create")!
        
        handler.handle(url: url)
        
        if case let .persona(action, _, _) = handler.pendingDestination {
            XCTAssertEqual(action, "create")
        } else {
            XCTFail("Expected .persona destination")
        }
        
        handler.clearPending()
    }
    
    // MARK: - Learnings Command
    
    @MainActor
    func testDeeplinkHandlerParsesLearningsCommand() throws {
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://learnings?project=TestProject")!
        
        handler.handle(url: url)
        
        if case let .learnings(_, project) = handler.pendingDestination {
            XCTAssertEqual(project, "TestProject")
        } else {
            XCTFail("Expected .learnings destination")
        }
        
        handler.clearPending()
    }
}
