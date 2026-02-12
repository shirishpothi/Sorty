//
//  LearningsEdgeCaseTests.swift
//  SortyTests
//
//  Edge case tests for LearningsManager: contradictory rules, ambiguous input,
//  auto-disable, learning strength, empty profiles, and data retention
//

import XCTest
@testable import SortyLib

@MainActor
final class LearningsEdgeCaseTests: XCTestCase {
    
    var manager: LearningsManager!
    
    override func setUp() async throws {
        manager = LearningsManager()
        manager.currentProfile = LearningsProfile()
        await manager.grantConsent()
    }
    
    override func tearDown() async throws {
        manager = nil
    }
    
    // MARK: - Contradictory Rules
    
    func testContradictoryRulesHigherPriorityWins() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        let rule1 = InferredRule(
            pattern: ".*\\.pdf",
            template: "Documents/{filename}",
            priority: 50,
            explanation: "Move PDFs to Documents"
        )
        let rule2 = InferredRule(
            pattern: ".*\\.pdf",
            template: "Archive/{filename}",
            priority: 90,
            explanation: "Move PDFs to Archive"
        )
        
        profile.inferredRules = [rule1, rule2]
        manager.currentProfile = profile
        manager.learningStrength = 1.0
        
        let activeRules = manager.getActiveRules()
        
