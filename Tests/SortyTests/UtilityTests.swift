
import XCTest
@testable import SortyLib

final class UtilityTests: XCTestCase {

    func testRenameRuleEngineAppliesRegexAndLiteralRules() {
        let rules = [
            RenameRule(pattern: "^IMG\\s+", replacement: "", isRegex: true),
            RenameRule(pattern: " ", replacement: "_", isRegex: false)
        ]

        let output = RenameRuleEngine.applyRules(to: "IMG 123 Summer Photo.jpg", rules: rules)
        XCTAssertEqual(output, "123_Summer_Photo.jpg")
    }
}
