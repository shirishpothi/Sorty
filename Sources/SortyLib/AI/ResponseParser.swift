//
//  ResponseParser.swift
//  Sorty
//
//  Parses AI JSON responses into OrganizationPlan
//  Updated to support Smart Renaming feature
//

import Foundation

struct ResponseParser {
    // MARK: - Response Models

    struct AIResponse: Codable {
        let folders: [FolderResponse]
        let folderAssignments: [FolderResponse]?
        let unorganized: [UnorganizedFileResponse]?
        let unorganizedIDs: [Int]?
        let notes: String?

        enum CodingKeys: String, CodingKey {
            case folders, unorganized, notes
            case folderAssignments = "folder_assignments"
            case unorganizedIDs = "unorganized_ids"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folders = try container.decodeIfPresent([FolderResponse].self, forKey: .folders) ?? []
            folderAssignments = try container.decodeIfPresent([FolderResponse].self, forKey: .folderAssignments)
            unorganized = try container.decodeIfPresent([UnorganizedFileResponse].self, forKey: .unorganized)
            unorganizedIDs = try container.decodeIfPresent([Int].self, forKey: .unorganizedIDs)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
        }
    }


    struct FolderResponse: Codable {
        let name: String
        let description: String?
        let reasoning: String?
        let subfolders: [FolderResponse]?
        let files: [FileEntry]
        let tags: [String]?
        let comment: String?
        let semanticTags: [String]?
        let confidence: Double?
        let ruleId: String?
        let fileIDs: [Int]?

        // Support both array of strings and array of FileEntry objects
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
            subfolders = try container.decodeIfPresent([FolderResponse].self, forKey: .subfolders)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
            semanticTags = try container.decodeIfPresent([String].self, forKey: .semanticTags)
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
            ruleId = try container.decodeIfPresent(String.self, forKey: .ruleId)
            fileIDs = try container.decodeIfPresent([Int].self, forKey: .fileIDs)

            // Try to decode files as FileEntry array first
            if let fileEntries = try? container.decode([FileEntry].self, forKey: .files) {
                files = fileEntries
            } else if let fileStrings = try? container.decode([String].self, forKey: .files) {
                // Fallback: convert string array to FileEntry array
                files = fileStrings.map { FileEntry(filename: $0) }
            } else {
                files = []
            }
        }

