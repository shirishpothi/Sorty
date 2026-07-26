import XCTest
@testable import SortyLib

final class SettingsSearchTests: XCTestCase {
    func testStrategyCategoryMatchesDeepScanningQuery() {
        XCTAssertTrue(SettingsCategory.strategy.matchesSearch(query: "deep scanning"))
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

    func testDeeplinkFeatureMatchesDeeplinkQuery() {
        let matches = SettingsCategory.deeplinks.featureMatches(query: "deeplink")

        XCTAssertTrue(matches.contains { $0.snippet.title == "Automation Deeplinks" })
    }

    func testDeeplinkCategoryMatchesSortySchemeQuery() {
        XCTAssertTrue(SettingsCategory.deeplinks.matchesSearch(query: "sorty://"))
    }

    func testDeeplinkFeatureMatchesDownloadsWordQuery() {
        let matches = SettingsCategory.deeplinks.featureMatches(query: "downloads")

        XCTAssertTrue(matches.contains { $0.snippet.title == "Organization Deeplinks" })
    }

    func testAutomationCategoryMatchesHyphenSeparatedQuery() {
        XCTAssertTrue(SettingsCategory.automation.matchesSearch(query: "launch-at-login"))
    }

    func testRulesFeatureMatchesFinderTagsQuery() {
        let matches = SettingsCategory.rules.featureMatches(query: "finder tags")

        XCTAssertEqual(matches.first?.snippet.title, "Enable File Tagging")
    }

    func testDeeplinkFeatureMatchPrioritizesAutomationDeeplinks() {
        let matches = SettingsCategory.deeplinks.featureMatches(query: "automation")

        XCTAssertEqual(matches.first?.snippet.title, "Automation Deeplinks")
    }

    func testCategoriesForGroupPartitionsAllCasesWithoutDuplicates() {
        let grouped = SettingsCategoryGroup.allCases.flatMap(SettingsCategory.categories(for:))
        let visibleCategories = SettingsCategory.allCases.filter { $0 != .tuning }

        XCTAssertEqual(Set(grouped), Set(visibleCategories))
        XCTAssertEqual(grouped.count, visibleCategories.count)
    }

    func testRulesFocusTargetMappingsForKnownSnippets() {
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Duplicate Handling")), .rulesContentRules)
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Enable File Tagging")), .rulesContentRules)
        XCTAssertEqual(SettingsCategory.rules.focusTarget(for: snippet(in: .rules, titled: "Organization Style")), .rulesOrganizationStyle)
        XCTAssertEqual(SettingsCategory.notifications.focusTarget(for: snippet(in: .notifications, titled: "System Notifications")), .notificationsSystem)
        XCTAssertEqual(SettingsCategory.advanced.focusTarget(for: snippet(in: .advanced, titled: "Block Internet Connections")), .advancedInternetPrivacy)
    }

    func testFocusTargetIsNilForUnknownSnippet() {
        let customSnippet = SettingsFeatureSnippet(title: "Unknown", summary: "Custom")

        XCTAssertNil(SettingsCategory.rules.focusTarget(for: customSnippet))
    }

    func testFocusTargetIsNilOutsideRulesCategory() {
        XCTAssertNil(SettingsCategory.help.focusTarget(for: snippet(in: .help, titled: "Support Links")))
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
