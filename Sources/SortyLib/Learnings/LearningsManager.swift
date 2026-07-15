//
//  LearningsManager.swift
//  Sorty
//
//  Observable manager coordinating all learnings functionality
//  Enhanced with secure storage, consent management, and behavior tracking
//

import Foundation
import CryptoKit
import SwiftUI
import Combine

/// Main manager for "The Learnings" feature
@MainActor
public class LearningsManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var currentProfile: LearningsProfile?
    @Published public var isLoading: Bool = false
    @Published public var error: String?
    @Published public var analysisResult: LearningsAnalysisResult?
    
    // Security & Consent
    @Published public var isLocked: Bool = false
    @Published public var requiresInitialSetup: Bool = false
    @Published public var showingImportPicker: Bool = false
    public let securityManager = SecurityManager.shared
    public let consentManager: LearningsConsentManager
    
    // Learning Controls
    @Published public var learningStrength: Double = 0.5 {
        didSet {
            userDefaults.set(learningStrength, forKey: "learningStrength")
        }
    }
    @Published public var useAIForLearnings: Bool = true {
        didSet {
            userDefaults.set(useAIForLearnings, forKey: "useAIForLearnings")
        }
    }
    @Published public var sessionLearningPaused: Bool = false
    @Published public var modelDirectories: [ReferenceModelDirectory] = []
    private var activeModelDirectoryURLs: [String: URL] = [:]
    @Published public private(set) var learningsModelSelection: LearningsModelSelection?
    @Published public var behaviorPreferences: BehaviorPreferences?

    /// Suggestions for files that should be added to exceptions (e.g., related project files)
    @Published public var pendingExceptionSuggestions: [ExceptionSuggestion] = []

    public struct ExceptionSuggestion: Identifiable {
        public let id = UUID()
        public let message: String
        public let fileNames: [String]
        public let groupName: String
    }
    
    @Published public var dataRetentionDays: Int = 0 {
        didSet {
            userDefaults.set(dataRetentionDays, forKey: "learningDataRetentionDays")
            guard dataRetentionDays != oldValue else { return }
            Task { await applyDataRetentionPolicy() }
        }
    }
    
    // MARK: - Learnings Summary for UI
    
    /// A summary of the learnings state for UI consumption
    public struct LearningsSummary: Sendable {
        /// The overall state of learnings
        public enum State: String, Sendable {
            case noConsent      // User hasn't granted consent
            case locked         // Learnings exist but access is locked
            case paused         // Learning collection is temporarily paused
            case empty          // Consent granted but no data yet
            case building       // Some data, but still learning
            case established    // Rich learnings profile available
        }
        
        /// Profile maturity level for adaptive UX
        public enum Maturity: String, Sendable {
            case new            // < 3 sessions
            case growing        // 3-10 sessions
            case established    // > 10 sessions with rules
        }
        
        public let state: State
        public let maturity: Maturity
        public let sessionCount: Int
        public let activeRuleCount: Int
        public let recentSessionCount: Int // Sessions in last 7 days
        public let hasActiveRules: Bool
        public let statusText: String
        public let shortStatusText: String
        
        /// Whether learnings are actively contributing to organization
        public var isActive: Bool {
            state == .building || state == .established
        }
        
        /// Whether the badge should be visible in the UI
        public var shouldShowBadge: Bool {
            state != .noConsent
        }
        
        /// Whether feedback controls should be enabled
        public var canProvideFeedback: Bool {
            state != .noConsent && state != .locked && state != .paused
        }
    }
    
    /// Computed summary for UI display - updated reactively when profile changes
    public var summary: LearningsSummary {
        computeSummary()
    }
    
    private func computeSummary() -> LearningsSummary {
        // Check consent first
        guard canCaptureLearnings else {
            return LearningsSummary(
                state: .noConsent,
                maturity: .new,
                sessionCount: 0,
                activeRuleCount: 0,
                recentSessionCount: 0,
                hasActiveRules: false,
                statusText: "Learning disabled",
                shortStatusText: "Off"
            )
        }
        
        // Check locked state
        if isLocked && consentManager.hasCompletedInitialSetup {
            return LearningsSummary(
                state: .locked,
                maturity: .new,
                sessionCount: 0,
                activeRuleCount: 0,
                recentSessionCount: 0,
                hasActiveRules: false,
                statusText: "Learnings locked",
                shortStatusText: "Locked"
            )
        }
        
        // Check paused state
        if sessionLearningPaused {
            let profile = currentProfile
            let sessionCount = profile?.sessions.count ?? 0
            let activeRuleCount = profile?.inferredRules.filter { $0.isEnabled && $0.status == .active }.count ?? 0
            let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
            let recentSessionCount = profile?.sessions.filter { ($0.completedAt ?? $0.timestamp) > weekAgo }.count ?? 0
            return LearningsSummary(
                state: .paused,
                maturity: computeMaturity(sessionCount: sessionCount, ruleCount: activeRuleCount),
                sessionCount: sessionCount,
                activeRuleCount: activeRuleCount,
                recentSessionCount: recentSessionCount,
                hasActiveRules: activeRuleCount > 0,
                statusText: activeRuleCount > 0 ? "Learning paused (\(activeRuleCount) active pattern\(activeRuleCount == 1 ? "" : "s"))" : "Learning paused",
                shortStatusText: "Paused"
            )
        }
        
        // Profile-based states
        guard let profile = currentProfile else {
            return LearningsSummary(
                state: .empty,
                maturity: .new,
                sessionCount: 0,
                activeRuleCount: 0,
                recentSessionCount: 0,
                hasActiveRules: false,
                statusText: "Ready to learn",
                shortStatusText: "Ready"
            )
        }
        
        let sessionCount = profile.sessions.count
        let activeRules = profile.inferredRules.filter { $0.isEnabled && $0.status == .active }
        let activeRuleCount = activeRules.count
        
        // Count recent sessions (last 7 days)
        let weekAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let recentSessionCount = profile.sessions.filter { ($0.completedAt ?? $0.timestamp) > weekAgo }.count
        
        let maturity = computeMaturity(sessionCount: sessionCount, ruleCount: activeRuleCount)
        
        // Determine state based on data richness
        let state: LearningsSummary.State
        let statusText: String
        let shortStatusText: String
        
        if sessionCount == 0 {
            state = .empty
            statusText = "Ready to learn from your organization"
            shortStatusText = "Ready"
        } else if activeRuleCount == 0 && sessionCount < 5 {
            state = .building
            let remaining = 5 - sessionCount
            statusText = "Learning... \(remaining) more session\(remaining == 1 ? "" : "s") to build patterns"
            shortStatusText = "Learning"
        } else {
            state = .established
            if activeRuleCount > 0 {
                statusText = "\(activeRuleCount) learned pattern\(activeRuleCount == 1 ? "" : "s") active"
                shortStatusText = "\(activeRuleCount) pattern\(activeRuleCount == 1 ? "" : "s")"
            } else {
                statusText = "\(sessionCount) session\(sessionCount == 1 ? "" : "s") learned"
                shortStatusText = "\(sessionCount) session\(sessionCount == 1 ? "" : "s")"
            }
        }
        
        return LearningsSummary(
            state: state,
            maturity: maturity,
            sessionCount: sessionCount,
            activeRuleCount: activeRuleCount,
            recentSessionCount: recentSessionCount,
            hasActiveRules: activeRuleCount > 0,
            statusText: statusText,
            shortStatusText: shortStatusText
        )
    }
    
    private func computeMaturity(sessionCount: Int, ruleCount: Int) -> LearningsSummary.Maturity {
        if sessionCount < 3 {
            return .new
        } else if sessionCount < 10 || ruleCount == 0 {
            return .growing
        } else {
            return .established
        }
    }
    
    // MARK: - Dependencies
    
    private let userDefaults: UserDefaults
    public let analyzer = LearningsAnalyzer()
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.consentManager = LearningsConsentManager(userDefaults: userDefaults)
        requiresInitialSetup = !consentManager.hasCompletedInitialSetup
        learningStrength = userDefaults.object(forKey: "learningStrength") as? Double ?? 0.5
        dataRetentionDays = userDefaults.integer(forKey: "learningDataRetentionDays")
        useAIForLearnings = userDefaults.object(forKey: "useAIForLearnings") as? Bool ?? true
        loadLearningsModelSelection()
        loadModelDirectories()
    }

    private var isLearningsEnabled: Bool {
        EntitlementRuntime.currentSnapshot.isEnabled(.learnings)
    }

    private var canCaptureLearnings: Bool {
        isLearningsEnabled && consentManager.canCollectData
    }
    
    public func configure(with config: AIConfig) {
        guard isLearningsEnabled else {
            error = nil
            return
        }
        do {
            let client = try AIClientFactory.createClient(config: effectiveAIConfig(from: config))
            analyzer.configure(aiClient: client)
        } catch {
            self.error = "Failed to configure AI: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Security & Authentication
    
    /// Unlock with Touch ID / password (required after initial setup)
    public func unlock() async {
        isLocked = false
        await loadProfile()
    }
    
    public func lock() {
        securityManager.lock()
        isLocked = true
        currentProfile = nil
        analysisResult = nil
    }
    
    /// Complete initial setup - future access will require Touch ID
    public func completeInitialSetup() {
        consentManager.completeInitialSetup()
        requiresInitialSetup = false
    }
    
    // MARK: - Consent Management
    
    /// Grant consent for data collection
    public func grantConsent() async {
        consentManager.grantConsent()
        
        loadProfileIfNeededForCollection()
        if var profile = currentProfile {
            profile.consentGranted = true
            profile.consentDate = Date()
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Withdraw consent
    public func withdrawConsent() async {
        consentManager.withdrawConsent()
        
        if var profile = currentProfile {
            profile.consentGranted = false
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Delete all learning data securely.
    /// - Returns: `true` when data was deleted, `false` when the operation could not run.
    @discardableResult
    public func clearAllData() async -> Bool {
        do {
            try await consentManager.deleteAllData()

            currentProfile = nil
            analysisResult = nil
            behaviorPreferences = nil
            pendingExceptionSuggestions = []
            sessionLearningPaused = false
            showingImportPicker = false
            isLocked = false
            requiresInitialSetup = true
            learningsModelSelection = nil
            stopAllModelDirectoryAccess()
            modelDirectories = []
            learningStrength = 0.5
            useAIForLearnings = true
            dataRetentionDays = 0

            [
                "learningStrength",
                "useAIForLearnings",
                "learningDataRetentionDays",
                Self.learningsModelSelectionKey,
                Self.modelDirectoriesKey,
                "lastLocalRuleInference",
            ].forEach(userDefaults.removeObject(forKey:))

            return true
        } catch {
            self.error = "Failed to clear data: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Secure Profile Storage
    
    private func loadProfile() async {
        isLoading = true
        do {
            if let profile = try LearningsFileManager.load() {
                currentProfile = prepareLoadedProfile(profile)
            } else {
                currentProfile = prepareLoadedProfile(LearningsProfile())
            }
        } catch {
            self.error = "Failed to load profile: \(error.localizedDescription)"
            currentProfile = prepareLoadedProfile(LearningsProfile())
        }
        isLoading = false
    }
    
    /// Load profile synchronously for background collection (without authentication)
    /// This allows data collection to work even when the UI is locked
    public func loadProfileIfNeededForCollection() {
        guard currentProfile == nil else { return }
        
        do {
            if let profile = try LearningsFileManager.load() {
                currentProfile = prepareLoadedProfile(profile)
            } else {
                currentProfile = prepareLoadedProfile(LearningsProfile())
            }
        } catch {
            self.error = "Failed to load profile: \(error.localizedDescription)"
            currentProfile = prepareLoadedProfile(LearningsProfile())
        }
    }
    
    private func saveProfile() async {
        guard let profile = currentProfile else { return }
        
        // Prune before saving to keep file size manageable
        pruneOldData()
        
        do {
            try LearningsFileManager.save(profile: currentProfile ?? profile)
        } catch {
            self.error = "Failed to save profile: \(error.localizedDescription)"
        }
    }

    private func prepareLoadedProfile(_ profile: LearningsProfile) -> LearningsProfile {
        var prepared = migrateLegacySessionsIfNeeded(in: profile)
        pruneOldData(in: &prepared)
        return prepared
    }

    public func upsertOrganizationSession(_ session: OrganizationSession) {
        guard canCaptureLearnings else { return }
        guard !isPathExcludedFromLearning(session.folderPath) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }

        upsertOrganizationSession(&profile, session: session)
        currentProfile = profile
        debouncedSave()
    }

    private func upsertOrganizationSession(_ profile: inout LearningsProfile, session: OrganizationSession) {
        if let index = profile.sessions.firstIndex(where: { $0.id == session.id }) {
            profile.sessions[index] = session
        } else {
            profile.sessions.append(session)
        }
        profile.sessions.sort { lhs, rhs in
            let lhsDate = lhs.completedAt ?? lhs.timestamp
            let rhsDate = rhs.completedAt ?? rhs.timestamp
            return lhsDate > rhsDate
        }
    }

    private func mutateSession(
        in profile: inout LearningsProfile,
        sessionId: String? = nil,
        folderPath: String? = nil,
        timestamp: Date = Date(),
        createIfMissing: Bool = true,
        mutation: (inout OrganizationSession) -> Void
    ) {
        if let sessionId, let index = profile.sessions.firstIndex(where: { $0.id == sessionId }) {
            mutation(&profile.sessions[index])
            return
        }

        if let folderPath, let index = bestMatchingSessionIndex(in: profile.sessions, folderPath: folderPath, timestamp: timestamp) {
            mutation(&profile.sessions[index])
            return
        }

        guard createIfMissing, let folderPath else { return }
        var session = OrganizationSession(timestamp: timestamp, folderPath: folderPath)
        mutation(&session)
        upsertOrganizationSession(&profile, session: session)
    }

    private func bestMatchingSessionIndex(
        in sessions: [OrganizationSession],
        folderPath: String,
        timestamp: Date,
        maxDistance: TimeInterval = 6 * 60 * 60
    ) -> Int? {
        let normalizedFolder = URL(fileURLWithPath: folderPath).standardizedFileURL.path

        return sessions.enumerated()
            .filter { _, session in
                URL(fileURLWithPath: session.folderPath).standardizedFileURL.path == normalizedFolder
            }
            .filter { _, session in
                abs((session.completedAt ?? session.timestamp).timeIntervalSince(timestamp)) <= maxDistance
            }
            .sorted { lhs, rhs in
                let lhsDelta = abs((lhs.element.completedAt ?? lhs.element.timestamp).timeIntervalSince(timestamp))
                let rhsDelta = abs((rhs.element.completedAt ?? rhs.element.timestamp).timeIntervalSince(timestamp))
                return lhsDelta < rhsDelta
            }
            .map(\.offset)
            .first
    }

    private func migrateLegacySessionsIfNeeded(in profile: LearningsProfile) -> LearningsProfile {
        guard profile.sessions.isEmpty else { return profile }

        var migrated = profile
        var sessions: [OrganizationSession] = []

        func upsert(_ session: OrganizationSession) {
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else {
                sessions.append(session)
            }
        }

        func appendEvent(
            folderPath: String,
            timestamp: Date,
            sessionId: String? = nil,
            createIfMissing: Bool = true,
            _ mutation: (inout OrganizationSession) -> Void
        ) {
            if let sessionId, let index = sessions.firstIndex(where: { $0.id == sessionId }) {
                mutation(&sessions[index])
                return
            }

            if let index = bestMatchingSessionIndex(in: sessions, folderPath: folderPath, timestamp: timestamp) {
                mutation(&sessions[index])
                return
            }

            guard createIfMissing else { return }
            var session = OrganizationSession(timestamp: timestamp, folderPath: folderPath)
            mutation(&session)
            upsert(session)
        }

        for cancelled in profile.cancelledOrganizations {
            var session = OrganizationSession(
                timestamp: cancelled.timestamp,
                completedAt: cancelled.timestamp,
                folderPath: cancelled.folderPath,
                planSummary: cancelled.proposedStructureSummary,
                reaction: .cancelled,
                events: [
                    OrganizationSessionEvent(
                        timestamp: cancelled.timestamp,
                        kind: .cancelled,
                        summary: "Cancelled organization during \(cancelled.cancelledAtStage)"
                    )
                ]
            )
            if let instructions = cancelled.instructions, !instructions.isEmpty {
                session.additionalInstructions.append(
                    UserInstruction(
                        timestamp: cancelled.timestamp,
                        instruction: instructions,
                        context: "cancelled",
                        folderPath: cancelled.folderPath,
                        fileCount: cancelled.fileCount,
                        isRegeneration: false
                    )
                )
            }
            upsert(session)
        }

        for regenerated in profile.regeneratedOrganizations {
            let folderPath = regenerated.folderPath
            appendEvent(folderPath: folderPath, timestamp: regenerated.timestamp) { session in
                session.completedAt = max(session.completedAt ?? .distantPast, regenerated.timestamp)
                session.reaction = .regenerated
                if let guiding = regenerated.guidingInstruction, !guiding.isEmpty {
                    session.guidingInstructions.append(
                        UserInstruction(
                            timestamp: regenerated.timestamp,
                            instruction: guiding,
                            context: "regeneration",
                            folderPath: folderPath,
                            isRegeneration: true
                        )
                    )
                }
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: regenerated.timestamp,
                        kind: .regenerated,
                        summary: "Regenerated organization attempt #\(regenerated.regenerationCount)"
                    )
                )
            }
        }

        for change in profile.postOrganizationChanges.sorted(by: { $0.timestamp < $1.timestamp }) {
            let folderPath = sessionFolderPath(for: change)
            appendEvent(folderPath: folderPath, timestamp: change.timestamp, sessionId: change.aiSessionId) { session in
                session.userCorrections.append(change)
                session.reaction = session.wasReverted ? .reverted : .corrected
                session.timeToReaction = minNonNil(session.timeToReaction, change.timestamp.timeIntervalSince(session.timestamp))
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: change.timestamp,
                        kind: .correction,
                        summary: "User moved a file after organization",
                        sourcePath: change.originalPath,
                        destinationPath: change.newPath
                    )
                )
            }
        }

        for revert in profile.historyReverts {
            let folderPath = revert.folderPath ?? ""
            appendEvent(folderPath: folderPath, timestamp: revert.timestamp, createIfMissing: !folderPath.isEmpty) { session in
                session.wasReverted = true
                session.reaction = .reverted
                session.completedAt = max(session.completedAt ?? .distantPast, revert.timestamp)
                session.timeToReaction = minNonNil(session.timeToReaction, revert.timestamp.timeIntervalSince(session.timestamp))
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: revert.timestamp,
                        kind: .reverted,
                        summary: revert.reason ?? "Organization was reverted",
                        metadata: ["entryId": revert.entryId]
                    )
                )
            }
        }

        for prompt in profile.steeringPrompts {
            let folderPath = prompt.folderPath ?? inferredFolderPath(from: prompt.sessionId, sessions: sessions)
            guard let folderPath else { continue }
            appendEvent(folderPath: folderPath, timestamp: prompt.timestamp, sessionId: prompt.sessionId) { session in
                session.steeringPrompts.append(prompt.prompt)
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: prompt.timestamp,
                        kind: .steeringPrompt,
                        summary: prompt.prompt
                    )
                )
            }
        }

        for instruction in profile.additionalInstructionsHistory {
            guard let folderPath = instruction.folderPath else { continue }
            appendEvent(folderPath: folderPath, timestamp: instruction.timestamp) { session in
                session.additionalInstructions.append(instruction)
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: instruction.timestamp,
                        kind: .additionalInstruction,
                        summary: instruction.instruction
                    )
                )
            }
        }

        for instruction in profile.guidingInstructionsHistory {
            guard let folderPath = instruction.folderPath else { continue }
            appendEvent(folderPath: folderPath, timestamp: instruction.timestamp) { session in
                session.guidingInstructions.append(instruction)
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: instruction.timestamp,
                        kind: .guidingInstruction,
                        summary: instruction.instruction
                    )
                )
            }
        }

        for event in profile.renameFeedbackHistory {
            guard let folderPath = event.folderPath else { continue }
            appendEvent(folderPath: folderPath, timestamp: event.timestamp) { session in
                session.renameFeedback.append(event)
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: event.timestamp,
                        kind: .renameFeedback,
                        summary: "Rename feedback for \(event.originalName)"
                    )
                )
            }
        }

        for example in profile.positiveExamples.sorted(by: { $0.timestamp < $1.timestamp }) {
            let folderPath = sessionFolderPath(for: example)
            appendEvent(folderPath: folderPath, timestamp: example.timestamp) { session in
                session.completedAt = max(session.completedAt ?? .distantPast, example.timestamp)
                session.reaction = session.userCorrections.isEmpty && !session.wasReverted ? .accepted : session.reaction
                session.filesMoved.append(
                    OrganizationSessionMovedFile(
                        sourcePath: example.srcPath,
                        destinationPath: example.dstPath
                    )
                )
            }
        }

        for example in profile.corrections.sorted(by: { $0.timestamp < $1.timestamp }) {
            let folderPath = sessionFolderPath(for: example)
            appendEvent(folderPath: folderPath, timestamp: example.timestamp) { session in
                session.reaction = session.wasReverted ? .reverted : .corrected
                session.timeToReaction = minNonNil(session.timeToReaction, example.timestamp.timeIntervalSince(session.timestamp))
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: example.timestamp,
                        kind: .correction,
                        summary: "Manual correction learned",
                        sourcePath: example.srcPath,
                        destinationPath: example.dstPath
                    )
                )
            }
        }

        for example in profile.rejections.sorted(by: { $0.timestamp < $1.timestamp }) {
            let folderPath = sessionFolderPath(for: example)
            appendEvent(folderPath: folderPath, timestamp: example.timestamp) { session in
                session.reaction = session.wasReverted ? .reverted : .corrected
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: example.timestamp,
                        kind: .rejection,
                        summary: "Rejected suggested placement",
                        sourcePath: example.srcPath,
                        destinationPath: example.dstPath
                    )
                )
            }
        }

        sessions.sort { ($0.completedAt ?? $0.timestamp) > ($1.completedAt ?? $1.timestamp) }
        migrated.sessions = sessions
        return migrated
    }

    private func inferredFolderPath(from sessionId: String?, sessions: [OrganizationSession]) -> String? {
        guard let sessionId else { return nil }
        return sessions.first(where: { $0.id == sessionId })?.folderPath
    }

    private func sessionFolderPath(for change: DirectoryChange) -> String {
        let originalFolder = URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().path
        let newFolder = change.newPath.isEmpty ? originalFolder : URL(fileURLWithPath: change.newPath).deletingLastPathComponent().path
        return commonAncestorPath([originalFolder, newFolder]) ?? originalFolder
    }

    private func sessionFolderPath(for example: LabeledExample) -> String {
        let sourceFolder = URL(fileURLWithPath: example.srcPath).deletingLastPathComponent().path
        let destinationFolder = URL(fileURLWithPath: example.dstPath).deletingLastPathComponent().path
        return commonAncestorPath([sourceFolder, destinationFolder]) ?? sourceFolder
    }

    private func commonAncestorPath(_ paths: [String]) -> String? {
        let components = paths
            .map { URL(fileURLWithPath: $0).standardizedFileURL.path.split(separator: "/").map(String.init) }
            .filter { !$0.isEmpty }

        guard let first = components.first else { return nil }
        var prefix: [String] = []

        for index in first.indices {
            let component = first[index]
            guard components.allSatisfy({ $0.indices.contains(index) && $0[index] == component }) else {
                break
            }
            prefix.append(component)
        }

        guard !prefix.isEmpty else { return "/" }
        return "/" + prefix.joined(separator: "/")
    }

    private func minNonNil(_ lhs: TimeInterval?, _ rhs: TimeInterval?) -> TimeInterval? {
        switch (lhs, rhs) {
        case let (left?, right?):
            return min(left, right)
        case let (left?, nil):
            return left
        case let (nil, right?):
            return right
        case (nil, nil):
            return nil
        }
    }

    // MARK: - Behavior Tracking
    
    /// Record additional instructions provided by user
    public func recordAdditionalInstruction(_ instruction: String, for folderPath: String, fileCount: Int? = nil) {
        guard canCaptureLearnings else { return }
        guard !isPathExcludedFromLearning(folderPath) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let userInstruction = UserInstruction(
            instruction: instruction,
            context: "pre_organization",
            folderPath: folderPath,
            fileCount: fileCount,
            isRegeneration: false
        )
        profile.additionalInstructionsHistory.append(userInstruction)
        mutateSession(in: &profile, folderPath: folderPath, timestamp: userInstruction.timestamp) { session in
            session.additionalInstructions.append(userInstruction)
            session.events.append(
                OrganizationSessionEvent(
                    timestamp: userInstruction.timestamp,
                    kind: .additionalInstruction,
                    summary: instruction
                )
            )
        }
        currentProfile = profile
        Task { await saveProfile() }
    }
    
    /// Record guiding instructions for next attempt
    public func recordGuidingInstruction(_ instruction: String, for folderPath: String? = nil, fileCount: Int? = nil) {
        guard canCaptureLearnings else { return }
        if let folderPath, isPathExcludedFromLearning(folderPath) { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let userInstruction = UserInstruction(
            instruction: instruction,
            context: "regeneration",
            folderPath: folderPath,
            fileCount: fileCount,
            isRegeneration: true
        )
        profile.guidingInstructionsHistory.append(userInstruction)
        if let folderPath {
            mutateSession(in: &profile, folderPath: folderPath, timestamp: userInstruction.timestamp) { session in
                session.guidingInstructions.append(userInstruction)
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: userInstruction.timestamp,
                        kind: .guidingInstruction,
                        summary: instruction
                    )
                )
            }
        }
        currentProfile = profile
        debouncedSave()
    }

    /// Record a cancelled organization session with rich context for learning
    public func recordCancelledOrganization(
        folderPath: String,
        fileCount: Int,
        proposedFolderCount: Int,
        instructions: String? = nil,
        stage: String,
        proposedFolderNames: [String]? = nil,
        proposedStructureSummary: String? = nil,
        fileExtensionCounts: [String: Int]? = nil,
        regenerationCount: Int = 0,
        regenerationInstructions: [String]? = nil,
        aiModel: String? = nil
    ) {
        guard canCaptureLearnings else { return }
        guard !isPathExcludedFromLearning(folderPath) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let cancelled = CancelledOrganization(
            folderPath: folderPath,
            fileCount: fileCount,
            proposedFolderCount: proposedFolderCount,
            instructions: instructions,
            cancelledAtStage: stage,
            proposedFolderNames: proposedFolderNames,
            proposedStructureSummary: proposedStructureSummary,
            fileExtensionCounts: fileExtensionCounts,
            regenerationCount: regenerationCount,
            regenerationInstructions: regenerationInstructions,
            aiModel: aiModel
        )
        profile.cancelledOrganizations.append(cancelled)
        mutateSession(in: &profile, folderPath: folderPath, timestamp: cancelled.timestamp) { session in
            session.completedAt = cancelled.timestamp
            session.planSummary = proposedStructureSummary ?? session.planSummary
            session.reaction = .cancelled
            session.events.append(
                OrganizationSessionEvent(
                    timestamp: cancelled.timestamp,
                    kind: .cancelled,
                    summary: "Cancelled organization during \(stage)"
                )
            )
        }
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a regenerated organization session
    public func recordRegeneratedOrganization(folderPath: String, previousPlanSummary: String? = nil, guidingInstruction: String? = nil, regenerationCount: Int) {
        guard canCaptureLearnings else { return }
        guard !isPathExcludedFromLearning(folderPath) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let regenerated = RegeneratedOrganization(
            folderPath: folderPath,
            previousPlanSummary: previousPlanSummary,
            guidingInstruction: guidingInstruction,
            regenerationCount: regenerationCount
        )
        profile.regeneratedOrganizations.append(regenerated)
        mutateSession(in: &profile, folderPath: folderPath, timestamp: regenerated.timestamp) { session in
            session.completedAt = regenerated.timestamp
            session.reaction = .regenerated
            session.planSummary = previousPlanSummary ?? session.planSummary
            session.events.append(
                OrganizationSessionEvent(
                    timestamp: regenerated.timestamp,
                    kind: .regenerated,
                    summary: "Regenerated organization attempt #\(regenerationCount)"
                )
            )
        }
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a steering prompt (post-organization feedback)
    public func recordSteeringPrompt(_ prompt: String, folderPath: String?, sessionId: String?) {
        guard canCaptureLearnings else { return }
        if let folderPath, isPathExcludedFromLearning(folderPath) { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let steeringPrompt = SteeringPrompt(
            prompt: prompt,
            folderPath: folderPath,
            sessionId: sessionId
        )
        profile.steeringPrompts.append(steeringPrompt)
        mutateSession(in: &profile, sessionId: sessionId, folderPath: folderPath, timestamp: steeringPrompt.timestamp, createIfMissing: folderPath != nil) { session in
            session.steeringPrompts.append(prompt)
            session.events.append(
                OrganizationSessionEvent(
                    timestamp: steeringPrompt.timestamp,
                    kind: .steeringPrompt,
                    summary: prompt
                )
            )
        }
        currentProfile = profile
        debouncedSave()
    }
    
    /// Record a directory change made after AI organization
    public func recordDirectoryChange(from original: String, to new: String, wasAIOrganized: Bool, sessionId: String? = nil) {
        guard canCaptureLearnings else { return }
        guard !shouldExcludeLearning(paths: [original, new]) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let change = DirectoryChange(
            originalPath: original,
            newPath: new,
            wasAIOrganized: wasAIOrganized,
            aiSessionId: sessionId
        )
        profile.postOrganizationChanges.append(change)
        currentProfile = profile
        debouncedSave()
        
        // Trigger auto-inference check after recording change
        Task { await checkAndTriggerAutoInference() }
    }

    public func recordRenameFeedback(
        originalName: String,
        suggestedName: String?,
        finalName: String?,
        folderPath: String?,
        action: ExampleAction,
        confidence: Double?
    ) {
        guard canCaptureLearnings else { return }
        if let folderPath, isPathExcludedFromLearning(folderPath) { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }

        let event = RenameFeedbackEvent(
            originalName: originalName,
            suggestedName: suggestedName,
            finalName: finalName,
            folderPath: folderPath,
            action: action,
            confidence: confidence
        )
        profile.renameFeedbackHistory.append(event)
        if let folderPath {
            mutateSession(in: &profile, folderPath: folderPath, timestamp: event.timestamp) { session in
                session.renameFeedback.append(event)
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: event.timestamp,
                        kind: .renameFeedback,
                        summary: "Rename feedback for \(originalName)"
                    )
                )
            }
        }
        currentProfile = profile

        // Feed rename outcomes into the existing example pipeline.
        let folder = folderPath ?? ""
        let src = folder.isEmpty ? originalName : "\(folder)/\(originalName)"
        let destinationName = finalName ?? originalName
        let dst = folder.isEmpty ? destinationName : "\(folder)/\(destinationName)"
        addLabeledExample(srcPath: src, dstPath: dst, action: action)
    }
    
    /// Record a history revert event
    public func recordHistoryRevert(entryId: String, operationCount: Int, folderPath: String? = nil, revertReason: String? = nil) {
        guard canCaptureLearnings else { return }
        if let folderPath, isPathExcludedFromLearning(folderPath) { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let event = RevertEvent(
            entryId: entryId,
            operationCount: operationCount,
            folderPath: folderPath,
            reason: revertReason
        )
        profile.historyReverts.append(event)
        currentProfile = profile
        debouncedSave()
    }
    
    // MARK: - Session Outcome Feedback
    
    /// Outcome feedback for a completed organization session
    public enum SessionOutcome: String, Sendable {
        case useful
        case notUseful
    }
    
    /// Record quick outcome feedback for a session from history view
    public func recordSessionOutcomeFeedback(sessionId: String, outcome: SessionOutcome, folderPath: String? = nil) {
        guard canCaptureLearnings else { return }
        guard !sessionLearningPaused else { return }
        if let folderPath, isPathExcludedFromLearning(folderPath) { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }

        let resolvedSessionID: String
        if profile.sessions.contains(where: { $0.id == sessionId }) {
            resolvedSessionID = sessionId
        } else if let matchedSession = profile.sessions.first(where: { $0.historyEntryId == sessionId }) {
            resolvedSessionID = matchedSession.id
        } else {
            resolvedSessionID = sessionId
        }
        
        mutateSession(in: &profile, sessionId: resolvedSessionID, folderPath: folderPath, createIfMissing: false) { session in
            switch outcome {
            case .useful:
                // Mark as accepted if not already corrected/reverted
                if session.reaction == .inProgress {
                    session.reaction = .accepted
                }
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: Date(),
                        kind: .feedback,
                        summary: "User marked session as useful"
                    )
                )
            case .notUseful:
                session.events.append(
                    OrganizationSessionEvent(
                        timestamp: Date(),
                        kind: .feedback,
                        summary: "User marked session as not useful"
                    )
                )
            }
        }
        
        currentProfile = profile
        debouncedSave()
    }
    
    /// Get the count of active rules applicable to a specific folder
    public func activeRuleCount(forFolder folderPath: String) -> Int {
        guard isLearningsEnabled else { return 0 }
        guard let profile = currentProfile else { return 0 }
        return profile.inferredRules
            .filter { $0.isEnabled && $0.status == .active }
            .filter { ruleMatchesScope(rule: $0, folderPath: folderPath, personaId: nil) }
            .count
    }
    
    /// Record a successfully completed organization run
    public func recordSuccessfulRun(folderPath: String, fileCount: Int, ruleIdsUsed: Set<String>) {
        guard canCaptureLearnings else { return }
        guard !isPathExcludedFromLearning(folderPath) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        // Use the actual file count if 0 was passed
        let count = fileCount > 0 ? fileCount : 0
        
        let job = JobManifest(
            projectName: "Automated Run",
            entries: Array(repeating: JobManifestEntry(originalPath: "", destinationPath: "", status: .success), count: count),
            status: .completed
        )
        profile.jobHistory.append(job)
        
        currentProfile = profile
        debouncedSave()
    }
    
    // MARK: - Inline Learning Moments
    
    /// Generate a post-organization learning moment based on the most uncertain decision
    public func generateInlineLearningMoment(
        from session: OrganizationSession,
        proposedFolders: [String]
    ) -> InlineLearningMoment? {
        guard isLearningsEnabled else { return nil }
        guard !session.filesMoved.isEmpty else { return nil }
        
        let existingFolderNames = Set(session.folderPatterns.map(\.folderName))
        
        // Priority 1: Files moved to newly-created folders (highest uncertainty)
        let movedToNewFolders = session.filesMoved.filter { moved in
            let destFolder = URL(fileURLWithPath: moved.destinationPath).deletingLastPathComponent().lastPathComponent
            return !existingFolderNames.contains(destFolder) && proposedFolders.contains(destFolder)
        }
        
        if let candidate = movedToNewFolders.first {
            let destFolder = URL(fileURLWithPath: candidate.destinationPath).deletingLastPathComponent().lastPathComponent
            let fileExt = URL(fileURLWithPath: candidate.sourcePath).pathExtension.lowercased()
            let fileDesc = fileExt.isEmpty ? candidate.fileName : ".\(fileExt) files"
            
            // Find alternative folders from the session
            let alternativeFolders = session.folderPatterns
                .map(\.folderName)
                .filter { $0 != destFolder }
                .prefix(2)
            
            guard !alternativeFolders.isEmpty else { return nil }
            
            var options = [destFolder] + alternativeFolders
            options.append("Create a different folder")
            
            return InlineLearningMoment(
                sessionId: session.id,
                folderPath: session.folderPath,
                prompt: "Should \(fileDesc) like '\(candidate.fileName)' go in '\(destFolder)' or '\(alternativeFolders.first!)'?",
                options: options,
                kind: .folderPlacement,
                relatedFilePath: candidate.sourcePath
            )
        }
        
        // Priority 2: Files with common extensions moved to unusual locations
        var extensionDestinations: [String: [String]] = [:]
        for moved in session.filesMoved {
            let ext = URL(fileURLWithPath: moved.sourcePath).pathExtension.lowercased()
            guard !ext.isEmpty else { continue }
            let destFolder = URL(fileURLWithPath: moved.destinationPath).deletingLastPathComponent().lastPathComponent
            extensionDestinations[ext, default: []].append(destFolder)
        }
        
        // Find extensions that went to multiple different folders
        for (ext, destinations) in extensionDestinations {
            let uniqueDestinations = Array(Set(destinations))
            guard uniqueDestinations.count >= 2 else { continue }
            
            let options = Array(uniqueDestinations.prefix(3)) + ["Keep them together in one folder"]
            
            return InlineLearningMoment(
                sessionId: session.id,
                folderPath: session.folderPath,
                prompt: ".\(ext) files were sorted into multiple folders. Should all .\(ext) files go together?",
                options: options,
                kind: .fileGrouping
            )
        }
        
        // No meaningful uncertainty — session was straightforward
        return nil
    }
    
    /// Record the user's answer to an inline learning moment
    public func recordInlineLearningMomentAnswer(_ answer: InlineLearningMomentAnswer) async {
        guard canCaptureLearnings else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        profile.inlineLearningMomentAnswers.append(answer)
        
        // Record as a steering prompt if the answer implies a clear preference
        let steeringPrompt = SteeringPrompt(
            prompt: "User preference: \(answer.selectedOption)",
            folderPath: nil,
            sessionId: answer.sessionId
        )
        profile.steeringPrompts.append(steeringPrompt)
        
        currentProfile = profile
        await saveProfile()
    }
    
    // MARK: - Debounced Saving
    
    private var saveTask: Task<Void, Never>?
    private let saveDebounceInterval: UInt64 = 2_000_000_000 // 2 seconds in nanoseconds
    
    /// Debounced save to prevent rapid successive writes
    private func debouncedSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: saveDebounceInterval)
            guard !Task.isCancelled else { return }
            await saveProfile()
        }
    }
    
    /// Force immediate save (for critical operations)
    public func forceSave() async {
        saveTask?.cancel()
        pruneOldData()
        await saveProfile()
    }
    
    /// Caps history arrays at 100 items to prevent bloat
    private func pruneOldData() {
        guard var profile = currentProfile else { return }
        pruneOldData(in: &profile)
        currentProfile = profile
    }

    /// Applies the selected retention period immediately and persists the deletion.
    /// This is also used after loading so expired records are never exposed or reused.
    public func applyDataRetentionPolicy(now: Date = Date()) async {
        guard var profile = currentProfile else { return }
        let previousSnapshot = learningProfileSnapshot(profile)
        pruneOldData(in: &profile, now: now)
        guard learningProfileSnapshot(profile) != previousSnapshot else { return }
        currentProfile = profile
        await saveProfile()
    }

    private func pruneOldData(in profile: inout LearningsProfile, now: Date = Date()) {
        if dataRetentionDays > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -dataRetentionDays, to: now) {
            profile.additionalInstructionsHistory.removeAll { $0.timestamp < cutoff }
            profile.guidingInstructionsHistory.removeAll { $0.timestamp < cutoff }
            profile.steeringPrompts.removeAll { $0.timestamp < cutoff }
            profile.postOrganizationChanges.removeAll { $0.timestamp < cutoff }
            profile.renameFeedbackHistory.removeAll { $0.timestamp < cutoff }
            profile.historyReverts.removeAll { $0.timestamp < cutoff }
            profile.positiveExamples.removeAll { $0.timestamp < cutoff }
            profile.rejections.removeAll { $0.timestamp < cutoff }
            profile.corrections.removeAll { $0.timestamp < cutoff }
            profile.jobHistory.removeAll { $0.timestamp < cutoff }
            profile.cancelledOrganizations.removeAll { $0.timestamp < cutoff }
            profile.regeneratedOrganizations.removeAll { $0.timestamp < cutoff }
            profile.sessions.removeAll { ($0.completedAt ?? $0.timestamp) < cutoff }
            profile.inlineLearningMomentAnswers.removeAll { $0.timestamp < cutoff }

            let retainedEvidenceIDs = Set(profile.positiveExamples.map(\.id))
                .union(profile.rejections.map(\.id))
                .union(profile.corrections.map(\.id))
            profile.inferredRules.removeAll { rule in
                let evidenceIDs = Set(rule.exampleIds).union(rule.evidenceIds)
                return !evidenceIDs.isEmpty && evidenceIDs.isDisjoint(with: retainedEvidenceIDs)
            }
            profile.rejectedRuleCooldowns = profile.rejectedRuleCooldowns.filter { $0.value >= cutoff }
        }

        let cap = 100
        if profile.additionalInstructionsHistory.count > cap {
            profile.additionalInstructionsHistory = Array(profile.additionalInstructionsHistory.suffix(cap))
        }
        if profile.guidingInstructionsHistory.count > cap {
            profile.guidingInstructionsHistory = Array(profile.guidingInstructionsHistory.suffix(cap))
        }
        if profile.steeringPrompts.count > cap {
            profile.steeringPrompts = Array(profile.steeringPrompts.suffix(cap))
        }
        if profile.postOrganizationChanges.count > cap {
            profile.postOrganizationChanges = Array(profile.postOrganizationChanges.suffix(cap))
        }
        if profile.renameFeedbackHistory.count > cap {
            profile.renameFeedbackHistory = Array(profile.renameFeedbackHistory.suffix(cap))
        }
        if profile.historyReverts.count > cap {
            profile.historyReverts = Array(profile.historyReverts.suffix(cap))
        }
        if profile.positiveExamples.count > cap {
            profile.positiveExamples = Array(profile.positiveExamples.suffix(cap))
        }
        if profile.rejections.count > cap {
            profile.rejections = Array(profile.rejections.suffix(cap))
        }
        if profile.corrections.count > cap {
            profile.corrections = Array(profile.corrections.suffix(cap))
        }
        if profile.jobHistory.count > cap {
            profile.jobHistory = Array(profile.jobHistory.suffix(cap))
        }
        if profile.cancelledOrganizations.count > cap {
            profile.cancelledOrganizations = Array(profile.cancelledOrganizations.suffix(cap))
        }
        if profile.regeneratedOrganizations.count > cap {
            profile.regeneratedOrganizations = Array(profile.regeneratedOrganizations.suffix(cap))
        }
        if profile.sessions.count > cap {
            profile.sessions = Array(profile.sessions.prefix(cap))
        }
        if profile.inlineLearningMomentAnswers.count > cap {
            profile.inlineLearningMomentAnswers = Array(profile.inlineLearningMomentAnswers.suffix(cap))
        }
    }
    
    // MARK: - Feedback Loop (Continuous Learning)
    
    /// Record a manual correction (File moved manually after AI organization)
    public func recordCorrection(originalPath: String, newPath: String) {
        guard canCaptureLearnings else { return }
        guard !shouldExcludeLearning(paths: [originalPath, newPath]) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: originalPath,
            dstPath: newPath,
            action: .edit
        )
        profile.corrections.append(example)
        currentProfile = profile
        debouncedSave()
        
        // Trigger auto-inference check after recording correction
        Task { await checkAndTriggerAutoInference() }
    }
    
    /// Record a rejection (File reverted or explicitly rejected)
    public func recordRejection(originalPath: String) {
        guard canCaptureLearnings else { return }
        guard !isPathExcludedFromLearning(originalPath) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: originalPath,
            dstPath: originalPath,
            action: .reject
        )
        profile.rejections.append(example)
        currentProfile = profile
        Task { 
            await saveProfile() 
            await checkAndTriggerAutoInference()
        }
    }
    
    // MARK: - Legacy Project Method Removals
    // Removing createProject, loadProject, saveProject (replaced by saveProfile), listProjects
    
    // MARK: - Example Management
    
    // MARK: - Path Management
    // Removed legacy project folder paths. Learnings now operates globally on user behavior.
    
    /// Add a positive example (User organized correctly)
    public func addPositiveExample(srcPath: String, dstPath: String) {
        addLabeledExample(srcPath: srcPath, dstPath: dstPath, action: .accept)
    }
    
    /// Internal helper to add a labeled example
    public func addLabeledExample(srcPath: String, dstPath: String, action: ExampleAction) {
        guard canCaptureLearnings else { return }
        guard !shouldExcludeLearning(paths: [srcPath, dstPath]) else { return }
        loadProfileIfNeededForCollection()
        guard var profile = currentProfile else { return }
        
        let example = LabeledExample(
            srcPath: srcPath,
            dstPath: dstPath,
            action: action
        )
        
        switch action {
        case .accept:
            profile.positiveExamples.append(example)
        case .reject:
            profile.rejections.append(example)
        case .edit:
            profile.corrections.append(example)
        default:
            break
        }
        
        currentProfile = profile
        Task { 
            await saveProfile()
            // Trigger auto-inference check after adding example
            await checkAndTriggerAutoInference()
        }
    }
    
    // MARK: - Analysis

    private func runAnalysis(rootPaths: [String], examplePaths: [String]) async {
        guard let profile = currentProfile else {
            error = "No profile loaded"
            return
        }

        let sanitizedProfile = filteredLearningProfile(from: profile)
        if learningProfileSnapshot(sanitizedProfile) != learningProfileSnapshot(profile) {
            currentProfile = sanitizedProfile
        }

        error = nil

        let filteredRootPaths = rootPaths.filter { !isPathExcludedFromLearning($0) }.orderedDeduplicated()
        let filteredExamplePaths = examplePaths.filter { !isPathExcludedFromLearning($0) }.orderedDeduplicated()

        do {
            analysisResult = try await analyzer.analyze(
                profile: sanitizedProfile,
                rootPaths: filteredRootPaths,
                examplePaths: filteredExamplePaths
            )

            if let result = analysisResult {
                var updatedProfile = sanitizedProfile
                updatedProfile.inferredRules = mergeInferredRules(existing: sanitizedProfile.inferredRules, new: result.inferredRules)
                currentProfile = updatedProfile
                await saveProfile()
            }
        } catch {
            self.error = "Analysis failed: \(error.localizedDescription)"
        }
    }
    
    /// Run analysis on current profile and paths
    public func analyze(rootPaths: [String], examplePaths: [String]) async {
        guard isLearningsEnabled else { return }
        guard useAIForLearnings else {
            error = "AI analysis is disabled. Enable 'Use AI for analysis' in Learnings settings."
            return
        }
        
        // Use configured model directories as example paths when none are explicitly provided
        let effectiveExamplePaths: [String]
        if examplePaths.isEmpty {
            effectiveExamplePaths = enabledModelDirectoryPaths()
        } else {
            effectiveExamplePaths = examplePaths
        }

        await runAnalysis(rootPaths: rootPaths, examplePaths: effectiveExamplePaths)
    }

    /// Re-synthesize learning insights without requiring scan roots.
    public func synthesizeLearnings() async {
        guard isLearningsEnabled else { return }
        guard useAIForLearnings else {
            error = "AI analysis is disabled. Enable 'Use AI for analysis' in Learnings settings."
            return
        }

        await runAnalysis(rootPaths: [], examplePaths: enabledModelDirectoryPaths())
    }
    
    /// Accept a proposed mapping
    public func acceptMapping(_ mapping: ProposedMapping) {
        addLabeledExample(
            srcPath: mapping.srcPath,
            dstPath: mapping.proposedDstPath,
            action: .accept
        )
    }
    
    /// Reject a proposed mapping
    public func rejectMapping(_ mapping: ProposedMapping) {
        addLabeledExample(
            srcPath: mapping.srcPath,
            dstPath: mapping.srcPath,  // Keep in place
            action: .reject
        )
    }
    
    /// Edit a proposed mapping
    public func editMapping(_ mapping: ProposedMapping, newDstPath: String) {
        addLabeledExample(
            srcPath: mapping.srcPath,
            dstPath: newDstPath,
            action: .edit
        )
    }
    
    // MARK: - Export
    
    /// Export preview to JSON file
    public func exportPreview(to url: URL) async throws {
        guard let result = analysisResult else {
            throw LearningsError.noAnalysisResult
        }
        
        let data = try result.toJSON()
        try data.write(to: url)
    }
    
    /// Export rules to JSON file
    public func exportRules(to url: URL) async throws {
        guard let profile = currentProfile else {
            throw LearningsError.noProject
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let data = try encoder.encode(profile.inferredRules)
        try data.write(to: url)
    }

    /// Export a portable, integrity-checked profile archive.
    @discardableResult
    func exportProfile(to url: URL) throws -> LearningsProfileArchiveSummary {
        let data = try makeProfileArchiveData()
        try data.write(to: url, options: .atomic)
        guard let profile = currentProfile else {
            throw LearningsProfileTransferError.noProfile
        }
        return LearningsProfileArchiveSummary(profile: profile)
    }

    func makeProfileArchiveData(
        appVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        buildVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        exportedAt: Date = Date()
    ) throws -> Data {
        guard let profile = currentProfile else {
            throw LearningsProfileTransferError.noProfile
        }

        let archive = LearningsProfileArchive(
            schemaVersion: LearningsProfileArchive.currentSchemaVersion,
            exportedAt: exportedAt,
            appVersion: appVersion,
            buildVersion: buildVersion,
            profileCreatedAt: profile.createdAt,
            summary: LearningsProfileArchiveSummary(profile: profile),
            settings: LearningsProfileSettingsSnapshot(
                learningStrength: learningStrength,
                usesAIForAnalysis: useAIForLearnings,
                dataRetentionDays: dataRetentionDays,
                modelSelection: learningsModelSelection
            ),
            profileDigestSHA256: try profileDigest(profile),
            profile: profile
        )

        let encoder = Self.profileJSONEncoder()
        return try encoder.encode(archive)
    }
    
    // MARK: - Import
    
    /// Import and merge a portable profile without importing its consent state.
    public func importProfile(from url: URL) async throws -> LearningsProfileImportResult {
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "learnings" || fileExtension == "json" else {
            throw LearningsProfileTransferError.unsupportedFile
        }

        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            throw LearningsProfileTransferError.unsupportedFile
        }
        guard (resourceValues.fileSize ?? 0) <= Self.maximumProfileImportBytes else {
            throw LearningsProfileTransferError.fileTooLarge
        }

        let hasScopedAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasScopedAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try await importProfile(data: data)
    }

    func importProfile(data: Data) async throws -> LearningsProfileImportResult {
        guard data.count <= Self.maximumProfileImportBytes else {
            throw LearningsProfileTransferError.fileTooLarge
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let topLevel = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let archive: LearningsProfileArchive?
        let importedProfile: LearningsProfile
        let wasLegacyProfile: Bool

        if topLevel?["schemaVersion"] != nil {
            do {
                let decodedArchive = try decoder.decode(LearningsProfileArchive.self, from: data)
                try validateArchive(decodedArchive)
                archive = decodedArchive
                importedProfile = decodedArchive.profile
                wasLegacyProfile = false
            } catch let error as LearningsProfileTransferError {
                throw error
            } catch {
                throw LearningsProfileTransferError.inconsistentArchive
            }
        } else {
            do {
                importedProfile = try decoder.decode(LearningsProfile.self, from: data)
                archive = nil
                wasLegacyProfile = true
            } catch {
                throw LearningsProfileTransferError.unsupportedFile
            }
        }

        let importedSummary = LearningsProfileArchiveSummary(profile: importedProfile)
        guard importedSummary.totalRecordCount <= Self.maximumProfileImportRecords else {
            throw LearningsProfileTransferError.tooManyRecords
        }

        let existingProfile = currentProfile ?? LearningsProfile(
            consentGranted: consentManager.hasConsented
        )
        let previousRecordCount = LearningsProfileArchiveSummary(profile: existingProfile).totalRecordCount
        let preparedImport = migrateLegacySessionsIfNeeded(in: importedProfile)
        var mergedProfile = mergeProfiles(existing: existingProfile, imported: preparedImport)

        let restoredSettingCount: Int
        if let settings = archive?.settings {
            try validateSettings(settings)
            applyImportedSettings(settings)
            restoredSettingCount = 4
        } else {
            restoredSettingCount = 0
        }

        let mergedRecordCount = LearningsProfileArchiveSummary(profile: mergedProfile).totalRecordCount
        pruneImportedProfile(&mergedProfile)
        currentProfile = mergedProfile
        await saveProfile()

        let resultingRecordCount = LearningsProfileArchiveSummary(
            profile: currentProfile ?? mergedProfile
        ).totalRecordCount
        return LearningsProfileImportResult(
            importedRecordCount: importedSummary.totalRecordCount,
            previousRecordCount: previousRecordCount,
            resultingRecordCount: resultingRecordCount,
            omittedByRetentionPolicy: max(0, mergedRecordCount - resultingRecordCount),
            restoredSettingCount: restoredSettingCount,
            wasLegacyProfile: wasLegacyProfile
        )
    }

    private static let maximumProfileImportBytes = 25 * 1_024 * 1_024
    private static let maximumProfileImportRecords = 10_000

    private static func profileJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func profileDigest(_ profile: LearningsProfile) throws -> String {
        let data = try Self.profileJSONEncoder().encode(profile)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validateArchive(_ archive: LearningsProfileArchive) throws {
        guard (1...LearningsProfileArchive.currentSchemaVersion).contains(archive.schemaVersion) else {
            throw LearningsProfileTransferError.unsupportedSchema(archive.schemaVersion)
        }
        guard archive.profileCreatedAt == archive.profile.createdAt,
              archive.summary == LearningsProfileArchiveSummary(profile: archive.profile),
              archive.profileDigestSHA256 == (try profileDigest(archive.profile)) else {
            throw LearningsProfileTransferError.inconsistentArchive
        }
        guard archive.summary.totalRecordCount <= Self.maximumProfileImportRecords else {
            throw LearningsProfileTransferError.tooManyRecords
        }
        try validateSettings(archive.settings)
    }

    private func validateSettings(_ settings: LearningsProfileSettingsSnapshot) throws {
        guard settings.learningStrength.isFinite,
              (0...1).contains(settings.learningStrength),
              [0, 30, 90, 365].contains(settings.dataRetentionDays),
              settings.modelSelection?.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != true else {
            throw LearningsProfileTransferError.invalidSettings
        }
    }

    private func applyImportedSettings(_ settings: LearningsProfileSettingsSnapshot) {
        learningStrength = settings.learningStrength
        useAIForLearnings = settings.usesAIForAnalysis
        dataRetentionDays = settings.dataRetentionDays

        if let selection = settings.modelSelection {
            setLearningsModelOverride(provider: selection.provider, model: selection.model)
        } else {
            clearLearningsModelOverride()
        }
    }

    private func mergeProfiles(
        existing: LearningsProfile,
        imported: LearningsProfile
    ) -> LearningsProfile {
        // Mutate a copy of the existing profile so fields introduced by newer app
        // versions remain intact even when an older archive does not know about them.
        var mergedProfile = existing
        var rejectedRuleCooldowns = existing.rejectedRuleCooldowns
        for (ruleID, importedDate) in imported.rejectedRuleCooldowns {
            rejectedRuleCooldowns[ruleID] = max(rejectedRuleCooldowns[ruleID] ?? .distantPast, importedDate)
        }

        mergedProfile.additionalInstructionsHistory = mergedByID(
            existing.additionalInstructionsHistory,
            imported.additionalInstructionsHistory
        ).sorted { $0.timestamp < $1.timestamp }
        mergedProfile.guidingInstructionsHistory = mergedByID(
            existing.guidingInstructionsHistory,
            imported.guidingInstructionsHistory
        ).sorted { $0.timestamp < $1.timestamp }
        mergedProfile.steeringPrompts = mergedByID(existing.steeringPrompts, imported.steeringPrompts)
            .sorted { $0.timestamp < $1.timestamp }
        mergedProfile.postOrganizationChanges = mergedByID(
            existing.postOrganizationChanges,
            imported.postOrganizationChanges
        ).sorted { $0.timestamp < $1.timestamp }
        mergedProfile.renameFeedbackHistory = mergedByID(
            existing.renameFeedbackHistory,
            imported.renameFeedbackHistory
        ).sorted { $0.timestamp < $1.timestamp }
        mergedProfile.historyReverts = mergedByID(existing.historyReverts, imported.historyReverts)
            .sorted { $0.timestamp < $1.timestamp }
        mergedProfile.cancelledOrganizations = mergedByID(
            existing.cancelledOrganizations,
            imported.cancelledOrganizations
        ).sorted { $0.timestamp < $1.timestamp }
        mergedProfile.regeneratedOrganizations = mergedByID(
            existing.regeneratedOrganizations,
            imported.regeneratedOrganizations
        ).sorted { $0.timestamp < $1.timestamp }
        mergedProfile.inferredRules = mergedByID(existing.inferredRules, imported.inferredRules)
        mergedProfile.corrections = mergedByID(existing.corrections, imported.corrections)
            .sorted { $0.timestamp < $1.timestamp }
        mergedProfile.rejections = mergedByID(existing.rejections, imported.rejections)
            .sorted { $0.timestamp < $1.timestamp }
        mergedProfile.positiveExamples = mergedByID(existing.positiveExamples, imported.positiveExamples)
            .sorted { $0.timestamp < $1.timestamp }
        mergedProfile.jobHistory = mergedByID(existing.jobHistory, imported.jobHistory)
            .sorted { $0.timestamp < $1.timestamp }
        mergedProfile.rejectedRuleCooldowns = rejectedRuleCooldowns
        mergedProfile.learningExclusionPatterns = Array(
            Set(existing.learningExclusionPatterns + imported.learningExclusionPatterns)
        ).sorted()
        mergedProfile.sessions = mergedByID(existing.sessions, imported.sessions)
            .sorted { ($0.completedAt ?? $0.timestamp) > ($1.completedAt ?? $1.timestamp) }
        mergedProfile.inlineLearningMomentAnswers = mergedByID(
            existing.inlineLearningMomentAnswers,
            imported.inlineLearningMomentAnswers
        ).sorted { $0.timestamp < $1.timestamp }
        return mergedProfile
    }

    private func pruneImportedProfile(_ profile: inout LearningsProfile, now: Date = Date()) {
        if dataRetentionDays > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -dataRetentionDays, to: now) {
            profile.additionalInstructionsHistory.removeAll { $0.timestamp < cutoff }
            profile.guidingInstructionsHistory.removeAll { $0.timestamp < cutoff }
            profile.steeringPrompts.removeAll { $0.timestamp < cutoff }
            profile.postOrganizationChanges.removeAll { $0.timestamp < cutoff }
            profile.renameFeedbackHistory.removeAll { $0.timestamp < cutoff }
            profile.historyReverts.removeAll { $0.timestamp < cutoff }
            profile.positiveExamples.removeAll { $0.timestamp < cutoff }
            profile.rejections.removeAll { $0.timestamp < cutoff }
            profile.corrections.removeAll { $0.timestamp < cutoff }
            profile.jobHistory.removeAll { $0.timestamp < cutoff }
            profile.cancelledOrganizations.removeAll { $0.timestamp < cutoff }
            profile.regeneratedOrganizations.removeAll { $0.timestamp < cutoff }
            profile.sessions.removeAll { ($0.completedAt ?? $0.timestamp) < cutoff }
            profile.inlineLearningMomentAnswers.removeAll { $0.timestamp < cutoff }

            let retainedEvidenceIDs = Set(profile.positiveExamples.map(\.id))
                .union(profile.rejections.map(\.id))
                .union(profile.corrections.map(\.id))
            profile.inferredRules.removeAll { rule in
                let evidenceIDs = Set(rule.exampleIds).union(rule.evidenceIds)
                return !evidenceIDs.isEmpty && evidenceIDs.isDisjoint(with: retainedEvidenceIDs)
            }
            profile.rejectedRuleCooldowns = profile.rejectedRuleCooldowns.filter { $0.value >= cutoff }
        }

        let cap = 100
        profile.additionalInstructionsHistory = Array(profile.additionalInstructionsHistory.suffix(cap))
        profile.guidingInstructionsHistory = Array(profile.guidingInstructionsHistory.suffix(cap))
        profile.steeringPrompts = Array(profile.steeringPrompts.suffix(cap))
        profile.postOrganizationChanges = Array(profile.postOrganizationChanges.suffix(cap))
        profile.renameFeedbackHistory = Array(profile.renameFeedbackHistory.suffix(cap))
        profile.historyReverts = Array(profile.historyReverts.suffix(cap))
        profile.positiveExamples = Array(profile.positiveExamples.suffix(cap))
        profile.rejections = Array(profile.rejections.suffix(cap))
        profile.corrections = Array(profile.corrections.suffix(cap))
        profile.jobHistory = Array(profile.jobHistory.suffix(cap))
        profile.cancelledOrganizations = Array(profile.cancelledOrganizations.suffix(cap))
        profile.regeneratedOrganizations = Array(profile.regeneratedOrganizations.suffix(cap))
        profile.sessions = Array(profile.sessions.prefix(cap))
        profile.inlineLearningMomentAnswers = Array(profile.inlineLearningMomentAnswers.suffix(cap))
    }

    private func mergedByID<Element: Identifiable>(
        _ existing: [Element],
        _ imported: [Element]
    ) -> [Element] where Element.ID: Hashable {
        var merged = existing
        var indexes = Dictionary(uniqueKeysWithValues: existing.enumerated().map { ($1.id, $0) })

        for element in imported {
            if let index = indexes[element.id] {
                merged[index] = element
            } else {
                indexes[element.id] = merged.count
                merged.append(element)
            }
        }

        return merged
    }
    
    // MARK: - Apply & Rollback
    
    @Published public var applyProgress: Double = 0
    @Published public var isApplying: Bool = false
    @Published public var lastJobId: String?
    
    /// Apply proposed mappings with optional backup
    public func applyMappings(backupDirectory: URL?, onlyHighConfidence: Bool = false) async {
        guard isLearningsEnabled else { return }
        guard var profile = currentProfile, let result = analysisResult else {
            error = "No profile or analysis result"
            return
        }
        
        isApplying = true
        applyProgress = 0
        error = nil
        
        let fm = FileManager.default
        let backupMode: BackupMode = backupDirectory != nil ? .copyToBackupDir : .none
        
        // Filter mappings based on confidence
        let mappingsToApply = result.proposedMappings.filter {
            !onlyHighConfidence || $0.confidenceLevel == .high
        }
        
        var entries: [JobManifestEntry] = []
        var successCount = 0
        var failCount = 0
        
        for (index, mapping) in mappingsToApply.enumerated() {
            do {
                var backupPath: String?
                
                // Create backup if needed
                if let backupDir = backupDirectory {
                    backupPath = backupDir.appendingPathComponent(
                        "\(UUID().uuidString)_\(URL(fileURLWithPath: mapping.srcPath).lastPathComponent)"
                    ).path
                    
                    try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
                    try fm.copyItem(atPath: mapping.srcPath, toPath: backupPath!)
                }
                
                // Create destination directory
                let destDir = URL(fileURLWithPath: mapping.proposedDstPath).deletingLastPathComponent()
                try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
                
                // Move file
                try fm.moveItem(atPath: mapping.srcPath, toPath: mapping.proposedDstPath)
                
                entries.append(JobManifestEntry(
                    originalPath: mapping.srcPath,
                    destinationPath: mapping.proposedDstPath,
                    backupPath: backupPath,
                    status: .success
                ))
                successCount += 1
            } catch {
                entries.append(JobManifestEntry(
                    originalPath: mapping.srcPath,
                    destinationPath: mapping.proposedDstPath,
                    status: .failed
                ))
                failCount += 1
            }
            
            applyProgress = Double(index + 1) / Double(mappingsToApply.count)
        }
        
        // Save job manifest
        let job = JobManifest(
            projectName: "User Profile",
            entries: entries,
            backupMode: backupMode,
            status: .completed
        )
        
        // Append to profile history
        profile.jobHistory.append(job)
        currentProfile = profile
        lastJobId = job.id
        
        await saveProfile()
        
        isApplying = false
        applyProgress = 1.0
        
        if failCount > 0 {
            self.error = "Applied \(successCount) files, \(failCount) failed"
        }
    }
    
    /// Rollback a job by its ID
    public func rollbackJob(jobId: String) async {
        guard var profile = currentProfile else {
            error = "No profile loaded"
            return
        }
        
        guard let job = profile.jobHistory.first(where: { $0.id == jobId }) else {
            error = "Job not found: \(jobId)"
            return
        }
        
        isApplying = true
        applyProgress = 0
        error = nil
        
        let fm = FileManager.default
        var successCount = 0
        var failCount = 0
        
        for (index, entry) in job.entries.enumerated() {
            do {
                if let backupPath = entry.backupPath, fm.fileExists(atPath: backupPath) {
                    // Remove current destination
                    if fm.fileExists(atPath: entry.destinationPath) {
                        try fm.removeItem(atPath: entry.destinationPath)
                    }
                    // Restore from backup
                    try fm.moveItem(atPath: backupPath, toPath: entry.originalPath)
                } else if fm.fileExists(atPath: entry.destinationPath) {
                    // Move back without backup
                    try fm.moveItem(atPath: entry.destinationPath, toPath: entry.originalPath)
                }
                successCount += 1
            } catch {
                failCount += 1
            }
            
            applyProgress = Double(index + 1) / Double(job.entries.count)
        }
        
        // Update job status
        if let jobIndex = profile.jobHistory.firstIndex(where: { $0.id == jobId }) {
            profile.jobHistory[jobIndex].status = .rolledBack
            currentProfile = profile
            await saveProfile()
        }
        
        isApplying = false
        applyProgress = 1.0
        
        if failCount > 0 {
            self.error = "Rolled back \(successCount) files, \(failCount) failed"
        }
    }
    // MARK: - Prompt Context Generation
    
    /// Generates a prompt context string based on the current profile
    /// This is the bridge between learned data and the AI organization engine.
    /// The context is intentionally short and session-centric so the model gets
    /// recent, attributable signals instead of a long undifferentiated dump.
    public func generatePromptContext(forFolder folderPath: String? = nil) -> String {
        guard isLearningsEnabled else { return "" }
        guard let profile = currentProfile, (profile.consentGranted || consentManager.hasConsented) else {
            return ""
        }

        let preparedProfile = prepareLoadedProfile(profile)
        if preparedProfile.sessions.count != profile.sessions.count {
            currentProfile = preparedProfile
        }

        let filteredProfile = filteredLearningProfile(from: preparedProfile)
        if !filteredProfile.consentGranted && !consentManager.hasConsented {
            return ""
        }

        let scopedSessions = filteredProfile.sessions
            .filter { session in
                guard let folderPath else { return true }
                return session.folderPath.hasPrefix(folderPath) || folderPath.hasPrefix(session.folderPath)
            }
            .sorted(by: { ($0.completedAt ?? $0.timestamp) > ($1.completedAt ?? $1.timestamp) })

        var hardRules: [String] = []

        let recentInstructions = (filteredProfile.additionalInstructionsHistory + filteredProfile.guidingInstructionsHistory)
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(4)
            .map { "Recent instruction (\(promptDateString($0.timestamp))): \($0.instruction)" }
        hardRules.append(contentsOf: recentInstructions)

        let activeRules = activeRules(
            from: filteredProfile,
            folderPath: folderPath,
            personaId: nil
        )
            .sorted {
                if $0.successRate == $1.successRate {
                    return $0.supportCount > $1.supportCount
                }
                return $0.successRate > $1.successRate
            }
            .prefix(4)
            .map { rule in
                let successRate = Int(rule.successRate * 100)
                return "Proven rule [rule_id: \(rule.id)] (\(successRate)% success): \(rule.explanation)"
            }
        hardRules.append(contentsOf: activeRules)
        hardRules = Array(hardRules.orderedDeduplicated().prefix(5))

        let recentContext = scopedSessions.prefix(5).map(summarizePromptSession)
        let learnedPatterns = buildPromptPatterns(from: filteredProfile, sessions: Array(scopedSessions.prefix(12)), folderPath: folderPath)

        let sections: [(String, [String])] = [
            ("HARD RULES, USER INSTRUCTIONS, AND PREFERENCES", hardRules),
            ("RECENT SESSION CONTEXT", recentContext),
            ("LEARNED PATTERNS", learnedPatterns)
        ]

        var output: [String] = [
            "LEARNINGS CONTEXT",
            "Use the following user-specific learnings to guide the organization plan. Prioritize explicit preferences first, then reference examples, then recent accepted/corrected sessions, then repeated patterns.",
            "When learnings apply, mirror their destination folder names, hierarchy depth, and filename conventions instead of falling back to generic categories."
        ]

        if let folderPath {
            output.append("Current folder: \(folderPath)")
        }

        for (title, items) in sections where !items.isEmpty {
            output.append("")
            output.append("## \(title)")
            output.append(contentsOf: items.prefix(5).map { "- \($0)" })
        }

        return output.count > 2 ? output.joined(separator: "\n") : ""
    }
    
    // MARK: - Prompt Context Helpers

    private func promptDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func summarizePromptSession(_ session: OrganizationSession) -> String {
        let date = promptDateString(session.completedAt ?? session.timestamp)
        let folderName = URL(fileURLWithPath: session.folderPath).lastPathComponent
        let movedCount = max(session.filesMoved.count, session.appliedRules.count)

        switch session.reaction {
        case .accepted:
            let destinations = session.folderPatterns.prefix(3).map(\.relativePath).joined(separator: ", ")
            if !destinations.isEmpty {
                return "\(date): Accepted run in \(folderName). \(movedCount) files stayed in place, using \(destinations)."
            }
            return "\(date): Accepted run in \(folderName). \(movedCount) files needed no corrections."
        case .corrected:
            let changeSummary = session.userCorrections.prefix(2).map { change in
                let from = URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent
                let to = URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
                return "\(from) -> \(to)"
            }.joined(separator: ", ")
            return "\(date): Corrected run in \(folderName). User changed \(session.userCorrections.count) placements\(changeSummary.isEmpty ? "." : ": \(changeSummary).")"
        case .reverted:
            return "\(date): Reverted run in \(folderName). Be more conservative with this folder."
        case .cancelled:
            return "\(date): Cancelled run in \(folderName). The proposed structure was not accepted."
        case .regenerated:
            return "\(date): Regenerated run in \(folderName). The first plan needed a second attempt."
        case .inProgress:
            return "\(date): Recent run in \(folderName) is still collecting feedback."
        }
    }

    private func buildPromptPatterns(
        from profile: LearningsProfile,
        sessions: [OrganizationSession],
        folderPath: String?
    ) -> [String] {
        var patterns: [String] = []

        let acceptedSessions = sessions.filter(\.acceptedWithoutCorrections)
        let correctedSessions = sessions.filter { $0.reaction == .corrected || !$0.userCorrections.isEmpty }

        var acceptedFolderPatterns: [String: (count: Int, extensions: [String: Int])] = [:]
        for session in acceptedSessions {
            for pattern in session.folderPatterns {
                var entry = acceptedFolderPatterns[pattern.relativePath] ?? (count: 0, extensions: [:])
                entry.count += pattern.fileCount
                for ext in pattern.fileExtensions {
                    entry.extensions[ext, default: 0] += 1
                }
                acceptedFolderPatterns[pattern.relativePath] = entry
            }
        }

        let topAcceptedPatterns = acceptedFolderPatterns
            .sorted { $0.value.count > $1.value.count }
            .prefix(4)
        for (path, payload) in topAcceptedPatterns {
            let topExtensions = payload.extensions
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { key, _ in key.isEmpty ? "files" : ".\(key)" }
                .joined(separator: ", ")
            patterns.append("Accepted structure: \(path) is a good destination for \(topExtensions.isEmpty ? "similar files" : topExtensions).")
        }

        var correctionPatterns: [String: Int] = [:]
        for session in correctedSessions {
            for change in session.userCorrections where change.wasAIOrganized {
                let from = URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent
                let to = URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
                let ext = URL(fileURLWithPath: change.originalPath).pathExtension.lowercased()
                let label = ext.isEmpty
                    ? "Prefer \(to) over \(from) for similar files."
                    : "CORRECTIONS: .\(ext) files were moved from \(from) to \(to)."
                correctionPatterns[label, default: 0] += 1
            }
        }

        patterns.append(contentsOf: correctionPatterns.sorted { $0.value > $1.value }.prefix(4).map(\.key))

        let positiveExamples = profile.positiveExamples
            .filter { example in
                guard let folderPath else { return true }
                return example.dstPath.hasPrefix(folderPath)
            }
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(4)
            .map { example in
                let ext = URL(fileURLWithPath: example.srcPath).pathExtension.lowercased()
                let sourceName = URL(fileURLWithPath: example.srcPath).lastPathComponent
                let destinationName = URL(fileURLWithPath: example.dstPath).lastPathComponent
                let folder = URL(fileURLWithPath: example.dstPath).deletingLastPathComponent().path
                return ext.isEmpty
                    ? "Accepted example: \(sourceName) belonged in \(folder) as \(destinationName)."
                    : "Accepted example: .\(ext) files like \(sourceName) belonged in \(folder) as \(destinationName)."
            }
        patterns.append(contentsOf: positiveExamples)

        let renameExamples = profile.renameFeedbackHistory
            .filter { $0.action == .edit || $0.action == .accept }
            .sorted(by: { $0.timestamp > $1.timestamp })
            .prefix(4)
            .compactMap { event -> String? in
                let learnedName = event.finalName ?? event.suggestedName
                guard let learnedName, learnedName != event.originalName else { return nil }
                return "Filename convention: \(event.originalName) -> \(learnedName) was \(event.action == .edit ? "user-edited" : "accepted"). Use similar naming for matching files."
            }
        patterns.append(contentsOf: renameExamples)

        return Array(patterns.orderedDeduplicated().prefix(8))
    }
    
    private struct LearningsSection {
        let id: String
        let title: String
        let priority: String
        let instruction: String
        let items: [LearningsItem]
    }
    
    private struct LearningsItem {
        let content: String
        var weight: Int = 50
        var confidence: Int? = nil
        var occurrences: Int? = nil
        var recency: String? = nil
        var ruleId: String? = nil
    }
    
    private func recencyWeight(from date: Date, to now: Date) -> Double {
        let daysSince = now.timeIntervalSince(date) / 86400
        if daysSince < 1 { return 1.0 }
        if daysSince < 7 { return 0.8 }
        if daysSince < 30 { return 0.5 }
        if daysSince < 90 { return 0.3 }
        return 0.1
    }
    
    private func recencyLabel(_ date: Date, now: Date) -> String {
        let daysSince = Int(now.timeIntervalSince(date) / 86400)
        if daysSince == 0 { return "today" }
        if daysSince == 1 { return "yesterday" }
        if daysSince < 7 { return "\(daysSince) days ago" }
        if daysSince < 30 { return "\(daysSince / 7) weeks ago" }
        if daysSince < 365 { return "\(daysSince / 30) months ago" }
        return "over a year ago"
    }
    
    private func formatAsXML(sections: [LearningsSection], folderPath: String?) -> String {
        var xml = "<learnings_context>\n"
        xml += "  <preamble>\n"
        xml += "    <instruction>IMPORTANT: The following learnings represent this user's organization preferences, corrections, and patterns. "
        xml += "Pay close attention to rejection patterns and corrections - these indicate what NOT to do. "
        xml += "Items with higher weights (closer to 100) are more important. Recent items should be prioritized.</instruction>\n"
        if let folder = folderPath {
            let folderName = URL(fileURLWithPath: folder).lastPathComponent
            xml += "    <context folder=\"\(escapeXML(folderName))\">\(escapeXML(folder))</context>\n"
        }
        xml += "  </preamble>\n\n"
        
        for section in sections {
            xml += "  <section id=\"\(section.id)\" priority=\"\(section.priority)\">\n"
            xml += "    <title>\(escapeXML(section.title))</title>\n"
            xml += "    <instruction>\(escapeXML(section.instruction))</instruction>\n"
            if !section.items.isEmpty {
                xml += "    <items>\n"
                for item in section.items {
                    var attrs = "weight=\"\(item.weight)\""
                    if let conf = item.confidence { attrs += " confidence=\"\(conf)%\"" }
                    if let occ = item.occurrences { attrs += " occurrences=\"\(occ)\"" }
                    if let rec = item.recency { attrs += " recency=\"\(rec)\"" }
                    if let rid = item.ruleId { attrs += " rule_id=\"\(escapeXML(rid))\"" }
                    xml += "      <item \(attrs)>\(escapeXML(item.content))</item>\n"
                }
                xml += "    </items>\n"
            }
            xml += "  </section>\n\n"
        }
        
        xml += "</learnings_context>"
        return xml
    }
    
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
    
    // MARK: - Impact Metrics
    
    /// Compute a summary of how learnings have affected organization results
    public func computeImpactSummary(lastNRuns: Int = 10) -> LearningsImpactSummary? {
        guard let profile = currentProfile else { return nil }
        
        let totalRuns = profile.jobHistory.count
        let completedRuns = profile.jobHistory.filter { $0.status == .completed }.count
        
        let filesRoutedByLearnings = profile.inferredRules.reduce(0) { $0 + $1.successCount }
        let correctionsAfterAI = profile.postOrganizationChanges.filter { $0.wasAIOrganized }.count
        
        let reverts = profile.historyReverts.count
        let cancelled = profile.cancelledOrganizations.count
        let regenerated = profile.regeneratedOrganizations.count

        let accepted = max(0, completedRuns - reverts)
        let rejected = min(completedRuns, reverts)
        
        let runsWithLearnings = completedRuns
        
        return LearningsImpactSummary(
            runsWithLearnings: runsWithLearnings,
            totalRuns: totalRuns,
            filesRoutedByLearnings: filesRoutedByLearnings,
            correctionsAfterAI: correctionsAfterAI,
            reverts: reverts,
            acceptedOrganizations: accepted,
            rejectedOrganizations: rejected,
            cancelledOrganizations: cancelled,
            regeneratedOrganizations: regenerated
        )
    }
    
    // MARK: - Rule Management
    
    /// Enable or disable a specific inferred rule
    public func setRuleEnabled(ruleId: String, enabled: Bool) async {
        guard isLearningsEnabled else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].isEnabled = enabled
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Record a rule success (applied and no correction followed)
    public func recordRuleSuccess(ruleId: String) {
        guard canCaptureLearnings else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].successCount += 1
            profile.inferredRules[index].lastAppliedAt = Date()
            currentProfile = profile
            debouncedSave()
        }
    }
    
    /// Record a rule failure (applied but user corrected)
    public func recordRuleFailure(ruleId: String) {
        guard canCaptureLearnings else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].failureCount += 1
            
            // Auto-disable rules with high failure rate
            let rule = profile.inferredRules[index]
            if rule.failureRate > 0.3 && (rule.successCount + rule.failureCount) >= 5 {
                profile.inferredRules[index].isEnabled = false
                DebugLogger.log("Auto-disabled rule '\(rule.explanation)' due to high failure rate")
            }
            
            currentProfile = profile
            debouncedSave()
        }
    }
    
    /// Get active rules filtered by learning strength and optionally by scope
    public func getActiveRules(forFolder folderPath: String? = nil, forPersona personaId: UUID? = nil) -> [InferredRule] {
        guard isLearningsEnabled else { return [] }
        guard let profile = currentProfile else { return [] }

        return activeRules(from: profile, folderPath: folderPath, personaId: personaId)
    }

    private func activeRules(
        from profile: LearningsProfile,
        folderPath: String?,
        personaId: UUID?
    ) -> [InferredRule] {
        let eligibleRules = profile.inferredRules
            .filter { $0.isEnabled && $0.status == .active }
            .filter { ruleMatchesScope(rule: $0, folderPath: folderPath, personaId: personaId) }
            .sorted { $0.priority > $1.priority }

        guard !eligibleRules.isEmpty else { return [] }

        // Keep one strongest rule at the minimum setting so Learnings remains useful,
        // then progressively admit more rules as the user increases the strength.
        let maxRules = min(
            eligibleRules.count,
            Int(Double(eligibleRules.count) * learningStrength) + 1
        )
        return Array(eligibleRules.prefix(maxRules))
    }
    
    // MARK: - Rule Suggestion Inbox
    
    /// Get pending approval rules
    public func getPendingRules() -> [InferredRule] {
        guard isLearningsEnabled else { return [] }
        guard let profile = currentProfile else { return [] }
        return profile.inferredRules.filter { $0.status == .pendingApproval }
    }
    
    /// Approve a pending rule
    public func approveRule(ruleId: String) async {
        guard isLearningsEnabled else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].status = .active
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Reject a pending rule with cooling-off period
    public func rejectRule(ruleId: String, cooldownDays: Int = 30) async {
        guard isLearningsEnabled else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].status = .rejected
            profile.inferredRules[index].rejectedAt = Date()
            profile.inferredRules[index].cooldownUntil = Date().addingTimeInterval(Double(cooldownDays) * 86400)
            profile.inferredRules[index].isEnabled = false
            
            // Track cooldown
            profile.rejectedRuleCooldowns[ruleId] = Date().addingTimeInterval(Double(cooldownDays) * 86400)
            
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Edit a pending rule's explanation and approve it
    public func editAndApproveRule(ruleId: String, newExplanation: String? = nil, newPriority: Int? = nil, newScope: RuleScope? = nil) async {
        guard isLearningsEnabled else { return }
        guard var profile = currentProfile else { return }
        
        if let index = profile.inferredRules.firstIndex(where: { $0.id == ruleId }) {
            profile.inferredRules[index].status = .active
            if let explanation = newExplanation {
                let rule = profile.inferredRules[index]
                let updatedRule = InferredRule(
                    id: rule.id,
                    pattern: rule.pattern,
                    template: rule.template,
                    metadataCues: rule.metadataCues,
                    priority: newPriority ?? rule.priority,
                    exampleIds: rule.exampleIds,
                    explanation: explanation,
                    successCount: rule.successCount,
                    failureCount: rule.failureCount,
                    isEnabled: true,
                    lastAppliedAt: rule.lastAppliedAt,
                    supportCount: rule.supportCount,
                    initialConfidence: rule.initialConfidence,
                    scope: newScope ?? rule.scope,
                    status: .active,
                    evidenceIds: rule.evidenceIds,
                    evidenceDescription: rule.evidenceDescription,
                    rejectedAt: rule.rejectedAt,
                    cooldownUntil: rule.cooldownUntil
                )
                profile.inferredRules[index] = updatedRule
            } else {
                if let priority = newPriority {
                    profile.inferredRules[index].priority = priority
                }
                if let scope = newScope {
                    profile.inferredRules[index].scope = scope
                }
            }
            currentProfile = profile
            await saveProfile()
        }
    }
    
    /// Check if a rule pattern is in cooldown (was recently rejected)
    public func isRuleInCooldown(pattern: String) -> Bool {
        guard isLearningsEnabled else { return false }
        guard let profile = currentProfile else { return false }
        let now = Date()
        
        return profile.inferredRules.contains { rule in
            rule.pattern == pattern && rule.status == .rejected &&
            (rule.cooldownUntil ?? .distantPast) > now
        }
    }
    
    // MARK: - Learning Exclusion Patterns
    
    /// Add a path exclusion pattern (learning will be skipped for matching paths)
    public func addLearningExclusion(_ pattern: String) async {
        guard var profile = currentProfile else { return }
        let storedPattern = normalizedLearningPatternForStorage(pattern)
        guard !storedPattern.isEmpty else { return }

        let normalizedPattern = normalizedLearningPattern(storedPattern)

        if !profile.learningExclusionPatterns.map(normalizedLearningPattern).contains(normalizedPattern) {
            profile.learningExclusionPatterns.append(storedPattern)
            currentProfile = profile
            analysisResult = nil
            await pruneExcludedLearningData()
            await saveProfile()
        }
    }
    
    /// Remove a learning exclusion pattern
    public func removeLearningExclusion(_ pattern: String) async {
        guard var profile = currentProfile else { return }
        let normalizedPattern = normalizedLearningPattern(pattern)
        profile.learningExclusionPatterns.removeAll {
            normalizedLearningPattern($0) == normalizedPattern
        }
        currentProfile = profile
        analysisResult = nil
        await saveProfile()
    }
    
    /// Check if a path should be excluded from learning
    public func isPathExcludedFromLearning(_ path: String) -> Bool {
        guard let profile = currentProfile else { return false }
        let normalizedPath = normalizedLearningPath(path)
        let pathComponents = normalizedPath.split(separator: "/").map(String.init)
        let fileName = URL(fileURLWithPath: normalizedPath).lastPathComponent.lowercased()

        return profile.learningExclusionPatterns.contains { pattern in
            let normalizedPattern = normalizedLearningPattern(pattern)
            guard !normalizedPattern.isEmpty else { return false }

            if normalizedPath == normalizedPattern || normalizedPath.hasSuffix("/" + normalizedPattern) {
                return true
            }

            let patternComponents = normalizedPattern.split(separator: "/").map(String.init)
            if !patternComponents.isEmpty && pathComponents.count >= patternComponents.count {
                for start in 0...(pathComponents.count - patternComponents.count) {
                    if Array(pathComponents[start..<(start + patternComponents.count)]) == patternComponents {
                        return true
                    }
                }
            }

            return fileName == normalizedPattern || pathComponents.contains(normalizedPattern)
        }
    }
    
    // MARK: - Model Directories (Local Persistence)
    
    private static let learningsModelSelectionKey = "learningsModelSelection"
    private static let modelDirectoriesKey = "learningsModelDirectories"
    private static let maxEnabledModelDirectories = 5
    private static let maxFolderEntriesPerDirectory = 20

    private func loadLearningsModelSelection() {
        guard let data = userDefaults.data(forKey: Self.learningsModelSelectionKey) else {
            learningsModelSelection = nil
            return
        }

        do {
            learningsModelSelection = try JSONDecoder().decode(LearningsModelSelection.self, from: data)
        } catch {
            DebugLogger.log("Failed to load learnings model selection: \(error.localizedDescription)")
            learningsModelSelection = nil
        }
    }

    private func saveLearningsModelSelection() {
        if let learningsModelSelection {
            do {
                let data = try JSONEncoder().encode(learningsModelSelection)
                userDefaults.set(data, forKey: Self.learningsModelSelectionKey)
            } catch {
                DebugLogger.log("Failed to save learnings model selection: \(error.localizedDescription)")
            }
        } else {
            userDefaults.removeObject(forKey: Self.learningsModelSelectionKey)
        }
    }

    public func setLearningsModelOverride(provider: AIProvider, model: String) {
        guard isLearningsEnabled else { return }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { return }
        learningsModelSelection = LearningsModelSelection(provider: provider, model: trimmedModel)
        saveLearningsModelSelection()
    }

    public func clearLearningsModelOverride() {
        learningsModelSelection = nil
        saveLearningsModelSelection()
    }

    public func effectiveAIConfig(from config: AIConfig) -> AIConfig {
        let gatedConfig = config.applyingEntitlements()
        guard isLearningsEnabled else { return gatedConfig }
        guard
            let learningsModelSelection,
            learningsModelSelection.provider == gatedConfig.provider
        else {
            return gatedConfig
        }

        var effectiveConfig = gatedConfig
        effectiveConfig.model = learningsModelSelection.model
        return effectiveConfig
    }
    
    private func loadModelDirectories() {
        guard let data = userDefaults.data(forKey: Self.modelDirectoriesKey) else {
            modelDirectories = []
            return
        }
        do {
            modelDirectories = try JSONDecoder().decode([ReferenceModelDirectory].self, from: data)
            restoreModelDirectoryAccess()
        } catch {
            DebugLogger.log("Failed to load model directories: \(error.localizedDescription)")
            modelDirectories = []
        }
    }
    
    private func saveModelDirectories() {
        do {
            let data = try JSONEncoder().encode(modelDirectories)
            userDefaults.set(data, forKey: Self.modelDirectoriesKey)
        } catch {
            DebugLogger.log("Failed to save model directories: \(error.localizedDescription)")
        }
    }
    
    /// Add a reference model directory from a URL, creating a security-scoped bookmark
    /// and triggering an initial scan. Deduplicates by canonical path.
    public func addModelDirectory(url: URL) -> Bool {
        let canonical = url.standardizedFileURL.path
        guard !modelDirectories.contains(where: { $0.canonicalPath == canonical }) else {
            return false
        }
        
        var bookmark: Data?
        do {
            bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            DebugLogger.log("Failed to create security-scoped bookmark for \(url.path): \(error.localizedDescription)")
        }
        
        let directory = ReferenceModelDirectory(
            path: url.path,
            bookmarkData: bookmark
        )
        modelDirectories.append(directory)
        saveModelDirectories()
        restoreModelDirectoryAccess()
        
        let directoryId = directory.id
        Task {
            await rescanModelDirectory(id: directoryId)
        }
        
        return true
    }
    
    /// Add a reference model directory by path (legacy convenience).
    /// Prefer `addModelDirectory(url:)` for proper bookmark persistence.
    public func addModelDirectory(path: String) -> Bool {
        addModelDirectory(url: URL(fileURLWithPath: path))
    }
    
    /// Add multiple directories at once, returning the count of newly added ones
    @discardableResult
    public func addModelDirectories(paths: [String]) -> Int {
        var added = 0
        for path in paths {
            if addModelDirectory(path: path) {
                added += 1
            }
        }
        return added
    }
    
    /// Remove a model directory by its ID
    public func removeModelDirectory(id: String) {
        stopModelDirectoryAccess(id: id)
        modelDirectories.removeAll { $0.id == id }
        saveModelDirectories()
    }
    
    /// Toggle the enabled state of a model directory
    public func toggleModelDirectory(id: String) {
        guard let index = modelDirectories.firstIndex(where: { $0.id == id }) else { return }
        modelDirectories[index].isEnabled.toggle()
        saveModelDirectories()
    }
    
    /// Validate all directories, restoring bookmark access where needed
    public func validateModelDirectories() {
        restoreModelDirectoryAccess()
    }
    
    /// Restore security-scoped access for all saved directories by resolving bookmarks.
    /// Updates stale bookmarks automatically.
    private func restoreModelDirectoryAccess() {
        var didUpdate = false
        for i in modelDirectories.indices {
            stopModelDirectoryAccess(id: modelDirectories[i].id)
            guard let bookmark = modelDirectories[i].bookmarkData else { continue }
            
            do {
                var isStale = false
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                
                guard resolvedURL.startAccessingSecurityScopedResource() else {
                    DebugLogger.log("Failed to access model directory: \(modelDirectories[i].displayName)")
                    continue
                }
                activeModelDirectoryURLs[modelDirectories[i].id] = resolvedURL
                
                if isStale {
                    do {
                        let newBookmark = try resolvedURL.bookmarkData(
                            options: .withSecurityScope,
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        modelDirectories[i].bookmarkData = newBookmark
                        didUpdate = true
                        DebugLogger.log("Refreshed stale bookmark for \(modelDirectories[i].displayName)")
                    } catch {
                        DebugLogger.log("Failed to refresh stale bookmark for \(modelDirectories[i].displayName): \(error.localizedDescription)")
                    }
                }
            } catch {
                DebugLogger.log("Failed to resolve bookmark for \(modelDirectories[i].displayName): \(error.localizedDescription)")
            }
        }
        
        if didUpdate {
            saveModelDirectories()
        }
    }
    
    /// Re-scan a model directory and update its cached snapshot
    public func rescanModelDirectory(id: String) async {
        guard let index = modelDirectories.firstIndex(where: { $0.id == id }) else { return }
        
        let directory = modelDirectories[index]
        let directoryURL = URL(fileURLWithPath: directory.path)
        
        guard directory.isAccessible else {
            DebugLogger.log("Cannot scan inaccessible directory: \(directory.displayName)")
            return
        }
        
        let snapshot: ReferenceDirectorySnapshot
        do {
            snapshot = try await ReferenceDirectoryScanner.scan(url: directoryURL)
        } catch is CancellationError {
            return
        } catch {
            DebugLogger.log(
                "Preserving previous snapshot for \(directory.displayName) after scan failure: \(error.localizedDescription)"
            )
            return
        }
        
        guard let currentIndex = modelDirectories.firstIndex(where: { $0.id == id }) else { return }
        modelDirectories[currentIndex].scanSnapshot = snapshot
        modelDirectories[currentIndex].lastScannedAt = snapshot.scannedAt
        saveModelDirectories()
    }

    private func stopModelDirectoryAccess(id: String) {
        guard let url = activeModelDirectoryURLs.removeValue(forKey: id) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private func stopAllModelDirectoryAccess() {
        for url in activeModelDirectoryURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeModelDirectoryURLs.removeAll()
    }
    
    /// Returns enabled, accessible reference directory paths (capped at maxEnabledModelDirectories)
    public func enabledModelDirectoryPaths() -> [String] {
        guard isLearningsEnabled else { return [] }
        return modelDirectories
            .filter { $0.isEnabled && $0.isAccessible }
            .prefix(Self.maxEnabledModelDirectories)
            .map { $0.path }
    }
    
    /// Build a reference-directory context string for prompt injection.
    /// Uses cached snapshots when available, falling back to live scan via PromptBuilder.
    public func generateModelDirectoryContext() -> String {
        guard isLearningsEnabled else { return "" }
        let enabledDirs = modelDirectories
            .filter { $0.isEnabled && $0.isAccessible }
            .prefix(Self.maxEnabledModelDirectories)
        
        let snapshots = enabledDirs.compactMap { dir -> (String, ReferenceDirectorySnapshot)? in
            guard let snapshot = dir.scanSnapshot else { return nil }
            return (dir.displayName, snapshot)
        }
        
        guard !snapshots.isEmpty else {
            let paths = enabledDirs.map(\.path)
            guard !paths.isEmpty else { return "" }
            return PromptBuilder.buildReferenceDirectoryContext(paths: Array(paths))
        }
        
        return formatSnapshotContext(snapshots: snapshots)
    }
    
    /// Format cached snapshots into a compact prompt context string (~15 lines max)
    private func formatSnapshotContext(snapshots: [(String, ReferenceDirectorySnapshot)]) -> String {
        var lines: [String] = [
            "## REFERENCE MODEL DIRECTORIES",
            "The user has provided the following well-organized directories as examples of their preferred folder structure and naming conventions. Treat these as few-shot examples: infer the convention, then apply the same style to similar incoming files. Match hierarchy depth, folder names, ordering, and filename patterns when relevant."
        ]
        
        for (name, snapshot) in snapshots {
            lines.append("")
            lines.append("Reference: \"\(name)\" (\(snapshot.totalFolderCount) folders, \(snapshot.totalFileCount) files)")
            
            if !snapshot.namingConventions.isEmpty {
                lines.append("  Naming: \(snapshot.namingConventions.joined(separator: ", "))")
            }
            
            let topFolders = snapshot.folderHierarchy.prefix(Self.maxFolderEntriesPerDirectory)
            for folder in topFolders {
                let typeInfo = folder.fileTypeDistribution
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { "\($0.key):\($0.value)" }
                    .joined(separator: ", ")
                let suffix = typeInfo.isEmpty ? "" : " [\(typeInfo)]"
                lines.append("  - \(folder.relativePath)\(suffix)")
                if !folder.sampleFileNames.isEmpty {
                    lines.append("    examples: \(folder.sampleFileNames.prefix(3).joined(separator: ", "))")
                }
            }
            
            if snapshot.folderHierarchy.count > Self.maxFolderEntriesPerDirectory {
                lines.append("  ... (\(snapshot.folderHierarchy.count - Self.maxFolderEntriesPerDirectory) more folders)")
            }
        }
        
        lines.append("")
        lines.append("IMPORTANT: These are reference examples only — do NOT move files into the reference directories. Instead, recreate analogous destination folders and names in the current organization plan. If the input resembles a media library, prefer inferred media conventions such as Artist/Album/Track, Movie (Year), Season/Episode, or date/event folders when the examples demonstrate them.")
        
        return lines.joined(separator: "\n")
    }

    private func shouldExcludeLearning(paths: [String]) -> Bool {
        paths.contains(where: isPathExcludedFromLearning)
    }

    private func normalizedLearningPattern(_ pattern: String) -> String {
        var normalized = pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\", with: "/")

        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }

        if normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }

        if normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        return normalized
    }

    private func normalizedLearningPatternForStorage(_ pattern: String) -> String {
        var normalized = pattern
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")

        while normalized.contains("//") {
            normalized = normalized.replacingOccurrences(of: "//", with: "/")
        }

        if normalized.hasPrefix("./") {
            normalized.removeFirst(2)
        }

        if normalized.hasSuffix("/") {
            normalized.removeLast()
        }

        return normalized
    }

    private func normalizedLearningPath(_ path: String) -> String {
        normalizedLearningPattern(URL(fileURLWithPath: path).standardizedFileURL.path)
    }

    func filteredLearningProfile(from profile: LearningsProfile) -> LearningsProfile {
        guard !profile.learningExclusionPatterns.isEmpty else { return profile }

        var filtered = profile

        filtered.additionalInstructionsHistory = profile.additionalInstructionsHistory.filter { instruction in
            guard let folderPath = instruction.folderPath else { return true }
            return !isPathExcludedFromLearning(folderPath)
        }
        filtered.guidingInstructionsHistory = profile.guidingInstructionsHistory.filter { instruction in
            guard let folderPath = instruction.folderPath else { return true }
            return !isPathExcludedFromLearning(folderPath)
        }
        filtered.steeringPrompts = profile.steeringPrompts.filter { prompt in
            guard let folderPath = prompt.folderPath else { return true }
            return !isPathExcludedFromLearning(folderPath)
        }
        filtered.postOrganizationChanges = profile.postOrganizationChanges.filter {
            !shouldExcludeLearning(paths: [$0.originalPath, $0.newPath].filter { !$0.isEmpty })
        }
        filtered.renameFeedbackHistory = profile.renameFeedbackHistory.filter { event in
            guard let folderPath = event.folderPath else { return true }
            return !isPathExcludedFromLearning(folderPath)
        }
        filtered.cancelledOrganizations = profile.cancelledOrganizations.filter {
            !isPathExcludedFromLearning($0.folderPath)
        }
        filtered.regeneratedOrganizations = profile.regeneratedOrganizations.filter {
            !isPathExcludedFromLearning($0.folderPath)
        }
        filtered.historyReverts = profile.historyReverts.filter { revert in
            guard let folderPath = revert.folderPath else { return true }
            return !isPathExcludedFromLearning(folderPath)
        }
        filtered.corrections = profile.corrections.filter {
            !shouldExcludeLearning(paths: [$0.srcPath, $0.dstPath])
        }
        filtered.rejections = profile.rejections.filter {
            !shouldExcludeLearning(paths: [$0.srcPath, $0.dstPath])
        }
        filtered.positiveExamples = profile.positiveExamples.filter {
            !shouldExcludeLearning(paths: [$0.srcPath, $0.dstPath])
        }
        filtered.sessions = profile.sessions.filter { session in
            !isPathExcludedFromLearning(session.folderPath)
        }.map { session in
            var updated = session
            updated.filesMoved = session.filesMoved.filter {
                !shouldExcludeLearning(paths: [$0.sourcePath, $0.destinationPath])
            }
            updated.userCorrections = session.userCorrections.filter {
                !shouldExcludeLearning(paths: [$0.originalPath, $0.newPath].filter { !$0.isEmpty })
            }
            updated.folderPatterns = session.folderPatterns.filter { pattern in
                !pattern.relativePath.isEmpty
            }
            return updated
        }

        let excludedExampleIDs = Set(profile.corrections.map(\.id))
            .subtracting(Set(filtered.corrections.map(\.id)))
            .union(Set(profile.rejections.map(\.id)).subtracting(Set(filtered.rejections.map(\.id))))
            .union(Set(profile.positiveExamples.map(\.id)).subtracting(Set(filtered.positiveExamples.map(\.id))))

        if !excludedExampleIDs.isEmpty {
            filtered.inferredRules = filtered.inferredRules.filter { rule in
                let usesExcludedExample = !Set(rule.exampleIds).isDisjoint(with: excludedExampleIDs)
                let usesExcludedEvidence = !Set(rule.evidenceIds).isDisjoint(with: excludedExampleIDs)
                return !usesExcludedExample && !usesExcludedEvidence
            }
        }

        return filtered
    }

    private func learningProfileSnapshot(_ profile: LearningsProfile) -> [Int] {
        [
            profile.additionalInstructionsHistory.count,
            profile.guidingInstructionsHistory.count,
            profile.steeringPrompts.count,
            profile.postOrganizationChanges.count,
            profile.renameFeedbackHistory.count,
            profile.historyReverts.count,
            profile.cancelledOrganizations.count,
            profile.regeneratedOrganizations.count,
            profile.corrections.count,
            profile.rejections.count,
            profile.positiveExamples.count,
            profile.inferredRules.count,
            profile.sessions.count
        ]
    }

    private func pruneExcludedLearningData() async {
        guard let profile = currentProfile else { return }
        let filtered = filteredLearningProfile(from: profile)
        guard learningProfileSnapshot(filtered) != learningProfileSnapshot(profile) else { return }
        currentProfile = filtered
        await saveProfile()
    }

    private func ruleMatchesScope(rule: InferredRule, folderPath: String?, personaId: UUID?) -> Bool {
        if folderPath == nil && personaId == nil {
            return true
        }

        switch rule.scope {
        case .global:
            return true
        case .folder(let rulePath):
            guard let folderPath else { return false }
            return folderPath.hasPrefix(rulePath) || rulePath == folderPath
        case .activePersona(let rulePersonaId):
            guard let personaId else { return false }
            return rulePersonaId == personaId
        }
    }

    private func mergeInferredRules(existing: [InferredRule], new: [InferredRule]) -> [InferredRule] {
        var merged: [String: InferredRule] = [:]

        for rule in existing {
            merged["\(rule.pattern)|\(rule.template)"] = rule
        }

        for rule in new {
            let key = "\(rule.pattern)|\(rule.template)"
            if let existingRule = merged[key] {
                merged[key] = InferredRule(
                    id: existingRule.id,
                    pattern: rule.pattern,
                    template: rule.template,
                    metadataCues: Array(Set(existingRule.metadataCues + rule.metadataCues)),
                    priority: max(existingRule.priority, rule.priority),
                    exampleIds: Array(Set(existingRule.exampleIds + rule.exampleIds)),
                    explanation: rule.explanation,
                    successCount: existingRule.successCount,
                    failureCount: existingRule.failureCount,
                    isEnabled: existingRule.isEnabled,
                    lastAppliedAt: existingRule.lastAppliedAt ?? rule.lastAppliedAt,
                    supportCount: max(existingRule.supportCount, rule.supportCount),
                    initialConfidence: rule.initialConfidence ?? existingRule.initialConfidence,
                    scope: rule.scope,
                    status: existingRule.status,
                    evidenceIds: Array(Set(existingRule.evidenceIds + rule.evidenceIds)),
                    evidenceDescription: rule.evidenceDescription ?? existingRule.evidenceDescription,
                    rejectedAt: existingRule.rejectedAt,
                    cooldownUntil: existingRule.cooldownUntil
                )
            } else {
                merged[key] = rule
            }
        }

        return merged.values.sorted { $0.priority > $1.priority }
    }
}

// MARK: - Errors

public enum LearningsError: LocalizedError {
    case noProject
    case noAnalysisResult
    case emptyRootPaths
    case saveFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noProject:
            return "No project is currently loaded"
        case .noAnalysisResult:
            return "No analysis result available. Run analysis first."
        case .emptyRootPaths:
            return "No root paths provided for analysis"
        case .saveFailed(let reason):
            return "Failed to save: \(reason)"
        }
    }
}
