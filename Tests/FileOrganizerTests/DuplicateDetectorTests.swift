
import XCTest
@testable import FileOrganizerLib

class DuplicateDetectorTests: XCTestCase {
    
    var detector: DuplicateDetector!
    
    override func setUp() {
        super.setUp()
        detector = DuplicateDetector()
    }
    
    func testDuplicateFinding() async {
        let file1 = FileItem(path: "/path/1", name: "a", extension: "txt", size: 10, isDirectory: false, sha256Hash: "hash1")
        let file2 = FileItem(path: "/path/2", name: "b", extension: "txt", size: 10, isDirectory: false, sha256Hash: "hash1")
        let file3 = FileItem(path: "/path/3", name: "c", extension: "txt", size: 20, isDirectory: false, sha256Hash: "hash2")
        
        let groups = await detector.findDuplicates(in: [file1, file2, file3])
        
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.hash, "hash1")
        XCTAssertEqual(groups.first?.files.count, 2)
        XCTAssertEqual(groups.first?.potentialSavings, 10)
    }
    
    func testSavingsCalculation() async {
        let file1 = FileItem(path: "/path/1", name: "a", extension: "txt", size: 100, isDirectory: false, sha256Hash: "h1")
        let file2 = FileItem(path: "/path/2", name: "b", extension: "txt", size: 100, isDirectory: false, sha256Hash: "h1")
        let file3 = FileItem(path: "/path/3", name: "c", extension: "txt", size: 100, isDirectory: false, sha256Hash: "h1")
        
        let groups = await detector.findDuplicates(in: [file1, file2, file3])
        let totalSavings = await detector.totalPotentialSavings(in: groups)
        
        XCTAssertEqual(totalSavings, 200)
    }
}
