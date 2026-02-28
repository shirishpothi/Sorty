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

    func testHelpFeatureMatchesDeeplinkQuery() {
        let matches = SettingsCategory.help.featureMatches(query: "deeplink")

        XCTAssertTrue(matches.contains { $0.snippet.title == "Automation Deeplinks" })
    }

    func testHelpCategoryMatchesSortySchemeQuery() {
        XCTAssertTrue(SettingsCategory.help.matchesSearch(query: "sorty://"))
    }

    func testAutomationCategoryMatchesHyphenSeparatedQuery() {
        XCTAssertTrue(SettingsCategory.automation.matchesSearch(query: "launch-at-login"))
    }

    func testRulesFeatureMatchesFinderTagsQuery() {
        let matches = SettingsCategory.rules.featureMatches(query: "finder tags")

        XCTAssertEqual(matches.first?.snippet.title, "Enable File Tagging")
    }

    func testHelpFeatureMatchPrioritizesAutomationDeeplinks() {
        let matches = SettingsCategory.help.featureMatches(query: "automation")

        XCTAssertEqual(matches.first?.snippet.title, "Automation Deeplinks")
    }

    func testCategoriesForGroupPartitionsAllCasesWithoutDuplicates() {
        let grouped = SettingsCategoryGroup.allCases.flatMap(SettingsCategory.categories(for:))

        XCTAssertEqual(Set(grouped), Set(SettingsCategory.allCases))
        XCTAssertEqual(grouped.count, SettingsCategory.allCases.count)
    }

    func testRulesFocusTargetMappingsForKnownSnippets() {
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Storage Locations")), .rulesStorageLocations)
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Organization Limits")), .rulesOrganizationLimits)
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Duplicate Handling")), .rulesContentRules)
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Enable File Tagging")), .rulesContentRules)
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Organization Style")), .rulesOrganizationStyle)
    }

    func testFocusTargetIsNilForUnknownSnippet() {
        let customSnippet = SettingsFeatureSnippet(title: "Unknown", summary: "Custom")

        XCTAssertNil(SettingsCategory.rules.focusTarget(for: customSnippet))
    }

    func testFocusTargetIsNilOutsideRulesCategory() {
        XCTAssertNil(SettingsCategory.help.focusTarget(for: snippet(in: .help, titled: "Automation Deeplinks")))
    }

    private func snippet(
        in category: SettingsCategory,
        titled title: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> SettingsFeatureSnippet {
        guard let snippet = category.featureSnippets.first(where: { $0.title == title }) else {
            XCTFail("Expected snippet '\(title)' in category '\(category.rawValue)'", file: file, line: line)
            return SettingsFeatureSnippet(title: "Missing", summary: "")
        }
        return snippet
    }
}
