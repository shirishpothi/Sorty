 //
//  DeeplinkTests.swift
//  SortyTests
//
//  Tests for deeplink URL parsing and navigation
//

import XCTest
@testable import SortyLib

final class DeeplinkTests: XCTestCase {
    
    // MARK: - URL Parsing Tests
    
    @MainActor
    func testOrganizeDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://organize?path=/Users/test/Downloads&persona=developer")!
        handler.handle(url: url)
        
        if case .organize(let path, let persona, let autostart) = handler.pendingDestination {
            XCTAssertEqual(path, "/Users/test/Downloads")
            XCTAssertEqual(persona, "developer")
            XCTAssertFalse(autostart)
        } else {
            XCTFail("Expected organize destination")
        }
        
        handler.clearPending()
        XCTAssertNil(handler.pendingDestination)
    }

    @MainActor
    func testOrganizeDeeplinkWithAutostart() {
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
    
    @MainActor
    func testOrganizeDeeplinkNoPath() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://organize")!
        handler.handle(url: url)
        
        if case .organize(let path, _, _) = handler.pendingDestination {
            XCTAssertNil(path)
        } else {
            XCTFail("Expected organize destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDuplicatesDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://duplicates?path=/tmp/test")!
        handler.handle(url: url)
        
        if case .duplicates(let path, let autostart) = handler.pendingDestination {
            XCTAssertEqual(path, "/tmp/test")
            XCTAssertFalse(autostart)
        } else {
            XCTFail("Expected duplicates destination")
        }
        
        handler.clearPending()
    }

    @MainActor
    func testDuplicatesDeeplinkWithAutostart() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://duplicates?path=/tmp/test&autostart=true")!
        handler.handle(url: url)
        
        if case .duplicates(let path, let autostart) = handler.pendingDestination {
            XCTAssertEqual(path, "/tmp/test")
            XCTAssertTrue(autostart)
        } else {
            XCTFail("Expected duplicates destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testLearningsDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://learnings?project=Photos")!
        handler.handle(url: url)
        
        if case .learnings(let action, let project) = handler.pendingDestination {
            XCTAssertNil(action)
            XCTAssertEqual(project, "Photos")
        } else {
            XCTFail("Expected learnings destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testSettingsDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://settings")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .settings(section: nil))
        handler.clearPending()
    }

    @MainActor
    func testSettingsWithSectionDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://settings?section=provider")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .settings(section: "provider"))
        handler.clearPending()
        
        let url2 = URL(string: "sorty://settings?section=notifications")!
        handler.handle(url: url2)
        XCTAssertEqual(handler.pendingDestination, .settings(section: "notifications"))
        handler.clearPending()
    }
    
    @MainActor
    func testHelpDeeplinkWithSection() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://help?section=personas")!
        handler.handle(url: url)
        
        if case .help(let section) = handler.pendingDestination {
            XCTAssertEqual(section, "personas")
        } else {
            XCTFail("Expected help destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testOpenDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://open")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .open(path: nil))
        handler.clearPending()
    }
    
    @MainActor
    func testOpenDeeplinkWithPath() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://open?path=/tmp/test")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .open(path: "/tmp/test"))
        handler.clearPending()
    }
    
    @MainActor
    func testHistoryDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://history")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .history)
        handler.clearPending()
    }
    
    @MainActor
    func testHealthDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://health")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .health)
        handler.clearPending()
    }
    
    @MainActor
    func testPersonaDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://persona?action=generate&prompt=Organize%20my%20music")!
        handler.handle(url: url)
        
        if case .persona(let action, let prompt, let generate) = handler.pendingDestination {
            XCTAssertEqual(action, "generate")
            XCTAssertEqual(prompt, "Organize my music")
            XCTAssertFalse(generate)
        } else {
            XCTFail("Expected persona destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testWatchedDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://watched?action=add&path=/Users/test/Code")!
        handler.handle(url: url)
        
        if case .watched(let action, let path) = handler.pendingDestination {
            XCTAssertEqual(action, "add")
            XCTAssertEqual(path, "/Users/test/Code")
        } else {
            XCTFail("Expected watched destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testRulesDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://rules?action=add&pattern=*.tmp")!
        handler.handle(url: url)
        
        if case .rules(let action, _, let pattern) = handler.pendingDestination {
            XCTAssertEqual(action, "add")
            XCTAssertEqual(pattern, "*.tmp")
        } else {
            XCTFail("Expected rules destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testWatchedListDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://watched")!
        handler.handle(url: url)
        
        if case .watched(let action, let path) = handler.pendingDestination {
            XCTAssertNil(action)
            XCTAssertNil(path)
        } else {
            XCTFail("Expected watched destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testLearningsHoningDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://learnings?action=honing")!
        handler.handle(url: url)
        
        if case .learnings(let action, _) = handler.pendingDestination {
            XCTAssertEqual(action, .honing)
        } else {
            XCTFail("Expected learnings honing destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testUnknownDeeplink() {
        let handler = DeeplinkHandler.shared
        handler.clearPending()
        
        let url = URL(string: "sorty://unknown")!
        handler.handle(url: url)
        
        XCTAssertNil(handler.pendingDestination)
    }
    
    @MainActor
    func testUnknownDeeplinkClearsPriorDestination() {
        let handler = DeeplinkHandler.shared
        
        handler.handle(url: URL(string: "sorty://health")!)
        XCTAssertEqual(handler.pendingDestination, .health)
        
        handler.handle(url: URL(string: "sorty://unknown")!)
        XCTAssertNil(handler.pendingDestination)
    }
    
    @MainActor
    func testWrongScheme() {
        let handler = DeeplinkHandler.shared
        
        handler.handle(url: URL(string: "sorty://history")!)
        XCTAssertEqual(handler.pendingDestination, .history)
        
        let url = URL(string: "https://organize")!
        handler.handle(url: url)
        
        XCTAssertNil(handler.pendingDestination)
    }
    
    @MainActor
    func testDeeplinkWithEncodedSpaces() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty://organize?path=/Users/test/My%20Documents")!
        handler.handle(url: url)
        
        if case .organize(let path, _, _) = handler.pendingDestination {
            XCTAssertEqual(path, "/Users/test/My Documents", "Should decode URL-encoded spaces")
        } else {
            XCTFail("Expected organize destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkWithEncodedUnicode() {
        let handler = DeeplinkHandler.shared
        
        // "文件" URL-encoded
        let url = URL(string: "sorty://organize?path=/tmp/%E6%96%87%E4%BB%B6")!
        handler.handle(url: url)
        
        if case .organize(let path, _, _) = handler.pendingDestination {
            XCTAssertEqual(path, "/tmp/文件", "Should decode URL-encoded unicode")
        } else {
            XCTFail("Expected organize destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testLegacyPathDeeplink() {
        let handler = DeeplinkHandler.shared
        
        let url = URL(string: "sorty:///Users/test/Downloads")!
        handler.handle(url: url)
        
        XCTAssertEqual(handler.pendingDestination, .organize(path: "/Users/test/Downloads", persona: nil, autostart: false))
        handler.clearPending()
    }
    
    // MARK: - URL Generation Tests
    
    @MainActor
    func testGenerateOrganizeURL() {
        let url = DeeplinkHandler.url(for: .organize(path: "/test/path", persona: nil, autostart: false))
        XCTAssertEqual(url?.absoluteString, "sorty://organize?path=/test/path")
    }
    
    @MainActor
    func testGenerateSettingsURL() {
        let url = DeeplinkHandler.url(for: .settings(section: nil))
        XCTAssertEqual(url?.absoluteString, "sorty://settings")
    }
    
    @MainActor
    func testGenerateOpenURL() {
        let url = DeeplinkHandler.url(for: .open(path: nil))
        XCTAssertEqual(url?.absoluteString, "sorty://open")
        
        let urlWithPath = DeeplinkHandler.url(for: .open(path: "/tmp/test"))
        XCTAssertEqual(urlWithPath?.absoluteString, "sorty://open?path=/tmp/test")
    }
    
    @MainActor
    func testGenerateLearningsURL() {
        let url = DeeplinkHandler.url(for: .learnings(action: nil, project: "MyProject"))
        XCTAssertEqual(url?.absoluteString, "sorty://learnings?project=MyProject")
        
        let hunkURL = DeeplinkHandler.url(for: .learnings(action: .honing, project: nil))
        XCTAssertEqual(hunkURL?.absoluteString, "sorty://learnings?action=honing")
    }
    
    @MainActor
    func testGeneratePersonaURL() {
        let url = DeeplinkHandler.url(for: .persona(action: "generate", prompt: "Test prompt", generate: true))
        XCTAssertEqual(url?.absoluteString, "sorty://persona?action=generate&prompt=Test%20prompt&generate=true")
    }
}
