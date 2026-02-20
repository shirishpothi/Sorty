import Foundation

public actor AIInsightExtractor {
    private static let analysisWindowSize = 2_000

    public init() {}

    public func extractInsight(
        from content: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        guard content.count > 20 else { return nil }

        let analysisWindow = String(content.suffix(Self.analysisWindowSize))

        if let structuredInsight = extractStructuredJSONInsight(
            from: analysisWindow,
            scannedFilePathLookup: scannedFilePathLookup,
            currentDirectoryPath: currentDirectoryPath
        ) {
            return structuredInsight
        }

        if let fileInsight = extractFileInsight(from: analysisWindow, scannedFilePathLookup: scannedFilePathLookup, currentDirectoryPath: currentDirectoryPath) {
            return fileInsight
        }

        if let folderInsight = extractFolderInsight(from: analysisWindow) {
            return folderInsight
        }

        if let constraintInsight = extractConstraintInsight(from: analysisWindow) {
            return constraintInsight
        }

        if let decisionInsight = extractDecisionInsight(from: analysisWindow) {
            return decisionInsight
        }

        return extractGeneralInsight(from: analysisWindow)
    }

    private func extractStructuredJSONInsight(
        from text: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        if let assignmentInsight = extractJSONFileAssignmentInsight(
            from: text,
            scannedFilePathLookup: scannedFilePathLookup,
            currentDirectoryPath: currentDirectoryPath
        ) {
            return assignmentInsight
        }

        if let folderInsight = extractJSONFolderInsight(from: text) {
            return folderInsight
        }

        if let reasoningInsight = extractJSONReasoningInsight(from: text) {
            return reasoningInsight
        }

        return nil
    }

    private func extractJSONFileAssignmentInsight(
        from text: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        let pattern = #""name"\s*:\s*"([^"\n]{2,80})"[\s\S]{0,500}?"files"\s*:\s*\[([\s\S]{0,500}?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return nil }

        for match in matches.reversed() {
            guard let folderRange = Range(match.range(at: 1), in: text),
                  let filesRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let folderName = normalizeName(String(text[folderRange]))
            guard isLikelyFolderName(folderName) else { continue }

            let fileSection = String(text[filesRange])
            if let fileName = extractLatestFileName(fromJSONFileSection: fileSection) {
                let resolvedFileName = URL(fileURLWithPath: fileName).lastPathComponent
                let filePath = findScannedFilePath(
                    for: resolvedFileName,
                    scannedFilePathLookup: scannedFilePathLookup,
                    currentDirectoryPath: currentDirectoryPath
                )
                if let insight = makeInsight(
                    text: "Assigning \(resolvedFileName) to \(folderName)",
                    category: .file,
                    filePath: filePath,
                    stableSeed: "\(folderName)|\(filePath ?? resolvedFileName)"
                ) {
                    return insight
                }
                continue
            }

            if let insight = makeInsight(
                text: "Preparing folder \(folderName)",
                category: .folder,
                stableSeed: folderName
            ) {
                return insight
            }
        }

        return nil
    }

    private func extractJSONFolderInsight(from text: String) -> AIInsight? {
        let pattern = #"(?:^|[\{,])\s*"name"\s*:\s*"([^"\n]{2,80})""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard let match = matches.last,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let folderName = normalizeName(String(text[range]))
        guard isLikelyFolderName(folderName) else { return nil }

        return makeInsight(
            text: "Preparing folder \(folderName)",
            category: .folder,
            stableSeed: folderName
        )
    }

    private func extractJSONReasoningInsight(from text: String) -> AIInsight? {
        let pattern = #""reasoning"\s*:\s*"([^"\n]{12,220})""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        guard let match = matches.last,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        var reasoning = normalizeName(String(text[range]))
        reasoning = reasoning.replacingOccurrences(of: #"\\n"#, with: " ")
        reasoning = reasoning.replacingOccurrences(of: #"\\/"#, with: "/")
        reasoning = collapseWhitespace(in: reasoning)
        guard reasoning.count >= 12 else { return nil }

        let trimmedReasoning = String(reasoning.prefix(90)) + (reasoning.count > 90 ? "..." : "")
        return makeInsight(
            text: trimmedReasoning,
            category: .decision,
            stableSeed: trimmedReasoning
        )
    }

    private func extractFileInsight(
        from text: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        if let knownAssignmentInsight = extractKnownFileAssignmentInsight(
            from: text,
            scannedFilePathLookup: scannedFilePathLookup,
            currentDirectoryPath: currentDirectoryPath
        ) {
            return knownAssignmentInsight
        }

        if let knownFileInsight = extractKnownScannedFileInsight(
            from: text,
            scannedFilePathLookup: scannedFilePathLookup,
            currentDirectoryPath: currentDirectoryPath
        ) {
            return knownFileInsight
        }

        let patterns = [
            #""filename"\s*:\s*"([^"\n]{3,120}\.[a-zA-Z0-9]{1,8})""#,
            #"(?:"|'|`)([^"'`\n]{3,80}\.[a-zA-Z0-9]{1,8})(?:"|'|`)"#,
            #"(?:name|path)[:\s]+([^\n]{3,120}\.[a-zA-Z0-9]{1,8})"#,
            #"\b([A-Za-z0-9_\-\(\)]+(?: [A-Za-z0-9_\-\(\)]+){0,2}\.[a-zA-Z0-9]{1,12})\b"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            guard !matches.isEmpty else { continue }

            for match in matches.reversed() {
                guard let range = Range(match.range(at: 1), in: text) else { continue }

                let normalizedName = normalizePotentialFileCandidate(String(text[range]))
                guard isLikelyFileName(normalizedName) else { continue }

                let fileName = URL(fileURLWithPath: normalizedName).lastPathComponent
                let filePath = findScannedFilePath(for: fileName, scannedFilePathLookup: scannedFilePathLookup, currentDirectoryPath: currentDirectoryPath)
                if filePath == nil, !isLikelyUnscannedFileName(fileName) {
                    continue
                }
                if let insight = makeInsight(
                    text: "Analyzing \(fileName)",
                    category: .file,
                    filePath: filePath,
                    stableSeed: filePath ?? fileName
                ) {
                    return insight
                }
            }
        }

        return nil
    }

    private func extractFolderInsight(from text: String) -> AIInsight? {
        let patterns = [
            #"(?:folder|directory|destination|target folder|creating folder)[:\s]+["']([^"'\n]{2,50})["']"#,
            #"(?:→|->|=>)\s*["']?([^"'\n,]{2,50})["']?"#,
            #"creating folder[:\s]+["']?([^"'\n,]{2,50})["']?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else { continue }
            guard let range = Range(match.range(at: 1), in: text) else { continue }

            let folderName = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty, folderName.count < 60 else { continue }
            if let insight = makeInsight(
                text: "Organizing into \(folderName)",
                category: .folder,
                stableSeed: folderName
            ) {
                return insight
            }
        }

        return nil
    }

    private func extractConstraintInsight(from text: String) -> AIInsight? {
        let patterns = [
            #"(?:considering|constraint|rule|preference)[:\s]+([^\.\n]{10,100})"#,
            #"(?:because|since|due to|based on|according to)[:\s]+([^\.\n]{10,100})"#,
            #"(?:respecting|following)[:\s]+([^\.\n]{10,100})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else { continue }
            guard let range = Range(match.range(at: 1), in: text) else { continue }

            let constraint = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard constraint.count > 10 else { continue }
            let trimmedConstraint = String(constraint.prefix(60)) + (constraint.count > 60 ? "..." : "")
            if let insight = makeInsight(text: trimmedConstraint, category: .constraint, stableSeed: trimmedConstraint) {
                return insight
            }
        }

        return nil
    }

    private func extractDecisionInsight(from text: String) -> AIInsight? {
        let patterns = [
            #"(?:will move|moving|placing|organizing|grouped with|categorized as|belongs to)[:\s]+([^\.\n]{8,80})"#,
            #"(?:selected|decided)[:\s]+([^\.\n]{8,80})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else { continue }
            guard let range = Range(match.range(at: 1), in: text) else { continue }

            let decision = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard decision.count > 5, decision.count < 90 else { continue }
            if let insight = makeInsight(text: decision, category: .decision, stableSeed: decision) {
                return insight
            }
        }

        return nil
    }

    private func extractGeneralInsight(from text: String) -> AIInsight? {
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))

        for sentence in sentences.reversed() {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 15 && trimmed.count <= 100 else { continue }

            let isProbablyJSONorCode =
                trimmed.contains("{") ||
                trimmed.contains("}") ||
                trimmed.contains("[") ||
                trimmed.contains("]") ||
                trimmed.contains("\":") ||
                trimmed.contains("':") ||
                trimmed.hasPrefix("\"") ||
                trimmed.hasPrefix("```") ||
                trimmed.hasPrefix("name\":") ||
                trimmed.hasPrefix("files\":")

            guard !isProbablyJSONorCode else { continue }
            if let insight = makeInsight(text: trimmed, category: .general, stableSeed: trimmed) {
                return insight
            }
        }

        return nil
    }

    private func findScannedFilePath(
        for fileName: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> String? {
        let key = fileName.lowercased()
        guard let matches = scannedFilePathLookup[key], !matches.isEmpty else { return nil }

        if matches.count == 1 {
            return matches[0]
        }

        if let currentDirectoryPath,
           let preferred = matches.first(where: { $0.hasPrefix(currentDirectoryPath + "/") }) {
            return preferred
        }

        return matches[0]
    }

    private func normalizeName(_ input: String) -> String {
        input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "`", with: "")
    }

    private func normalizePotentialFileCandidate(_ input: String) -> String {
        var normalized = normalizeName(input)
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.trimmingCharacters(in: CharacterSet(charactersIn: "()[]{}<>"))
        normalized = collapseWhitespace(in: normalized)
        return normalized
    }

    private struct CandidateMatch {
        let value: String
        let range: NSRange
    }

    private struct KnownFileMention {
        let fileName: String
        let filePath: String
        let location: Int
    }

    private func extractKnownFileAssignmentInsight(
        from text: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        guard !scannedFilePathLookup.isEmpty else { return nil }
        let fileCandidates = extractKnownFileMentions(
            from: text,
            scannedFilePathLookup: scannedFilePathLookup,
            currentDirectoryPath: currentDirectoryPath
        )
        let folderCandidates = extractPotentialFolderMentions(from: text)
        guard !fileCandidates.isEmpty, !folderCandidates.isEmpty else { return nil }

        for fileCandidate in fileCandidates.reversed() {
            let nearbyFolder = folderCandidates
                .filter { abs($0.range.location - fileCandidate.location) <= 240 }
                .max(by: { $0.range.location < $1.range.location })

            guard let nearbyFolder else { continue }

            if let insight = makeInsight(
                text: "Assigning \(fileCandidate.fileName) to \(nearbyFolder.value)",
                category: .file,
                filePath: fileCandidate.filePath,
                stableSeed: "\(fileCandidate.filePath)|\(nearbyFolder.value)"
            ) {
                return insight
            }
        }

        return nil
    }

    private func extractKnownScannedFileInsight(
        from text: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        guard !scannedFilePathLookup.isEmpty else { return nil }
        let mentions = extractKnownFileMentions(
            from: text,
            scannedFilePathLookup: scannedFilePathLookup,
            currentDirectoryPath: currentDirectoryPath
        )
        guard let mention = mentions.last else { return nil }

        return makeInsight(
            text: "Analyzing \(mention.fileName)",
            category: .file,
            filePath: mention.filePath,
            stableSeed: mention.filePath
        )
    }

    private func extractKnownFileMentions(
        from text: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> [KnownFileMention] {
        guard !text.isEmpty else { return [] }
        let lowercasedText = text.lowercased()
        var mentions: [KnownFileMention] = []

        for (fileNameKey, candidatePaths) in scannedFilePathLookup {
            guard !fileNameKey.isEmpty, !candidatePaths.isEmpty else { continue }
            guard let matchRange = lowercasedText.range(of: fileNameKey, options: [.backwards]) else { continue }

            let location = lowercasedText.distance(from: lowercasedText.startIndex, to: matchRange.lowerBound)
            let resolvedPath: String
            if candidatePaths.count == 1 {
                resolvedPath = candidatePaths[0]
            } else if let currentDirectoryPath,
                      let preferredPath = candidatePaths.first(where: { $0.hasPrefix(currentDirectoryPath + "/") }) {
                resolvedPath = preferredPath
            } else {
                resolvedPath = candidatePaths[0]
            }

            let displayName = URL(fileURLWithPath: resolvedPath).lastPathComponent
            let resolvedDisplayName = displayName.isEmpty ? fileNameKey : displayName
            mentions.append(KnownFileMention(
                fileName: resolvedDisplayName,
                filePath: resolvedPath,
                location: location
            ))
        }

        return mentions.sorted { lhs, rhs in
            if lhs.location == rhs.location {
                return lhs.fileName.count < rhs.fileName.count
            }
            return lhs.location < rhs.location
        }
    }

    private func extractPotentialFolderMentions(from text: String) -> [CandidateMatch] {
        let patterns = [
            #"\b([A-Za-z0-9][A-Za-z0-9_\-]{1,40})\s+folder\b"#,
            #"\bfolder\s+([A-Za-z0-9][A-Za-z0-9_\-]{1,40})\b"#
        ]

        var matches: [CandidateMatch] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let regexMatches = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
            for match in regexMatches {
                guard let range = Range(match.range(at: 1), in: text) else { continue }
                let folderName = collapseWhitespace(in: normalizeName(String(text[range])))
                guard isLikelyFolderName(folderName) else { continue }
                matches.append(CandidateMatch(value: folderName, range: match.range(at: 1)))
            }
        }

        return matches.sorted { $0.range.location < $1.range.location }
    }

    private func extractLatestFileName(fromJSONFileSection fileSection: String) -> String? {
        let objectPattern = #""filename"\s*:\s*"([^"\n]{2,180})""#
        if let objectRegex = try? NSRegularExpression(pattern: objectPattern, options: [.caseInsensitive]) {
            let matches = objectRegex.matches(in: fileSection, options: [], range: NSRange(fileSection.startIndex..., in: fileSection))
            if let match = matches.last,
               let range = Range(match.range(at: 1), in: fileSection) {
                let fileName = normalizeName(String(fileSection[range]))
                if isLikelyFileName(fileName) {
                    return fileName
                }
            }
        }

        let simplePattern = #""([^"\n]{2,180}\.[a-zA-Z0-9]{1,12})""#
        if let simpleRegex = try? NSRegularExpression(pattern: simplePattern, options: []) {
            let matches = simpleRegex.matches(in: fileSection, options: [], range: NSRange(fileSection.startIndex..., in: fileSection))
            for match in matches.reversed() {
                guard let range = Range(match.range(at: 1), in: fileSection) else { continue }
                let fileName = normalizeName(String(fileSection[range]))
                if isLikelyFileName(fileName) {
                    return fileName
                }
            }
        }

        return nil
    }

    private func isLikelyFileName(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty, candidate.count <= 180 else { return false }
        let ext = URL(fileURLWithPath: candidate).pathExtension
        return !ext.isEmpty && !candidate.contains("{") && !candidate.contains("}")
    }

    private func isLikelyUnscannedFileName(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyFileName(candidate) else { return false }

        let ext = URL(fileURLWithPath: candidate).pathExtension.lowercased()
        let stem = (candidate as NSString).deletingPathExtension
        let words = stem.split(separator: " ").map { String($0).lowercased() }
        guard !words.isEmpty else { return false }
        guard words.count <= 4 else { return false }
        guard ext.count <= 12 else { return false }

        let blockedWords: Set<String> = [
            "we", "they", "all", "many", "have", "has", "are", "is", "it",
            "this", "that", "these", "those", "perhaps", "maybe", "suggests"
        ]
        if words.contains(where: { blockedWords.contains($0) }) {
            return false
        }

        let hasSpace = stem.contains(" ")
        let hasSignal = stem.contains("_") || stem.contains("-") || stem.rangeOfCharacter(from: .decimalDigits) != nil
        if hasSpace && !hasSignal {
            return false
        }

        return true
    }

    private func isLikelyFolderName(_ value: String) -> Bool {
        let candidate = collapseWhitespace(in: value)
        guard !candidate.isEmpty, candidate.count <= 80 else { return false }
        guard !candidate.contains("{"), !candidate.contains("}") else { return false }
        guard !candidate.contains(":"), !candidate.contains("<"), !candidate.contains(">"), !candidate.contains("=") else { return false }

        let lowercased = candidate.lowercased()
        guard !lowercased.contains("file"), !lowercased.contains("reasoning") else { return false }
        guard !lowercased.contains("preferred categories"),
              !lowercased.contains("top-level"),
              !lowercased.contains("top level"),
              !lowercased.contains("limit"),
              !lowercased.contains("json"),
              !lowercased.contains("response format"),
              !lowercased.contains("instructions") else {
            return false
        }

        let ext = URL(fileURLWithPath: candidate).pathExtension
        return ext.isEmpty
    }

    private func collapseWhitespace(in text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeInsight(
        text: String,
        category: AIInsight.Category,
        filePath: String? = nil,
        stableSeed: String? = nil
    ) -> AIInsight? {
        let cleaned = collapseWhitespace(in: text)
        guard cleaned.count >= 8 else { return nil }
        guard !isLowSignalInsightText(cleaned, category: category) else { return nil }
        return AIInsight(text: cleaned, category: category, filePath: filePath, stableSeed: stableSeed)
    }

    private func isLowSignalInsightText(_ text: String, category: AIInsight.Category) -> Bool {
        let lowercased = text.lowercased()
        let blockedSubstrings = [
            "not be moved",
            "not be renamed",
            "not be modified",
            "strictly excluded",
            "preferred categories",
            "top-level folders",
            "top level folders",
            "max top-level",
            "max top level",
            "folder_assignments",
            "response format",
            "valid json",
            "json schema",
            "system prompt",
            "user instructions",
            "analyzing (json"
        ]

        if blockedSubstrings.contains(where: { lowercased.contains($0) }) {
            return true
        }
        if lowercased.contains("perhaps ") || lowercased.contains(" maybe ") {
            return true
        }
        if lowercased.hasPrefix("analyzing category") {
            return true
        }
        if category == .file {
            if lowercased.hasPrefix("analyzing we ") ||
                lowercased.hasPrefix("analyzing they ") ||
                lowercased.hasPrefix("analyzing it ") ||
                lowercased.hasPrefix("analyzing this ") ||
                lowercased.hasPrefix("analyzing that ") {
                return true
            }
        }
        if lowercased.contains("limit:") && (lowercased.contains("<=") || lowercased.contains(">=")) {
            return true
        }
        if category == .general && (lowercased.contains("json") || lowercased.contains("```")) {
            return true
        }
        return false
    }
}
