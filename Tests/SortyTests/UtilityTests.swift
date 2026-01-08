
import XCTest
@testable import SortyLib

final class UtilityTests: XCTestCase {
    
    func testDateFilenameTimestamp() {
        let date = Date(timeIntervalSince1970: 1735992058) // 2025-01-04 12:00:58 UTC
        // Note: Formatting is local, but let's check the format
        let timestamp = date.filenameTimestamp
        
        // Regex: YYYY-MM-DD HH-MM-SS
        let regex = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2} \d{2}-\d{2}-\d{2}$"#)
        let range = NSRange(location: 0, length: timestamp.utf16.count)
        XCTAssertNotNil(regex.firstMatch(in: timestamp, options: [], range: range))
    }
}
