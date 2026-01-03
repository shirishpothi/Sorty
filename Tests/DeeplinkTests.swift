//
//  DeeplinkTests.swift
//  FileOrganizerTests
//
//  Tests for deeplink URL parsing and navigation
//

import XCTest
@testable import FileOrganizerLib

final class DeeplinkTests: XCTestCase {
    
    // MARK: - URL Parsing Tests
    
    @MainActor
    func testOrganizeDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://organize?path=/Users/test/Downloads")!
        handler.handle(url: url)
        
        if case .organize(let path) = handler.pendingDestination {
            XCTAssertEqual(path, "/Users/test/Downloads")
        } else {
            XCTFail("Expected organize destination")
        }
        
        handler.clearPending()
        XCTAssertNil(handler.pendingDestination)
    }
    
    @MainActor
    func testOrganizeDeeplinkNoPath() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://organize")!
        handler.handle(url: url)
        
        if case .organize(let path) = handler.pendingDestination {
            XCTAssertNil(path)
        } else {
            XCTFail("Expected organize destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDuplicatesDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://duplicates?path=/tmp/test")!
        handler.handle(url: url)
        
        if case .duplicates(let path) = handler.pendingDestination {
            XCTAssertEqual(path, "/tmp/test")
        } else {
            XCTFail("Expected duplicates destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testLearningsDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://learnings?project=Photos")!
        handler.handle(url: url)
        
        if case .learnings(let project) = handler.pendingDestination {
            XCTAssertEqual(project, "Photos")
        } else {
            XCTFail("Expected learnings destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testSettingsDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://settings")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .settings)
        handler.clearPending()
    }
    
    @MainActor
    func testHelpDeeplinkWithSection() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://help?section=personas")!
        handler.handle(url: url)
        
        if case .help(let section) = handler.pendingDestination {
            XCTAssertEqual(section, "personas")
        } else {
            XCTFail("Expected help destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testHistoryDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://history")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .history)
        handler.clearPending()
    }
    
    @MainActor
    func testHealthDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "fileorganizer://health")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .health)
        handler.clearPending()
    }
    
    @MainActor
    func testUnknownDeeplink() {
        let handler = DeeplinkHandler.shared
        handler.clearPending()
        
        let url = URL(string: "fileorganizer://unknown")!
        handler.handle(url: url)
        
        XCTAssertNil(handler.pendingDestination)
    }
    
    @MainActor
    func testWrongScheme() {
        let handler = DeeplinkHandler.shared
        handler.clearPending()
        
        let url = URL(string: "https://organize")!
        handler.handle(url: url)
        
        XCTAssertNil(handler.pendingDestination)
    }
    
    // MARK: - URL Generation Tests
    
    @MainActor
    func testGenerateOrganizeURL() {
        let url = DeeplinkHandler.url(for: .organize(path: "/test/path"))
        XCTAssertEqual(url?.absoluteString, "fileorganizer://organize?path=/test/path")
    }
    
    @MainActor
    func testGenerateSettingsURL() {
        let url = DeeplinkHandler.url(for: .settings)
        XCTAssertEqual(url?.absoluteString, "fileorganizer://settings")
    }
    
    @MainActor
    func testGenerateLearningsURL() {
        let url = DeeplinkHandler.url(for: .learnings(project: "MyProject"))
        XCTAssertEqual(url?.absoluteString, "fileorganizer://learnings?project=MyProject")
    }
}
