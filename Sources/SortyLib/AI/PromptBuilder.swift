//
//  PromptBuilder.swift
//  Sorty
//
//  Constructs optimized prompts for AI organization
//

import Foundation

struct PromptBuilder {
    static func buildSystemPrompt(enableReasoning: Bool = false, personaInfo: String) -> String {
        var prompt = SystemPrompt.prompt
        
        // Add persona-specific instructions
        if !personaInfo.isEmpty {
            prompt += personaInfo
        }
        
        if enableReasoning {
            prompt += """
            
            ## IMPORTANT: Detailed Reasoning Mode Enabled
            
            For EACH folder in your response, you MUST include a comprehensive "reasoning" field that provides:
            
            1. **Pattern Recognition**: What naming patterns, file types, or metadata led you to group these files together? Be specific about the patterns you observed.
            
            2. **Semantic Grouping**: Explain the logical relationship between the files in this folder. What do they have in common beyond just file type?
            
            3. **Alternative Consideration**: Briefly mention 1-2 alternative folder structures you considered and why you rejected them in favor of this organization.
            
            4. **User Benefit**: How does this organization improve the user's workflow or findability?
            
            The reasoning should be 3-5 sentences minimum per folder. Shallow, one-sentence explanations are NOT acceptable.
            
            Example of GOOD reasoning:
            "These invoice PDFs share a consistent naming pattern with vendor prefixes (AWS_, GCP_, Azure_) and date suffixes. They're grouped under 'Cloud Services/Invoices' rather than just 'Documents' because the user clearly manages multiple cloud accounts and would benefit from having all billing-related files for infrastructure costs in one location. I considered grouping by date but the vendor-based organization provides faster lookup when reconciling specific provider bills."
            
            The JSON structure becomes:
            {
              "folders": [
                {
                  "name": "folder_name",
                  "description": "brief purpose description",
                  "reasoning": "Detailed 3-5 sentence explanation as described above",
                  "subfolders": [...],
                  "files": [...]
                }
              ],
              ...
            }
            """
        }
        
        return prompt
    }
    
    static func buildOrganizationPrompt(files: [FileItem], enableReasoning: Bool = false, includeContentMetadata: Bool = false, customInstructions: String? = nil) -> String {
        var prompt = "Organize the following files into a logical folder structure:\n\n"
        
        if let instructions = customInstructions, !instructions.isEmpty {
            prompt += "USER INSTRUCTIONS: \(instructions)\n\n"
        }
        
        prompt += "Files to organize (\(files.count) total):\n\n"
        
        // Group files by extension for better context
        let groupedByExtension = Dictionary(grouping: files) { $0.extension.lowercased() }
        
        for (ext, fileList) in groupedByExtension.sorted(by: { $0.key < $1.key }) {
            let extLabel = ext.isEmpty ? "no extension" : ".\(ext)"
            prompt += "\(extLabel.uppercased()) files (\(fileList.count)):\n"
            for file in fileList.prefix(50) {
                var fileDesc = "  - \(file.displayName) (\(file.formattedSize))"
                
                // Include content metadata if available and requested
                if includeContentMetadata, let metadata = file.contentMetadata, !metadata.isEmpty {
                    fileDesc += " \(metadata.summary)"
                }
                
                prompt += "\(fileDesc)\n"
            }
            if fileList.count > 50 {
                prompt += "  ... and \(fileList.count - 50) more \(extLabel) files\n"
            }
        }
        
        if enableReasoning {
            prompt += "\nProvide detailed reasoning for each folder. Include the organization structure in JSON format."
        } else {
            prompt += "\nProvide the organization structure in JSON format."
        }
        
        return prompt
    }
    
    /// Compact prompt for Apple Intelligence (reduced context window)
    static func buildCompactPrompt(files: [FileItem], enableReasoning: Bool = false) -> String {
        var prompt = "Organize these files:\n\n"
        
        // Group by extension
        let grouped = Dictionary(grouping: files) { $0.extension.lowercased() }
        
        // Only include summary counts if too many files
        if files.count > 100 {
            prompt += "File summary (\(files.count) total):\n"
            for (ext, fileList) in grouped.sorted(by: { $0.value.count > $1.value.count }).prefix(10) {
                let extLabel = ext.isEmpty ? "misc" : ext
                prompt += "- \(extLabel): \(fileList.count) files\n"
                // Show first 5 examples
                for file in fileList.prefix(5) {
                    let name = file.name.prefix(30)
                    prompt += "  • \(name)\n"
                }
            }
        } else {
            // Show all files but truncate names
            for (ext, fileList) in grouped.sorted(by: { $0.key < $1.key }) {
                let extLabel = ext.isEmpty ? "misc" : ext
                prompt += "\(extLabel) (\(fileList.count)):\n"
                for file in fileList.prefix(20) {
                    let name = file.name.prefix(25)
                    prompt += "  - \(name)\n"
                }
                if fileList.count > 20 {
                    prompt += "  (+\(fileList.count - 20) more)\n"
                }
            }
        }
        
        prompt += "\nReturn JSON with folder structure."
        if enableReasoning {
            prompt += " Include reasoning for each folder."
        }
        
        return prompt
    }
    
    /// Compact system prompt for Apple Intelligence
    static func buildCompactSystemPrompt(enableReasoning: Bool = false) -> String {
        let prompt = """
        You are a file organization assistant. Analyze files and suggest folders.
        
        Rules:
        - Max 3 levels deep
        - Use clear folder names
        - Group by type: Documents, Media, Code, Archives
        
        Return JSON:
        {"folders":[{"name":"","description":"",\(enableReasoning ? "\"reasoning\":\"\",": "")"files":[""],"subfolders":[]}],"unorganized":[{"filename":"","reason":""}]}
        """
        
        return prompt
    }
    
    // Legacy method for compatibility
    static func buildAnalysisPrompt(files: [FileItem]) -> String {
        return buildOrganizationPrompt(files: files, enableReasoning: false)
    }
    
    static func buildPromptForProvider(_ provider: AIProvider, files: [FileItem], enableReasoning: Bool = false, customInstructions: String? = nil) -> String {
        switch provider {
        case .appleFoundationModel:
            // Append instructions
            var prompt = buildCompactPrompt(files: files, enableReasoning: enableReasoning)
            if let instructions = customInstructions, !instructions.isEmpty {
                prompt = "USER INSTRUCTIONS: \(instructions)\n\n" + prompt
            }
            return prompt
        case .anthropic:
            // Anthropic handles system prompts separately but we ensure the user prompt is robust
            return buildOrganizationPrompt(files: files, enableReasoning: enableReasoning, includeContentMetadata: true, customInstructions: customInstructions)
        case .openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .ollama:
            return buildOrganizationPrompt(files: files, enableReasoning: enableReasoning, includeContentMetadata: true, customInstructions: customInstructions)
        }
    }
}


