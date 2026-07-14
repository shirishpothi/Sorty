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

    private struct LossyArray<Element: Decodable>: Decodable {
        let elements: [Element]

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var decoded: [Element] = []

            while !container.isAtEnd {
                let elementDecoder = try container.superDecoder()
                if let element = try? Element(from: elementDecoder) {
                    decoded.append(element)
                }
            }

            elements = decoded
        }
    }

    struct AIResponse: Decodable {
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
            folders = try container.decodeIfPresent(LossyArray<FolderResponse>.self, forKey: .folders)?.elements ?? []
            folderAssignments = try container.decodeIfPresent(
                LossyArray<FolderResponse>.self,
                forKey: .folderAssignments
            )?.elements
            unorganized = try container.decodeIfPresent([UnorganizedFileResponse].self, forKey: .unorganized)
            unorganizedIDs = try container.decodeIfPresent([Int].self, forKey: .unorganizedIDs)
            notes = try container.decodeIfPresent(String.self, forKey: .notes)
        }
    }


    struct FolderResponse: Decodable {
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
            subfolders = try container.decodeIfPresent(
                LossyArray<FolderResponse>.self,
                forKey: .subfolders
            )?.elements
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
        let renameConfidence: Double?
        let tags: [String]?
        let comment: String?

        init(
            filename: String,
            suggestedName: String? = nil,
            renameReason: String? = nil,
            renameConfidence: Double? = nil,
            tags: [String]? = nil,
            comment: String? = nil
        ) {
            self.filename = filename
            self.suggestedName = suggestedName
            self.renameReason = renameReason
            self.renameConfidence = renameConfidence
            self.tags = tags
            self.comment = comment
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(filename, forKey: .filename)
            try container.encodeIfPresent(suggestedName, forKey: .suggestedName)
            try container.encodeIfPresent(renameReason, forKey: .renameReason)
            try container.encodeIfPresent(renameConfidence, forKey: .renameConfidence)
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
                self.renameConfidence = nil
                self.tags = nil
                self.comment = nil
                return
            }

            // Otherwise decode as object
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filename = try container.decode(String.self, forKey: .filename)
            suggestedName = try container.decodeIfPresent(String.self, forKey: .suggestedName)
            renameReason = try container.decodeIfPresent(String.self, forKey: .renameReason)
            renameConfidence = try container.decodeIfPresent(Double.self, forKey: .renameConfidence)
            tags = try container.decodeIfPresent([String].self, forKey: .tags)
            comment = try container.decodeIfPresent(String.self, forKey: .comment)
        }

        enum CodingKeys: String, CodingKey {
            case filename
            case suggestedName = "suggested_name"
            case renameReason = "rename_reason"
            case renameConfidence = "rename_confidence"
            case tags
            case comment
        }
    }


    struct UnorganizedFileResponse: Decodable {
        let filename: String
        let reason: String

        init(filename: String, reason: String) {
            self.filename = filename
            self.reason = reason
        }

        init(from decoder: Decoder) throws {
            if let container = try? decoder.singleValueContainer(),
               let simpleFilename = try? container.decode(String.self) {
                self.filename = simpleFilename
                self.reason = "Marked as unorganized by AI response"
                return
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let decodedFilename = try? container.decode(String.self, forKey: .filename) {
                self.filename = decodedFilename
            } else if let fallbackFilename = try? container.decode(String.self, forKey: .file) {
                self.filename = fallbackFilename
            } else {
                throw DecodingError.keyNotFound(
                    CodingKeys.filename,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing filename")
                )
            }

            let decodedReason = (try? container.decode(String.self, forKey: .reason))?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let decodedReason, !decodedReason.isEmpty {
                self.reason = decodedReason
            } else {
                self.reason = "Marked as unorganized by AI response"
            }
        }

        enum CodingKeys: String, CodingKey {
            case filename
            case reason
            case file
        }
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
                if let jsonStart = embeddedJSONStart(inProgressLine: line) {
                    let jsonPortion = String(line[jsonStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !jsonPortion.isEmpty {
                        pastPreamble = true
                        result.append(jsonPortion)
                    }
                }
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

    private static func embeddedJSONStart(inProgressLine line: String) -> String.Index? {
        let lowered = line.lowercased()
        guard lowered.contains("ready to output organization structure") else { return nil }

        let objectStart = line.firstIndex(of: "{")
        let arrayStart = line.firstIndex(of: "[")

        switch (objectStart, arrayStart) {
        case let (.some(lhs), .some(rhs)):
            return lhs < rhs ? lhs : rhs
        case let (.some(lhs), .none):
            return lhs
        case let (.none, .some(rhs)):
            return rhs
        case (.none, .none):
            return nil
        }
    }

    static func parseResponse(
        _ jsonString: String,
        originalFiles: [FileItem],
        mode: OrganizationMode = .organize
    ) throws -> OrganizationPlan {
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
        cleanedJSON = sanitizeJSONPayload(cleanedJSON)

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

                guard !suggestions.isEmpty else {
                    throw ParserError.missingRequiredFields
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

        let hasExplicitUnorganizedFiles = !(response.unorganized ?? []).isEmpty ||
            !(response.unorganizedIDs ?? []).isEmpty
        guard !folderPayload.isEmpty || hasExplicitUnorganizedFiles else {
            throw ParserError.missingRequiredFields
        }

        // Convert response to OrganizationPlan
        let suggestions = folderPayload.map { folder in
            convertFolderResponse(folder, originalFiles: originalFiles, fileIdIndex: fileIdIndex, mode: mode)
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
        fileIdIndex: [Int: FileItem],
        mode: OrganizationMode
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
                if seenFileIds.insert(file.id).inserted {
                    files.append(file)
                }

                // Parse-level safeguard: strip all rename fields in organize-only mode.
                if mode != .organize {
                    let clampedConfidence = fileEntry.renameConfidence.map { min(max($0, 0.0), 1.0) }
                    if let confidence = clampedConfidence, confidence < FileRenameMapping.lowConfidenceThreshold {
                        let mapping = FileRenameMapping(
                            originalFile: file,
                            suggestedName: nil,
                            renameReason: "AI unsure (confidence: \(String(format: "%.2f", confidence)))",
                            renameConfidence: confidence
                        )
                        renameMappings.append(mapping)
                        continue
                    }

                    let suggestedName = fileEntry.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let renameReason = fileEntry.renameReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !suggestedName.isEmpty || !renameReason.isEmpty || clampedConfidence != nil {
                        let mapping = FileRenameMapping(
                            originalFile: file,
                            suggestedName: suggestedName.isEmpty ? nil : suggestedName,
                            renameReason: renameReason.isEmpty ? nil : renameReason,
                            renameConfidence: clampedConfidence
                        )
                        renameMappings.append(mapping)
                    }
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
            convertFolderResponse(subfolder, originalFiles: originalFiles, fileIdIndex: fileIdIndex, mode: mode)
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

    private static func sanitizeJSONPayload(_ payload: String) -> String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let extracted = extractLikelyJSONObject(from: trimmed) ?? trimmed
        return removeTrailingCommas(in: extracted)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractLikelyJSONObject(from text: String) -> String? {
        let candidates = balancedJSONObjectCandidates(in: text)
        guard !candidates.isEmpty else { return nil }

        if let preferred = candidates.last(where: { candidate in
            let lower = candidate.lowercased()
            return lower.contains("\"folders\"") ||
                lower.contains("\"folder_assignments\"") ||
                lower.contains("\"unorganized\"") ||
                lower.contains("\"f\"")
        }) {
            return preferred
        }

        return candidates.max(by: { $0.count < $1.count })
    }

    private static func balancedJSONObjectCandidates(in text: String) -> [String] {
        var candidates: [String] = []
        var depth = 0
        var objectStart: String.Index?
        var inString = false
        var isEscaping = false

        for index in text.indices {
            let character = text[index]

            if inString {
                if isEscaping {
                    isEscaping = false
                    continue
                }
                if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                continue
            }

            if character == "{" {
                if depth == 0 {
                    objectStart = index
                }
                depth += 1
                continue
            }

            if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let startIndex = objectStart {
                    candidates.append(String(text[startIndex...index]))
                    objectStart = nil
                }
            }
        }

        return candidates
    }

    private static func removeTrailingCommas(in json: String) -> String {
        json.replacingOccurrences(
            of: #",\s*([\}\]])"#,
            with: "$1",
            options: .regularExpression
        )
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
            cleanedJSON = sanitizeJSONPayload(cleanedJSON)

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
    static func extractPartialResults(
        _ jsonString: String,
        originalFiles: [FileItem],
        mode: OrganizationMode = .organize
    ) -> OrganizationPlan? {
        // Try to extract folder names and file assignments even from malformed JSON
        var suggestions: [FolderSuggestion] = []
        var assignedFiles: Set<UUID> = []
        let workingJSON = stripProgressPreamble(jsonString)
        let fileIdIndex = Dictionary(uniqueKeysWithValues: originalFiles.enumerated().map { ($0.offset + 1, $0.element) })

        for segment in folderObjectSegments(in: workingJSON) {
            if let data = sanitizeJSONPayload(segment).data(using: .utf8),
               let folder = try? JSONDecoder().decode(FolderResponse.self, from: data) {
                let suggestion = convertFolderResponse(
                    folder,
                    originalFiles: originalFiles,
                    fileIdIndex: fileIdIndex,
                    mode: mode
                )
                let suggestionFileIDs = collectAssignedFileIDs(from: [suggestion])
                if suggestionFileIDs.contains(where: { !assignedFiles.contains($0) }) {
                    assignedFiles.formUnion(suggestionFileIDs)
                    suggestions.append(suggestion)
                }
                continue
            }

            guard let folderName = stringValue(forKey: "name", in: segment) else { continue }
            let fileNames = fileNames(in: segment)
            let fileIDs = integerValues(forKey: "file_ids", in: segment)
            var folderFiles: [FileItem] = []

            for fileName in fileNames {
                guard let file = findFile(named: fileName, in: originalFiles),
                      assignedFiles.insert(file.id).inserted else { continue }
                folderFiles.append(file)
            }
            for id in fileIDs {
                guard let file = fileIdIndex[id],
                      assignedFiles.insert(file.id).inserted else { continue }
                folderFiles.append(file)
            }

            if !folderFiles.isEmpty {
                suggestions.append(FolderSuggestion(
                    folderName: folderName,
                    files: folderFiles,
                    reasoning: "Extracted from partial response"
                ))
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

    private static func folderObjectSegments(in text: String) -> [String] {
        ["folders", "folder_assignments"].flatMap { key in
            objectSegments(inArrayForKey: key, text: text)
        }
    }

    private static func objectSegments(inArrayForKey key: String, text: String) -> [String] {
        var segments: [String] = []
        var searchStart = text.startIndex
        let marker = "\"\(key)\""

        while searchStart < text.endIndex,
              let keyRange = text.range(of: marker, range: searchStart..<text.endIndex),
              let arrayStart = arrayStart(after: keyRange.upperBound, in: text) {
            var index = text.index(after: arrayStart)
            var objectStart: String.Index?
            var objectDepth = 0
            var arrayDepth = 1
            var isInsideString = false
            var isEscaping = false

            while index < text.endIndex, arrayDepth > 0 {
                let character = text[index]

                if isInsideString {
                    if isEscaping {
                        isEscaping = false
                    } else if character == "\\" {
                        isEscaping = true
                    } else if character == "\"" {
                        isInsideString = false
                    }
                    index = text.index(after: index)
                    continue
                }

                switch character {
                case "\"":
                    isInsideString = true
                case "[":
                    arrayDepth += 1
                case "]":
                    arrayDepth -= 1
                case "{":
                    if objectDepth == 0 {
                        objectStart = index
                    }
                    objectDepth += 1
                case "}":
                    if objectDepth > 0 {
                        objectDepth -= 1
                        if objectDepth == 0, let objectStart {
                            segments.append(String(text[objectStart...index]))
                        }
                    }
                default:
                    break
                }

                index = text.index(after: index)
            }

            if objectDepth > 0, let objectStart {
                segments.append(String(text[objectStart...]))
            }

            if index > keyRange.upperBound {
                searchStart = index
            } else {
                searchStart = keyRange.upperBound
            }
        }

        return segments
    }

    private static func arrayStart(after start: String.Index, in text: String) -> String.Index? {
        guard let colon = text[start...].firstIndex(of: ":") else { return nil }
        var index = text.index(after: colon)
        while index < text.endIndex, text[index].isWhitespace {
            index = text.index(after: index)
        }
        return index < text.endIndex, text[index] == "[" ? index : nil
    }

    private static func stringValue(forKey key: String, in object: String) -> String? {
        if let data = sanitizeJSONPayload(object).data(using: .utf8),
           let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let value = dictionary[key] as? String {
            return value
        }

        let pattern = "\\\"\(NSRegularExpression.escapedPattern(for: key))\\\"\\s*:\\s*\\\"([^\\\"]+)\\\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: object, range: NSRange(object.startIndex..., in: object)),
              let valueRange = Range(match.range(at: 1), in: object) else { return nil }
        return String(object[valueRange])
    }

    private static func fileNames(in object: String) -> [String] {
        if let payload = arrayPayload(forKey: "files", in: object),
           let data = payload.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return values.compactMap { value in
                if let filename = value as? String {
                    return filename
                }
                return (value as? [String: Any])?["filename"] as? String
            }
        }

        guard let remainder = arrayRemainder(forKey: "files", in: object) else { return [] }
        return partialFileNames(in: remainder)
    }

    private static func partialFileNames(in arrayRemainder: String) -> [String] {
        let filenamePattern = #"\"filename\"\s*:\s*\"([^\"]+)\""#
        if let regex = try? NSRegularExpression(pattern: filenamePattern) {
            let matches = regex.matches(
                in: arrayRemainder,
                range: NSRange(arrayRemainder.startIndex..., in: arrayRemainder)
            )
            let filenames = matches.compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: arrayRemainder) else { return nil }
                return String(arrayRemainder[range])
            }
            if !filenames.isEmpty {
                return filenames
            }
        }

        var values: [String] = []
        var index = arrayRemainder.startIndex
        var arrayDepth = 0
        var objectDepth = 0
        var stringStart: String.Index?
        var isEscaping = false

        while index < arrayRemainder.endIndex {
            let character = arrayRemainder[index]
            if let start = stringStart {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    if arrayDepth == 1, objectDepth == 0 {
                        values.append(String(arrayRemainder[start..<index]))
                    }
                    stringStart = nil
                }
            } else {
                switch character {
                case "\"":
                    stringStart = arrayRemainder.index(after: index)
                case "[":
                    arrayDepth += 1
                case "]":
                    arrayDepth -= 1
                case "{":
                    objectDepth += 1
                case "}":
                    objectDepth = max(0, objectDepth - 1)
                default:
                    break
                }
            }
            index = arrayRemainder.index(after: index)
        }

        return values
    }

    private static func integerValues(forKey key: String, in object: String) -> [Int] {
        if let payload = arrayPayload(forKey: key, in: object),
           let data = payload.data(using: .utf8),
           let values = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return values.compactMap { ($0 as? NSNumber)?.intValue }
        }

        guard let remainder = arrayRemainder(forKey: key, in: object),
              let regex = try? NSRegularExpression(pattern: #"\d+"#) else { return [] }
        return regex.matches(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)).compactMap { match in
            guard let range = Range(match.range, in: remainder) else { return nil }
            return Int(remainder[range])
        }
    }

    private static func arrayRemainder(forKey key: String, in object: String) -> String? {
        let marker = "\"\(key)\""
        guard let keyRange = object.range(of: marker),
              let start = arrayStart(after: keyRange.upperBound, in: object) else { return nil }
        return String(object[start...])
    }

    private static func arrayPayload(forKey key: String, in object: String) -> String? {
        let marker = "\"\(key)\""
        guard let keyRange = object.range(of: marker),
              let start = arrayStart(after: keyRange.upperBound, in: object) else { return nil }

        var index = start
        var depth = 0
        var isInsideString = false
        var isEscaping = false

        while index < object.endIndex {
            let character = object[index]

            if isInsideString {
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    isInsideString = false
                }
            } else {
                if character == "\"" {
                    isInsideString = true
                } else if character == "[" {
                    depth += 1
                } else if character == "]" {
                    depth -= 1
                    if depth == 0 {
                        return String(object[start...index])
                    }
                }
            }

            index = object.index(after: index)
        }

        return nil
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
