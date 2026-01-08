//
//  LearningsAnalyzer.swift
//  Sorty
//
//  Main analyzer that orchestrates rule induction and proposal generation
//

import Foundation
import Combine

/// Main analyzer for "The Learnings" feature
@MainActor
public class LearningsAnalyzer: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var isAnalyzing: Bool = false
    @Published public var progress: Double = 0.0
    @Published public var currentStatus: String = ""
    @Published public var lastResult: LearningsAnalysisResult?
    
    // MARK: - Dependencies
    
    private let ruleInducer = RuleInducer() // Legacy pattern matcher
    private var llmInducer: LLMRuleInducer?
    private let contentAnalyzer = ContentAnalyzer()
    
    public init() {}
    
    // Configure with AI Client for advanced learning
    public func configure(aiClient: AIClientProtocol) {
        self.llmInducer = LLMRuleInducer(aiClient: aiClient)
    }
    
    // MARK: - Public API
    
    /// Analyze using profile data and target paths
    public func analyze(
        profile: LearningsProfile,
        rootPaths: [String],
        examplePaths: [String]
    ) async throws -> LearningsAnalysisResult {
        isAnalyzing = true
        progress = 0.0
        currentStatus = "Starting analysis..."
        
        defer {
            isAnalyzing = false
            currentStatus = ""
        }
        
        // Step 1: LLM Rule Induction (Primary) if available
        currentStatus = "Asking AI to find patterns..."
        progress = 0.1
        
        var rules: [InferredRule] = []
        let exampleFolderURLs = examplePaths.map { URL(fileURLWithPath: $0) }
        
        // Combine manual corrections/rejections/positive examples into training set
        let trainingExamples = profile.corrections + profile.rejections + profile.positiveExamples
        
        if let llm = llmInducer {
            // Enhanced rule induction with steering prompts and guiding instructions
            let aiRules = await llm.induceRules(
                from: trainingExamples,
                exampleFolders: exampleFolderURLs,
                honingAnswers: profile.honingAnswers,
                steeringPrompts: profile.steeringPrompts,
                guidingInstructions: profile.guidingInstructionsHistory
            )
            rules.append(contentsOf: aiRules)
        }
        
        // Fallback/Supplement: Pattern Rule Induction
        if rules.isEmpty {
            currentStatus = "Scanning for regex patterns..."
            let legacyRules = await ruleInducer.induceRules(
                from: trainingExamples,
                exampleFolders: exampleFolderURLs
            )
            rules.append(contentsOf: legacyRules)
        }
        
        progress = 0.3
        
        // Step 2: Scan root paths for files to organize
        currentStatus = "Scanning files..."
        var allFiles: [URL] = []
        
        for rootPath in rootPaths {
            let rootURL = URL(fileURLWithPath: rootPath)
            let files = await scanDirectory(rootURL, sampleSize: 100) // Hardcoded sample size for now or pass in config
            allFiles.append(contentsOf: files)
        }
        
        progress = 0.5
        
        // Step 3: Generate proposals for each file
        currentStatus = "Generating proposals..."
        var mappings: [ProposedMapping] = []
        var conflicts: [MappingConflict] = []
        var destinationCounts: [String: [String]] = [:]  // dst -> [src paths]
        
        guard let primaryRootPath = rootPaths.first else {
            throw LearningsError.emptyRootPaths
        }
        
        for (index, fileURL) in allFiles.enumerated() {
            let mapping = await proposeMapping(for: fileURL, using: rules, rootPath: primaryRootPath)
            mappings.append(mapping)
            
            // Track for conflict detection
            destinationCounts[mapping.proposedDstPath, default: []].append(mapping.srcPath)
            
            progress = 0.5 + (Double(index + 1) / Double(allFiles.count)) * 0.4
        }
        
        // Step 4: Detect conflicts
        for (dst, srcs) in destinationCounts where srcs.count > 1 {
            conflicts.append(MappingConflict(
                srcPaths: srcs,
                proposedDstPath: dst,
                suggestedResolution: .autoSuffix
            ))
        }
        
        progress = 0.95
        
        // Step 5: Build result
        let confidenceSummary = calculateConfidenceSummary(mappings)
        let stagedPlan = buildStagedPlan(mappings: mappings, rules: rules)
        let humanSummary = generateHumanSummary(rules: rules, mappings: mappings)
        
        let result = LearningsAnalysisResult(
            inferredRules: rules,
            proposedMappings: mappings,
            stagedPlan: stagedPlan,
            confidenceSummary: confidenceSummary,
            conflicts: conflicts,
            jobManifestTemplate: "~/Library/Application Support/Sorty/Learnings/Jobs/",
            humanSummary: humanSummary
        )
        
        lastResult = result
        progress = 1.0
        currentStatus = "Analysis complete"
        
        return result
    }
    
    /// Generate proposal for a single file
    public func proposeMapping(
        for fileURL: URL,
        using rules: [InferredRule],
        rootPath: String
    ) async -> ProposedMapping {
        let filename = fileURL.lastPathComponent
        let ext = fileURL.pathExtension
        let category = FileCategory.from(extension: ext)
        
        var bestMatch: (rule: InferredRule, confidence: Double)?
        var alternatives: [AlternativeMapping] = []
        
        // Try each rule in priority order
        for rule in rules {
            if let regex = try? NSRegularExpression(pattern: rule.pattern),
               regex.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)) != nil {
                
                // Calculate confidence based on priority and match quality
                let confidence = Double(rule.priority) / 100.0
                
                if bestMatch == nil || confidence > bestMatch!.confidence {
                    if let prev = bestMatch {
                        // Demote previous best to alternative
                        let altDst = applyTemplate(prev.rule.template, to: fileURL, rootPath: rootPath)
                        alternatives.append(AlternativeMapping(
                            proposedDstPath: altDst,
                            confidence: prev.confidence,
                            explanation: "Alternative using rule: \(prev.rule.explanation)"
                        ))
                    }
                    bestMatch = (rule, confidence)
                } else {
                    // Add as alternative
                    let altDst = applyTemplate(rule.template, to: fileURL, rootPath: rootPath)
                    alternatives.append(AlternativeMapping(
                        proposedDstPath: altDst,
                        confidence: confidence,
                        explanation: "Alternative using rule: \(rule.explanation)"
                    ))
                }
            }
        }
        
        // If no rule matched, use fallback
        let proposedDstPath: String
        let ruleId: String?
        let confidence: Double
        let explanation: String
        
        if let match = bestMatch {
            proposedDstPath = applyTemplate(match.rule.template, to: fileURL, rootPath: rootPath)
            ruleId = match.rule.id
            confidence = min(match.confidence, 0.95)  // Cap at 0.95
            explanation = "Matched rule: \(match.rule.explanation)"
        } else {
            // Fallback: organize by category
            proposedDstPath = "\(rootPath)/\(category.rawValue.capitalized)/\(filename)"
            ruleId = nil
            confidence = 0.3
            explanation = "No matching rule found - using category-based fallback"
        }
        
        return ProposedMapping(
            srcPath: fileURL.path,
            proposedDstPath: proposedDstPath,
            ruleId: ruleId,
            confidence: confidence,
            explanation: explanation,
            alternatives: alternatives
        )
    }
    
    // MARK: - Private Methods
    
    /// Scan directory for files
    private func scanDirectory(_ url: URL, sampleSize: Int) async -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        
        var files: [URL] = []
        
        while let fileURL = enumerator.nextObject() as? URL {
            let isDirectory = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if !isDirectory {
                files.append(fileURL)
                
                // Sample size limit for performance
                if files.count >= sampleSize {
                    break
                }
            }
        }
        
        return files
    }
    
    /// Apply template to generate destination path
    private func applyTemplate(_ template: String, to fileURL: URL, rootPath: String) -> String {
        var result = template
        let filename = fileURL.lastPathComponent
        let ext = fileURL.pathExtension
        let category = FileCategory.from(extension: ext)
        
        // Extract date from filename or use file date
        let date = PatternMatcher.extractDate(from: filename) ?? Date()
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = String(format: "%02d", calendar.component(.month, from: date))
        let day = String(format: "%02d", calendar.component(.day, from: date))
        let dateStr = "\(year)-\(month)-\(day)"
        
        // Replace placeholders
        result = result.replacingOccurrences(of: "{filename}", with: filename)
        result = result.replacingOccurrences(of: "{category}", with: category.rawValue.capitalized)
        result = result.replacingOccurrences(of: "{year}", with: String(year))
        result = result.replacingOccurrences(of: "{month}", with: month)
        result = result.replacingOccurrences(of: "{date}", with: dateStr)
        
        // Prepend root path if template is relative
        if !result.hasPrefix("/") {
            result = rootPath + "/" + result
        }
        
        return result
    }
    
    /// Calculate confidence summary
    private func calculateConfidenceSummary(_ mappings: [ProposedMapping]) -> ConfidenceSummary {
        var high = 0, medium = 0, low = 0
        
        for mapping in mappings {
            switch mapping.confidenceLevel {
            case .high: high += 1
            case .medium: medium += 1
            case .low: low += 1
            }
        }
        
        return ConfidenceSummary(high: high, medium: medium, low: low)
    }
    
    /// Build staged execution plan
    private func buildStagedPlan(mappings: [ProposedMapping], rules: [InferredRule]) -> [StagedPlanStep] {
        guard !mappings.isEmpty else { return [] }
        
        // If many low-confidence mappings, recommend staged apply
        let lowConfidenceCount = mappings.filter { $0.confidenceLevel == .low }.count
        let lowConfidenceRatio = Double(lowConfidenceCount) / Double(mappings.count)
        
        if lowConfidenceRatio > 0.3 {
            // High risk - recommend careful staging
            return [
                StagedPlanStep(
                    stageDescription: "Apply to 5 sample files first for review",
                    folderExamples: Array(mappings.prefix(5).map { $0.srcPath }),
                    estimatedCount: 5,
                    riskLevel: .low
                ),
                StagedPlanStep(
                    stageDescription: "After review, apply to remaining high-confidence files",
                    folderExamples: [],
                    estimatedCount: mappings.filter { $0.confidenceLevel == .high }.count,
                    riskLevel: .medium
                ),
                StagedPlanStep(
                    stageDescription: "Finally, apply to medium/low-confidence files with prompts",
                    folderExamples: [],
                    estimatedCount: mappings.filter { $0.confidenceLevel != .high }.count,
                    riskLevel: .high
                )
            ]
        } else {
            // Lower risk - simpler staging
            return [
                StagedPlanStep(
                    stageDescription: "Apply to all \(mappings.count) files",
                    folderExamples: [],
                    estimatedCount: mappings.count,
                    riskLevel: lowConfidenceRatio > 0.1 ? .medium : .low
                )
            ]
        }
    }
    
    /// Generate human-readable summary
    private func generateHumanSummary(rules: [InferredRule], mappings: [ProposedMapping]) -> [String] {
        var summary: [String] = []
        
        if !rules.isEmpty {
            summary.append("Learned \(rules.count) organization rule\(rules.count == 1 ? "" : "s") from examples")
        }
        
        // Describe top rules
        for rule in rules.prefix(3) {
            summary.append("• \(rule.explanation)")
        }
        
        // Confidence overview
        let confidenceSummary = calculateConfidenceSummary(mappings)
        summary.append("Proposal confidence: \(confidenceSummary.high) high, \(confidenceSummary.medium) medium, \(confidenceSummary.low) low")
        
        return summary
    }
}
