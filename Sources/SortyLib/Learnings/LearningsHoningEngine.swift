//
//  LearningsHoningEngine.swift
//  Sorty
//
//  Advanced "Honing" system for deep user profiling.
//  Asking 5-20 questions to refine the mental model of the user.
//  Enhanced with contextual/targeted questions based on user behavior patterns.
//

import Foundation
import Combine

public struct HoningSession: Identifiable, Codable, Sendable {
    public let id: String
    public var questions: [HoningQuestion]
    public var answers: [HoningAnswer]
    public var isComplete: Bool
    public let targetQuestionCount: Int
    public var contextualTopics: [String]
    
    public init(id: String = UUID().uuidString, targetQuestionCount: Int = 5, contextualTopics: [String] = []) {
        self.id = id
        self.questions = []
        self.answers = []
        self.isComplete = false
        self.targetQuestionCount = targetQuestionCount
        self.contextualTopics = contextualTopics
    }
}

/// Contextual topic definitions for targeted questioning
public enum HoningTopic: String, CaseIterable {
    case archivingStrategy = "archiving_strategy"
    case projectOrganization = "project_organization"
    case folderDepthPreference = "folder_depth_preference"
    case dateBasedOrganization = "date_based_organization"
    case fileTypeOrganization = "file_type_organization"
    case duplicateHandling = "duplicate_handling"
    case namingConventions = "naming_conventions"
    case frequentCorrections = "frequent_corrections"
    
    var promptContext: String {
        switch self {
        case .archivingStrategy:
            return """
            The user has been moving files to archive-type folders. Ask about their preferred archival strategy:
            - When to archive vs delete
            - How to organize archives (by year, by project, by type)
            - What triggers archiving (age, completion, size)
            """
        case .projectOrganization:
            return """
            The user organizes files by project. Clarify their project organization philosophy:
            - Project folder naming (client name, project code, date)
            - Internal project structure (phases, asset types, deliverables)
            - Cross-project file handling
            """
        case .folderDepthPreference:
            return """
            The user has many subfolders. Understand their hierarchy preference:
            - Flat vs deep structure trade-offs
            - Maximum folder depth comfort level
            - When to create subfolders vs keep files together
            """
        case .dateBasedOrganization:
            return """
            The user frequently uses date-based organization. Clarify:
            - Date format preference (YYYY-MM-DD, Month Year, etc.)
            - Primary date grouping (year, month, week, day)
            - Date source (creation date, modification date, filename date)
            """
        case .fileTypeOrganization:
            return """
            The user groups files by type/extension. Understand:
            - Category naming (Documents, PDFs, Images, Media)
            - Type-specific handling (RAW photos separate from JPEGs)
            - Mixed-type folder policies
            """
        case .duplicateHandling:
            return """
            Ask about duplicate file handling preferences:
            - Keep newest vs oldest vs largest
            - Duplicate detection criteria (name, content, both)
            - Where to move detected duplicates
            """
        case .namingConventions:
            return """
            Understand file naming preferences:
            - Preferred naming pattern (descriptive, coded, dated)
            - Handling of ugly filenames (IMG_20240101, DSC_1234)
            - Rename vs preserve original names
            """
        case .frequentCorrections:
            return """
            The user frequently corrects AI organization. Ask about what's going wrong:
            - Which types of files are being misplaced
            - What the preferred destination should be
            - Any specific rules the AI should learn
            """
        }
    }
    
