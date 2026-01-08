//
//  LearningsHoningEngine.swift
//  Sorty
//
//  Advanced "Honing" system for deep user profiling.
//  Asking 5-20 questions to refine the mental model of the user.
//

import Foundation
import Combine

public struct HoningSession: Identifiable, Codable, Sendable {
    public let id: String
    public var questions: [HoningQuestion]
    public var answers: [HoningAnswer]
    public var isComplete: Bool
    public let targetQuestionCount: Int
    
    public init(id: String = UUID().uuidString, targetQuestionCount: Int = 5) {
        self.id = id
        self.questions = []
        self.answers = []
        self.isComplete = false
        self.targetQuestionCount = targetQuestionCount
    }
}

@MainActor
public class LearningsHoningEngine: ObservableObject {
    @Published public var currentSession: HoningSession?
    @Published public var isGenerating: Bool = false
    @Published public var error: String?
    public var onComplete: (([HoningAnswer]) -> Void)?
    
    public var aiConfig: AIConfig
    
    private let honingCheckPrompt = """
    You are an expert Psycho-Analyst for Digital Organization Habits.
    Review the user's current answers and profile.
    Do we have enough information to construct a PERFECT optimization model for them?
    
    Reply with JSON:
    {
        "isSufficient": true/false,
        "reasoning": "We still need to know how they handle archiving vs deletion..."
    }
    """
    
    private let questionGenerationPrompt = """
    You are a Senior Systems Architect specializing in Information Architecture.
    Generate a deep, multiple-choice question to clarify the user's file organization philosophy.
    
    FOCUS AREAS:
    - Deletion vs Archiving
    - Depth vs Breadth (Deep folders vs Flat structure)
    - Metadata preference (Date-based vs Content-based)
    - Project Lifecycle (Active -> Archive vs All-Together)
    - File specific handling (RAW photos, Code, Invoices)
    
    CRITICAL RULES:
    1. AVOID duplicative questions. Look at previous q/a context.
    2. NEVER use generic options like "Option A", "Option B", "Yes", "No".
    3. Options MUST be descriptive philosophical choices (e.g., "Sort by Date", "Group by Client").
    4. Provide exactly 3 distinct options.
    
    OUTPUT JSON:
    {
        "text": "When you finish a project, what is your preferred archival strategy?",
        "options": [
            "Move entire project folder to a dedicated Archive directory by year",
            "Keep in main projects folder but tag as 'Archived'",
            "Delete raw assets but keep final deliverables in a Portfolio folder"
        ]
    }
    """
    
    public init(config: AIConfig) {
        self.aiConfig = config
    }
    
    /// Start a new honing session
    public func startSession(questionCount: Int = 5) async {
        currentSession = HoningSession(targetQuestionCount: questionCount)
        await generateNextQuestion()
    }
    
    /// Submit an answer and proceed
    public func submitAnswer(_ answer: HoningAnswer) async {
        guard var session = currentSession else { return }
        
        session.answers.append(answer)
        currentSession = session
        
        if session.answers.count >= session.targetQuestionCount {
            finishSession()
        } else {
            await generateNextQuestion()
        }
    }
    
    private func generateNextQuestion() async {
        isGenerating = true
        error = nil
        
        do {
            var genConfig = aiConfig
            genConfig.maxTokens = 1000
            let client = try AIClientFactory.createClient(config: genConfig)
            
            // Build context from previous answers
            var context = "Context so far:\n"
            if let session = currentSession {
                for answer in session.answers {
                    // Find question text for this answer if possible, or just send IDs
                    // Simplified: just sending raw answer data for now
                    context += "- QID: \(answer.questionId), Answer: \(answer.selectedOption)\n"
                }
            }
            
            let prompt = context + "\n\nGenerate the next critical question."
            let jsonString = try await client.generateText(prompt: prompt, systemPrompt: questionGenerationPrompt)
            
            if let data = cleanAndParseJSON(jsonString) {
                // Use a local DTO to decode since the prompt doesn't match HoningQuestion (missing ID)
                struct AIQuestionResponse: Decodable {
                    let text: String
                    let options: [String]
                }
                
                if let response = try? JSONDecoder().decode(AIQuestionResponse.self, from: data) {
                    let question = HoningQuestion(
                        id: UUID().uuidString,
                        text: response.text,
                        options: response.options
                    )
                    
                    // Verify it's not a duplicate
                    if !(currentSession?.questions.contains(where: { $0.text == question.text }) ?? false) {
                        currentSession?.questions.append(question)
                        UserDefaults.standard.set(0, forKey: "HoningRetryCount") // Reset retry count on success
                    } else {
                        // If duplicate, try again up to 3 times
                        let retryCount = UserDefaults.standard.integer(forKey: "HoningRetryCount")
                        if retryCount < 3 {
                            UserDefaults.standard.set(retryCount + 1, forKey: "HoningRetryCount")
                            await generateNextQuestion()
                            return
                        }
                        
                        // Otherwise just finish if we have enough
                        UserDefaults.standard.set(0, forKey: "HoningRetryCount")
                        if (currentSession?.questions.count ?? 0) > 0 {
                            finishSession()
                        }
                    }
                } else {
                    self.error = "Failed to decode question JSON"
                    LogManager.shared.log("JSON Decode Error. Data: \(String(data: data, encoding: .utf8) ?? "nil")", level: .error, category: "HoningEngine")
                }
            } else {
                self.error = "Failed to parse question from AI"
            }
            
        } catch {
            self.error = "Generation failed: \(error.localizedDescription)"
        }
        
        isGenerating = false
    }
    
    private func finishSession() {
        currentSession?.isComplete = true
        if let answers = currentSession?.answers {
            onComplete?(answers)
        }
    }
    
    private func cleanAndParseJSON(_ input: String) -> Data? {
        var jsonString = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Try to find markdown code blocks
        // Regex to match ```json ... ``` or just ``` ... ```
        // Allowing for optional 'json' tag and dot matches newlines
        let pattern = "```(?:json)?\\s*([\\s\\S]*?)\\s*```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
           let range = Range(match.range(at: 1), in: jsonString) {
            jsonString = String(jsonString[range])
        } else {
            // 2. Fallback: Find first '{' and last '}'
            if let startIndex = jsonString.firstIndex(of: "{"),
               let endIndex = jsonString.lastIndex(of: "}") {
                jsonString = String(jsonString[startIndex...endIndex])
            }
        }
        
        return jsonString.data(using: .utf8)
    }
}
