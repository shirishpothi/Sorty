
import XCTest
@testable import SortyLib

class ExclusionRulesTests: XCTestCase {
    
    var manager: ExclusionRulesManager!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        manager = ExclusionRulesManager()
        // Clear existing rules to start fresh
        for rule in manager.rules {
            manager.removeRule(rule)
        }
    }
    
    @MainActor
    func testExtensionExclusion() {
        let rule = ExclusionRule(type: .fileExtension, pattern: "tmp")
        manager.addRule(rule)
        
        let file1 = FileItem(path: "/p/a.tmp", name: "a", extension: "tmp", size: 0, isDirectory: false)
        let file2 = FileItem(path: "/p/b.txt", name: "b", extension: "txt", size: 0, isDirectory: false)
        
        XCTAssertTrue(manager.shouldExclude(file1))
        XCTAssertFalse(manager.shouldExclude(file2))
    }
    
    @MainActor
    func testFileNameExclusion() {
        let rule = ExclusionRule(type: .fileName, pattern: "secret")
        manager.addRule(rule)
        
        let file1 = FileItem(path: "/p/my_secret_file.txt", name: "my_secret_file", extension: "txt", size: 0, isDirectory: false)
        let file2 = FileItem(path: "/p/normal.txt", name: "normal", extension: "txt", size: 0, isDirectory: false)
        
        XCTAssertTrue(manager.shouldExclude(file1))
        XCTAssertFalse(manager.shouldExclude(file2))
    }
    
    @MainActor
    func testFolderNameExclusion() {
        let rule = ExclusionRule(type: .folderName, pattern: "cache")
        manager.addRule(rule)
        
        let file1 = FileItem(path: "/Library/Cache/data.db", name: "data", extension: "db", size: 0, isDirectory: false)
        let file2 = FileItem(path: "/Documents/data.db", name: "data", extension: "db", size: 0, isDirectory: false)
        
        XCTAssertTrue(manager.shouldExclude(file1))
        XCTAssertFalse(manager.shouldExclude(file2))
    }
    
    @MainActor
    func testDisabledRule() {
        let rule = ExclusionRule(type: .fileExtension, pattern: "tmp", isEnabled: false)
        manager.addRule(rule)
        
        let file = FileItem(path: "/p/a.tmp", name: "a", extension: "tmp", size: 0, isDirectory: false)
        XCTAssertFalse(manager.shouldExclude(file))
    }
}
