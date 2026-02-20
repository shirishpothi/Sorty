//
//  PromptBuilder.swift
//  Sorty
//
//  Constructs optimized prompts for AI organization
//

import Foundation

struct PromptBuilder {
    static func buildSystemPrompt(enableReasoning: Bool = false, personaInfo: String, maxTopLevelFolders: Int = 10, mode: OrganizationMode = .organize, enableTagging: Bool = true) -> String {
        var prompt = SystemPrompt.buildPrompt(maxTopLevelFolders: maxTopLevelFolders, mode: mode, enableTagging: enableTagging)
        
        if !personaInfo.isEmpty {
            prompt += """
            
            
            # ═══════════════════════════════════════════════════════
            # ACTIVE PERSONA — HIGHEST PRIORITY INSTRUCTIONS
            # ═══════════════════════════════════════════════════════
            #
            # The following persona rules OVERRIDE all default grouping,
            # naming, and hierarchy rules above. When this persona's
            # instructions conflict with the defaults, ALWAYS follow
            # the persona. The persona defines your identity for this
            # organization task.
            # ═══════════════════════════════════════════════════════
            
            \(personaInfo)
            
            # ═══════════════════════════════════════════════════════
            # END PERSONA — Resume base rules for anything not
            # explicitly covered by the persona above.
            # ═══════════════════════════════════════════════════════
            """
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
    
    static func buildOrganizationPrompt(files: [FileItem], mode: OrganizationMode = .organize, namingStyle: NamingStyle = .descriptive, customNamingInstructions: String? = nil, enableReasoning: Bool = false, enableSmartRename: Bool = false, includeContentMetadata: Bool = false, customInstructions: String? = nil, storageLocationsContext: String? = nil, existingFoldersContext: String? = nil) -> String {
        var prompt: String
        
        if mode == .renameOnly {
            prompt = "Suggest intelligent and descriptive filenames for the following files. DO NOT suggest any folder structure; ALL files must be returned in a single root folder named '.'. Focus purely on making filenames more informative based on their content and metadata. This mode is strictly for renaming files in their current location.\n\n"
        } else if mode == .organizeAndRename {
            prompt = "Organize the following files into a logical folder structure. You should suggest both descriptive folders and improved filenames within those folders:\n\n"
        } else {
            prompt = "Organize the following files into a logical folder structure. Suggest descriptive folders but KEEP the original filenames unchanged:\n\n"
        }
        
        if let instructions = customInstructions, !instructions.isEmpty {
            prompt += """
            ╔══════════════════════════════════════════════════════════╗
            ║  MANDATORY USER REQUIREMENTS — MUST FOLLOW EXACTLY      ║
            ╠══════════════════════════════════════════════════════════╣
            ║  The following instructions come directly from the user. ║
            ║  They override ALL default rules. If the user says       ║
            ║  "do X", you MUST do X. If the user says "don't do Y",  ║
            ║  you MUST NOT do Y. No exceptions, no creative           ║
            ║  reinterpretation. Follow them LITERALLY.                ║
            ╚══════════════════════════════════════════════════════════╝

            USER INSTRUCTIONS: \(instructions)

            \(instructions)

            ════════════════════════════════════════════════════════════
            
            
            """
        }
        
        // Add storage locations context if provided
        if let storageContext = storageLocationsContext, !storageContext.isEmpty {
            prompt += "\(storageContext)\n\n"
        }
        
        // Add existing folders context - encourage reuse of existing structure
        if let existingContext = existingFoldersContext, !existingContext.isEmpty {
            prompt += "\(existingContext)\n\n"
        }
        
        // Rename instructions: ONLY include if in a renaming mode. 
        // If mode is .organize, we explicitly IGNORE enableSmartRename to ensure filenames remain unchanged.
        if mode == .renameOnly || mode == .organizeAndRename {
            prompt += """
            ## INTELLIGENT RENAMING
            Suggest meaningful, descriptive filenames that help users understand file contents at a glance.
            - \(namingStyle.promptInstructions)
            """
            
            if let customNaming = customNamingInstructions, !customNaming.isEmpty {
                prompt += "\n- CUSTOM NAMING PREFERENCE: \(customNaming)"
            }
            
            prompt += """
            
            - Remove redundant prefixes like "IMG_", "DSC_", "Screenshot ", "Document (1)".
            - Keep filenames concise (max 60 chars) but highly informative.
            - Ensure names are valid for macOS filesystem and keep extensions unchanged.
            
            """
        }
        
        prompt += "Files to process (\(files.count) total):\n\n"
        
        // Group files by extension for better context
        let groupedByExtension = Dictionary(grouping: files) { $0.extension.lowercased() }
        
        for (ext, fileList) in groupedByExtension.sorted(by: { $0.key < $1.key }) {
            let extLabel = ext.isEmpty ? "no extension" : ".\(ext)"
            prompt += "\(extLabel.uppercased()) files (\(fileList.count)):\n"
            for file in fileList.prefix(50) {
                var fileDesc = "  - \(file.displayName) (\(file.formattedSize))"
                
                // Include content metadata if available and requested
                if includeContentMetadata, let metadata = file.contentMetadata, !metadata.isEmpty {
                    fileDesc += "\n    [Content Analysis] \(metadata.summary)"
                }
                
                prompt += "\(fileDesc)\n"
            }
            if fileList.count > 50 {
                prompt += "  ... and \(fileList.count - 50) more \(extLabel) files\n"
            }
        }

        if includeContentMetadata {
            prompt += "\n## IMAGE & CONTENT ANALYSIS\n"
            prompt += "For files with content metadata, use the extracted text, descriptions, and visual content to make better organization decisions:\n"
            prompt += "- Image content: Use visible subjects, scenes, and text to determine appropriate folders and tags\n"
            prompt += "- Document text: Group related documents by their actual content, not just filenames\n"
            prompt += "- OCR results: Use text found in images/screenshots for more accurate categorization\n\n"
        }

        if mode == .renameOnly {
            prompt += "\nReturn the suggestions in JSON format. Use a single folder named '.' to represent the current location for all files."
        } else if enableReasoning {
            prompt += "\nProvide detailed reasoning for each folder. Include the organization structure in JSON format."
        } else {
            prompt += "\nProvide the organization structure in JSON format."
        }
        
        return prompt
    }
    
    
    /// Estimate token count (rough: 1 token ≈ 4 chars for English)
    static func estimateTokens(_ text: String) -> Int {
        return text.count / 4
    }

    /// Select compaction level based on full prompt budget.
    enum CompactionLevel {
        case standard
        case ultra
        case summary
        case micro
    }

    static func selectCompactionLevel(
        files: [FileItem],
        config: AIConfig,
        customInstructions: String? = nil,
        maxTokens: Int = 1200,
        safetyMargin: Double = 0.65
    ) -> CompactionLevel {
        let effectiveBudget = max(200, Int(Double(maxTokens) * safetyMargin))

        let levels: [CompactionLevel] = [.standard, .ultra, .summary, .micro]
        for level in levels {
            let prompts = promptPair(for: level, config: config, files: files)
            let fullPrompt = mergePromptBudgetStrings(
                system: prompts.system,
                user: prompts.user,
                customInstructions: customInstructions
            )
            if estimateTokens(fullPrompt) <= effectiveBudget {
                return level
            }
        }

        return .micro
    }

    static func selectCompactionLevel(files: [FileItem], maxTokens: Int = 1500) -> CompactionLevel {
        let samplePrompt = buildCompactPrompt(files: files)
        let estimated = estimateTokens(samplePrompt)

        if estimated < Int(Double(maxTokens) * 0.45) { return .standard }
        if estimated < Int(Double(maxTokens) * 0.7) { return .ultra }
        if estimated < maxTokens { return .summary }
        return .micro
    }

    private static func mergePromptBudgetStrings(system: String, user: String, customInstructions: String?) -> String {
        var merged = system + "\n" + user
        if let customInstructions, !customInstructions.isEmpty {
            merged += "\nUSER INSTRUCTIONS:\n" + customInstructions
        }
        return merged
    }

    private static func compactFileLine(id: Int, file: FileItem, maxNameLength: Int) -> String {
        let ext = file.extension.isEmpty ? "-" : file.extension.lowercased()
        let displayName = file.displayName.isEmpty ? file.name : file.displayName
        let clippedName = String(displayName.prefix(maxNameLength))
        return "\(id)|\(ext)|\(clippedName)"
    }

    private static func compactFileIdTable(files: [FileItem], maxNameLength: Int) -> String {
        var lines: [String] = []
        lines.reserveCapacity(files.count)
        for (index, file) in files.enumerated() {
            lines.append(compactFileLine(id: index + 1, file: file, maxNameLength: maxNameLength))
        }
        return lines.joined(separator: "\n")
    }

    private static func compactFileSummary(files: [FileItem], maxExtensions: Int = 12) -> String {
        let grouped = Dictionary(grouping: files) { $0.extension.lowercased() }
        let summary = grouped
            .sorted { $0.value.count > $1.value.count }
            .prefix(maxExtensions)
            .map { ext, entries in
                "\(ext.isEmpty ? "misc" : ext):\(entries.count)"
            }
            .joined(separator: ", ")
        return "Types: \(summary)"
    }

    private static func compactResponseContract(mode: OrganizationMode, enableReasoning: Bool) -> String {
        let reasoning = enableReasoning ? ",\"reasoning\":\"\"" : ""
        let filePayload: String
        if mode == .renameOnly || mode == .organizeAndRename {
            filePayload = "\"files\":[{\"filename\":\"\",\"suggested_name\":\"\",\"rename_reason\":\"\"}]"
        } else {
            filePayload = "\"files\":[\"filename\"]"
        }
        return """
        Return JSON. Preferred compact format:
        {"folder_assignments":[{"name":"",\(enableReasoning ? "\"reasoning\":\"\"," : "")"file_ids":[1,2]}],"notes":""}
        Legacy format is also accepted:
        {"folders":[{"name":"",\(enableReasoning ? "\"reasoning\":\"\"," : "")\(filePayload),"subfolders":[]}],"unorganized":[{"filename":"","reason":""}]}
        """
    }

    private static func minimalCompactSystemPrompt(mode: OrganizationMode = .organize, enableReasoning: Bool = false) -> String {
        var base = "You organize files into practical folders."
        if mode == .renameOnly {
            base += " Keep all files in '.' and only suggest better names."
        }
        base += " Use file_ids from the user list. Include every file exactly once unless unorganized."
        if enableReasoning {
            base += " Add concise reasoning for each folder."
        }
        return base
    }

    static func buildUltraCompactPrompt(
        files: [FileItem],
        mode: OrganizationMode = .organize,
        enableReasoning: Bool = false
    ) -> (system: String, user: String) {
        let system = minimalCompactSystemPrompt(mode: mode, enableReasoning: enableReasoning)
        let table = compactFileIdTable(files: files, maxNameLength: 24)
        let user = """
        \(compactFileSummary(files: files))
        Files (id|ext|name):
        \(table)

        \(compactResponseContract(mode: mode, enableReasoning: enableReasoning))
        """
        return (system, user)
    }

    static func buildSummaryPrompt(
        files: [FileItem],
        mode: OrganizationMode = .organize,
        enableReasoning: Bool = false
    ) -> (system: String, user: String) {
        let system = minimalCompactSystemPrompt(mode: mode, enableReasoning: enableReasoning)
        let table = compactFileIdTable(files: files, maxNameLength: 14)
        let user = """
        \(compactFileSummary(files: files, maxExtensions: 8))
        IDs (id|ext|name):
        \(table)

        \(compactResponseContract(mode: mode, enableReasoning: enableReasoning))
        """
        return (system, user)
    }

    static func buildMicroPrompt(
        files: [FileItem],
        mode: OrganizationMode = .organize,
        enableReasoning: Bool = false
    ) -> (system: String, user: String) {
        let system = minimalCompactSystemPrompt(mode: mode, enableReasoning: false)
        var lines: [String] = []
        lines.reserveCapacity(files.count)
        for (index, file) in files.enumerated() {
            let ext = file.extension.isEmpty ? "-" : file.extension.lowercased()
            lines.append("\(index + 1)|\(ext)")
        }
        let user = """
        \(compactFileSummary(files: files, maxExtensions: 6))
        IDs (id|ext):
        \(lines.joined(separator: "\n"))

        \(compactResponseContract(mode: mode, enableReasoning: enableReasoning))
        """
        return (system, user)
    }
    
    /// Compact prompt for Apple Intelligence (reduced context window)
    static func buildCompactPrompt(files: [FileItem], mode: OrganizationMode = .organize, enableReasoning: Bool = false) -> String {
        var prompt: String
        if mode == .renameOnly {
            prompt = "Suggest better names for these files (keep in place):\n\n"
        } else {
            prompt = "Organize these files:\n\n"
        }
        prompt += "\(compactFileSummary(files: files, maxExtensions: 12))\n"
        prompt += "Use file IDs for mapping. Every file is listed once.\n"
        prompt += "Files (id|ext|name):\n"
        prompt += compactFileIdTable(files: files, maxNameLength: 32)
        prompt += "\n\n"
        prompt += compactResponseContract(mode: mode, enableReasoning: enableReasoning)
        
        return prompt
    }
    
    /// Compact system prompt for Apple Intelligence
    static func buildCompactSystemPrompt(mode: OrganizationMode = .organize, enableReasoning: Bool = false, enableSmartRename: Bool = false, maxTopLevelFolders: Int = 10, enableTagging: Bool = true) -> String {
        var prompt = "You are a file management assistant. "
        
        if mode == .renameOnly {
            prompt += "Analyze files and suggest better filenames. Keep files in the '.' folder.\n\n"
        } else {
            prompt += "Analyze files and suggest folders.\n\n"
        }
        
        prompt += """
        Rules:
        - Max 3 levels deep
        - HARD LIMIT: You MUST output ≤ \(maxTopLevelFolders) top-level folders. Merge categories if needed.
        - Never name a folder the same as an existing file in the input.
        - Use clear folder names
        - Prefer using file_ids in compact responses when IDs are provided.
        - Group by type: Documents, Media, Code, Archives
        \(mode == .renameOnly || mode == .organizeAndRename ? "- Suggest better filenames where appropriate" : "")
        \(enableTagging ? "" : "- Do NOT include tags or comments. Omit \"tags\" and \"comment\" fields.")
        
        Return JSON:
        {"folder_assignments":[{"name":"",\(enableReasoning ? "\"reasoning\":\"\"," : "")"file_ids":[1,2]}],"notes":""}
        or legacy:
        {"folders":[{"name":"","description":"",\(enableReasoning ? "\"reasoning\":\"\",": "")\(enableTagging ? "\"tags\":[\"\"]," : "")"files":[\(mode == .renameOnly || mode == .organizeAndRename ? "{\"filename\":\"\",\"suggested_name\":\"\",\"rename_reason\":\"\"}" : "\"\"")],"subfolders":[]}],"unorganized":[{"filename":"","reason":""}]}
        """
        
        return prompt
    }

    static func promptPair(for level: CompactionLevel, config: AIConfig, files: [FileItem]) -> (system: String, user: String) {
        switch level {
        case .standard:
            let system = config.systemPromptOverride
                ?? buildCompactSystemPrompt(
                    mode: config.mode,
                    enableReasoning: config.enableReasoning,
                    enableSmartRename: config.enableSmartRename,
                    maxTopLevelFolders: config.maxTopLevelFolders,
                    enableTagging: config.enableFileTagging
                )
            let user = buildCompactPrompt(files: files, mode: config.mode, enableReasoning: config.enableReasoning)
            return (system, user)
        case .ultra:
            return buildUltraCompactPrompt(files: files, mode: config.mode, enableReasoning: config.enableReasoning)
        case .summary:
            return buildSummaryPrompt(files: files, mode: config.mode, enableReasoning: config.enableReasoning)
        case .micro:
            return buildMicroPrompt(files: files, mode: config.mode, enableReasoning: config.enableReasoning)
        }
    }
    
    // Legacy method for compatibility
    static func buildAnalysisPrompt(files: [FileItem]) -> String {
        return buildOrganizationPrompt(files: files, enableReasoning: false)
    }
    
    static func buildPromptForProvider(_ provider: AIProvider, files: [FileItem], mode: OrganizationMode = .organize, namingStyle: NamingStyle = .descriptive, customNamingInstructions: String? = nil, enableReasoning: Bool = false, enableSmartRename: Bool = false, customInstructions: String? = nil, storageLocationsContext: String? = nil, existingFoldersContext: String? = nil) -> String {
        switch provider {
        case .appleFoundationModel:
            // Append instructions
            var prompt = buildCompactPrompt(files: files, mode: mode, enableReasoning: enableReasoning)
            if mode == .renameOnly || enableSmartRename {
                prompt += " (\(namingStyle.displayName))"
                if let customNaming = customNamingInstructions, !customNaming.isEmpty {
                    prompt += " Custom style: \(customNaming)"
                }
            }
            if let instructions = customInstructions, !instructions.isEmpty {
                prompt = "⚠️ MANDATORY USER INSTRUCTIONS (override all defaults): \(instructions)\n\n" + prompt
            }
            if let storageContext = storageLocationsContext, !storageContext.isEmpty {
                prompt = "\(storageContext)\n\n" + prompt
            }
            if let existingContext = existingFoldersContext, !existingContext.isEmpty {
                prompt = "\(existingContext)\n\n" + prompt
            }
            return prompt
        case .anthropic:
            // Anthropic handles system prompts separately but we ensure the user prompt is robust
            return buildOrganizationPrompt(files: files, mode: mode, namingStyle: namingStyle, customNamingInstructions: customNamingInstructions, enableReasoning: enableReasoning, enableSmartRename: enableSmartRename, includeContentMetadata: true, customInstructions: customInstructions, storageLocationsContext: storageLocationsContext, existingFoldersContext: existingFoldersContext)
        case .openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .ollama, .gemini:
            return buildOrganizationPrompt(files: files, mode: mode, namingStyle: namingStyle, customNamingInstructions: customNamingInstructions, enableReasoning: enableReasoning, enableSmartRename: enableSmartRename, includeContentMetadata: true, customInstructions: customInstructions, storageLocationsContext: storageLocationsContext, existingFoldersContext: existingFoldersContext)
        }
    }
    
    /// Scan a directory for existing folders (1-2 levels deep) to include in the prompt
    static func buildExistingFoldersContext(at directoryURL: URL, maxDepth: Int = 2) -> String? {
        let fileManager = FileManager.default
        var existingFolders: [String] = []
        
        func scanDirectory(_ url: URL, depth: Int, prefix: String = "") {
            guard depth <= maxDepth else { return }
            
            guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
                return
            }
            
            for item in contents {
                guard let isDirectory = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDirectory == true else {
                    continue
                }
                
                let folderName = prefix.isEmpty ? item.lastPathComponent : "\(prefix)/\(item.lastPathComponent)"
                existingFolders.append(folderName)
                
                // Recurse for subfolders
                if depth < maxDepth {
                    scanDirectory(item, depth: depth + 1, prefix: folderName)
                }
            }
        }
        
        scanDirectory(directoryURL, depth: 1)
        
        guard !existingFolders.isEmpty else { return nil }
        
        // Limit to first 30 folders to keep prompt size reasonable
        let foldersToShow = existingFolders.prefix(30)
        let truncated = existingFolders.count > 30
        
        var context = "## EXISTING FOLDERS (prefer reusing these when semantically appropriate):\n"
        context += foldersToShow.joined(separator: ", ")
        if truncated {
            context += ", ... and \(existingFolders.count - 30) more"
        }
        context += "\n\nIMPORTANT: Prefer organizing files into existing folders when the folder name matches the file's purpose. Only create new folders when no existing folder is suitable."
        
        return context
    }
}
