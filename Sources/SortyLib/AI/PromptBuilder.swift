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
    
    static func buildOrganizationPrompt(
        files: [FileItem],
        mode: OrganizationMode = .organize,
        namingStyle: NamingStyle = .descriptive,
        renameNamingOptions: RenameNamingOptions = .default,
        customNamingInstructions: String? = nil,
        renameRules: [RenameRule] = [],
        renameRuleMode: RenameRuleApplicationMode = .beforeAI,
        enableReasoning: Bool = false,
        enableSmartRename: Bool = false,
        includeContentMetadata: Bool = false,
        customInstructions: String? = nil,
        storageLocationsContext: String? = nil,
        existingFoldersContext: String? = nil,
        analyzedImageFilenames: [String] = []
    ) -> String {
        var prompt: String
        
        if mode == .renameOnly {
            prompt = "Suggest intelligent and descriptive filenames for the following files. DO NOT suggest any folder structure; ALL files must be returned in a single root folder named '.'. Focus purely on making filenames more informative based on their content and metadata. This mode is strictly for renaming files in their current location.\n\n"
        } else if mode == .organizeAndRename {
            prompt = "Organize the following files into a logical folder structure. You should suggest both descriptive folders and improved filenames within those folders:\n\n"
        } else {
            prompt = "Organize the following files into a logical folder structure. Suggest descriptive folders but KEEP the original filenames unchanged:\n\n"
        }

        if mode != .renameOnly {
            prompt += """
            ## LIVE ORGANIZATION PREVIEW
            Sorty shows file moves as your JSON streams in. To keep that preview accurate and immediate:
            - Emit folder objects with "name" before "files", then list files in that folder as soon as the destination is decided.
            - Put "files" before "subfolders" inside each folder object so direct moves can appear immediately.
            - Do not add artificial delays or non-JSON file-move narration; the app animates the real streamed JSON tokens.

            """

            prompt += """
            ## ORGANIZATION COMPLETENESS
            Prefer placing every file into a logical folder. Use `unorganized` only as a last resort when a file genuinely has no defensible relationship to any existing or newly created folder.
            If a file is merely ambiguous, choose the best broad folder such as Documents, Media, Archives, Reference, or a nearby project/category folder instead of leaving it unorganized.

            """
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

            ════════════════════════════════════════════════════════════
            
            
            """
        }

        if mode == .organize {
            prompt += """
            ## ORGANIZE-ONLY WORKFLOW BOUNDARY
            This run is organize-only. Keep every original filename unchanged even if user instructions,
            persona guidance, learned preferences, naming rules, or provider defaults mention renaming.
            Do not include `suggested_name`, `rename_reason`, or `rename_confidence` fields.

            """
        }
        
        // Add organization-only routing context if provided.
        if mode != .renameOnly, let storageContext = storageLocationsContext, !storageContext.isEmpty {
            prompt += "\(storageContext)\n\n"
        }
        
        // Add existing folders context - encourage reuse of existing structure in organization modes.
        if mode != .renameOnly, let existingContext = existingFoldersContext, !existingContext.isEmpty {
            prompt += "\(existingContext)\n\n"
        }
        
        // Rename instructions: ONLY include if in a renaming mode. 
        // If mode is .organize, we explicitly IGNORE enableSmartRename to ensure filenames remain unchanged.
        if mode == .renameOnly || mode == .organizeAndRename {
            prompt += """
            ## INTELLIGENT RENAMING
            Suggest meaningful, descriptive filenames that help users understand file contents at a glance.
            - \(namingStyle.promptInstructions)
            - \(renameNamingOptions.promptInstructions)
            - Spaces are valid macOS filename characters. Use spaces when the separator preference asks for them; do not force underscores or hyphens unless configured.
            - When renaming multiple files in the same folder, keep one consistent naming pattern.
            - Return a `rename_confidence` score between 0.0 and 1.0 for each rename.
            - Prefer renaming files in this workflow. Keep the original name only when it is already clear and specific, protected/stable, or user instructions exclude a file/pattern from renaming.
            - When keeping a file unchanged, omit `suggested_name` and include a short `rename_reason` explaining why it stayed the same.
            - Include `suggested_name` whenever evidence supports a clearer name; for generic camera, screenshot, scan, download, or default app names, assume a rename is needed unless evidence is missing.
            - `rename_reason` must be concrete and evidence-based (cite content cues, date, project, or ambiguity being resolved). Avoid vague reasons like "more descriptive".
            - Do not invent dates, clients, invoice numbers, people, or projects. If evidence is weak, keep the original name and use low confidence.
            """

            if let customNaming = customNamingInstructions, !customNaming.isEmpty {
                let expanded = expandedCustomNamingInstructions(
                    customNaming,
                    files: files,
                    maxExamples: 5
                )
                prompt += "\n- CUSTOM NAMING PREFERENCE: \(expanded)"
            }

            if !renameRules.isEmpty {
                prompt += "\n- CUSTOM RENAME RULES (\(renameRuleMode.displayName)):"
                for rule in renameRules.prefix(10) {
                    let modeLabel = rule.isRegex ? "regex" : "text"
                    prompt += "\n  • [\(modeLabel)] \(rule.pattern) -> \(rule.replacement)"
                }
                if renameRuleMode == .rulesOnly {
                    prompt += "\n  • RULE MODE: Use only these custom rules for renaming and avoid AI creativity."
                } else {
                    prompt += "\n  • RULE MODE: Apply these rules first, then refine with AI when useful."
                }
            }
            
            prompt += """
            
            - Remove redundant prefixes like "IMG_", "DSC_", "Screenshot ", "Document (1)".
            - Keep filenames concise (max 60 chars) but highly informative.
            - Ensure names are valid for macOS filesystem and keep extensions unchanged.
            - Do NOT rename dotfiles/config files (e.g., .gitignore, .env, Makefile).
            - Do NOT rename files that already follow clear semantic version patterns (e.g., v1.2.3).
            
            """
        }

        if !analyzedImageFilenames.isEmpty {
            let orderedNames = analyzedImageFilenames
                .enumerated()
                .map { "\($0.offset + 1). \($0.element)" }
                .joined(separator: "\n")

            prompt += """
            ## AI VISION ATTACHMENTS
            I've attached \(analyzedImageFilenames.count) images from this folder.
            For each attached image, briefly describe what you see and use that visual context to improve folder categorization.
            The following images are attached in order:
            \(orderedNames)

            """
        }
        
        prompt += "Files to process (\(files.count) total):\n\n"
        
        // Group files by extension for better context
        let groupedByExtension = Dictionary(grouping: files) { $0.extension.lowercased() }
        
        for (ext, fileList) in groupedByExtension.sorted(by: { $0.key < $1.key }) {
            let extLabel = ext.isEmpty ? "no extension" : ".\(ext)"
            prompt += "\(extLabel.uppercased()) files (\(fileList.count)):\n"
            
            // Prioritize files with content metadata (deep-scanned) before applying the cap
            let sortedFiles: [FileItem]
            if includeContentMetadata {
                sortedFiles = fileList.sorted { a, b in
                    let aHasMetadata = a.contentMetadata != nil && !a.contentMetadata!.isEmpty
                    let bHasMetadata = b.contentMetadata != nil && !b.contentMetadata!.isEmpty
                    if aHasMetadata != bHasMetadata { return aHasMetadata }
                    return false
                }
            } else {
                sortedFiles = fileList
            }
            
            for file in sortedFiles.prefix(50) {
                var fileDesc = "  - \(file.displayName) (\(file.formattedSize))"
                
                // Include file dates
                let dateFormatter = ISO8601DateFormatter()
                dateFormatter.formatOptions = [.withFullDate]
                if let created = file.creationDate {
                    fileDesc += ", created: \(dateFormatter.string(from: created))"
                }
                if let modified = file.modificationDate {
                    fileDesc += ", modified: \(dateFormatter.string(from: modified))"
                }
                
                // Include Finder tags
                if let tags = file.finderTags, !tags.isEmpty {
                    fileDesc += "\n    [Tags] \(tags.joined(separator: ", "))"
                }
                
                // Include Finder comment
                if let comment = file.finderComment, !comment.isEmpty {
                    fileDesc += "\n    [Finder Comment] \(truncateForPrompt(comment, maxLength: 200))"
                }
                
                // Include content metadata if available and requested
                if includeContentMetadata, let metadata = file.contentMetadata, !metadata.isEmpty {
                    if mode == .renameOnly || mode == .organizeAndRename {
                        let snippet = renameMetadataSnippet(for: file, maxLength: 220)
                        if !snippet.isEmpty {
                            fileDesc += "\n    [Rename Context] \(snippet)"
                        }
                    } else {
                        fileDesc += "\n    [Content Analysis] \(metadata.summary)"
                    }
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
        
        prompt += "## FILE METADATA\n"
        prompt += "Files include metadata when available — use it for smarter organization:\n"
        prompt += "- Treat filenames as helpful but imperfect labels; do not overfit to names like IMG_, Screenshot, scan, final, or untitled\n"
        prompt += "- Parent/ancestor folders: Use relative paths as context for project, client, event, course, or workflow, without blindly preserving the old layout\n"
        prompt += "- Content metadata: Prefer extracted titles, text, OCR, EXIF/media info, Finder comments, and tags over ambiguous filenames when making decisions\n"
        prompt += "- Dates (created/modified): Group by time period or project phase when relevant\n"
        prompt += "- Finder Tags: Respect existing user categorization; group tagged files together when appropriate\n"
        prompt += "- Finder Comments: User annotations that provide context about the file's purpose or content\n\n"

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
        var line = "\(id)|\(ext)|\(clippedName)"
        
        // Append Finder metadata compactly when present
        var extras: [String] = []
        if let tags = file.finderTags, !tags.isEmpty {
            extras.append("tags:\(tags.joined(separator: ","))")
        }
        if let comment = file.finderComment, !comment.isEmpty {
            extras.append("comment:\(String(comment.prefix(40)))")
        }
        let parentPath = URL(fileURLWithPath: file.path).deletingLastPathComponent().lastPathComponent
        if !parentPath.isEmpty && parentPath != "/" {
            extras.append("parent:\(String(parentPath.prefix(32)))")
        }
        if !extras.isEmpty {
            line += "|\(extras.joined(separator: "|"))"
        }
        return line
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
            filePayload = "\"files\":[{\"filename\":\"\",\"suggested_name\":\"\",\"rename_reason\":\"\",\"rename_confidence\":0.0}]"
        } else {
            filePayload = "\"files\":[\"filename\"]"
        }
        return """
        Return JSON. Preferred compact format:
        {"folder_assignments":[{"name":"",\(enableReasoning ? "\"reasoning\":\"\"," : "")"file_ids":[1,2]}],"notes":""}
        Legacy format is also accepted:
        {"folders":[{"name":"",\(enableReasoning ? "\"reasoning\":\"\"," : "")\(filePayload),"subfolders":[]}],"unorganized":[{"filename":"","reason":""}]}
        Prefer assigning every file to a folder. Use unorganized only as a rare last resort when no logical destination exists.
        """
    }

    private static func minimalCompactSystemPrompt(mode: OrganizationMode = .organize, enableReasoning: Bool = false) -> String {
        var base = "You organize files into practical folders."
        if mode == .renameOnly {
            base += " Keep all files in '.' and only suggest better names."
        }
        if mode == .renameOnly || mode == .organizeAndRename {
            base += " Rename only when there is a material clarity improvement; keep already-good names unchanged."
        }
        base += " Use file_ids from the user list. Include every file exactly once. Prefer assigning every file to a folder; use unorganized only as a rare last resort when no logical destination exists."
        if enableReasoning {
            base += " Add concise reasoning for each folder."
        }
        base += " Before JSON, emit up to 8 progress lines starting with '>> category: text' (categories: file, folder, pattern, decision, constraint, general). Then output JSON only."
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
        - NEVER create a single top-level folder that contains everything UNLESS explicitly requested by the user in custom instructions. If all files belong to a single overarching category, use its subcategories as your top-level folders instead.
        - Never name a folder the same as an existing file in the input.
        - Use clear folder names
        - Prefer assigning every file to a folder; use unorganized only as a rare last resort when no logical destination exists.
        - If a file is ambiguous, place it in the best broad folder instead of leaving it unorganized.
        - Prefer using file_ids in compact responses when IDs are provided.
        - Group by type: Documents, Media, Code, Archives
        - If learnings_context is provided with rule_id attributes, include "rule_id" on folders influenced by those rules.
        \(mode == .renameOnly || mode == .organizeAndRename ? "- Prefer better filenames; keep originals only when they are already clear, stable/protected, or user-excluded." : "")
        \(mode == .renameOnly || mode == .organizeAndRename ? "- Generic camera, screenshot, scan, download, or default app names should usually receive suggested_name when evidence supports it." : "")
        \(mode == .renameOnly || mode == .organizeAndRename ? "- For each rename_reason, cite concrete evidence and avoid generic wording." : "")
        \(enableTagging ? "" : "- Do NOT include tags or comments. Omit \"tags\" and \"comment\" fields.")
        
        Before JSON, emit up to 8 progress lines: ">> category: text" (categories: file, folder, pattern, decision, constraint, general). Then output JSON only.
        
        Return JSON:
        {"folder_assignments":[{"name":"",\(enableReasoning ? "\"reasoning\":\"\"," : "")"file_ids":[1,2]}],"notes":""}
        or legacy:
        {"folders":[{"name":"","description":"",\(enableReasoning ? "\"reasoning\":\"\",": "")\(enableTagging ? "\"tags\":[\"\"]," : "")"files":[\(mode == .renameOnly || mode == .organizeAndRename ? "{\"filename\":\"\",\"suggested_name\":\"\",\"rename_reason\":\"\",\"rename_confidence\":0.0}" : "\"\"")],"subfolders":[]}],"unorganized":[{"filename":"","reason":""}]}
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
    
    static func buildPromptForProvider(
        _ provider: AIProvider,
        files: [FileItem],
        mode: OrganizationMode = .organize,
        namingStyle: NamingStyle = .descriptive,
        renameNamingOptions: RenameNamingOptions = .default,
        customNamingInstructions: String? = nil,
        renameRules: [RenameRule] = [],
        renameRuleMode: RenameRuleApplicationMode = .beforeAI,
        enableReasoning: Bool = false,
        enableSmartRename: Bool = false,
        customInstructions: String? = nil,
        storageLocationsContext: String? = nil,
        existingFoldersContext: String? = nil
    ) -> String {
        switch provider {
        case .appleFoundationModel:
            // Append instructions
            var prompt = buildCompactPrompt(files: files, mode: mode, enableReasoning: enableReasoning)
            if mode == .renameOnly || mode == .organizeAndRename {
                prompt += " (\(namingStyle.displayName))"
                prompt += " \(renameNamingOptions.promptInstructions)"
                if let customNaming = customNamingInstructions, !customNaming.isEmpty {
                    prompt += " Custom style: \(customNaming)"
                }
            }
            if let instructions = customInstructions, !instructions.isEmpty {
                prompt = "⚠️ MANDATORY USER INSTRUCTIONS (override all defaults): \(instructions)\n\n" + prompt
            }
            if mode != .renameOnly, let storageContext = storageLocationsContext, !storageContext.isEmpty {
                prompt = "\(storageContext)\n\n" + prompt
            }
            if mode != .renameOnly, let existingContext = existingFoldersContext, !existingContext.isEmpty {
                prompt = "\(existingContext)\n\n" + prompt
            }
            return prompt
        case .anthropic:
            // Anthropic handles system prompts separately but we ensure the user prompt is robust
            return buildOrganizationPrompt(files: files, mode: mode, namingStyle: namingStyle, renameNamingOptions: renameNamingOptions, customNamingInstructions: customNamingInstructions, renameRules: renameRules, renameRuleMode: renameRuleMode, enableReasoning: enableReasoning, enableSmartRename: enableSmartRename, includeContentMetadata: true, customInstructions: customInstructions, storageLocationsContext: storageLocationsContext, existingFoldersContext: existingFoldersContext)
        case .openAI, .githubCopilot, .groq, .openAICompatible, .openRouter, .ollama, .gemini:
            return buildOrganizationPrompt(files: files, mode: mode, namingStyle: namingStyle, renameNamingOptions: renameNamingOptions, customNamingInstructions: customNamingInstructions, renameRules: renameRules, renameRuleMode: renameRuleMode, enableReasoning: enableReasoning, enableSmartRename: enableSmartRename, includeContentMetadata: true, customInstructions: customInstructions, storageLocationsContext: storageLocationsContext, existingFoldersContext: existingFoldersContext)
        }
    }

    private static func expandedCustomNamingInstructions(
        _ instructions: String,
        files: [FileItem],
        maxExamples: Int
    ) -> String {
        guard instructions.contains("{") else { return instructions }

        let examples = files.prefix(maxExamples).enumerated().map { index, file in
            let expanded = expandTemplateVariables(instructions, for: file, counter: index + 1)
            return "\(file.displayName) -> \(expanded)"
        }

        guard !examples.isEmpty else { return instructions }
        return "\(instructions) | Examples: \(examples.joined(separator: " ; "))"
    }

    private static func expandTemplateVariables(_ template: String, for file: FileItem, counter: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let relevantDate = file.modificationDate ?? file.creationDate ?? Date()

        let replacements: [String: String] = [
            "{date}": formatter.string(from: relevantDate),
            "{ext}": file.extension.lowercased(),
            "{size}": file.formattedSize,
            "{counter}": String(format: "%02d", counter)
        ]

        var output = template
        for (token, value) in replacements {
            output = output.replacingOccurrences(of: token, with: value)
        }
        return output
    }

    private static func renameMetadataSnippet(for file: FileItem, maxLength: Int) -> String {
        var parts: [String] = []

        if let metadata = file.contentMetadata {
            if let title = metadata.documentTitle, !title.isEmpty {
                parts.append("Title: \(truncateForPrompt(title, maxLength: maxLength))")
            }
            if let ocr = metadata.ocrText, !ocr.isEmpty {
                parts.append("OCR: \(truncateForPrompt(ocr, maxLength: maxLength))")
            }
            if let preview = metadata.textPreview, !preview.isEmpty {
                parts.append("Text: \(truncateForPrompt(preview, maxLength: maxLength))")
            }
            if let keywords = metadata.keywords, !keywords.isEmpty {
                parts.append("Keywords: \(truncateForPrompt(keywords.joined(separator: ", "), maxLength: maxLength))")
            }
            if let detected = metadata.detectedKeywords, !detected.isEmpty {
                parts.append("Detected: \(truncateForPrompt(detected.joined(separator: ", "), maxLength: maxLength))")
            }
            if let exif = metadata.exifData, !exif.isEmpty {
                let exifSummary = exif.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                parts.append("EXIF: \(truncateForPrompt(exifSummary, maxLength: maxLength))")
            }
            if let pages = metadata.pageCount {
                parts.append("Pages: \(pages)")
            }
            if let duration = metadata.duration {
                let minutes = Int(duration) / 60
                let seconds = Int(duration) % 60
                parts.append("Duration: \(minutes)m \(seconds)s")
            }
            if let mediaInfo = metadata.mediaInfo, !mediaInfo.isEmpty {
                let mediaSummary = mediaInfo.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                parts.append("Media: \(truncateForPrompt(mediaSummary, maxLength: maxLength))")
            }
        }

        if let comment = file.finderComment, !comment.isEmpty {
            parts.append("Comment: \(truncateForPrompt(comment, maxLength: maxLength))")
        }

        if let tags = file.finderTags, !tags.isEmpty {
            parts.append("Tags: \(tags.joined(separator: ", "))")
        }

        if parts.isEmpty, let semantic = file.semanticTextContent, !semantic.isEmpty {
            parts.append(truncateForPrompt(semantic, maxLength: maxLength))
        }

        return parts.joined(separator: " | ")
    }

    private static func truncateForPrompt(_ text: String, maxLength: Int) -> String {
        let normalized = text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength)) + "..."
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

    static func buildDirectoryManifestContext(
        baseDirectoryURL: URL,
        files: [FileItem],
        maxEntries: Int = 400
    ) -> String? {
        guard !files.isEmpty else { return nil }

        let sortedFiles = files.sorted {
            let lhs = relativePath(for: $0, baseDirectoryURL: baseDirectoryURL)
            let rhs = relativePath(for: $1, baseDirectoryURL: baseDirectoryURL)
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        let extensionSummary = Dictionary(grouping: sortedFiles) { file in
            file.extension.isEmpty ? "(none)" : file.extension.lowercased()
        }
        .sorted { $0.value.count > $1.value.count }
        .prefix(12)
        .map { "\($0.key):\($0.value.count)" }
        .joined(separator: ", ")

        let parentSummary = Dictionary(grouping: sortedFiles) { file in
            let relative = relativePath(for: file, baseDirectoryURL: baseDirectoryURL)
            let parent = URL(fileURLWithPath: relative).deletingLastPathComponent().path
            return parent == "/" || parent == "." ? "(root)" : parent
        }
        .sorted { $0.value.count > $1.value.count }
        .prefix(10)
        .map { "\($0.key): \($0.value.count)" }
        .joined(separator: ", ")

        let manifestLines = sortedFiles.prefix(maxEntries).map { file in
            let relative = relativePath(for: file, baseDirectoryURL: baseDirectoryURL)
            var line = "- \(relative) | \(file.extension.isEmpty ? "no-ext" : file.extension.lowercased()) | \(file.formattedSize)"
            if let modified = file.modificationDate {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                line += " | modified \(formatter.string(from: modified))"
            }
            return line
        }

        let ancestorNames = directoryContextNames(for: baseDirectoryURL)

        var context = """
        ## SOURCE FOLDER CONTEXT
        Source directory: \(baseDirectoryURL.lastPathComponent)
        Ancestor context: \(ancestorNames.isEmpty ? "n/a" : ancestorNames.joined(separator: " / "))
        Files in current organization scope: \(files.count)
        Extension mix: \(extensionSummary.isEmpty ? "n/a" : extensionSummary)
        Folder distribution: \(parentSummary.isEmpty ? "(root only)" : parentSummary)
        Relative paths in scope:
        \(manifestLines.joined(separator: "\n"))
        """

        if files.count > maxEntries {
            context += "\n- ... and \(files.count - maxEntries) more files in scope"
        }

        context += "\nUse this context to understand projects, clients, events, and existing groupings before deciding on folder structure. Do not rely on filenames alone."
        return context
    }

    private static func directoryContextNames(for directoryURL: URL, maxAncestors: Int = 3) -> [String] {
        var names: [String] = []
        var cursor = directoryURL.deletingLastPathComponent()

        while names.count < maxAncestors {
            let name = cursor.lastPathComponent
            guard !name.isEmpty && name != "/" else { break }
            names.append(name)

            let next = cursor.deletingLastPathComponent()
            guard next.path != cursor.path else { break }
            cursor = next
        }

        return names.reversed()
    }

    private static func relativePath(for file: FileItem, baseDirectoryURL: URL) -> String {
        let path = file.path
        let basePath = baseDirectoryURL.path
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        let resolvedBasePath = baseDirectoryURL.resolvingSymlinksInPath().path
        if resolvedPath.hasPrefix(resolvedBasePath + "/") {
            return String(resolvedPath.dropFirst(resolvedBasePath.count + 1))
        }
        if path.hasPrefix(basePath + "/") {
            return String(path.dropFirst(basePath.count + 1))
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    
    // MARK: - Reference Model Directory Context
    
    /// Build a reference-directory context section from one or more model directories.
    /// Scans folder structure only (no file content analysis) to keep prompts lightweight.
    /// - Parameters:
    ///   - paths: Filesystem paths to reference directories
    ///   - maxDepth: Maximum directory traversal depth (default 3)
    ///   - maxEntriesPerDirectory: Maximum folder entries per directory (default 20)
    /// - Returns: Formatted prompt context string, or empty string if no valid directories
    static func buildReferenceDirectoryContext(
        paths: [String],
        maxDepth: Int = 3,
        maxEntriesPerDirectory: Int = 20
    ) -> String {
        let fm = FileManager.default
        var sections: [String] = []
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            
            let dirName = url.lastPathComponent
            var folders: [String] = []
            
            func scan(_ scanURL: URL, depth: Int, prefix: String) {
                guard depth <= maxDepth, folders.count < maxEntriesPerDirectory else { return }
                
                guard let contents = try? fm.contentsOfDirectory(
                    at: scanURL,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { return }
                
                let subdirs = contents.filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                
                for subdir in subdirs {
                    guard folders.count < maxEntriesPerDirectory else { return }
                    let name = prefix.isEmpty ? subdir.lastPathComponent : "\(prefix)/\(subdir.lastPathComponent)"
                    folders.append(name)
                    
                    if depth < maxDepth {
                        scan(subdir, depth: depth + 1, prefix: name)
                    }
                }
            }
            
            scan(url, depth: 1, prefix: "")
            
            guard !folders.isEmpty else { continue }
            
            let truncated = folders.count >= maxEntriesPerDirectory
            let folderList = folders.map { "  - \($0)" }.joined(separator: "\n")
            var section = "Reference: \"\(dirName)\"\n\(folderList)"
            if truncated {
                section += "\n  ... (truncated to \(maxEntriesPerDirectory) entries)"
            }
            sections.append(section)
        }
        
        guard !sections.isEmpty else { return "" }
        
        return """
        ## REFERENCE MODEL DIRECTORIES
        The user has provided the following well-organized directories as examples of their preferred folder structure and naming conventions. Use these as guidance for how to name and organize folders — match the style, hierarchy depth, and naming patterns you see here.
        
        \(sections.joined(separator: "\n\n"))
        
        IMPORTANT: These are reference examples only — do NOT reorganize files into these directories. Instead, replicate the naming style and structure patterns in your organization plan.
        """
    }
}
