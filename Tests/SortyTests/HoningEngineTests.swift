//
//  HoningEngineTests.swift
//  SortyTests
//
//  Comprehensive tests for The Learnings Honing Engine
//

import XCTest
@testable import SortyLib

// MARK: - HoningSession Tests

final class HoningSessionTests: XCTestCase {
    
    func testSessionInitializationWithDefaults() {
        let session = HoningSession()
        
        XCTAssertFalse(session.id.isEmpty)
        XCTAssertTrue(session.questions.isEmpty)
        XCTAssertTrue(session.answers.isEmpty)
        XCTAssertFalse(session.isComplete)
        XCTAssertEqual(session.targetQuestionCount, 5)
        XCTAssertTrue(session.contextualTopics.isEmpty)
    }
    
    func testSessionInitializationWithCustomValues() {
        let session = HoningSession(
            id: "custom-id",
            targetQuestionCount: 10,
            contextualTopics: ["archiving_strategy", "project_organization"]
        )
        
        XCTAssertEqual(session.id, "custom-id")
        XCTAssertEqual(session.targetQuestionCount, 10)
        XCTAssertEqual(session.contextualTopics.count, 2)
        XCTAssertTrue(session.contextualTopics.contains("archiving_strategy"))
    }
    
    func testSessionIsIdentifiable() {
        let session1 = HoningSession(id: "session-1")
        let session2 = HoningSession(id: "session-2")
        
        XCTAssertNotEqual(session1.id, session2.id)
    }
    
    func testSessionCodable() throws {
        let original = HoningSession(
            id: "test-session",
            targetQuestionCount: 7,
            contextualTopics: ["date_based_organization"]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HoningSession.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.targetQuestionCount, original.targetQuestionCount)
        XCTAssertEqual(decoded.contextualTopics, original.contextualTopics)
        XCTAssertEqual(decoded.isComplete, original.isComplete)
    }
    
    func testSessionMutability() {
        var session = HoningSession()
        
        let question = HoningQuestion(id: "q1", text: "Test question?", options: ["A", "B", "C"])
        session.questions.append(question)
        
        XCTAssertEqual(session.questions.count, 1)
        XCTAssertEqual(session.questions.first?.id, "q1")
        
        let answer = HoningAnswer(questionId: "q1", selectedOption: "A")
        session.answers.append(answer)
        
        XCTAssertEqual(session.answers.count, 1)
        
        session.isComplete = true
        XCTAssertTrue(session.isComplete)
    }
}

// MARK: - HoningTopic Tests

final class HoningTopicTests: XCTestCase {
    
    func testAllCasesExist() {
        let allCases = HoningTopic.allCases
        
        XCTAssertTrue(allCases.contains(.archivingStrategy))
        XCTAssertTrue(allCases.contains(.projectOrganization))
        XCTAssertTrue(allCases.contains(.folderDepthPreference))
        XCTAssertTrue(allCases.contains(.dateBasedOrganization))
        XCTAssertTrue(allCases.contains(.fileTypeOrganization))
        XCTAssertTrue(allCases.contains(.duplicateHandling))
        XCTAssertTrue(allCases.contains(.namingConventions))
        XCTAssertTrue(allCases.contains(.frequentCorrections))
    }
    
    func testRawValues() {
        XCTAssertEqual(HoningTopic.archivingStrategy.rawValue, "archiving_strategy")
        XCTAssertEqual(HoningTopic.projectOrganization.rawValue, "project_organization")
        XCTAssertEqual(HoningTopic.folderDepthPreference.rawValue, "folder_depth_preference")
        XCTAssertEqual(HoningTopic.dateBasedOrganization.rawValue, "date_based_organization")
        XCTAssertEqual(HoningTopic.fileTypeOrganization.rawValue, "file_type_organization")
        XCTAssertEqual(HoningTopic.duplicateHandling.rawValue, "duplicate_handling")
        XCTAssertEqual(HoningTopic.namingConventions.rawValue, "naming_conventions")
        XCTAssertEqual(HoningTopic.frequentCorrections.rawValue, "frequent_corrections")
    }
    
    func testPromptContextNotEmpty() {
        for topic in HoningTopic.allCases {
            XCTAssertFalse(topic.promptContext.isEmpty, "Prompt context should not be empty for \(topic)")
            XCTAssertGreaterThan(topic.promptContext.count, 50, "Prompt context should be substantial for \(topic)")
        }
    }
    
    func testSampleQuestionsHaveContent() {
        for topic in HoningTopic.allCases {
            let sample = topic.sampleQuestion
            
            XCTAssertFalse(sample.text.isEmpty, "Sample question text should not be empty for \(topic)")
            XCTAssertTrue(sample.text.contains("?"), "Sample question should be a question for \(topic)")
            XCTAssertEqual(sample.options.count, 3, "Sample should have exactly 3 options for \(topic)")
            
            for option in sample.options {
                XCTAssertFalse(option.isEmpty, "Option should not be empty for \(topic)")
                XCTAssertGreaterThan(option.count, 10, "Options should be descriptive for \(topic)")
            }
        }
    }
    