        enum CodingKeys: String, CodingKey {
            case name, description, reasoning, subfolders, files
            case tags, comment
            case semanticTags = "semantic_tags"
            case confidence
            case ruleId = "rule_id"
            case fileIDs = "file_ids"
        }
    }


    /// Represents a file entry in the AI response with optional rename suggestion
    struct FileEntry: Codable {
        let filename: String
        let suggestedName: String?
        let renameReason: String?
        let tags: [String]?
        let comment: String?

        init(filename: String, suggestedName: String? = nil, renameReason: String? = nil, tags: [String]? = nil, comment: String? = nil) {
            self.filename = filename
            self.suggestedName = suggestedName
            self.renameReason = renameReason
            self.tags = tags
            self.comment = comment
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(filename, forKey: .filename)
            try container.encodeIfPresent(suggestedName, forKey: .suggestedName)
            try container.encodeIfPresent(renameReason, forKey: .renameReason)
            try container.encodeIfPresent(tags, forKey: .tags)
            try container.encodeIfPresent(comment, forKey: .comment)
        }

        // Support both simple string and object format
        init(from decoder: Decoder) throws {
            // Try to decode as a simple string first
            if let container = try? decoder.singleValueContainer(),
               let simpleFilename = try? container.decode(String.self) {
                self.filename = simpleFilename
                self.suggestedName = nil
                self.renameReason = nil
                self.tags = nil
                self.comment = nil
                return
            }

            // Otherwise decode as object
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filename = try container.decode(String.self, forKey: .filename)
            suggestedName = try container.decodeIfPresent(String.self, forKey: .suggestedName)
            renameReason = try container.decodeIfPresent(String.self, forKey: .renameReason)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }

        enum CodingKeys: String, CodingKey {
            case filename
            case suggestedName = "suggested_name"
            case renameReason = "rename_reason"
            case tags
            case comment
        }
    }


    struct UnorganizedFileResponse: Codable {
        let filename: String
        let reason: String
    }

    // MARK: - Parsing

    /// Strip progress preamble lines (lines starting with ">> ") from before the JSON
    static func stripProgressPreamble(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        var result: [String] = []
        var pastPreamble = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !pastPreamble && trimmed.hasPrefix(">> ") {
                continue
            }
            if !pastPreamble && trimmed.isEmpty {
                continue
            }
            pastPreamble = true
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    static func parseResponse(_ jsonString: String, originalFiles: [FileItem]) throws -> OrganizationPlan {
        // Strip progress preamble lines before JSON
        var cleanedJSON = stripProgressPreamble(jsonString)

        // Clean the JSON string - remove markdown code blocks if present
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedJSON.hasPrefix("```json") {
            cleanedJSON = String(cleanedJSON.dropFirst(7))
        }
        if cleanedJSON.hasPrefix("```") {
            cleanedJSON = String(cleanedJSON.dropFirst(3))
        }
        if cleanedJSON.hasSuffix("```") {
            cleanedJSON = String(cleanedJSON.dropLast(3))
        }
        cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle edge case where JSON might be wrapped in extra content
        if let startIndex = cleanedJSON.firstIndex(of: "{"),
           let endIndex = cleanedJSON.lastIndex(of: "}") {
            cleanedJSON = String(cleanedJSON[startIndex...endIndex])
        }

        guard let jsonData = cleanedJSON.data(using: .utf8) else {
            throw ParserError.invalidJSON
        }

        // Check for ultra-compact format first
        if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
            if let compactFolders = jsonObject["f"] as? [[String: Any]] {
                // Parse ultra-compact format: {"f":[{"n":"Folder","files":[]}]}
                let suggestions = compactFolders.compactMap { dict -> FolderSuggestion? in
                    guard let name = dict["n"] as? String,
                          let fileNames = dict["files"] as? [String] else { return nil }
                    
                    var files: [FileItem] = []
                    for fileName in fileNames {
                        if let file = findFile(named: fileName, in: originalFiles) {
                            files.append(file)
                        }
                    }
                    
                    return FolderSuggestion(
                        folderName: name,
                        files: files,
                        reasoning: "Generated from ultra-compact format"
                    )
                }
                
                // Identify unorganized files
                let organizedIds = Set(suggestions.flatMap { $0.files }.map { $0.id })
                let unorganizedFiles = originalFiles.filter { !organizedIds.contains($0.id) }
                
                return OrganizationPlan(
                    suggestions: suggestions,
                    unorganizedFiles: unorganizedFiles,
                    notes: "Processed via ultra-compact strategy",
                    timestamp: Date(),
                    version: 1
                )
            }
        }

        let decoder = JSONDecoder()
        // Do NOT use convertFromSnakeCase here as we handle it in CodingKeys
        
        let response: AIResponse

        do {
            response = try decoder.decode(AIResponse.self, from: jsonData)
        } catch {
            // Try with default key strategy
            let defaultDecoder = JSONDecoder()
            response = try defaultDecoder.decode(AIResponse.self, from: jsonData)
        }

        let fileIdIndex = Dictionary(uniqueKeysWithValues: originalFiles.enumerated().map { ($0.offset + 1, $0.element) })
        let folderPayload = response.folders.isEmpty ? (response.folderAssignments ?? []) : response.folders

        // Convert response to OrganizationPlan
        let suggestions = folderPayload.map { folder in
            convertFolderResponse(folder, originalFiles: originalFiles, fileIdIndex: fileIdIndex)
        }
        let assignedFileIDs = collectAssignedFileIDs(from: suggestions)

        var unorganizedDetails = (response.unorganized ?? []).map { unorg in
            UnorganizedFile(filename: unorg.filename, reason: unorg.reason)
        }
        if let unorganizedIDs = response.unorganizedIDs {
            for id in unorganizedIDs {
                if let file = fileIdIndex[id] {
                    unorganizedDetails.append(
                        UnorganizedFile(
                            filename: file.displayName,
                            reason: "Marked as unorganized in compact file_ids response"
                        )
                    )
                }
            }
        }

        var unorganizedFiles: [FileItem] = []
        var seenUnorganizedIDs: Set<UUID> = []

        for detail in unorganizedDetails {
            guard let file = findFile(named: detail.filename, in: originalFiles) else { continue }
            guard !assignedFileIDs.contains(file.id) else { continue }
            guard seenUnorganizedIDs.insert(file.id).inserted else { continue }
            unorganizedFiles.append(file)
        }

        // Defensive fallback: if the model omitted/garbled mappings, keep unmatched files visible.
        for file in originalFiles where !assignedFileIDs.contains(file.id) {
            guard seenUnorganizedIDs.insert(file.id).inserted else { continue }
            unorganizedFiles.append(file)
            unorganizedDetails.append(
                UnorganizedFile(
                    filename: file.displayName,
                    reason: "Could not map this file from AI response; kept unorganized."
                )
            )
        }

        return OrganizationPlan(
            suggestions: suggestions,
            unorganizedFiles: unorganizedFiles,
            unorganizedDetails: unorganizedDetails,
            notes: response.notes ?? "",
            timestamp: Date(),
            version: 1
        )
    }

    private static func collectAssignedFileIDs(from suggestions: [FolderSuggestion]) -> Set<UUID> {
        var ids: Set<UUID> = []

        func walk(_ folder: FolderSuggestion) {
            for file in folder.files {
                ids.insert(file.id)
            }
            for subfolder in folder.subfolders {
                walk(subfolder)
            }
        }

        for suggestion in suggestions {
            walk(suggestion)
        }

        return ids
    }

    private static func convertFolderResponse(
        _ folder: FolderResponse,
        originalFiles: [FileItem],
        fileIdIndex: [Int: FileItem]
    ) -> FolderSuggestion {
        var files: [FileItem] = []
        var renameMappings: [FileRenameMapping] = []
        var seenFileIds: Set<UUID> = []

        if let fileIDs = folder.fileIDs {
            for id in fileIDs {
                guard let file = fileIdIndex[id], !seenFileIds.contains(file.id) else { continue }
                seenFileIds.insert(file.id)
                files.append(file)
            }
        }

        for fileEntry in folder.files {
            if let file = findFile(named: fileEntry.filename, in: originalFiles) {
                // Deduplicate: Don't add the same physical file twice to the same folder
                guard !seenFileIds.contains(file.id) else { continue }
                seenFileIds.insert(file.id)

                files.append(file)

                // Create rename mapping if suggested
                if let suggestedName = fileEntry.suggestedName, !suggestedName.isEmpty {
                    let mapping = FileRenameMapping(
                        originalFile: file,
                        suggestedName: suggestedName,
                        renameReason: fileEntry.renameReason
                    )
                    renameMappings.append(mapping)
                }

                // Add tags if present
                if let tags = fileEntry.tags, !tags.isEmpty {
                    // We'll collect these into a temporary list and add to FolderSuggestion logic below
                    // NOTE: FolderSuggestion doesn't have a mutable 'addTag' during init easily without
                    // accumulating them first. Let's create the FileTagMapping here.
                }
            }
        }
        
        // Collect tag and comment mappings
        var tagMappings: [FileTagMapping] = []
        for fileEntry in folder.files {
           if let file = findFile(named: fileEntry.filename, in: originalFiles) {
               let tags = fileEntry.tags ?? []
               let comment = fileEntry.comment
               if !tags.isEmpty || (comment != nil && !comment!.isEmpty) {
                   tagMappings.append(FileTagMapping(originalFile: file, tags: tags, comment: comment))
               }
           }
        }

        let subfolders = (folder.subfolders ?? []).map { subfolder in
            convertFolderResponse(subfolder, originalFiles: originalFiles, fileIdIndex: fileIdIndex)
        }

        return FolderSuggestion(
            folderName: folder.name,
            description: folder.description ?? "",
            files: files,
            subfolders: subfolders,
            reasoning: folder.reasoning ?? folder.description ?? "",
            fileRenameMappings: renameMappings,
            fileTagMappings: tagMappings,
            tags: folder.tags ?? [],
            comment: folder.comment,
            semanticTags: folder.semanticTags ?? [],
            confidenceScore: folder.confidence,
            ruleId: folder.ruleId
        )
    }

    /// Find a file by name with fuzzy matching support
    private static func findFile(named filename: String, in files: [FileItem]) -> FileItem? {
        let candidates = normalizedFilenameCandidates(from: filename)
        guard !candidates.isEmpty else { return nil }

        // Exact match on displayName or name
        for candidate in candidates {
            if let exact = files.first(where: { $0.displayName == candidate }) {
                return exact
            }
            if let exactName = files.first(where: { $0.name == candidate }) {
                return exactName
            }
        }

        // Case-insensitive match
        for candidate in candidates {
            let lowered = candidate.lowercased()
            if let caseInsensitive = files.first(where: {
                $0.displayName.lowercased() == lowered || $0.name.lowercased() == lowered
            }) {
                return caseInsensitive
            }
        }

        // Special case: AI provides extension only (like "sh", "png", "jpg")
        for candidate in candidates where candidate.count <= 5 && !candidate.contains(".") {
            if let extMatch = files.first(where: { $0.extension.lowercased() == candidate.lowercased() }) {
                return extMatch
            }
        }

        // Partial match (only for names longer than 3 chars to avoid false positives)
        for candidate in candidates where candidate.count > 3 {
            if let partial = files.first(where: {
                $0.displayName.contains(candidate) || candidate.contains($0.displayName)
            }) {
                return partial
            }
        }

        return nil
    }

    private static func normalizedFilenameCandidates(from raw: String) -> [String] {
        var candidates: [String] = []
        var seen: Set<String> = []

        func appendCandidate(_ value: String) {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return }
            candidates.append(trimmed)
        }

        appendCandidate(raw)

        let strippedQuotes = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
        appendCandidate(strippedQuotes)

        let slashNormalized = strippedQuotes.replacingOccurrences(of: "\\", with: "/")
        appendCandidate(slashNormalized)

        if slashNormalized.hasPrefix("./") {
            appendCandidate(String(slashNormalized.dropFirst(2)))
        }

        if let lastPathComponent = slashNormalized.split(separator: "/").last {
            appendCandidate(String(lastPathComponent))
        }

        if let decoded = slashNormalized.removingPercentEncoding {
            appendCandidate(decoded)
            if let decodedLastPathComponent = decoded.split(separator: "/").last {
                appendCandidate(String(decodedLastPathComponent))
            }
        }

        return candidates
    }

    // MARK: - Validation

    static func validateStructure(_ jsonString: String) -> Bool {
        do {
            var cleanedJSON = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleanedJSON.hasPrefix("```json") {
                cleanedJSON = String(cleanedJSON.dropFirst(7))
            }
            if cleanedJSON.hasPrefix("```") {
                cleanedJSON = String(cleanedJSON.dropFirst(3))
            }
            if cleanedJSON.hasSuffix("```") {
                cleanedJSON = String(cleanedJSON.dropLast(3))
            }
            cleanedJSON = cleanedJSON.trimmingCharacters(in: .whitespacesAndNewlines)

            if let startIndex = cleanedJSON.firstIndex(of: "{"),
               let endIndex = cleanedJSON.lastIndex(of: "}") {
                cleanedJSON = String(cleanedJSON[startIndex...endIndex])
            }

            guard let jsonData = cleanedJSON.data(using: .utf8) else {
                return false
            }

            let _ = try JSONDecoder().decode(AIResponse.self, from: jsonData)
            return true
        } catch {
            return false
        }
    }

    /// Extract partial results even if parsing fails
    static func extractPartialResults(_ jsonString: String, originalFiles: [FileItem]) -> OrganizationPlan? {
        // Try to extract folder names and file assignments even from malformed JSON
        var suggestions: [FolderSuggestion] = []
        var assignedFiles: Set<UUID> = []

        // Simple regex-based extraction as fallback
        let folderPattern = #"\"name\"\s*:\s*\"([^\"]+)\""#
        let filesPattern = #"\"files\"\s*:\s*\[([^\]]+)\]"#

        if let folderRegex = try? NSRegularExpression(pattern: folderPattern),
           let filesRegex = try? NSRegularExpression(pattern: filesPattern) {

            let range = NSRange(jsonString.startIndex..., in: jsonString)
            let folderMatches = folderRegex.matches(in: jsonString, range: range)
            let filesMatches = filesRegex.matches(in: jsonString, range: range)

            for (index, folderMatch) in folderMatches.enumerated() {
                if let folderRange = Range(folderMatch.range(at: 1), in: jsonString) {
                    let folderName = String(jsonString[folderRange])

                    var folderFiles: [FileItem] = []

                    // Try to find corresponding files
                    if index < filesMatches.count {
                        if let filesRange = Range(filesMatches[index].range(at: 1), in: jsonString) {
                            let filesContent = String(jsonString[filesRange])

                            // Extract quoted strings
                            let fileNamePattern = #"\"([^\"]+)\""#
                            if let fileNameRegex = try? NSRegularExpression(pattern: fileNamePattern) {
                                let fileNameMatches = fileNameRegex.matches(in: filesContent, range: NSRange(filesContent.startIndex..., in: filesContent))

                                for fileNameMatch in fileNameMatches {
                                    if let nameRange = Range(fileNameMatch.range(at: 1), in: filesContent) {
                                        let fileName = String(filesContent[nameRange])
                                        if let file = findFile(named: fileName, in: originalFiles),
                                           !assignedFiles.contains(file.id) {
                                            folderFiles.append(file)
                                            assignedFiles.insert(file.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !folderFiles.isEmpty {
                        suggestions.append(FolderSuggestion(
                            folderName: folderName,
                            files: folderFiles,
                            reasoning: "Extracted from partial response"
                        ))
                    }
                }
            }
        }

        guard !suggestions.isEmpty else { return nil }

        // Unassigned files go to unorganized
        let unorganizedFiles = originalFiles.filter { !assignedFiles.contains($0.id) }

        return OrganizationPlan(
            suggestions: suggestions,
            unorganizedFiles: unorganizedFiles,
            notes: "Partial extraction - some organization data may be missing",
            timestamp: Date(),
            version: 1
        )
    }
}

// MARK: - Errors

enum ParserError: LocalizedError {
    case invalidJSON
    case missingRequiredFields
    case fileNotFound
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON response from AI"
        case .missingRequiredFields:
            return "Response missing required fields"
        case .fileNotFound:
            return "Referenced file not found in original list"
        case .emptyResponse:
            return "Empty response from AI"
        }
    }
}
