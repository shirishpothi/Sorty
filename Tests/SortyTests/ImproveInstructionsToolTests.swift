//
//  ImproveInstructionsToolTests.swift
//  SortyTests
//

import XCTest
@testable import SortyLib

final class ImproveInstructionsToolTests: XCTestCase {
    func testParsesReplacementAction() {
        let outcome = ImproveInstructionsTool.parse(
            #"{"action":"replace","replacement":"Group invoices by client and year."}"#
        )

        XCTAssertEqual(outcome, .replacement("Group invoices by client and year."))
    }

    func testParsesRequestUserInputAction() {
        let outcome = ImproveInstructionsTool.parse(
            #"{"action":"request_user_input","message":"Add the instruction you want improved."}"#
        )

        XCTAssertEqual(outcome, .needsUserInput("Add the instruction you want improved."))
    }

    func testParsesJSONInsideMarkdownFence() {
        let outcome = ImproveInstructionsTool.parse(
            """
            ```json
            {"action":"replace","replacement":"Keep project files together."}
            ```
            """
        )

        XCTAssertEqual(outcome, .replacement("Keep project files together."))
    }

    func testInterceptsLegacyClarificationProse() {
        let response = "Please provide specific instructions you would like me to improve. Your original input does not contain any text to refine."

        XCTAssertEqual(ImproveInstructionsTool.parse(response), .needsUserInput(response))
    }

    func testInterceptsPlainTextRefusal() {
        let response = "I can't assist with improving those instructions."

        XCTAssertEqual(ImproveInstructionsTool.parse(response), .needsUserInput(response))
    }

    func testPreservesPlainTextFallbackAsReplacement() {
        let response = "Group screenshots by project, then sort each project by capture month."

        XCTAssertEqual(ImproveInstructionsTool.parse(response), .replacement(response))
    }

    func testNaturalLanguageResolverCreatesOrdinaryRules() throws {
        let rules = try NaturalLanguageExclusionResolver.decodeRules(
            from: """
            [
              {"kind":"folder_name","pattern":"Archive","description":"Archive folders"},
              {"kind":"file_size","value":2,"unit":"GB","comparison":"larger","description":"Large files"}
            ]
            """
        )

        XCTAssertEqual(rules.map(\.type), [.folderName, .fileSize])
        XCTAssertEqual(rules[0].pattern, "Archive")
        XCTAssertEqual(rules[1].numericValue, 2_048)
        XCTAssertEqual(rules[1].sizeUnit, .gigabytes)
        XCTAssertTrue(rules.allSatisfy { $0.isAIGenerated == true })
    }

    func testNaturalLanguageResolverPreservesSubdayAge() throws {
        let rule = try XCTUnwrap(
            NaturalLanguageExclusionResolver.decodeRules(
                from: #"[{"kind":"modification_age","value":30,"unit":"minutes","comparison":"newer"}]"#
            ).first
        )

        XCTAssertEqual(rule.type, .modificationDate)
        XCTAssertEqual(rule.ageUnit, .minutes)
        XCTAssertEqual(rule.ageIntervalSeconds, 1_800)
        XCTAssertFalse(try XCTUnwrap(rule.comparisonGreater))
    }
}
