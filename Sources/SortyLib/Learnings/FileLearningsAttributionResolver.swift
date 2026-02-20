import Foundation

public enum LearningsAttributionScope: String, Sendable {
    case fileRuleMatch
    case folderRuleGuidance
}

public enum LearningsAttributionKind: String, Sendable {
    case learnedRule
    case ruleEvidence
    case honingPreference
}

public struct LearningsAttributionItem: Sendable, Hashable {
    public let kind: LearningsAttributionKind
    public let title: String
    public let detail: String

    public init(kind: LearningsAttributionKind, title: String, detail: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct FileLearningsAttribution: Sendable {
    public let rule: InferredRule?
    public let scope: LearningsAttributionScope?
    public let items: [LearningsAttributionItem]

    public init(rule: InferredRule?, scope: LearningsAttributionScope?, items: [LearningsAttributionItem]) {
        self.rule = rule
        self.scope = scope
        self.items = items
    }

    public var hasContent: Bool {
        !items.isEmpty
    }

    public var learningsItems: [LearningsAttributionItem] {
        items.filter { $0.kind != .honingPreference }
    }

    public var honingItems: [LearningsAttributionItem] {
        items.filter { $0.kind == .honingPreference }
    }

    public static let empty = FileLearningsAttribution(rule: nil, scope: nil, items: [])
}

public enum FileLearningsAttributionResolver {
    public static func resolve(
        file: FileItem,
        suggestion: FolderSuggestion,
        profile: LearningsProfile?
    ) -> FileLearningsAttribution {
        guard let profile,
              let ruleID = resolvedRuleID(for: suggestion) else {
            return .empty
        }

        let rule = profile.inferredRules.first(where: { $0.id == ruleID })
        let scope = attributionScope(for: file, rule: rule)
        var items: [LearningsAttributionItem] = []

        if let rule {
            let confidence = String(describing: rule.confidenceLevel).capitalized
            let ruleTitle = scope == .fileRuleMatch ? "Learned Rule Matched File" : "Learned Rule Guided Folder"
            items.append(
                LearningsAttributionItem(
                    kind: .learnedRule,
                    title: ruleTitle,
                    detail: "\(rule.explanation)\nConfidence: \(confidence) • Support: \(rule.supportCount)"
                )
            )

            if let evidence = normalizedEvidenceText(from: rule) {
                items.append(
                    LearningsAttributionItem(
                        kind: .ruleEvidence,
                        title: "Rule Evidence",
                        detail: evidence
                    )
                )
            }

            let honingSignals = explicitHoningSignals(from: rule)
            items.append(
                contentsOf: honingSignals.map {
                    LearningsAttributionItem(
                        kind: .honingPreference,
                        title: "Honing Preference Used",
                        detail: $0
                    )
                }
            )
        } else {
            items.append(
                LearningsAttributionItem(
                    kind: .learnedRule,
                    title: "Learned Rule ID",
                    detail: ruleID
                )
            )
        }

        return FileLearningsAttribution(rule: rule, scope: scope, items: items)
    }

    private static func resolvedRuleID(for suggestion: FolderSuggestion) -> String? {
        if let directRuleID = normalizedRuleID(suggestion.ruleId) {
            return directRuleID
        }

        for tag in suggestion.semanticTags {
            if tag.lowercased().hasPrefix("rule:") {
                let extracted = String(tag.dropFirst("rule:".count))
                if let semanticRuleID = normalizedRuleID(extracted) {
                    return semanticRuleID
                }
            }
        }

        return nil
    }

    private static func normalizedRuleID(_ rawRuleID: String?) -> String? {
        guard let rawRuleID else { return nil }
        let trimmed = rawRuleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func attributionScope(for file: FileItem, rule: InferredRule?) -> LearningsAttributionScope {
        guard let rule else { return .folderRuleGuidance }
        guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
            return .folderRuleGuidance
        }

        let fileDisplayName = file.displayName
        let filePath = file.path

        let displayNameRange = NSRange(fileDisplayName.startIndex..<fileDisplayName.endIndex, in: fileDisplayName)
        if regex.firstMatch(in: fileDisplayName, options: [], range: displayNameRange) != nil {
            return .fileRuleMatch
        }

        let filePathRange = NSRange(filePath.startIndex..<filePath.endIndex, in: filePath)
        if regex.firstMatch(in: filePath, options: [], range: filePathRange) != nil {
            return .fileRuleMatch
        }

        return .folderRuleGuidance
    }

    private static func normalizedEvidenceText(from rule: InferredRule) -> String? {
        let trimmed = rule.evidenceDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func explicitHoningSignals(from rule: InferredRule) -> [String] {
        let evidenceSources: [String] = [rule.evidenceDescription].compactMap { $0 } + rule.evidenceIds
        var signals: [String] = []
        var seen: Set<String> = []

        for rawEvidence in evidenceSources {
            for segment in rawEvidence.components(separatedBy: CharacterSet(charactersIn: ";\n")) {
                let normalized = normalizedEvidenceSegment(segment)
                guard !normalized.isEmpty else { continue }

                guard let signal = honingSignal(from: normalized) else { continue }

                let key = signal.lowercased()
                if seen.insert(key).inserted {
                    signals.append(signal)
                }
            }
        }

        return signals
    }

    private static func normalizedEvidenceSegment(_ segment: String) -> String {
        segment
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func honingSignal(from segment: String) -> String? {
        let lowercased = segment.lowercased()
        let markers = [
            "preference:",
            "honing:",
            "honing preference:",
            "user preference:",
            "from honing:"
        ]

        for marker in markers {
            if lowercased.hasPrefix(marker) {
                let extracted = segment.dropFirst(marker.count).trimmingCharacters(in: .whitespacesAndNewlines)
                return extracted.isEmpty ? nil : extracted
            }
        }

        return nil
    }
}