    func testArchivingStrategySampleQuestion() {
        let sample = HoningTopic.archivingStrategy.sampleQuestion
        
        XCTAssertTrue(sample.text.lowercased().contains("project"))
        XCTAssertTrue(sample.options.contains { $0.contains("Archive") })
    }
    
    func testDuplicateHandlingSampleQuestion() {
        let sample = HoningTopic.duplicateHandling.sampleQuestion
        
        XCTAssertTrue(sample.text.lowercased().contains("duplicate"))
        XCTAssertTrue(sample.options.contains { $0.lowercased().contains("newest") })
        XCTAssertTrue(sample.options.contains { $0.lowercased().contains("oldest") })
    }
    
    func testTopicFromRawValue() {
        XCTAssertEqual(HoningTopic(rawValue: "archiving_strategy"), .archivingStrategy)
        XCTAssertEqual(HoningTopic(rawValue: "project_organization"), .projectOrganization)
        XCTAssertNil(HoningTopic(rawValue: "invalid_topic"))
    }
}

// MARK: - LearningsHoningEngine Tests

@MainActor
final class LearningsHoningEngineTests: XCTestCase {
    
    var engine: LearningsHoningEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        let config = AIConfig(apiKey: "test-key", model: "test-model")
        engine = LearningsHoningEngine(config: config)
    }
    
    override func tearDown() async throws {
        engine = nil
        try await super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertNil(engine.currentSession)
        XCTAssertFalse(engine.isGenerating)
        XCTAssertNil(engine.error)
    }
    
    func testStartSession() async {
        await engine.startSession()
        
        XCTAssertNotNil(engine.currentSession)
        XCTAssertFalse(engine.currentSession!.isComplete)
        XCTAssertEqual(engine.currentSession!.targetQuestionCount, 5)
    }
    
    func testStartSessionWithCustomQuestionCount() async {
        await engine.startSession(questionCount: 10)
        
        XCTAssertNotNil(engine.currentSession)
        XCTAssertEqual(engine.currentSession!.targetQuestionCount, 10)
    }
    
    func testStartSessionWithContextualTopics() async {
        let topics = ["archiving_strategy", "date_based_organization"]
        await engine.startSession(questionCount: 5, contextualTopics: topics)
        
        XCTAssertNotNil(engine.currentSession)
        XCTAssertEqual(engine.currentSession!.contextualTopics, topics)
    }
    
    func testBehaviorContextProperty() {
        XCTAssertNil(engine.behaviorContext)
        
        let context = BehaviorAnalysisContext(
            recentCorrectionCount: 5,
            recentRevertCount: 2,
            topDestinationFolders: ["Documents", "Archive"],
            topFileTypes: ["pdf", "jpg"],
            frequentPatterns: ["date_based"]
        )
        
        engine.behaviorContext = context
        
        XCTAssertNotNil(engine.behaviorContext)
        XCTAssertEqual(engine.behaviorContext?.recentCorrectionCount, 5)
    }
    
    func testIsGeneratingStartsFalse() {
        XCTAssertFalse(engine.isGenerating)
    }
    
    func testErrorStartsNil() {
        XCTAssertNil(engine.error)
    }
    
    func testSubmitAnswerWithSession() async {
        await engine.startSession()
        
        // Manually add a question to simulate flow
        var session = engine.currentSession!
        let question = HoningQuestion(id: "q1", text: "Test?", options: ["A", "B", "C"])
        session.questions.append(question)
        engine.currentSession = session
        
        let answer = HoningAnswer(questionId: "q1", selectedOption: "A")
        await engine.submitAnswer(answer)
        
        XCTAssertEqual(engine.currentSession!.answers.count, 1)
        XCTAssertEqual(engine.currentSession!.answers.first?.questionId, "q1")
        XCTAssertEqual(engine.currentSession!.answers.first?.selectedOption, "A")
    }
    
    func testOnCompleteCallback() async {
        var callbackInvoked = false
        var receivedAnswers: [HoningAnswer]?
        
        engine.onComplete = { answers in
            callbackInvoked = true
            receivedAnswers = answers
        }
        
        await engine.startSession(questionCount: 1)
        
        // Add and answer a question
        var session = engine.currentSession!
        let question = HoningQuestion(id: "q1", text: "Test?", options: ["A", "B", "C"])
        session.questions.append(question)
        engine.currentSession = session
        
        let answer = HoningAnswer(questionId: "q1", selectedOption: "B")
        await engine.submitAnswer(answer)
        
        // Session should complete after answering target number of questions
        XCTAssertTrue(callbackInvoked)
        XCTAssertEqual(receivedAnswers?.count, 1)
        XCTAssertEqual(receivedAnswers?.first?.selectedOption, "B")
    }
}

// MARK: - BehaviorAnalysisContext Tests

final class BehaviorAnalysisContextTests: XCTestCase {
    