        XCTAssertFalse(activeRules.isEmpty)
        XCTAssertEqual(activeRules.first?.explanation, "Move PDFs to Archive",
                       "Higher priority rule should come first")
    }
    
    func testContradictoryRulesDisabledRuleExcluded() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        let rule1 = InferredRule(
            pattern: ".*\\.pdf",
            template: "Documents/{filename}",
            priority: 90,
            explanation: "Move PDFs to Documents",
            isEnabled: false
        )
        let rule2 = InferredRule(
            pattern: ".*\\.pdf",
            template: "Archive/{filename}",
            priority: 50,
            explanation: "Move PDFs to Archive",
            isEnabled: true
        )
        
        profile.inferredRules = [rule1, rule2]
        manager.currentProfile = profile
        manager.learningStrength = 1.0
        
        let activeRules = manager.getActiveRules()
        
        XCTAssertEqual(activeRules.count, 1)
        XCTAssertEqual(activeRules.first?.explanation, "Move PDFs to Archive")
    }
    
    // MARK: - Ambiguous Input Tests
    
    func testAmbiguousAnswerWithBothArchiveAndDelete() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "archive old files and delete duplicates")
        ]
        manager.currentProfile = profile
        
        manager.extractBehaviorPreferences()
        
        XCTAssertNotNil(manager.behaviorPreferences)
        // "archive" appears before "delete", so archive preference wins in iteration
        XCTAssertEqual(manager.behaviorPreferences?.deletionVsArchive, .archive)
    }
    
    func testAmbiguousAnswerDeleteOnlyKeyword() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "delete everything old")
        ]
        manager.currentProfile = profile
        
        manager.extractBehaviorPreferences()
        
        XCTAssertEqual(manager.behaviorPreferences?.deletionVsArchive, .delete)
    }
    
    func testAmbiguousAnswerArchiveByYear() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "archive files by year")
        ]
        manager.currentProfile = profile
        
        manager.extractBehaviorPreferences()
        
        XCTAssertEqual(manager.behaviorPreferences?.deletionVsArchive, .archiveByYear)
    }
    
    func testMultipleHoningAnswersCombine() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "Use flat structure"),
            HoningAnswer(questionId: "q2", selectedOption: "Organize by date and year"),
            HoningAnswer(questionId: "q3", selectedOption: "Keep the newest version")
        ]
        manager.currentProfile = profile
        
        manager.extractBehaviorPreferences()
        
        XCTAssertEqual(manager.behaviorPreferences?.folderDepthPreference, .flat)
        XCTAssertEqual(manager.behaviorPreferences?.dateVsContentPreference, .date)
        XCTAssertEqual(manager.behaviorPreferences?.duplicateKeeperStrategy, .keepNewest)
    }
    
    func testProjectOrganizationPreference() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "Organize by project name")
        ]
        manager.currentProfile = profile
        
        manager.extractBehaviorPreferences()
        
        XCTAssertEqual(manager.behaviorPreferences?.dateVsContentPreference, .project)
    }
    
    func testDeepHierarchyPreference() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "Use deep hierarchy for everything")
        ]
        manager.currentProfile = profile
        
        manager.extractBehaviorPreferences()
        
        XCTAssertEqual(manager.behaviorPreferences?.folderDepthPreference, .deep)
    }
    
    // MARK: - Rule Auto-Disable Tests
    
    func testRuleAutoDisableOnHighFailureRate() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        let rule = InferredRule(
            id: "test-rule",
            pattern: ".*\\.txt",
            template: "TextFiles/{filename}",
            priority: 50,
            explanation: "Move text files",
            successCount: 1,
            failureCount: 0
        )
        profile.inferredRules = [rule]
        manager.currentProfile = profile
        
        // Record failures until auto-disable triggers (failureRate > 0.3 && total >= 5)
        for _ in 0..<5 {
            manager.recordRuleFailure(ruleId: "test-rule")
        }
        
        let updatedRule = manager.currentProfile?.inferredRules.first
        XCTAssertNotNil(updatedRule)
        XCTAssertFalse(updatedRule!.isEnabled, "Rule should be auto-disabled after high failure rate")
        XCTAssertGreaterThan(updatedRule!.failureRate, 0.3)
    }
    
    func testRuleNotDisabledWithLowFailureRate() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        let rule = InferredRule(
            id: "good-rule",
            pattern: ".*\\.jpg",
            template: "Photos/{filename}",
            priority: 70,
            explanation: "Move photos",
            successCount: 10,
            failureCount: 0
        )
        profile.inferredRules = [rule]
        manager.currentProfile = profile
        
        manager.recordRuleFailure(ruleId: "good-rule")
        
        let updatedRule = manager.currentProfile?.inferredRules.first
        XCTAssertNotNil(updatedRule)
        XCTAssertTrue(updatedRule!.isEnabled, "Rule with low failure rate should remain enabled")
        XCTAssertEqual(updatedRule!.failureCount, 1)
    }
    
    func testRecordRuleFailureForNonexistentRule() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.inferredRules = []
        manager.currentProfile = profile
        
        manager.recordRuleFailure(ruleId: "nonexistent-rule")
        
        XCTAssertTrue(manager.currentProfile!.inferredRules.isEmpty,
                       "Recording failure for nonexistent rule should be a no-op")
    }
    
    // MARK: - Learning Strength Tests
    
    func testLearningStrengthZeroReturnsMinimalRules() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        for i in 0..<10 {
            profile.inferredRules.append(
                InferredRule(
                    pattern: ".*\\.\(i)",
                    template: "Folder\(i)/{filename}",
                    priority: i * 10,
                    explanation: "Rule \(i)"
                )
            )
        }
        manager.currentProfile = profile
        manager.learningStrength = 0.0
        
        let activeRules = manager.getActiveRules()
        
        // With strength 0.0: Int(0.0 * 10) + 1 = 1
        XCTAssertEqual(activeRules.count, 1,
                       "Learning strength 0.0 should return only 1 rule (the +1 minimum)")
    }
    
    func testLearningStrengthOneReturnsAllRules() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        for i in 0..<5 {
            profile.inferredRules.append(
                InferredRule(
                    pattern: ".*\\.\(i)",
                    template: "Folder\(i)/{filename}",
                    priority: i * 10,
                    explanation: "Rule \(i)"
                )
            )
        }
        manager.currentProfile = profile
        manager.learningStrength = 1.0
        
        let activeRules = manager.getActiveRules()
        
        // With strength 1.0: Int(1.0 * 5) + 1 = 6, but only 5 rules exist
        XCTAssertEqual(activeRules.count, 5)
    }
    
    func testLearningStrengthHalfReturnsSubset() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        for i in 0..<10 {
            profile.inferredRules.append(
                InferredRule(
                    pattern: ".*\\.\(i)",
                    template: "Folder\(i)/{filename}",
                    priority: i * 10,
                    explanation: "Rule \(i)"
                )
            )
        }
        manager.currentProfile = profile
        manager.learningStrength = 0.5
        
        let activeRules = manager.getActiveRules()
        
        // With strength 0.5: Int(0.5 * 10) + 1 = 6
        XCTAssertEqual(activeRules.count, 6)
        XCTAssertEqual(activeRules.first?.priority, 90,
                       "Highest priority rules should be returned first")
    }
    
    func testActiveRulesSortedByPriority() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        
        profile.inferredRules = [
            InferredRule(pattern: "a", template: "A/", priority: 10, explanation: "Low priority"),
            InferredRule(pattern: "b", template: "B/", priority: 90, explanation: "High priority"),
            InferredRule(pattern: "c", template: "C/", priority: 50, explanation: "Medium priority"),
        ]
        manager.currentProfile = profile
        manager.learningStrength = 1.0
        
        let activeRules = manager.getActiveRules()
        
        XCTAssertEqual(activeRules[0].priority, 90)
        XCTAssertEqual(activeRules[1].priority, 50)
        XCTAssertEqual(activeRules[2].priority, 10)
    }
    
    // MARK: - Empty / Nil Profile Tests
    
    func testGetActiveRulesWithNilProfile() {
        manager.currentProfile = nil
        
        let rules = manager.getActiveRules()
        XCTAssertTrue(rules.isEmpty, "getActiveRules should return empty array when profile is nil")
    }
    
    func testExtractBehaviorPreferencesWithNilProfile() {
        manager.currentProfile = nil
        
        manager.extractBehaviorPreferences()
        
        XCTAssertNil(manager.behaviorPreferences,
                      "extractBehaviorPreferences should not set preferences when profile is nil")
    }
    
    func testExtractBehaviorPreferencesWithEmptyAnswers() {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = []
        manager.currentProfile = profile
        
        manager.extractBehaviorPreferences()
        
        XCTAssertNotNil(manager.behaviorPreferences)
        // Should return defaults
        XCTAssertEqual(manager.behaviorPreferences?.deletionVsArchive, .archive)
        XCTAssertEqual(manager.behaviorPreferences?.folderDepthPreference, .balanced)
        XCTAssertEqual(manager.behaviorPreferences?.dateVsContentPreference, .content)
        XCTAssertEqual(manager.behaviorPreferences?.duplicateKeeperStrategy, .keepNewest)
    }
    
    func testGeneratePromptContextWithNilProfile() {
        manager.currentProfile = nil
        
        let context = manager.generatePromptContext()
        XCTAssertTrue(context.isEmpty, "Context should be empty with nil profile")
    }
    
    func testEmptyProfileHasNoRulesOrExamples() {
        let profile = LearningsProfile()
        
        XCTAssertTrue(profile.inferredRules.isEmpty)
        XCTAssertTrue(profile.corrections.isEmpty)
        XCTAssertTrue(profile.rejections.isEmpty)
        XCTAssertTrue(profile.positiveExamples.isEmpty)
        XCTAssertTrue(profile.honingAnswers.isEmpty)
        XCTAssertTrue(profile.additionalInstructionsHistory.isEmpty)
        XCTAssertTrue(profile.postOrganizationChanges.isEmpty)
        XCTAssertTrue(profile.historyReverts.isEmpty)
        XCTAssertTrue(profile.jobHistory.isEmpty)
        XCTAssertFalse(profile.consentGranted)
    }
    
    // MARK: - Data Retention Tests
    
    func testDataRetentionDaysDefault() {
        let freshManager = LearningsManager()
        // Default from UserDefaults is 0 (no retention limit)
        XCTAssertEqual(freshManager.dataRetentionDays, UserDefaults.standard.integer(forKey: "learningDataRetentionDays"))
    }
    
    func testDataRetentionDaysPersists() {
        manager.dataRetentionDays = 90
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "learningDataRetentionDays"), 90)
        
        manager.dataRetentionDays = 0
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "learningDataRetentionDays"), 0)
    }
    
    func testLearningStrengthPersists() {
        manager.learningStrength = 0.75
        XCTAssertEqual(UserDefaults.standard.double(forKey: "learningStrength"), 0.75)
    }
    
    // MARK: - InferredRule Model Edge Cases
    
    func testFailureRateWithZeroUsage() {
        let rule = InferredRule(
            pattern: ".*",
            template: "{filename}",
            priority: 50,
            explanation: "Test",
            successCount: 0,
            failureCount: 0
        )
        
        XCTAssertEqual(rule.failureRate, 0)
        XCTAssertEqual(rule.successRate, 0)
    }
    
    func testFailureRateCalculation() {
        let rule = InferredRule(
            pattern: ".*",
            template: "{filename}",
            priority: 50,
            explanation: "Test",
            successCount: 7,
            failureCount: 3
        )
        
        XCTAssertEqual(rule.failureRate, 0.3)
        XCTAssertEqual(rule.successRate, 0.7)
    }
    
    func testConfidenceLevelHighFromUsageData() {
        let rule = InferredRule(
            pattern: ".*",
            template: "{filename}",
            priority: 50,
            explanation: "Test",
            successCount: 10,
            failureCount: 0,
            supportCount: 5
        )
        
        XCTAssertEqual(rule.confidenceLevel, .high)
    }
    
    func testConfidenceLevelLowFromHighFailure() {
        let rule = InferredRule(
            pattern: ".*",
            template: "{filename}",
            priority: 50,
            explanation: "Test",
            successCount: 1,
            failureCount: 4
        )
        
        XCTAssertEqual(rule.confidenceLevel, .low)
    }
    
    func testConfidenceLevelFallsBackToInitialConfidence() {
        let rule = InferredRule(
            pattern: ".*",
            template: "{filename}",
            priority: 50,
            explanation: "Test",
            successCount: 0,
            failureCount: 0,
            initialConfidence: .high
        )
        
        XCTAssertEqual(rule.confidenceLevel, .high)
    }
    
    func testConfidenceLevelDefaultMedium() {
        let rule = InferredRule(
            pattern: ".*",
            template: "{filename}",
            priority: 50,
            explanation: "Test",
            successCount: 0,
            failureCount: 0,
            supportCount: 2
        )
        
        XCTAssertEqual(rule.confidenceLevel, .medium)
    }
    
    // MARK: - Profile Behavior Tracking Edge Cases
    
    func testProfileWithMaximumDataRetention() {
        let profile = LearningsProfile(
            additionalInstructionsHistory: (0..<100).map {
                UserInstruction(instruction: "Instruction \($0)")
            },
            honingAnswers: (0..<50).map {
                HoningAnswer(questionId: "q\($0)", selectedOption: "Option \($0)")
            },
            inferredRules: (0..<20).map {
                InferredRule(pattern: "\($0)", template: "\($0)/", priority: $0, explanation: "Rule \($0)")
            }
        )
        
        XCTAssertEqual(profile.additionalInstructionsHistory.count, 100)
        XCTAssertEqual(profile.honingAnswers.count, 50)
        XCTAssertEqual(profile.inferredRules.count, 20)
    }
    
    func testProfileCodableRoundTrip() throws {
        var profile = LearningsProfile()
        profile.consentGranted = true
        profile.honingAnswers = [
            HoningAnswer(questionId: "q1", selectedOption: "flat structure")
        ]
        profile.inferredRules = [
            InferredRule(pattern: ".*\\.pdf", template: "Docs/{filename}", priority: 80, explanation: "PDFs to Docs")
        ]
        profile.additionalInstructionsHistory = [
            UserInstruction(instruction: "Keep everything organized by type")
        ]
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(profile)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LearningsProfile.self, from: data)
        
        XCTAssertEqual(decoded.consentGranted, true)
        XCTAssertEqual(decoded.honingAnswers.count, 1)
        XCTAssertEqual(decoded.honingAnswers.first?.selectedOption, "flat structure")
        XCTAssertEqual(decoded.inferredRules.count, 1)
        XCTAssertEqual(decoded.inferredRules.first?.pattern, ".*\\.pdf")
        XCTAssertEqual(decoded.additionalInstructionsHistory.count, 1)
    }
}