    var sampleQuestion: (text: String, options: [String]) {
        switch self {
        case .archivingStrategy:
            return (
                "When a project is complete and you won't need to actively work on it, what should happen to its files?",
                [
                    "Move to an Archive folder organized by year (e.g., Archive/2024/ProjectName)",
                    "Keep in place but rename with 'ARCHIVED_' prefix for visibility",
                    "Compress into a ZIP file and move to cold storage location"
                ]
            )
        case .projectOrganization:
            return (
                "How do you prefer to structure your project folders?",
                [
                    "By client/entity first, then project name (e.g., ClientA/WebsiteRedesign/)",
                    "By project name with embedded metadata (e.g., 2024-Q1_ClientA_WebRedesign/)",
                    "Flat list of project folders with consistent internal structure"
                ]
            )
        case .folderDepthPreference:
            return (
                "What's your ideal folder nesting depth for organized files?",
                [
                    "Flat structure - maximum 2 levels (e.g., Category/file.pdf)",
                    "Moderate depth - 3-4 levels (e.g., Year/Month/Category/file.pdf)",
                    "Deep hierarchy - as many levels as needed for precise categorization"
                ]
            )
        case .dateBasedOrganization:
            return (
                "When organizing files by date, what should be the primary grouping level?",
                [
                    "Year folders with month subfolders (2024/January/files...)",
                    "Year-Month folders without additional nesting (2024-01/files...)",
                    "Daily folders when volume is high, monthly otherwise"
                ]
            )
        case .fileTypeOrganization:
            return (
                "For files that could belong to multiple categories, what takes priority?",
                [
                    "File type/extension (all PDFs together, regardless of content)",
                    "Content/purpose (all invoices together, regardless of format)",
                    "Project context (keep all project files together, mixed types)"
                ]
            )
        case .duplicateHandling:
            return (
                "When duplicate files are detected, which version should be kept?",
                [
                    "Keep the newest version (most recently modified)",
                    "Keep the oldest version (original/first copy)",
                    "Keep the largest file (highest quality/resolution)"
                ]
            )
        case .namingConventions:
            return (
                "How should files with cryptic names (IMG_20240101, DSC_1234) be handled?",
                [
                    "Preserve original names - they contain useful metadata",
                    "Rename to descriptive format if content can be detected",
                    "Add descriptive prefix while keeping original name (Invoice_IMG_20240101)"
                ]
            )
        case .frequentCorrections:
            return (
                "What type of organization decisions do you find yourself correcting most often?",
                [
                    "Files placed in wrong category folders",
                    "Incorrect date-based grouping",
                    "Over-zealous splitting of related files into separate folders"
                ]
            )
        }
    }
}

@MainActor
public class LearningsHoningEngine: ObservableObject {
    @Published public var currentSession: HoningSession?
    @Published public var isGenerating: Bool = false
    @Published public var error: String?
    public var onComplete: (([HoningAnswer]) -> Void)?
    
    public var aiConfig: AIConfig
    
    /// Behavior context for generating targeted questions
    public var behaviorContext: BehaviorAnalysisContext?
    
    private let honingCheckPrompt = """
    You are an expert Psycho-Analyst for Digital Organization Habits.
    Review the user's current answers and profile.
    Do we have enough information to construct a PERFECT optimization model for them?
    
    Reply with JSON:
    {
        "isSufficient": true/false,
        "reasoning": "We still need to know how they handle archiving vs deletion..."
    }
    """
    
    private func buildContextualPrompt(topics: [String], previousContext: String) -> String {
        var prompt = """
        You are a Senior Systems Architect specializing in Information Architecture.
        Generate a deep, multiple-choice question to clarify the user's file organization philosophy.
        
        """
        
        // Add topic-specific guidance
        if !topics.isEmpty {
            prompt += "FOCUS ON THESE SPECIFIC AREAS (based on user's recent behavior):\n"
            for topicName in topics {
                if let topic = HoningTopic(rawValue: topicName) {
                    prompt += "\n### \(topicName.uppercased()):\n\(topic.promptContext)\n"
                }
            }
            prompt += "\n"
        }
        
        // Add behavior context if available
        if let context = behaviorContext {
            prompt += """
            USER BEHAVIOR ANALYSIS:
            - Recent corrections: \(context.recentCorrectionCount) files moved after AI organization
            - Most common destination folders: \(context.topDestinationFolders.joined(separator: ", "))
            - File types frequently organized: \(context.topFileTypes.joined(separator: ", "))
            - Reverts in last 30 days: \(context.recentRevertCount)
            
            Ask questions that address patterns in this behavior.
            
            """
        }
        
        prompt += """
        CRITICAL RULES:
        1. AVOID duplicative questions. Look at previous q/a context.
        2. NEVER use generic options like "Option A", "Option B", "Yes", "No".
        3. Options MUST be descriptive philosophical choices (e.g., "Sort by Date", "Group by Client").
        4. Provide exactly 3 distinct options.
        5. Questions should be SPECIFIC and ACTIONABLE - they should map to concrete organization rules.
        
        OUTPUT JSON:
        {
            "text": "When you finish a project, what is your preferred archival strategy?",
            "options": [
                "Move entire project folder to a dedicated Archive directory by year",
                "Keep in main projects folder but tag as 'Archived'",
                "Delete raw assets but keep final deliverables in a Portfolio folder"
            ]
        }
        """
        
        return prompt
    }
    