    func testDefaultInitialization() {
        let context = BehaviorAnalysisContext()
        
        XCTAssertEqual(context.recentCorrectionCount, 0)
        XCTAssertEqual(context.recentRevertCount, 0)
        XCTAssertTrue(context.topDestinationFolders.isEmpty)
        XCTAssertTrue(context.topFileTypes.isEmpty)
        XCTAssertTrue(context.frequentPatterns.isEmpty)
    }
    
    func testCustomInitialization() {
        let context = BehaviorAnalysisContext(
            recentCorrectionCount: 10,
            recentRevertCount: 3,
            topDestinationFolders: ["Projects", "Documents", "Archive"],
            topFileTypes: ["pdf", "docx", "xlsx"],
            frequentPatterns: ["by_date", "by_project"]
        )
        
        XCTAssertEqual(context.recentCorrectionCount, 10)
        XCTAssertEqual(context.recentRevertCount, 3)
        XCTAssertEqual(context.topDestinationFolders.count, 3)
        XCTAssertEqual(context.topFileTypes.count, 3)
        XCTAssertEqual(context.frequentPatterns.count, 2)
    }
    
    func testSendableConformance() {
        let context = BehaviorAnalysisContext(
            recentCorrectionCount: 5,
            recentRevertCount: 1,
            topDestinationFolders: ["Downloads"],
            topFileTypes: ["jpg"],
            frequentPatterns: []
        )
        
        // Should be usable in concurrent contexts (Sendable conformance)
        Task {
            let _ = context.recentCorrectionCount
        }
        
        XCTAssertTrue(true) // If we got here, Sendable conformance works
    }
}

// MARK: - HoningQuestion Tests

final class HoningQuestionTests: XCTestCase {
    
    func testQuestionCreation() {
        let question = HoningQuestion(
            id: "q-123",
            text: "How do you prefer to organize documents?",
            options: ["By date", "By project", "By type"]
        )
        
        XCTAssertEqual(question.id, "q-123")
        XCTAssertEqual(question.text, "How do you prefer to organize documents?")
        XCTAssertEqual(question.options.count, 3)
    }
    
    func testQuestionCodable() throws {
        let original = HoningQuestion(
            id: "q-test",
            text: "Test question?",
            options: ["Option 1", "Option 2", "Option 3"]
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HoningQuestion.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.text, original.text)
        XCTAssertEqual(decoded.options, original.options)
    }
    
    func testQuestionWithEmptyOptions() {
        let question = HoningQuestion(id: "q1", text: "Empty?", options: [])
        
        XCTAssertTrue(question.options.isEmpty)
    }
    
    func testQuestionWithManyOptions() {
        let options = (1...10).map { "Option \($0)" }
        let question = HoningQuestion(id: "q1", text: "Many options?", options: options)
        
        XCTAssertEqual(question.options.count, 10)
    }
}

// MARK: - HoningAnswer Tests

final class HoningAnswerTests: XCTestCase {
    
    func testAnswerCreation() {
        let answer = HoningAnswer(questionId: "q-123", selectedOption: "By date")
        
        XCTAssertEqual(answer.questionId, "q-123")
        XCTAssertEqual(answer.selectedOption, "By date")
    }
    
    func testAnswerCodable() throws {
        let original = HoningAnswer(questionId: "q-test", selectedOption: "Option A")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HoningAnswer.self, from: data)
        
        XCTAssertEqual(decoded.questionId, original.questionId)
        XCTAssertEqual(decoded.selectedOption, original.selectedOption)
    }
    
    func testAnswerIdentifiable() {
        let answer = HoningAnswer(questionId: "q1", selectedOption: "A")
        
        // HoningAnswer should have an id property for Identifiable
        XCTAssertFalse(answer.id.isEmpty)
    }
}

// MARK: - Integration Tests

@MainActor
final class HoningEngineIntegrationTests: XCTestCase {
    
    func testFullSessionFlow() async {
        let config = AIConfig(apiKey: "test", model: "test")
        let engine = LearningsHoningEngine(config: config)
        
        var completionCalled = false
        engine.onComplete = { (_: [HoningAnswer]) in
            completionCalled = true
        }
        
        // Start session
        await engine.startSession(questionCount: 2)
        XCTAssertNotNil(engine.currentSession)
        
        // Add first question and answer
        var session = engine.currentSession!
        session.questions.append(HoningQuestion(id: "q1", text: "Q1?", options: ["A", "B"]))
        engine.currentSession = session
        await engine.submitAnswer(HoningAnswer(questionId: "q1", selectedOption: "A"))
        
        // Add second question and answer
        session = engine.currentSession!
        session.questions.append(HoningQuestion(id: "q2", text: "Q2?", options: ["X", "Y"]))
        engine.currentSession = session
        await engine.submitAnswer(HoningAnswer(questionId: "q2", selectedOption: "Y"))
        
        // Session should be complete
        XCTAssertTrue(engine.currentSession!.isComplete)
        XCTAssertTrue(completionCalled)
        XCTAssertEqual(engine.currentSession!.answers.count, 2)
    }
}
