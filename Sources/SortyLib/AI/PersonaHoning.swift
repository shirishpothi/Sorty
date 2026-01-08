//
//  PersonaHoning.swift
//  Sorty
//
//  Logic for refining persona generation through Q&A
//

import Foundation
import Combine

public struct HoningQuestion: Identifiable, Codable, Sendable {
    public let id: String
    public let text: String
    public let options: [String]
    
    public init(id: String = UUID().uuidString, text: String, options: [String]) {
        self.id = id
        self.text = text
        self.options = options
    }
}

public struct HoningAnswer: Identifiable, Codable, Sendable {
    public let id: String
    public let questionId: String
    public let selectedOption: String
    
    public init(id: String = UUID().uuidString, questionId: String, selectedOption: String) {
        self.id = id
        self.questionId = questionId
        self.selectedOption = selectedOption
    }
}

@MainActor
public class PersonaHoningEngine: ObservableObject {
    private let metaQuestionPrompt = """
    You are a Master Systems Architect specializing in Information Theory and Data Governance. Your goal is to refine a user's file organization request into a rigorous, expert-level system.
    
    The user has a rough idea. You must Identify 3 critical "Architectural Tensions" where different sorting philosophies would yield radically different results.
    
    ### CRITICAL ANALYSIS AREAS:
    1. **Primary Dimension**: Should the core hierarchy be Subject-based (What it is), Activity-based (What I'm doing with it), or Temporal (When it happened)?
    2. **Granularity vs. Efficiency**: Deep nested folders for precision, or shallow folders with strict naming patterns for speed?
    3. **Edge Case Philosophy**: How to handle "Multi-category" files or "Orphans" that don't fit the main system?
    
    ### QUESTION GUIDELINES:
    - **Thoughtful**: Don't ask simple yes/no. Ask "How should we weigh X vs Y?"
    - **Impactful**: Every answer must fundamentally change at least 300 characters of the final system prompt.
    - **Options**: Provide 3 distinct, professional philosophies as options.
    
    ### EXAMPLES:
    - *Low Value*: "Do you want to sort by date?"
    - *High Value*: "For project-based work, should we prioritize the Lifecycle Stage (Drafts, Review, Archive) or the Project Entity (Client Name, Case ID) as the primary root?"
    
    OUTPUT FORMAT:
    JSON array of exactly 3 objects. No markdown.
    [
        {
            "id": "q1",
            "text": "Critical architectural question...",
            "options": ["Philosophically distinct option 1", "Philosophically distinct option 2", "Philosophically distinct option 3"]
        }
    ]
    """
    
    public func generateQuestions(from description: String, config: AIConfig) async throws -> [HoningQuestion] {
        var genConfig = config
        genConfig.maxTokens = 2000
        
        let client = try AIClientFactory.createClient(config: genConfig)
        
        let prompt = "User Description: \"\(description)\"\n\nGenerate 3 clarifying questions in JSON format."
        
        var jsonString = try await client.generateText(prompt: prompt, systemPrompt: metaQuestionPrompt)
        
        // Clean markdown
        if jsonString.contains("```") {
             let lines = jsonString.components(separatedBy: .newlines)
             jsonString = lines.filter { !$0.contains("```") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        guard let data = jsonString.data(using: .utf8),
              let questions = try? JSONDecoder().decode([HoningQuestion].self, from: data) else {
            // Fallback if JSON fails (return empty to skip honing)
            LogManager.shared.log("Failed to decode honing questions: \(jsonString)", level: .error, category: "PersonaHoning")
            return []
        }
        
        return questions
    }
}