    private let questionGenerationPrompt = """
    You are a Senior Systems Architect specializing in Information Architecture.
    Generate a deep, multiple-choice question to clarify the user's file organization philosophy.
    
    FOCUS AREAS:
    - Deletion vs Archiving
    - Depth vs Breadth (Deep folders vs Flat structure)
    - Metadata preference (Date-based vs Content-based)
    - Project Lifecycle (Active -> Archive vs All-Together)
    - File specific handling (RAW photos, Code, Invoices)
    
    CRITICAL RULES:
    1. AVOID duplicative questions. Look at previous q/a context.
    2. NEVER use generic options like "Option A", "Option B", "Yes", "No".
    3. Options MUST be descriptive philosophical choices (e.g., "Sort by Date", "Group by Client").
    4. Provide exactly 3 distinct options.
    
    OUTPUT JSON:
    {
        "text": "When you finish a project, what is your preferred archival strategy?",
        "options": [
            "Move entire project folder to a dedicated Archive directory by year",
            "Keep in main projects folder but tag as 'Archived'",
            "Delete raw assets but keep final deliverables in a Portfolio folder"
        ]
    }
    """
    
    public init(config: AIConfig) {
        self.aiConfig = config
    }
    
    /// Start a new honing session with contextual topics
    public func startSession(questionCount: Int = 5, contextualTopics: [String] = []) async {
        currentSession = HoningSession(targetQuestionCount: questionCount, contextualTopics: contextualTopics)
        await generateNextQuestion()
    }
    
    /// Start a new honing session (legacy - no topics)
    public func startSession(questionCount: Int = 5) async {
        await startSession(questionCount: questionCount, contextualTopics: [])
    }
    
    /// Start a targeted session focusing on specific topics from behavior analysis
    public func startTargetedSession(topics: [String], behaviorContext: BehaviorAnalysisContext? = nil) async {
        self.behaviorContext = behaviorContext
        let questionCount = min(max(topics.count, 3), 7) // 3-7 questions based on topics
        await startSession(questionCount: questionCount, contextualTopics: topics)
    }
    
    /// Submit an answer and proceed
    public func submitAnswer(_ answer: HoningAnswer) async {
        guard var session = currentSession else { return }
        
        session.answers.append(answer)
        currentSession = session
        
        if session.answers.count >= session.targetQuestionCount {
            finishSession()
        } else {
            await generateNextQuestion()
        }
    }
    
