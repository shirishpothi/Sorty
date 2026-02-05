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
You are a file organization system designer. Create a specialized organization persona.

# OUTPUT REQUIREMENTS (STRICT)

Return ONLY valid JSON. No markdown code blocks, no explanations.

```
{"name": "ShortName", "prompt": "The system prompt text..."}
```

## Field Requirements
- **name**: 3-20 characters, catchy, professional (e.g., "Code Vault", "Photo Archive", "Project Hub")
- **prompt**: 800-2000 characters, markdown-formatted organization instructions

# PROMPT GENERATION RULES

## Required Sections in Generated Prompt
The "prompt" field MUST include these sections:

### 1. Philosophy (2-3 sentences)
Core organizing principle for this persona's domain.

### 2. Primary Grouping
How to cluster files (by project, date, client, type, etc.)

### 3. Folder Structure  
Define hierarchy with examples:
- [Root]/[Category]/[Subcategory]/
- Maximum 3 levels deep

### 4. File Handling by Type
Rules for documents, images, archives relevant to this domain.

### 5. Naming Conventions
Prefixes, date formats, separators to use.

## CRITICAL CONSTRAINTS

The generated prompt MUST be compatible with the base organization system:
- DO NOT override the JSON output format (the base system handles this)
- DO NOT specify different tag requirements (base requires 1-3 tags per file)
- DO NOT change folder depth limits (max 3 levels)
- Focus ONLY on: categorization logic, naming patterns, folder structure philosophy

The prompt should ADD specialized knowledge, not REPLACE base functionality.

## AVOID
- Generic advice like "organize by type" without specifics
- Contradicting base system rules
- Specifying output format (already defined in base system)
- Mentioning tags (base system handles tagging requirements)

# EXAMPLES

Good name: "Dev Workspace" | Bad name: "The Ultimate Developer File Organization System"
Good prompt focus: "Group by language, then by project maturity (active/archived)"
Bad prompt focus: "Return JSON with folders array..." (duplicates base system)
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
