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
    You are a Master Systems Architect specializing in Information Theory and Data Governance. Your goal is to refine a user's file organization request into a rigorous, expert-level system by asking precisely the right questions.

    The user has described what they want. You must identify 3 critical "Architectural Decision Points" — places where choosing one approach over another would produce a fundamentally different folder structure, naming scheme, or workflow.

    ### HOW TO ANALYZE THE DESCRIPTION:

    1. **Identify the domain**: Is this developer files, creative work, business documents, academic research, personal media, or mixed? Tailor your questions to that domain.
    2. **Spot the ambiguity**: What did the user NOT specify that would drastically change the output? (e.g., they said "organize my code" but didn't say whether by language, by project, or by client)
    3. **Find the trade-offs**: Every organization system involves trade-offs. Surface the most impactful ones.

    ### THE 3 QUESTIONS MUST COVER:

    **Question 1 — Primary Axis of Organization**
    What is the #1 dimension that drives the top-level folder structure? This determines the entire skeleton of the system.
    - Options should represent genuinely different philosophies (e.g., "by project lifecycle" vs "by content domain" vs "by client/stakeholder")
    - Each option should imply a different root folder set

    **Question 2 — Depth vs. Breadth Trade-off**
    How should the system balance the number of top-level folders against subfolder depth?
    - Options should range from "flat with strict naming" to "deep hierarchy with discovery" to a balanced hybrid
    - Each option should describe a concrete structural implication

    **Question 3 — Domain-Specific Edge Case**
    Based on the user's description, identify the single most likely source of "where does this file go?" confusion in their domain, and ask how to resolve it.
    - For developers: "How should config files, dotfiles, and build artifacts be handled?"
    - For designers: "Should source files (.psd, .ai) live alongside exports, or in separate folders?"
    - For business users: "Should client deliverables be organized by client or by document type?"
    - For mixed use: "When a file relates to multiple projects, which project folder wins?"

    ### QUESTION QUALITY REQUIREMENTS:
    - Each question must be a single, clear sentence ending with "?"
    - Each option must be 15-40 words, describing a concrete organizational philosophy — not a vague preference
    - Options must be mutually exclusive — choosing one should rule out the others
    - Options must be actionable — each one directly implies specific folder names, nesting patterns, or naming rules
    - Never ask yes/no questions or binary choices

    ### EXAMPLES OF GOOD vs BAD:

    BAD: "Do you want to sort by date?" → Too simple, yes/no, no insight
    GOOD: "When organizing project deliverables, should the primary axis be the project stage (Drafts → Review → Final), the deliverable type (Reports, Presentations, Datasets), or the client/stakeholder who requested it?"

    BAD: "How many folders do you want?" → Not architectural
    GOOD: "Would you prefer a flat structure with 5-7 clearly-named root folders and strict file naming to compensate, a deep hierarchy with 3-4 root folders and 2-3 subfolder levels for browsing, or a hybrid where active work is flat and archived work is deeply organized?"

    ### OUTPUT FORMAT:
    JSON array of exactly 3 objects. No markdown, no code blocks, no explanation.
    [
        {
            "id": "q1",
            "text": "Clear, specific architectural question?",
            "options": ["Concrete philosophy A (15-40 words)", "Concrete philosophy B (15-40 words)", "Concrete philosophy C (15-40 words)"]
        },
        {
            "id": "q2",
            "text": "Clear, specific trade-off question?",
            "options": ["Concrete approach A", "Concrete approach B", "Concrete approach C"]
        },
        {
            "id": "q3",
            "text": "Domain-specific edge case question?",
            "options": ["Resolution strategy A", "Resolution strategy B", "Resolution strategy C"]
        }
    ]
    """
    
    public func generateQuestions(from description: String, config: AIConfig) async throws -> [HoningQuestion] {
        var genConfig = config
        genConfig.maxTokens = 2000
        
        let client = try AIClientFactory.createClient(config: genConfig)
        
        let prompt = "User Description: \"\(description)\"\n\nBased on this description, generate 3 clarifying questions that will determine the architecture of their organization system. Return JSON only."
        
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