    private func generateNextQuestion() async {
        isGenerating = true
        error = nil
        
        guard let session = currentSession else {
            isGenerating = false
            return
        }
        
        // First, try to use a pre-defined question for contextual topics if available
        if let question = getNextContextualQuestion(for: session) {
            currentSession?.questions.append(question)
            isGenerating = false
            return
        }
        
        // Fall back to AI-generated question
        do {
            var genConfig = aiConfig
            genConfig.maxTokens = 1000
            let client = try AIClientFactory.createClient(config: genConfig)
            
            // Build context from previous answers
            var context = "Context so far:\n"
            for answer in session.answers {
                // Find question text for richer context
                if let question = session.questions.first(where: { $0.id == answer.questionId }) {
                    context += "- Q: \(question.text)\n  A: \(answer.selectedOption)\n"
                } else {
                    context += "- Answer: \(answer.selectedOption)\n"
                }
            }
            
            // Use contextual prompt if topics are available
            let systemPrompt: String
            if !session.contextualTopics.isEmpty {
                systemPrompt = buildContextualPrompt(topics: session.contextualTopics, previousContext: context)
            } else {
                systemPrompt = questionGenerationPrompt
            }
            
            let prompt = context + "\n\nGenerate the next critical question."
            let jsonString = try await client.generateText(prompt: prompt, systemPrompt: systemPrompt)
            
            if let data = cleanAndParseJSON(jsonString) {
                struct AIQuestionResponse: Decodable {
                    let text: String
                    let options: [String]
                }
                
                if let response = try? JSONDecoder().decode(AIQuestionResponse.self, from: data) {
                    let question = HoningQuestion(
                        id: UUID().uuidString,
                        text: response.text,
                        options: response.options
                    )
                    
                    // Verify it's not a duplicate
                    if !(currentSession?.questions.contains(where: { $0.text == question.text }) ?? false) {
                        currentSession?.questions.append(question)
                        UserDefaults.standard.set(0, forKey: "HoningRetryCount")
                    } else {
                        // If duplicate, try again up to 3 times
                        let retryCount = UserDefaults.standard.integer(forKey: "HoningRetryCount")
                        if retryCount < 3 {
                            UserDefaults.standard.set(retryCount + 1, forKey: "HoningRetryCount")
                            await generateNextQuestion()
                            return
                        }
                        
                        // Otherwise just finish if we have enough
                        UserDefaults.standard.set(0, forKey: "HoningRetryCount")
                        if (currentSession?.questions.count ?? 0) > 0 {
                            finishSession()
                        }
                    }
                } else {
                    self.error = "Failed to decode question JSON"
                    LogManager.shared.log("JSON Decode Error. Data: \(String(data: data, encoding: .utf8) ?? "nil")", level: .error, category: "HoningEngine")
                }
            } else {
                self.error = "Failed to parse question from AI"
            }
            
        } catch {
            self.error = "Generation failed: \(error.localizedDescription)"
        }
        
        isGenerating = false
    }
    
    /// Get the next pre-defined question based on contextual topics
    private func getNextContextualQuestion(for session: HoningSession) -> HoningQuestion? {
        // Find topics we haven't asked about yet
        let answeredTopics = Set(session.answers.compactMap { answer -> String? in
            // Map answer back to topic based on question text
            for topic in HoningTopic.allCases {
                if session.questions.first(where: { $0.id == answer.questionId })?.text == topic.sampleQuestion.text {
                    return topic.rawValue
                }
            }
            return nil
        })
        
        // Find the next unanswered contextual topic
        for topicName in session.contextualTopics where !answeredTopics.contains(topicName) {
            if let topic = HoningTopic(rawValue: topicName) {
                let sample = topic.sampleQuestion
                
                // Check we haven't already asked this exact question
                if !session.questions.contains(where: { $0.text == sample.text }) {
                    return HoningQuestion(
                        id: UUID().uuidString,
                        text: sample.text,
                        options: sample.options
                    )
                }
            }
        }
        
        return nil
    }
    
    private func finishSession() {
        currentSession?.isComplete = true
        if let answers = currentSession?.answers {
            onComplete?(answers)
        }
    }
    
    private func cleanAndParseJSON(_ input: String) -> Data? {
        var jsonString = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 1. Try to find markdown code blocks
        // Regex to match ```json ... ``` or just ``` ... ```
        // Allowing for optional 'json' tag and dot matches newlines
        let pattern = "```(?:json)?\\s*([\\s\\S]*?)\\s*```"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: jsonString, range: NSRange(jsonString.startIndex..., in: jsonString)),
           let range = Range(match.range(at: 1), in: jsonString) {
            jsonString = String(jsonString[range])
        } else {
            // 2. Fallback: Find first '{' and last '}'
            if let startIndex = jsonString.firstIndex(of: "{"),
               let endIndex = jsonString.lastIndex(of: "}") {
                jsonString = String(jsonString[startIndex...endIndex])
            }
        }
        
        return jsonString.data(using: .utf8)
    }
}

// MARK: - Behavior Analysis Context

/// Context about user behavior patterns for targeted question generation
public struct BehaviorAnalysisContext: Sendable {
    public let recentCorrectionCount: Int
    public let recentRevertCount: Int
    public let topDestinationFolders: [String]
    public let topFileTypes: [String]
    public let frequentPatterns: [String]
    
