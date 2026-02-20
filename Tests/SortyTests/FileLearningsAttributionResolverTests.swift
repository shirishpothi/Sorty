import XCTest
@testable import SortyLib

final class FileLearningsAttributionResolverTests: XCTestCase {
    func testResolveReturnsEmptyWhenSuggestionHasNoRuleAttribution() {
        let file = FileItem(path: "/tmp/report.pdf", name: "report", extension: "pdf", size: 1024)
        let suggestion = FolderSuggestion(folderName: "Reports", files: [file])

        let result = FileLearningsAttributionResolver.resolve(file: file, suggestion: suggestion, profile: LearningsProfile())

        XCTAssertFalse(result.hasContent)
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertNil(result.scope)
    }

    func testResolveUsesDirectRuleIDAndExtractsExplicitHoningSignals() {
        let file = FileItem(path: "/tmp/report.pdf", name: "report", extension: "pdf", size: 1024)
        let suggestion = FolderSuggestion(folderName: "Reports", files: [file], ruleId: "rule-1")

        let rule = InferredRule(
            id: "rule-1",
            pattern: ".*\\.pdf$",
            template: "Reports/{filename}",
            priority: 80,
            explanation: "PDF files should go in Reports",
            supportCount: 4,
            evidenceIds: ["Preference: Prefer project folders"],
            evidenceDescription: "User moved similar PDFs; Preference: Prefer project folders"
        )
        let profile = LearningsProfile(inferredRules: [rule])

        let result = FileLearningsAttributionResolver.resolve(file: file, suggestion: suggestion, profile: profile)

        XCTAssertTrue(result.hasContent)
        XCTAssertEqual(result.scope, .fileRuleMatch)
        XCTAssertEqual(result.learningsItems.filter { $0.kind == .learnedRule }.count, 1)
        XCTAssertEqual(result.learningsItems.filter { $0.kind == .ruleEvidence }.count, 1)
        XCTAssertEqual(result.honingItems.count, 1)
        XCTAssertTrue(result.honingItems[0].detail.contains("Prefer project folders"))
    }

    func testResolveUsesSemanticTagRuleFallback() {
        let file = FileItem(path: "/tmp/notes.txt", name: "notes", extension: "txt", size: 512)
        let suggestion = FolderSuggestion(folderName: "Notes", files: [file], semanticTags: ["rule:rule-2"])

        let rule = InferredRule(
            id: "rule-2",
            pattern: ".*\\.txt$",
            template: "Notes/{filename}",
            priority: 70,
            explanation: "Text notes should stay in Notes"
        )
        let profile = LearningsProfile(inferredRules: [rule])

        let result = FileLearningsAttributionResolver.resolve(file: file, suggestion: suggestion, profile: profile)

        XCTAssertTrue(result.hasContent)
        XCTAssertEqual(result.scope, .fileRuleMatch)
        XCTAssertEqual(result.learningsItems.filter { $0.kind == .learnedRule }.count, 1)
    }

    func testResolveDoesNotUseGlobalHoningAnswersWithoutExplicitEvidence() {
        let file = FileItem(path: "/tmp/image.png", name: "image", extension: "png", size: 4096)
        let suggestion = FolderSuggestion(folderName: "Images", files: [file], ruleId: "rule-3")

        let rule = InferredRule(
            id: "rule-3",
            pattern: ".*\\.png$",
            template: "Images/{filename}",
            priority: 60,
            explanation: "PNG files should go in Images",
            evidenceDescription: "User moved screenshots into Images"
        )
        let profile = LearningsProfile(
            honingAnswers: [HoningAnswer(questionId: "q1", selectedOption: "Always group by project")],
            inferredRules: [rule]
        )

        let result = FileLearningsAttributionResolver.resolve(file: file, suggestion: suggestion, profile: profile)

        XCTAssertTrue(result.hasContent)
        XCTAssertTrue(result.honingItems.isEmpty)
    }
}
