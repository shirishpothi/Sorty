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
        let unorganized: [UnorganizedFileResponse]?
        let notes: String?

        enum CodingKeys: String, CodingKey {
            case folders, unorganized, notes
        }
    }


    struct FolderResponse: Codable {
        let name: String
        let description: String?
        let reasoning: String?
        let subfolders: [FolderResponse]?
        let files: [FileEntry]
        let semanticTags: [String]?
        let confidence: Double?

        // Support both array of strings and array of FileEntry objects
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            reasoning = try container.decodeIfPresent(String.self, forKey: .reasoning)
            subfolders = try container.decodeIfPresent([FolderResponse].self, forKey: .subfolders)
            semanticTags = try container.decodeIfPresent([String].self, forKey: .semanticTags)
            confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)

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
            case semanticTags = "semantic_tags"
            case confidence
        }
    }


    /// Represents a file entry in the AI response with optional rename suggestion
    struct FileEntry: Codable {
        let filename: String
        let suggestedName: String?
        let renameReason: String?
        let tags: [String]?

        init(filename: String, suggestedName: String? = nil, renameReason: String? = nil, tags: [String]? = nil) {
            self.filename = filename
            self.suggestedName = suggestedName
            self.renameReason = renameReason
            self.tags = tags
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(filename, forKey: .filename)
            try container.encodeIfPresent(suggestedName, forKey: .suggestedName)
            try container.encodeIfPresent(renameReason, forKey: .renameReason)
            try container.encodeIfPresent(tags, forKey: .tags)
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
                return
            }

            // Otherwise decode as object
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filename = try container.decode(String.self, forKey: .filename)
            suggestedName = try container.decodeIfPresent(String.self, forKey: .suggestedName)
            renameReason = try container.decodeIfPresent(String.self, forKey: .renameReason)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
        }

        enum CodingKeys: String, CodingKey {
            case filename
            case suggestedName = "suggested_name"
            case renameReason = "rename_reason"
            case tags
        }
    }


    struct UnorganizedFileResponse: Codable {
        let filename: String
        let reason: String
    }

    // MARK: - Parsing

    static func parseResponse(_ jsonString: String, originalFiles: [FileItem]) throws -> OrganizationPlan {
        // Clean the JSON string - remove markdown code blocks if present
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

        // Convert response to OrganizationPlan
        let suggestions = response.folders.map { folder in
            convertFolderResponse(folder, originalFiles: originalFiles)
        }

        let unorganizedDetails = (response.unorganized ?? []).map { unorg in
            UnorganizedFile(filename: unorg.filename, reason: unorg.reason)
        }

        let unorganizedFiles = unorganizedDetails.compactMap { detail -> FileItem? in
            findFile(named: detail.filename, in: originalFiles)
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

    private static func convertFolderResponse(_ folder: FolderResponse, originalFiles: [FileItem]) -> FolderSuggestion {
        var files: [FileItem] = []
        var renameMappings: [FileRenameMapping] = []

        for fileEntry in folder.files {
            if let file = findFile(named: fileEntry.filename, in: originalFiles) {
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
        
        // Collect tag mappings
        var tagMappings: [FileTagMapping] = []
        for fileEntry in folder.files {
           if let file = findFile(named: fileEntry.filename, in: originalFiles),
              let tags = fileEntry.tags, !tags.isEmpty {
               tagMappings.append(FileTagMapping(originalFile: file, tags: tags))
           }
        }

        let subfolders = (folder.subfolders ?? []).map { subfolder in
            convertFolderResponse(subfolder, originalFiles: originalFiles)
        }

        return FolderSuggestion(
            folderName: folder.name,
            description: folder.description ?? "",
            files: files,
            subfolders: subfolders,
            reasoning: folder.reasoning ?? folder.description ?? "",
            fileRenameMappings: renameMappings,
            fileTagMappings: tagMappings,
            semanticTags: folder.semanticTags ?? [],
            confidenceScore: folder.confidence
        )
    }

    /// Find a file by name with fuzzy matching support
    private static func findFile(named filename: String, in files: [FileItem]) -> FileItem? {
        // Exact match on displayName
        if let exact = files.first(where: { $0.displayName == filename }) {
            return exact
        }

        // Exact match on name only
        if let nameMatch = files.first(where: { $0.name == filename }) {
            return nameMatch
        }

        // Case-insensitive match
        if let caseInsensitive = files.first(where: {
            $0.displayName.lowercased() == filename.lowercased()
        }) {
            return caseInsensitive
        }

        // Partial match (filename contains or is contained)
        if let partial = files.first(where: {
            $0.displayName.contains(filename) || filename.contains($0.displayName)
        }) {
            return partial
        }

        return nil
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