    public init(
        recentCorrectionCount: Int = 0,
        recentRevertCount: Int = 0,
        topDestinationFolders: [String] = [],
        topFileTypes: [String] = [],
        frequentPatterns: [String] = []
    ) {
        self.recentCorrectionCount = recentCorrectionCount
        self.recentRevertCount = recentRevertCount
        self.topDestinationFolders = topDestinationFolders
        self.topFileTypes = topFileTypes
        self.frequentPatterns = frequentPatterns
    }
}

// MARK: - LearningsManager Extension for Behavior Analysis

extension LearningsManager {
    
    /// Analyze recent user behavior to identify topics that need clarification
    public func analyzeBehaviorForHoning() -> (topics: [String], context: BehaviorAnalysisContext) {
        var topics: [String] = []
        
        guard let profile = currentProfile else {
            return (topics: [], context: BehaviorAnalysisContext())
        }
        
        // Analyze recent corrections (last 30 days)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let recentCorrections = profile.postOrganizationChanges.filter { $0.timestamp > thirtyDaysAgo }
        let recentReverts = profile.historyReverts.filter { $0.timestamp > thirtyDaysAgo }
        
        // Extract patterns from corrections
        var destinationFolders: [String: Int] = [:]
        var fileTypes: [String: Int] = [:]
        
        for correction in recentCorrections {
            // Count destination folders
            let destFolder = URL(fileURLWithPath: correction.newPath).deletingLastPathComponent().lastPathComponent
            destinationFolders[destFolder, default: 0] += 1
            
            // Count file types
            let ext = URL(fileURLWithPath: correction.newPath).pathExtension.lowercased()
            if !ext.isEmpty {
                fileTypes[ext, default: 0] += 1
            }
        }
        
        // Determine topics based on patterns
        let topDests = destinationFolders.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        let topTypes = fileTypes.sorted { $0.value > $1.value }.prefix(5).map { $0.key }
        
        // Check for archive-related patterns
        if topDests.contains(where: { $0.lowercased().contains("archive") || $0.lowercased().contains("old") }) {
            topics.append(HoningTopic.archivingStrategy.rawValue)
        }
        
        // Check for project-related patterns
        if topDests.contains(where: { $0.lowercased().contains("project") || $0.lowercased().contains("client") }) {
            topics.append(HoningTopic.projectOrganization.rawValue)
        }
        
        // Check for date-related patterns
        let hasDateFolders = topDests.contains { folder in
            folder.range(of: "\\d{4}", options: .regularExpression) != nil ||
            ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"].contains(folder.lowercased())
        }
        if hasDateFolders {
            topics.append(HoningTopic.dateBasedOrganization.rawValue)
        }
        
        // Check for type-based organization
        let typeCategories = Set(topTypes.map { FileCategory.from(extension: $0) })
        if typeCategories.count > 1 {
            topics.append(HoningTopic.fileTypeOrganization.rawValue)
        }
        
        // If high correction rate, ask about what's going wrong
        if recentCorrections.count > 10 {
            topics.append(HoningTopic.frequentCorrections.rawValue)
        }
        
        // Check for folder depth issues (many nested paths)
        let avgDepth = recentCorrections.isEmpty ? 0 : recentCorrections.reduce(0.0) { sum, change in
            sum + Double(URL(fileURLWithPath: change.newPath).pathComponents.count)
        } / Double(recentCorrections.count)
        if avgDepth > 5 {
            topics.append(HoningTopic.folderDepthPreference.rawValue)
        }
        
        // Build context
        let context = BehaviorAnalysisContext(
            recentCorrectionCount: recentCorrections.count,
            recentRevertCount: recentReverts.count,
            topDestinationFolders: topDests,
            topFileTypes: topTypes,
            frequentPatterns: topics
        )
        
        // Remove duplicates while preserving order
        topics = topics.orderedDeduplicated()
        
        return (topics: topics, context: context)
    }
    
    /// Enhanced version of generateContextualHoningTopics that includes behavior analysis
    public func generateEnhancedHoningTopics() -> (topics: [String], context: BehaviorAnalysisContext) {
        let basicTopics = generateContextualHoningTopics()
        let (behaviorTopics, context) = analyzeBehaviorForHoning()
        
        // Merge and deduplicate
        var allTopics = basicTopics + behaviorTopics
        allTopics = allTopics.orderedDeduplicated()
        
        return (topics: allTopics, context: context)
    }
}
