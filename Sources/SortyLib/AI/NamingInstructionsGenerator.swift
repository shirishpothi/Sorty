//
//  NamingInstructionsGenerator.swift
//  Sorty
//
//  Generates detailed naming instructions from natural language descriptions
//

import Foundation
import Combine

@MainActor
public class NamingInstructionsGenerator: ObservableObject {
    @Published public var isGenerating: Bool = false
    @Published public var error: Error?
    
    private let metaSystemPrompt = """
    You are an expert file naming consultant. Convert the user's naming preferences into precise, actionable renaming rules.

    ### YOUR TASK
    Create detailed naming instructions (200-400 words) that an AI file organizer can follow exactly.

    ### REQUIRED OUTPUT STRUCTURE
    1. **Pattern Format**: Define the exact naming pattern with placeholders (e.g., `YYYY-MM-DD_ClientName_Description.ext`)
    2. **Component Rules**: Explain each component:
       - Date formats (ISO, US, EU)
       - Case conventions (lowercase, Title Case, UPPERCASE)
       - Separator characters (underscore, hyphen, space)
       - Required/optional elements
    3. **Examples**: Provide 3-4 before/after examples showing transformations
    4. **Edge Cases**: Handle:
       - Files without clear dates
       - Unknown client/project names
       - Duplicate names
       - Special characters to remove or replace

    ### CONSTRAINTS
    - Be specific and unambiguous
    - Use concrete examples, not abstract descriptions
    - Output plain text instructions only (no JSON, no markdown code blocks)
    - Keep between 200-400 words

    ### EXAMPLE OUTPUT
    "Rename files using pattern: YYYY-MM-DD_ClientName_Description.ext

    Date: Extract from filename or file metadata. Use ISO format (2024-01-15).
    Client: Use PascalCase with no spaces (e.g., 'acme corp' → 'AcmeCorp').
    Description: Use lowercase with underscores, max 30 chars.
    
    Examples:
    - 'invoice march 2024.pdf' → '2024-03-01_Unknown_invoice.pdf'
    - 'ACME Project Final v2.docx' → '2024-01-15_Acme_project_final.docx'
    
    Edge cases:
    - No date found: Use file modification date
    - Duplicate names: Append _001, _002, etc."
    """
    
    public init() {}

    public func generateNamingInstructions(from description: String, config: AIConfig) async throws -> String {
        isGenerating = true
        error = nil
        
        defer {
            isGenerating = false
        }
        
        do {
            var genConfig = config
            genConfig.maxTokens = 1000
            genConfig.requestTimeout = 60
            
            let client = try AIClientFactory.createClient(config: genConfig)
            
            let prompt = """
            User's naming preferences: \(description)
            
            Generate detailed naming instructions based on these preferences.
            """
            
            let result = try await client.generateText(prompt: prompt, systemPrompt: metaSystemPrompt)
            
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            self.error = error
            throw error
        }
    }
}
