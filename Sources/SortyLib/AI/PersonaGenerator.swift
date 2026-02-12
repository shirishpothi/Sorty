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
You are a world-class Information Architect. Your job is to design a specialized file organization persona — a detailed, opinionated system prompt that will guide an AI to organize files exactly as an expert in that domain would.

# OUTPUT REQUIREMENTS (STRICT)

Return ONLY valid JSON. No markdown code blocks, no explanations, no text outside the JSON.

```
{"name": "ShortName", "prompt": "The system prompt text..."}
```

## Field Requirements
- **name**: 3-20 characters, catchy, professional (e.g., "Code Vault", "Photo Archive", "Legal Desk", "Studio Flow")
- **prompt**: 1500-3000 characters, richly detailed, domain-specific organization instructions

# PROMPT GENERATION BLUEPRINT

The "prompt" field you generate MUST contain ALL of the following sections, clearly labeled with markdown headers. Prompts that are vague, generic, or under 1500 characters are UNACCEPTABLE.

## Section 1: Philosophy (3-4 sentences)
Define the core organizing principle. What mental model does this persona use? What does "organized" mean in this domain? State the single most important axis of organization (by project? by client? by date? by workflow stage?) and WHY.

Example for a Developer persona: "Code is organized by project lifecycle. Active work is separated from archived experiments. Every repository-like structure stays intact — never split source files from their configs. The goal is: open a project folder and have everything you need to build, test, and deploy."

## Section 2: Primary Grouping Strategy
Define the top-level folder hierarchy explicitly. Provide 4-7 concrete folder names this persona would use, with one-line descriptions. State what axis drives the top level (topic, client, date, workflow stage) and what drives the second level.

Example for a Photographer persona:
- Shoots/ — Active and recent photo sessions, grouped by date or event
- Portfolio/ — Curated final selects for showcase
- Stock/ — Licensed or licensable images
- Archive/ — Completed, delivered, or older work
- Resources/ — Presets, overlays, templates, LUTs

## Section 3: Hierarchy Template
Provide a concrete folder tree example showing 2-3 levels of nesting. Use realistic filenames.

Example:
Projects/
  ClientName ProjectTitle/
    Deliverables/
    Working Files/
    Reference/
  Another Project/
    ...

## Section 4: File Type Rules
For the 4-6 most relevant file types in this domain, state EXACTLY where they go. Be specific — don't just say "documents go in Documents."

Example for a Designer:
- .psd/.ai/.sketch → Working Files/ under the relevant project
- .png/.jpg (exports) → Deliverables/ under the relevant project
- .ttf/.otf (fonts) → Resources/Fonts/
- .pdf (briefs, contracts) → the project's Reference/ subfolder

## Section 5: Naming Conventions
Define the naming pattern files and folders should follow. Include separator style, date format, and any required prefixes/suffixes.

Example: "Use snake_case. Prefix client-facing deliverables with the client code. Dates use YYYY-MM-DD. Version suffixes: _v1, _v2, _final. Example: acme_brand_guide_v2_2026-01-15.pdf"

## Section 6: Edge Cases & Special Rules
Address 3-5 domain-specific edge cases. What happens with ambiguous files? How are temp files handled? What about files that span multiple projects?

Example for a Developer:
- .env, .gitignore, Makefile → Stay at project root, never move into subfolders
- node_modules/, .build/, __pycache__/ → Flag as "generated" and suggest exclusion
- README.md → Always stays at project root
- Files outside any project context → go to a "Sandbox/" or "Snippets/" catch-all

## Section 7: Priority Rules
When the persona's rules conflict with general organization heuristics, state which wins. List 2-3 explicit priority overrides.

Example: "Project cohesion > file type grouping. A .png that belongs to a code project stays in that project's assets folder, NOT in a global Images folder. Workflow stage > alphabetical sorting."

# CRITICAL CONSTRAINTS

The generated prompt MUST be compatible with the base organization system:
- DO NOT override the JSON output format (the base system handles this)
- DO NOT specify different tag requirements (base system requires 1-3 tags per file)
- DO NOT change folder depth limits (max 3 levels)
- Focus ONLY on: categorization logic, naming patterns, folder structure philosophy, domain-specific intelligence
- The prompt should ADD specialized knowledge on top of the base system, not REPLACE it

# DOMAIN INTELLIGENCE HINTS

If the description mentions development/coding, include knowledge of: .gitignore, build folders, package managers (node_modules, .build, target/), config files, README placement, test file conventions.

If the description mentions photography/media, include knowledge of: RAW vs processed, sidecar files (.xmp), EXIF-based grouping, portfolio curation, client delivery structure.

If the description mentions business/legal, include knowledge of: client-matter organization, retention policies, version control for contracts, regulatory document types.

If the description mentions academia/research, include knowledge of: citation files (.bib), datasets, paper drafts, LaTeX projects, literature review organization.

# QUALITY BAR

A GOOD generated prompt is one where: if you gave 100 random files to the AI with this persona active, an expert in that domain would look at the result and say "yes, this is exactly how I would organize these."

A BAD generated prompt is generic advice that could apply to anyone ("sort documents by type"). Every sentence should contain domain-specific insight.

## AVOID
- Generic advice like "organize by type" without domain-specific rationale
- Contradicting base system rules (JSON format, tag counts, depth limits)
- Specifying output format (already defined in base system)
- Mentioning tags (base system handles tagging requirements)
- Prompts under 1500 characters — these are too shallow to be useful
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
