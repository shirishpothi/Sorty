import Foundation

public actor AIInsightExtractor {
    private static let analysisWindowSize = 700

    public init() {}

    public func extractInsight(
        from content: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        guard content.count > 50 else { return nil }

        let analysisWindow = String(content.suffix(Self.analysisWindowSize))

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

    private func extractFileInsight(
        from text: String,
        scannedFilePathLookup: [String: [String]],
        currentDirectoryPath: String?
    ) -> AIInsight? {
        let patterns = [
            #"(?:file|document|processing|analyzing|reading|inspecting)[:\s]+["']?([^"'\n,]{3,80})["']?"#,
            #"(?:"|'|`)([^"'`\n]{3,80}\.[a-zA-Z0-9]{1,8})(?:"|'|`)"#,
            #"(?:name|path)[:\s]+([^\n]{3,120}\.[a-zA-Z0-9]{1,8})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else { continue }
            guard let range = Range(match.range(at: 1), in: text) else { continue }

            let rawName = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedName = normalizeName(rawName)
            guard !normalizedName.isEmpty, normalizedName.count < 120 else { continue }

            let fileName = URL(fileURLWithPath: normalizedName).lastPathComponent
            let filePath = findScannedFilePath(for: fileName, scannedFilePathLookup: scannedFilePathLookup, currentDirectoryPath: currentDirectoryPath)
            return AIInsight(
                text: "Analyzing \(fileName)",
                category: .file,
                filePath: filePath,
                stableSeed: filePath ?? fileName
            )
        }

        return nil
    }

    private func extractFolderInsight(from text: String) -> AIInsight? {
        let patterns = [
            #"(?:folder|directory|destination|move to|into|target folder|category)[:\s]+["']?([^"'\n,/]{2,50})["']?"#,
            #"(?:→|->|=>)\s*["']?([^"'\n,]{2,50})["']?"#,
            #"creating folder[:\s]+["']?([^"'\n,]{2,50})["']?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            guard let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)) else { continue }
            guard let range = Range(match.range(at: 1), in: text) else { continue }

            let folderName = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folderName.isEmpty, folderName.count < 60 else { continue }
            return AIInsight(
                text: "Organizing into \(folderName)",
                category: .folder,
                stableSeed: folderName
            )
        }

        return nil
    }

    private func extractConstraintInsight(from text: String) -> AIInsight? {
        let patterns = [
            #"(?:considering|constraint|rule|preference|must|important)[:\s]+([^\.\n]{10,100})"#,
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
            return AIInsight(text: trimmedConstraint, category: .constraint, stableSeed: trimmedConstraint)
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
            return AIInsight(text: decision, category: .decision, stableSeed: decision)
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
                trimmed.hasPrefix("```")

            guard !isProbablyJSONorCode else { continue }
            return AIInsight(text: trimmed, category: .general, stableSeed: trimmed)
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
}
