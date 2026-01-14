//
//  LocalRuleInferenceEngine.swift
//  Sorty
//
//  Lightweight local rule inference engine that learns patterns from user behavior
//  without requiring LLM calls. Uses statistical analysis and pattern matching.
//

import Foundation

/// A lightweight rule inference engine that runs locally without AI
public actor LocalRuleInferenceEngine {
    
    // MARK: - Configuration
    
    /// Minimum number of examples needed to infer a rule
    private let minExamplesForRule: Int = 2
    
    /// Minimum confidence threshold for rule creation
    private let minConfidenceThreshold: Double = 0.6
    
    /// Weight multiplier for recent examples (last 7 days)
    private let recentWeightMultiplier: Double = 2.0
    
    // MARK: - Rule Inference
    
    /// Infer rules from user behavior data
    public func inferRules(from profile: LearningsProfile) async -> [InferredRule] {
        var rules: [InferredRule] = []
        
        // 1. Infer rules from corrections (highest signal - user explicitly moved files)
        let correctionRules = inferRulesFromCorrections(profile.postOrganizationChanges)
        rules.append(contentsOf: correctionRules)
        
        // 2. Infer rules from positive examples (user-accepted organization)
        let positiveRules = inferRulesFromExamples(profile.positiveExamples, action: .accept)
        rules.append(contentsOf: positiveRules)
        
        // 3. Infer rules from rejections (what NOT to do - creates inverse patterns)
        let rejectionRules = inferRulesFromRejections(profile.rejections)
        rules.append(contentsOf: rejectionRules)
        
        // 4. Infer rules from steering prompts (explicit user instructions)
        let steeringRules = inferRulesFromSteeringPrompts(profile.steeringPrompts)
        rules.append(contentsOf: steeringRules)
        
        // 5. Merge similar rules and boost confidence
        rules = mergeAndDeduplicateRules(rules)
        
        // 6. Sort by priority (existing rules come first, then by confidence)
        rules.sort { $0.priority > $1.priority }
        
        return rules
    }
    
    // MARK: - Correction-based Inference
    
    private func inferRulesFromCorrections(_ changes: [DirectoryChange]) -> [InferredRule] {
        var rules: [InferredRule] = []
        
        // Group corrections by destination folder pattern
        var destinationPatterns: [String: [DirectoryChange]] = [:]
        
        for change in changes where change.wasAIOrganized {
            let destFolder = URL(fileURLWithPath: change.newPath).deletingLastPathComponent().path
            destinationPatterns[destFolder, default: []].append(change)
        }
        
        // For each destination with multiple corrections, infer a rule
        for (destFolder, changes) in destinationPatterns where changes.count >= minExamplesForRule {
            // Analyze source file patterns
            let srcFilenames = changes.map { URL(fileURLWithPath: $0.originalPath).lastPathComponent }
            
            // Try to find common patterns
            if let pattern = findCommonPattern(in: srcFilenames) {
                let destFolderName = URL(fileURLWithPath: destFolder).lastPathComponent
                let confidence = calculateConfidence(exampleCount: changes.count, isRecent: areRecent(changes.map { $0.timestamp }))
                
                let rule = InferredRule(
                    id: "local-correction-\(UUID().uuidString.prefix(8))",
                    pattern: pattern.regex,
                    template: "\(destFolder)/{filename}",
                    metadataCues: [],
                    priority: Int(confidence * 100),
                    exampleIds: changes.map { $0.id },
                    explanation: "Files matching '\(pattern.description)' should go to '\(destFolderName)/' (learned from \(changes.count) corrections)",
                    successCount: 0,
                    failureCount: 0,
                    isEnabled: true,
                    lastAppliedAt: nil,
                    supportCount: changes.count
                )
                rules.append(rule)
            }
            
            // Also infer rules based on file extensions
            let extensionRules = inferExtensionBasedRules(from: changes, destFolder: destFolder)
            rules.append(contentsOf: extensionRules)
        }
        
        return rules
    }
    
    private func inferExtensionBasedRules(from changes: [DirectoryChange], destFolder: String) -> [InferredRule] {
        var rules: [InferredRule] = []
        
        // Group by file extension
        var byExtension: [String: [DirectoryChange]] = [:]
        for change in changes {
            let ext = URL(fileURLWithPath: change.newPath).pathExtension.lowercased()
            if !ext.isEmpty {
                byExtension[ext, default: []].append(change)
            }
        }
        
        for (ext, extChanges) in byExtension where extChanges.count >= minExamplesForRule {
            let destFolderName = URL(fileURLWithPath: destFolder).lastPathComponent
            let confidence = calculateConfidence(exampleCount: extChanges.count, isRecent: areRecent(extChanges.map { $0.timestamp }))
            
            let rule = InferredRule(
                id: "local-ext-\(ext)-\(UUID().uuidString.prefix(8))",
                pattern: ".*\\.\(ext)$",
                template: "\(destFolder)/{filename}",
                metadataCues: [],
                priority: Int(confidence * 80), // Slightly lower priority than pattern-based
                exampleIds: extChanges.map { $0.id },
                explanation: ".\(ext.uppercased()) files should go to '\(destFolderName)/' (learned from \(extChanges.count) examples)",
                successCount: 0,
                failureCount: 0,
                isEnabled: true,
                lastAppliedAt: nil,
                supportCount: extChanges.count
            )
            rules.append(rule)
        }
        
        return rules
    }
    
    // MARK: - Positive Example Inference
    
    private func inferRulesFromExamples(_ examples: [LabeledExample], action: ExampleAction) -> [InferredRule] {
        var rules: [InferredRule] = []
        
        // Group by destination folder
        var byDestFolder: [String: [LabeledExample]] = [:]
        for example in examples where example.action == action {
            let destFolder = URL(fileURLWithPath: example.dstPath).deletingLastPathComponent().path
            byDestFolder[destFolder, default: []].append(example)
        }
        
        for (destFolder, folderExamples) in byDestFolder where folderExamples.count >= minExamplesForRule {
            let srcFilenames = folderExamples.map { URL(fileURLWithPath: $0.srcPath).lastPathComponent }
            
            if let pattern = findCommonPattern(in: srcFilenames) {
                let destFolderName = URL(fileURLWithPath: destFolder).lastPathComponent
                let confidence = calculateConfidence(exampleCount: folderExamples.count, isRecent: areRecent(folderExamples.map { $0.timestamp }))
                
                let rule = InferredRule(
                    id: "local-positive-\(UUID().uuidString.prefix(8))",
                    pattern: pattern.regex,
                    template: "\(destFolder)/{filename}",
                    metadataCues: [],
                    priority: Int(confidence * 70), // Lower priority than corrections
                    exampleIds: folderExamples.map { $0.id },
                    explanation: "Files matching '\(pattern.description)' go to '\(destFolderName)/' (learned from \(folderExamples.count) accepted examples)",
                    successCount: 0,
                    failureCount: 0,
                    isEnabled: true,
                    lastAppliedAt: nil,
                    supportCount: folderExamples.count
                )
                rules.append(rule)
            }
        }
        
        return rules
    }
    
    // MARK: - Rejection-based Inference
    
    private func inferRulesFromRejections(_ rejections: [LabeledExample]) -> [InferredRule] {
        // For rejections, we don't create positive rules - instead we could create
        // "avoid" rules or just use this data to reduce confidence in matching patterns
        // For now, we skip rejection-based rules to avoid complexity
        return []
    }
    
    // MARK: - Steering Prompt Inference
    
    private func inferRulesFromSteeringPrompts(_ prompts: [SteeringPrompt]) -> [InferredRule] {
        var rules: [InferredRule] = []
        
        // Parse common patterns from steering prompts
        for prompt in prompts {
            let lowered = prompt.prompt.lowercased()
            
            // Pattern: "put X in Y folder" / "move X to Y"
            if let rule = parseMovementInstruction(prompt.prompt, sessionId: prompt.sessionId) {
                rules.append(rule)
            }
            
            // Pattern: "don't put X in Y" - could be used for negative rules
            // For now, skip negative patterns
            
            // Pattern: "organize by date/type/project"
            if lowered.contains("by date") || lowered.contains("by year") || lowered.contains("by month") {
                let rule = InferredRule(
                    id: "local-steering-date-\(UUID().uuidString.prefix(8))",
                    pattern: ".*",
                    template: "{year}/{month}/{filename}",
                    metadataCues: ["fs:ctime"],
                    priority: 60,
                    exampleIds: [],
                    explanation: "Organize files by date (from user instruction)",
                    successCount: 0,
                    failureCount: 0,
                    isEnabled: true,
                    lastAppliedAt: nil,
                    supportCount: 1
                )
                rules.append(rule)
            }
            
            if lowered.contains("by type") || lowered.contains("by extension") {
                let rule = InferredRule(
                    id: "local-steering-type-\(UUID().uuidString.prefix(8))",
                    pattern: ".*",
                    template: "{category}/{filename}",
                    metadataCues: [],
                    priority: 55,
                    exampleIds: [],
                    explanation: "Organize files by type (from user instruction)",
                    successCount: 0,
                    failureCount: 0,
                    isEnabled: true,
                    lastAppliedAt: nil,
                    supportCount: 1
                )
                rules.append(rule)
            }
        }
        
        return rules
    }
    
    private func parseMovementInstruction(_ instruction: String, sessionId: String?) -> InferredRule? {
        let lowered = instruction.lowercased()
        
        // Try to extract "X to Y" or "X in Y" patterns
        let patterns = [
            "put (\\w+) (?:files? )?(?:in|to|into) ([\\w\\s/]+)",
            "move (\\w+) to ([\\w\\s/]+)",
            "(\\w+) should go (?:in|to) ([\\w\\s/]+)"
        ]
        
        for patternStr in patterns {
            if let regex = try? NSRegularExpression(pattern: patternStr, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)) {
                
                guard match.numberOfRanges >= 3,
                      let fileTypeRange = Range(match.range(at: 1), in: lowered),
                      let folderRange = Range(match.range(at: 2), in: lowered) else {
                    continue
                }
                
                let fileType = String(lowered[fileTypeRange]).trimmingCharacters(in: .whitespaces)
                let folderName = String(lowered[folderRange]).trimmingCharacters(in: .whitespaces)
                
                // Try to map file type to extension or category
                let extensionPattern: String
                if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "jpg", "png", "mp3", "mp4"].contains(fileType) {
                    extensionPattern = ".*\\.\(fileType)$"
                } else if ["documents", "photos", "images", "videos", "music", "audio"].contains(fileType) {
                    // Map to category
                    extensionPattern = ".*" // Will be handled by category matching
                } else {
                    extensionPattern = ".*\(fileType).*"
                }
                
                return InferredRule(
                    id: "local-steering-\(UUID().uuidString.prefix(8))",
                    pattern: extensionPattern,
                    template: "\(folderName)/{filename}",
                    metadataCues: [],
                    priority: 75, // High priority for explicit instructions
                    exampleIds: [],
                    explanation: "\(fileType.capitalized) files should go to '\(folderName)/' (from your instruction)",
                    successCount: 0,
                    failureCount: 0,
                    isEnabled: true,
                    lastAppliedAt: nil,
                    supportCount: 1
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Pattern Detection
    
    private struct DetectedPattern {
        let regex: String
        let description: String
    }
    
    private func findCommonPattern(in filenames: [String]) -> DetectedPattern? {
        guard !filenames.isEmpty else { return nil }
        
        // 1. Check for common prefix
        if let prefix = findLongestCommonPrefix(filenames), prefix.count >= 3 {
            return DetectedPattern(
                regex: "^\(NSRegularExpression.escapedPattern(for: prefix)).*",
                description: "files starting with '\(prefix)'"
            )
        }
        
        // 2. Check for common extension grouping
        let extensions = Set(filenames.map { URL(fileURLWithPath: $0).pathExtension.lowercased() })
        if extensions.count == 1, let ext = extensions.first, !ext.isEmpty {
            return DetectedPattern(
                regex: ".*\\.\(ext)$",
                description: ".\(ext.uppercased()) files"
            )
        }
        
        // 3. Check for date pattern in filenames
        let hasDatePattern = filenames.allSatisfy { name in
            name.range(of: "\\d{4}[-_]?\\d{2}[-_]?\\d{2}", options: .regularExpression) != nil ||
            name.range(of: "IMG_\\d+", options: .regularExpression) != nil ||
            name.range(of: "VID_\\d+", options: .regularExpression) != nil
        }
        if hasDatePattern {
            return DetectedPattern(
                regex: ".*(\\d{4}[-_]?\\d{2}[-_]?\\d{2}|IMG_\\d+|VID_\\d+).*",
                description: "dated/camera files"
            )
        }
        
        // 4. Check for common keywords
        let keywords = extractCommonKeywords(from: filenames)
        if let keyword = keywords.first, keyword.count >= 3 {
            return DetectedPattern(
                regex: ".*\(NSRegularExpression.escapedPattern(for: keyword)).*",
                description: "files containing '\(keyword)'"
            )
        }
        
        return nil
    }
    
    private func findLongestCommonPrefix(_ strings: [String]) -> String? {
        guard let first = strings.first else { return nil }
        
        var prefix = ""
        for (index, _) in first.enumerated() {
            let candidate = String(first.prefix(index + 1))
            if strings.allSatisfy({ $0.hasPrefix(candidate) }) {
                prefix = candidate
            } else {
                break
            }
        }
        
        return prefix.isEmpty ? nil : prefix
    }
    
    private func extractCommonKeywords(from filenames: [String]) -> [String] {
        // Tokenize all filenames and find common words
        let allTokens = filenames.flatMap { filename -> [String] in
            let name = (filename as NSString).deletingPathExtension
            return name.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 }
                .map { $0.lowercased() }
        }
        
        // Count occurrences
        var counts: [String: Int] = [:]
        for token in allTokens {
            counts[token, default: 0] += 1
        }
        
        // Find tokens that appear in majority of files
        let threshold = filenames.count / 2
        return counts.filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .map { $0.key }
    }
    
    // MARK: - Helpers
    
    private func calculateConfidence(exampleCount: Int, isRecent: Bool) -> Double {
        // Base confidence from example count (logarithmic scaling)
        var confidence = min(0.5 + log10(Double(exampleCount + 1)) * 0.3, 0.95)
        
        // Boost for recent examples
        if isRecent {
            confidence = min(confidence * recentWeightMultiplier, 0.98)
        }
        
        return confidence
    }
    
    private func areRecent(_ dates: [Date]) -> Bool {
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        return dates.contains { $0 > sevenDaysAgo }
    }
    
    // MARK: - Rule Merging
    
    private func mergeAndDeduplicateRules(_ rules: [InferredRule]) -> [InferredRule] {
        guard !rules.isEmpty else { return [] }
        
        // Group rules by similar pattern
        var merged: [String: InferredRule] = [:]
        
        for rule in rules {
            // Normalize pattern for comparison
            let key = "\(rule.pattern)|\(rule.template)"
            
            if let existing = merged[key] {
                // Merge: boost priority, combine example IDs, update support count
                let newPriority = min(existing.priority + 10, 100)
                let newSupport = existing.supportCount + rule.supportCount
                
                merged[key] = InferredRule(
                    id: existing.id,
                    pattern: existing.pattern,
                    template: existing.template,
                    metadataCues: existing.metadataCues,
                    priority: newPriority,
                    exampleIds: Array(Set(existing.exampleIds + rule.exampleIds)),
                    explanation: existing.explanation,
                    successCount: existing.successCount + rule.successCount,
                    failureCount: existing.failureCount + rule.failureCount,
                    isEnabled: existing.isEnabled,
                    lastAppliedAt: existing.lastAppliedAt ?? rule.lastAppliedAt,
                    supportCount: newSupport
                )
            } else {
                merged[key] = rule
            }
        }
        
        return Array(merged.values)
    }
}

// MARK: - LearningsManager Integration

extension LearningsManager {
    
    /// Run local rule inference without requiring AI
    public func runLocalRuleInference() async {
        guard var profile = currentProfile else { return }
        
        let engine = LocalRuleInferenceEngine()
        let inferredRules = await engine.inferRules(from: profile)
        
        // Merge with existing rules, preferring existing ones
        var existingRulePatterns = Set(profile.inferredRules.map { "\($0.pattern)|\($0.template)" })
        
        for newRule in inferredRules {
            let key = "\(newRule.pattern)|\(newRule.template)"
            if !existingRulePatterns.contains(key) {
                profile.inferredRules.append(newRule)
                existingRulePatterns.insert(key)
            }
        }
        
        currentProfile = profile
        await forceSave()
        
        LogManager.shared.log("Local rule inference complete: \(inferredRules.count) new rules inferred", category: "Learnings")
    }
    
    /// Trigger automatic rule inference when enough new data is available
    public func checkAndTriggerAutoInference() async {
        guard let profile = currentProfile else { return }
        
        // Check if we have enough new data since last inference
        let lastInferenceDate = UserDefaults.standard.object(forKey: "lastLocalRuleInference") as? Date ?? Date.distantPast
        let hoursSinceLastInference = Date().timeIntervalSince(lastInferenceDate) / 3600
        
        // Run inference if:
        // 1. More than 24 hours since last inference, OR
        // 2. We have 5+ new corrections since last inference
        let recentCorrections = profile.postOrganizationChanges.filter { $0.timestamp > lastInferenceDate }
        
        if hoursSinceLastInference > 24 || recentCorrections.count >= 5 {
            await runLocalRuleInference()
            UserDefaults.standard.set(Date(), forKey: "lastLocalRuleInference")
        }
    }
}
