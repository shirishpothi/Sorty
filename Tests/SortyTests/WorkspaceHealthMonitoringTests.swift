
import XCTest
@testable import SortyLib

/// Tests for file monitoring in WorkspaceHealthManager.
/// Note: File system monitoring with DispatchSource and Timer is inherently
/// environment-dependent and cannot be reliably tested in automated CI.
/// These tests verify the property behaviors without invoking actual monitoring.
@MainActor
class WorkspaceHealthMonitoringTests: XCTestCase {
    var healthManager: WorkspaceHealthManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        healthManager = WorkspaceHealthManager()
        
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        healthManager = nil
        try await super.tearDown()
    }
    
    /// Test that fileChangeDetected can be set and read
    func testFileChangeDetectedProperty() async throws {
        // Initially nil
        XCTAssertNil(healthManager.fileChangeDetected)
        
        // Can be set
        healthManager.fileChangeDetected = Date()
        XCTAssertNotNil(healthManager.fileChangeDetected)
        
        // Can be reset
        healthManager.fileChangeDetected = nil
        XCTAssertNil(healthManager.fileChangeDetected)
    }
    
    /// Test that the manager initializes with expected default state
    func testInitialState() async throws {
        XCTAssertFalse(healthManager.isAnalyzing)
        XCTAssertNil(healthManager.lastAnalysisDate)
        // Note: opportunities and insights may be loaded from persistence
        // so we only test the analyzing state and lastAnalysisDate
    }
    
    /// Test that config can be updated
    func testConfigUpdate() async throws {
        // Get a unique test value different from current
        let currentThreshold = healthManager.config.largeFileSizeThreshold
        let testThreshold: Int64 = currentThreshold == 500_000_000 ? 600_000_000 : 500_000_000
        
        let newConfig = WorkspaceHealthConfig(
            largeFileSizeThreshold: testThreshold
        )
        healthManager.updateConfig(newConfig)
        XCTAssertEqual(healthManager.config.largeFileSizeThreshold, testThreshold)
    }
}
