//
//  PersonaGenerator.swift
//  Sorty
//
//  Generates organization personas from natural language descriptions
//

import Foundation
import Combine

@MainActor

public class PersonaGenerator: ObservableObject {
    @Published public var isGenerating: Bool = false
    @Published public var error: Error?
    
    // Meta-prompt to guide the AI in creating a system prompt
    private let metaSystemPrompt = """
    You are a Senior Data Architect and world-class expert at file organization systems. Your goal is to design a professional, highly specific, and EXTENSIVE (1500+ characters) "System Prompt" based on the user's requirements.

    ### TASK 1: THE NAME
    Create a creative, professional, and evocative name for this persona.
    - CONSTRAINT: The "name" should be short and catchy (max 20 characters).
    - QUALITY: Use natural, readable language. Avoid clunky abbreviations.
    - EXAMPLES: "Galactic Library", "Code Architect", "Photo Archivist", "Project Master"

    ### TASK 2: THE SYSTEM PROMPT (THE TEMPLATE)
    You MUST develop the prompt extensively. Do not be generic. Provide clever, non-obvious organization rules. Use the following EXACT structure:

    ## [Persona Name] Organization Strategy

    ### Primary Grouping
    - Provide a deep philosophical justification for the primary grouping.
    - Describe exactly how files should be clustered (e.g., by project lifecycle, client priority, or thematic content).

    ### File Type Handling
    - **Documents**: Detailed rules for PDFs, Word docs, Spreadsheets. Mention metadata extraction if applicable.
    - **Images**: Detailed rules for JPGs, PNGs, RAW files, Assets. Differentiate between work-in-progress and final exports.
    - **Other**: How to handle archives (.zip), videos (.mp4), or technical files (.json, .csv).

    ### Folder Structure
    Explicitly define a deep, nested folder structure with at least 3 levels of hierarchy.
    Example:
    - [Root]/[Category]/[Year]/[ProjectName]/
    - [Root]/System/Archives/Legacy/

    ### Special Rules
    - **Naming Patterns**: Define specific prefixes or suffixes (e.g., YYYY-MM-DD_FileName).
    - **Edge Cases**: How to handle files that fit in multiple categories or have "Final_v2_final" style names.
    - **Deep Scan Rules**: What specific patterns should the AI look for inside files?
    - **Cleanup**: Rules for moving temporary or ephemeral files to a "Trash" or "Review" folder.

    ### OUTPUT FORMAT
    You MUST return a valid JSON object. No chatter. No markdown blocks.
    {
      "name": "Short catchy name",
      "prompt": "Extensive (1500+ chars) expert-level markdown system prompt..."
    }
    """
    
    public init() {}

    public func generatePersona(from description: String, answers: [HoningAnswer] = [], config: AIConfig) async throws -> (name: String, prompt: String) {
        isGenerating = true
        error = nil
        
        defer {
            isGenerating = false
        }
        
        do {
            // Create a config with high token limit for this specific task
            var genConfig = config
            genConfig.maxTokens = 4000 // Ensure we have enough tokens for 1500+ char prompts
            genConfig.requestTimeout = 180 // Allow more time for deep thinking
            
            let client = try AIClientFactory.createClient(config: genConfig)
            
            var prompt = "User description: \(description)"
            
            if !answers.isEmpty {
                prompt += "\n\n### ARCHITECTURAL ANCHORS (MANDATORY):\n"
                prompt += "The following user choices define the core philosophy of this system. The entire hierarchy, naming pattern, and edge-case logic MUST be built around these anchors:\n"
                for answer in answers {
                    prompt += "- \(answer.selectedOption)\n"
                }
            }
            
            prompt += "\n\nGenerate the JSON for this expert organization persona."
            
            var jsonString = try await client.generateText(prompt: prompt, systemPrompt: metaSystemPrompt)
            
            // Clean up common AI artifacts like ```json ... ```
            if jsonString.contains("```") {
                let lines = jsonString.components(separatedBy: .newlines)
                jsonString = lines.filter { !$0.contains("```") }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            
            // Basic JSON parsing
            guard let data = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
                  let name = json["name"],
                  let generatedPrompt = json["prompt"] else {
                
                // Fallback extraction if JSON is buried in text
                if let nameRange = jsonString.range(of: "\"name\": \""),
                   let nameEnd = jsonString.range(of: "\"", range: nameRange.upperBound..<jsonString.endIndex),
                   let promptRange = jsonString.range(of: "\"prompt\": \""),
                   let promptEnd = jsonString.range(of: "\"", range: promptRange.upperBound..<jsonString.endIndex) {
                    
                    let extractedName = String(jsonString[nameRange.upperBound..<nameEnd.lowerBound])
                    let extractedPrompt = String(jsonString[promptRange.upperBound..<promptEnd.lowerBound])
                    return (enforceNameLength(extractedName), extractedPrompt)
                }
                
                return (enforceNameLength("Custom Persona"), jsonString)
            }
            
            return (enforceNameLength(name), generatedPrompt)
            
        } catch {
            self.error = error
            throw error
        }
    }
    
    private func enforceNameLength(_ name: String) -> String {
        let maxLength = 20
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmed.count > maxLength {
            return String(trimmed.prefix(maxLength))
        }
        return trimmed
    }
}
