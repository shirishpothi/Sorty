//
//  LLMRuleInducer.swift
//  FileOrganizer
//
//  Expert system that uses LLMs to infer organization rules from examples
//  Enhanced with temporal analysis, confidence scoring, and contextual understanding
//

import Foundation

/// Uses AI to induce organization rules from labeled examples
public actor LLMRuleInducer {
    
    private let aiClient: AIClientProtocol
    
    /// Weight multiplier for recent examples (last 7 days)
    private let recentWeightMultiplier: Double = 2.0
    
    /// Weight multiplier for medium-age examples (7-30 days)
    private let mediumWeightMultiplier: Double = 1.5
    
    public init(aiClient: AIClientProtocol) {
        self.aiClient = aiClient
    }
    
    /// Induce rules from examples using LLM reasoning with enhanced context
    public func induceRules(
        from examples: [LabeledExample],
        exampleFolders: [URL],
        honingAnswers: [HoningAnswer] = [],
        steeringPrompts: [SteeringPrompt] = [],
        guidingInstructions: [UserInstruction] = []
    ) async -> [InferredRule] {
        // If no examples, we can't learn anything
        if examples.isEmpty && exampleFolders.isEmpty && steeringPrompts.isEmpty && guidingInstructions.isEmpty {
            return []
        }
        
        // Weight examples by recency
        let weightedExamples = applyTemporalWeighting(examples)
        
        // Prepare prompt for the LLM
        let prompt = buildEnhancedPrompt(
            examples: weightedExamples,
            exampleFolders: exampleFolders,
            honingAnswers: honingAnswers,
            steeringPrompts: steeringPrompts,
            guidingInstructions: guidingInstructions
        )
        
        do {
            // Ask LLM to reason about the rules
            let response = try await aiClient.generateText(prompt: prompt, systemPrompt: enhancedSystemPrompt)
            return parseResponse(response)
        } catch {
            DebugLogger.log("LLM Rule Induction failed: \(error)")
            return []
        }
    }
    
    // MARK: - Temporal Weighting
    
    private struct WeightedExample {
        let example: LabeledExample
        let weight: Double
        let ageCategory: String
    }
    
    private func applyTemporalWeighting(_ examples: [LabeledExample]) -> [WeightedExample] {
        let now = Date()
        let sevenDaysAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)
        
        return examples.map { example in
            let weight: Double
            let ageCategory: String
            
            if example.timestamp > sevenDaysAgo {
                weight = recentWeightMultiplier
                ageCategory = "recent"
            } else if example.timestamp > thirtyDaysAgo {
                weight = mediumWeightMultiplier
                ageCategory = "medium"
            } else {
                weight = 1.0
                ageCategory = "old"
            }
            
            return WeightedExample(example: example, weight: weight, ageCategory: ageCategory)
        }
    }
    
    // MARK: - Prompt Building
    
    private var enhancedSystemPrompt: String {
        """
        You are an expert File Organization Architect. Your goal is to analyze a set of file moves (source -> destination), user feedback, and preferences to infer strict logical rules that govern the user's organization style.
        
        CRITICAL: Weight recent examples and feedback MORE HEAVILY than older ones. The user's most recent behavior is the strongest signal of their preferences.
        
        Output RULES in JSON format. Each rule should have:
        - "pattern": A regex to match source filenames.
        - "template": A destination path template. Use placeholders like {year}, {month}, {date}, {ext}, {filename}, {author}.
        - "explanation": A concise human-readable explanation.
        - "priority": An integer 1-100 (100 is highest). Specific rules (e.g. "Contracts") get higher priority than generic ones (e.g. "PDFs").
        - "confidence": A float 0.0-1.0 indicating how confident you are in this rule based on the evidence.
        
        PRIORITY GUIDELINES:
        - Rules from explicit user feedback (steering prompts, honing answers): 80-100
        - Rules from recent corrections (user moved file after AI): 60-80
        - Rules from older corrections or implicit patterns: 40-60
        - Fallback category-based rules: 20-40
        
        Supported placeholders:
        - {year}, {month}, {day}: Extracted from file creation date or filename date
        - {ext}: File extension
        - {filename}: Original filename
        - {category}: File category (Documents, Media, Code, etc.)
        
        Example Input:
        "Invoice_2023_01.pdf" -> "Finance/2023/Invoices/Invoice_2023_01.pdf"
        
        Example Output Rule:
        {
          "pattern": "Invoice.*\\.pdf$",
          "template": "Finance/{year}/Invoices/{filename}",
          "explanation": "Organize invoices by year",
          "priority": 80,
          "confidence": 0.85
        }
        """
    }
    
    private func buildEnhancedPrompt(
        examples: [WeightedExample],
        exampleFolders: [URL],
        honingAnswers: [HoningAnswer],
        steeringPrompts: [SteeringPrompt],
        guidingInstructions: [UserInstruction]
    ) -> String {
        var context = "Analyze the following user behaviors and preferences to infer organization rules:\n\n"
        
        // 0. Steering Prompts (HIGHEST PRIORITY - Explicit post-organization feedback)
        if !steeringPrompts.isEmpty {
            context += "### USER STEERING PROMPTS (HIGHEST PRIORITY - Apply these exactly):\n"
            context += "These are direct corrections/requests the user made after seeing organization results:\n"
            let recentPrompts = steeringPrompts.suffix(10)
            for prompt in recentPrompts {
                context += "- \"\(prompt.prompt)\"\n"
            }
            context += "\n"
        }
        
        // 1. Honing Answers (High Level Philosophy)
        if !honingAnswers.isEmpty {
            context += "### USER ORGANIZATION PHILOSOPHY:\n"
            context += "The user has explicitly answered these questions about their preferences:\n"
            for answer in honingAnswers {
                context += "- Preference: \(answer.selectedOption)\n"
            }
            context += "\nThese preferences should inform ALL inferred rules.\n\n"
        }
        
        // 2. Guiding Instructions
        if !guidingInstructions.isEmpty {
            context += "### USER GUIDING INSTRUCTIONS:\n"
            let recentInstructions = guidingInstructions.suffix(10)
            for instruction in recentInstructions {
                context += "- \"\(instruction.instruction)\"\n"
            }
            context += "\n"
        }
        
        // 3. Explicit Examples (Weighted by recency)
        if !examples.isEmpty {
            context += "### FILE MOVES (Weighted by recency):\n"
            
            // Sort by weight (recent first)
            let sortedExamples = examples.sorted { $0.weight > $1.weight }
            
            for weightedExample in sortedExamples.prefix(30) {
                let example = weightedExample.example
                let src = URL(fileURLWithPath: example.srcPath).lastPathComponent
                let dst = example.dstPath
                let actionEmoji = example.action == .reject ? "❌ REJECTED" : (example.action == .edit ? "✏️ CORRECTED" : "✅ ACCEPTED")
                let weightLabel = weightedExample.ageCategory == "recent" ? "[RECENT - HIGH WEIGHT]" : (weightedExample.ageCategory == "medium" ? "[MEDIUM AGE]" : "[OLDER]")
                
                context += "- \(weightLabel) \(actionEmoji): \"\(src)\" -> \"\(dst)\"\n"
            }
            context += "\n"
        }
        
        // 4. Folder Structure Examples
        if !exampleFolders.isEmpty {
            context += "### EXISTING STRUCTURE (Implicit preferences from folder names):\n"
            for folder in exampleFolders {
                context += "- Folder: \(folder.lastPathComponent)\n"
            }
            context += "\n"
        }
        
        context += "Based on this evidence, output a JSON array of organization rules. Prioritize rules that address the steering prompts and explicit preferences first."
        return context
    }
    
    // Legacy prompt builder for backwards compatibility
    private func buildPrompt(examples: [LabeledExample], exampleFolders: [URL], honingAnswers: [HoningAnswer]) -> String {
        let weightedExamples = applyTemporalWeighting(examples)
        return buildEnhancedPrompt(
            examples: weightedExamples,
            exampleFolders: exampleFolders,
            honingAnswers: honingAnswers,
            steeringPrompts: [],
            guidingInstructions: []
        )
    }
    
    // MARK: - Parsing
    
    private struct LLMRuleResponse: Codable {
        let pattern: String
        let template: String
        let explanation: String
        let priority: Int
        let confidence: Double?
    }
    
    private func parseResponse(_ response: String) -> [InferredRule] {
        // Extract JSON from potential markdown blocks
        let cleanJson = extractJSON(from: response)
        
        guard let data = cleanJson.data(using: .utf8) else { return [] }
        
        do {
            let llmRules = try JSONDecoder().decode([LLMRuleResponse].self, from: data)
            
            return llmRules.map { rule in
                InferredRule(
                    pattern: rule.pattern,
                    template: rule.template,
                    priority: rule.priority,
                    explanation: rule.explanation
                )
            }
        } catch {
            DebugLogger.log("Failed to parse LLM response: \(error)")
            DebugLogger.log("Raw Response: \(response)")
            return []
        }
    }
    
    private func extractJSON(from text: String) -> String {
        // 1. Try to find JSON markdown blocks: ```json ... ``` or ``` ... ```
        if let startRange = text.range(of: "```json"),
           let endRange = text.range(of: "```", options: .backwards, range: startRange.upperBound..<text.endIndex) {
            let content = text[startRange.upperBound..<endRange.lowerBound]
            return String(content).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let startRange = text.range(of: "```"),
                  let endRange = text.range(of: "```", options: .backwards, range: startRange.upperBound..<text.endIndex) {
            let content = text[startRange.upperBound..<endRange.lowerBound]
            return String(content).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // 2. Fallback: Find the first '[' and last ']' for array response
        if let startRange = text.range(of: "["),
           let endRange = text.range(of: "]", options: .backwards) {
            let range = startRange.lowerBound..<endRange.upperBound
            return String(text[range])
        }
        
        // 3. Fallback: Find the first '{' and last '}' for single object response
        if let startRange = text.range(of: "{"),
           let endRange = text.range(of: "}", options: .backwards) {
            let range = startRange.lowerBound..<endRange.upperBound
            let objectJson = String(text[range])
            // If we found an object but expected an array, wrap it in brackets for the decoder
            return "[\(objectJson)]"
        }
        
        return text
    }
}
