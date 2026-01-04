
import XCTest
@testable import FileOrganizerLib

class WorkspaceHealthMonitoringTests: XCTestCase {
    var healthManager: WorkspaceHealthManager!
    var tempDirectory: URL!
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        healthManager = WorkspaceHealthManager()
        
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        healthManager = nil
        super.tearDown()
    }
    
    @MainActor
    func testFileMonitoringDetectsChanges() async throws {
        // 1. Start monitoring
        healthManager.startMonitoring(path: tempDirectory.path)
        
        // 2. Create a file
        let file = tempDirectory.appendingPathComponent("test.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        
        // 3. Wait for change detection (debounce is 2.0s)
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3s
        
        // 4. Assert change detected
        XCTAssertNotNil(healthManager.fileChangeDetected)
        
        // 5. Reset and test modification
        healthManager.fileChangeDetected = nil
        try "new content".write(to: file, atomically: true, encoding: .utf8)
        
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3s
        XCTAssertNotNil(healthManager.fileChangeDetected)
    }
}
