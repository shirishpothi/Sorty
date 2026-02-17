import XCTest
@testable import SortyLib

final class SettingsSearchTests: XCTestCase {
    func testStrategyCategoryMatchesDeepScanningQuery() {
        XCTAssertTrue(SettingsCategory.strategy.matchesSearch(query: "deep scanning"))
    }

    func testRulesCategoryMatchesStorageLocationQuery() {
        XCTAssertTrue(SettingsCategory.rules.matchesSearch(query: "storage locations"))
    }

    func testProviderCategoryMatchesApiKeyQuery() {
        XCTAssertTrue(SettingsCategory.provider.matchesSearch(query: "api key"))
    }

    func testUnrelatedCategoryDoesNotMatchQuery() {
        XCTAssertFalse(SettingsCategory.help.matchesSearch(query: "deep scanning"))
    }

    func testRulesFeatureMatchesFileTaggingQuery() {
        let matches = SettingsCategory.rules.featureMatches(query: "file tagging")

        XCTAssertTrue(matches.contains { $0.snippet.title == "Enable File Tagging" })
    }

    func testHelpFeatureMatchesFileTaggingQuery() {
        let matches = SettingsCategory.help.featureMatches(query: "file tagging")

        XCTAssertTrue(matches.contains { $0.snippet.title == "Smart Tags and File Tagging" })
    }
}
