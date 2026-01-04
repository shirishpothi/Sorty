//
//  LearningsView.swift
//  FileOrganizer
//
//  Passive Learning Dashboard - observes user behavior to build preferences
//  NOT an organization wizard - this watches and learns in the background
//  Enhanced with improved UI/UX and grouped preference display
//

import SwiftUI
import LocalAuthentication
import AppKit
import UniformTypeIdentifiers

// MARK: - Main View

struct LearningsView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var manager: LearningsManager
    
    @State private var showingConsentSheet = false
    @State private var showingHoningSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingWithdrawConfirmation = false
    @State private var selectedTab: LearningsTab = .overview
    
    enum LearningsTab: String, CaseIterable {
        case overview = "Overview"
        case preferences = "Preferences"
        case activity = "Activity"
    }
    
    var body: some View {
        Group {
            if manager.isLocked {
                authenticationGateView
            } else if !manager.consentManager.hasConsented {
                onboardingView
            } else {
                dashboardView
            }
        }
        .frame(minWidth: 650, minHeight: 550)
        .onAppear {
            Task {
                await manager.unlock()
            }
        }
    }
    
    // MARK: - Authentication Gate
    
    private var authenticationGateView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            Image(systemName: manager.securityManager.biometryType == .touchID ? "touchid" : 
                  manager.securityManager.biometryType == .faceID ? "faceid" : "lock.shield")
                .font(.system(size: 72))
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Text("Authentication Required")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Use \(manager.securityManager.biometryDisplayName) to access your learning data.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            
            Button(action: {
                Task { await manager.unlock() }
            }) {
                Label("Unlock with \(manager.securityManager.biometryDisplayName)", systemImage: "lock.open")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            if let error = manager.securityManager.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.callout)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Onboarding (Simple: Welcome + Consent)
    
    private var onboardingView: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Hero
            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            
            Text("The Learnings")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("A passive learning system that watches how you organize files and learns your preferences over time.")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            
            // What it does
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "eye", title: "Watches", description: "Observes when you modify directories after AI organization")
                featureRow(icon: "arrow.uturn.backward", title: "Learns from Reverts", description: "Understands when AI suggestions weren't right")
                featureRow(icon: "text.bubble", title: "Remembers Instructions", description: "Captures your additional guidance and preferences")
                featureRow(icon: "sparkles", title: "Improves Over Time", description: "Uses learnings to make better future suggestions")
            }
            .padding(24)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(12)
            
            // Privacy
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("Encrypted locally • Biometric Protection • Delete anytime")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            
            // Enable button
            Button(action: {
                Task {
                    await manager.grantConsent()
                    manager.completeInitialSetup()
                }
            }) {
                Label("Enable Learning", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
            Spacer()
        }
        .padding(32)
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Dashboard (Main View)
    
    private var dashboardView: some View {
        VStack(spacing: 0) {
            // Header
            dashboardHeader
            
            Divider()
            
            // Tab Bar
            HStack(spacing: 0) {
                ForEach(LearningsTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            Divider()
                .padding(.top, 8)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .overview:
                        overviewSection
                    case .preferences:
                        preferencesSection
                    case .activity:
                        activitySection
                    }
                }
                .padding(24)
            }
        }
        .sheet(isPresented: $showingHoningSheet) {
            LearningsHoningView(config: settingsViewModel.config) { answers in
                Task {
                    await manager.saveHoningResults(answers)
                    showingHoningSheet = false
                }
            }
        }
        .alert("Delete All Learning Data?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await manager.clearAllData() }
            }
        } message: {
            Text("This will permanently delete all your learning data and preferences. This cannot be undone.")
        }
        .alert("Withdraw Consent?", isPresented: $showingWithdrawConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Withdraw", role: .destructive) {
                Task { await manager.withdrawConsent() }
            }
        } message: {
            Text("Learning will stop but your existing data will be preserved. You can re-enable learning later.")
        }
        // Menu action handlers
        .onReceive(NotificationCenter.default.publisher(for: .startHoningSession)) { _ in
            if !manager.isLocked && manager.consentManager.hasConsented {
                showingHoningSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showLearningsStats)) { _ in
            selectedTab = .overview
        }
        .onReceive(NotificationCenter.default.publisher(for: .pauseLearning)) { _ in
            showingWithdrawConfirmation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportLearningsProfile)) { _ in
            // Export handled by the manager
            exportProfile()
        }

    }
    
    // MARK: - Export Profile
    
    private func exportProfile() {
        guard let profile = manager.currentProfile else { return }
        
        let panel = NSSavePanel()
        let learningsType = UTType(filenameExtension: "learnings", conformingTo: .json) ?? .json
        panel.allowedContentTypes = [learningsType]
        panel.nameFieldStringValue = "learnings_profile_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).learnings"
        panel.message = "Export Learning Profile"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(profile)
                try data.write(to: url)
                HapticFeedbackManager.shared.success()
                NSWorkspace.shared.open(url)
            } catch {
                DebugLogger.log("Failed to export profile: \(error)")
                HapticFeedbackManager.shared.error()
            }
        }
    }
    
    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("The Learnings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Passively learning from your organization habits")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
            statusBadge
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func tabButton(_ tab: LearningsTab) -> some View {
        Button(action: { selectedTab = tab }) {
            Text(tab.rawValue)
                .font(.subheadline)
                .fontWeight(selectedTab == tab ? .semibold : .regular)
                .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Stats Grid
            statsSection
            
            // Quick Actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Actions")
                    .font(.headline)
                
                HStack(spacing: 12) {
                    ActionCard(
                        icon: "wand.and.stars",
                        title: "Refine Preferences",
                        description: "Answer questions to improve accuracy",
                        color: .purple
                    ) {
                        showingHoningSheet = true
                    }
                    
                    ActionCard(
                        icon: "arrow.clockwise",
                        title: "Re-analyze Patterns",
                        description: "Update rules from recent activity",
                        color: .blue
                    ) {
                        // Trigger re-analysis
                        Task {
                            await manager.analyze(rootPaths: [], examplePaths: [])
                        }
                    }
                }
            }
            
            // Recent Insights
            if let profile = manager.currentProfile, !profile.inferredRules.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top Learned Patterns")
                        .font(.headline)
                    
                    ForEach(profile.inferredRules.prefix(3)) { rule in
                        InsightCard(rule: rule)
                    }
                }
            }
        }
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let profile = manager.currentProfile {
                // Explicit Preferences (from Honing)
                if !profile.honingAnswers.isEmpty {
                    PreferenceGroup(
                        title: "Your Preferences",
                        subtitle: "Answers from honing sessions",
                        icon: "person.fill.checkmark",
                        color: .blue
                    ) {
                        ForEach(profile.honingAnswers) { answer in
                            PreferenceRow(
                                icon: "checkmark.circle.fill",
                                text: answer.selectedOption,
                                color: .blue
                            )
                        }
                    }
                }
                
                // Learned Rules
                if !profile.inferredRules.isEmpty {
                    PreferenceGroup(
                        title: "Learned Patterns",
                        subtitle: "Inferred from your behavior",
                        icon: "wand.and.stars",
                        color: .purple
                    ) {
                        ForEach(profile.inferredRules.prefix(5)) { rule in
                            PreferenceRow(
                                icon: "lightbulb.fill",
                                text: rule.explanation,
                                color: .purple,
                                priority: rule.priority
                            )
                        }
                    }
                }
                
                // Steering Prompts (Recent Feedback)
                if !profile.steeringPrompts.isEmpty {
                    PreferenceGroup(
                        title: "Recent Feedback",
                        subtitle: "Your post-organization instructions",
                        icon: "text.bubble.fill",
                        color: .orange
                    ) {
                        ForEach(profile.steeringPrompts.suffix(5)) { prompt in
                            PreferenceRow(
                                icon: "quote.bubble",
                                text: prompt.prompt,
                                color: .orange
                            )
                        }
                    }
                }
                
                // Empty State
                if profile.honingAnswers.isEmpty && profile.inferredRules.isEmpty && profile.steeringPrompts.isEmpty {
                    ContentUnavailableView(
                        "No Preferences Yet",
                        systemImage: "brain.head.profile",
                        description: Text("Preferences will appear here as you organize files and provide feedback.")
                    )
                }
                
                // Refine Button
                Button(action: { showingHoningSheet = true }) {
                    Label("Refine Preferences", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
    
    // MARK: - Activity Section
    
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let profile = manager.currentProfile {
                // Corrections
                if !profile.postOrganizationChanges.isEmpty {
                    ActivityGroup(
                        title: "Recent Corrections",
                        subtitle: "Files you moved after AI organization",
                        icon: "arrow.left.arrow.right",
                        color: .blue,
                        count: profile.postOrganizationChanges.count
                    ) {
                        ForEach(profile.postOrganizationChanges.suffix(5)) { change in
                            ActivityRow(change: change)
                        }
                    }
                }
                
                // Reverts
                if !profile.historyReverts.isEmpty {
                    ActivityGroup(
                        title: "Reverts",
                        subtitle: "Organization sessions you undid",
                        icon: "arrow.uturn.backward",
                        color: .orange,
                        count: profile.historyReverts.count
                    ) {
                        ForEach(profile.historyReverts.suffix(5)) { revert in
                            RevertRow(revert: revert)
                        }
                    }
                }
                
                // Instructions History
                if !profile.additionalInstructionsHistory.isEmpty {
                    ActivityGroup(
                        title: "Instructions Given",
                        subtitle: "Custom instructions you've provided",
                        icon: "text.bubble",
                        color: .purple,
                        count: profile.additionalInstructionsHistory.count
                    ) {
                        ForEach(profile.additionalInstructionsHistory.suffix(5)) { instruction in
                            InstructionRow(instruction: instruction)
                        }
                    }
                }
                
                // Empty State
                if profile.postOrganizationChanges.isEmpty && profile.historyReverts.isEmpty && profile.additionalInstructionsHistory.isEmpty {
                    ContentUnavailableView(
                        "No Activity Yet",
                        systemImage: "clock",
                        description: Text("Your organization activity will appear here as you use the app.")
                    )
                }
            }
            
            Divider()
            
            // Data Management
            dataManagementSection
        }
        .fileImporter(
            isPresented: $manager.showingImportPicker,
            allowedContentTypes: [UTType(filenameExtension: "learnings", conformingTo: .json) ?? .json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    do {
                        try await manager.importProfile(from: url)
                        HapticFeedbackManager.shared.success()
                    } catch {
                        DebugLogger.log("Failed to import profile: \(error)")
                        HapticFeedbackManager.shared.error()
                        manager.error = "Import failed: \(error.localizedDescription)"
                    }
                }
            case .failure(let error):
                DebugLogger.log("Import failed: \(error)")
            }
        }
    }
    
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data & Privacy")
                .font(.headline)
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        Text("Your data is encrypted locally")
                            .font(.subheadline)
                    }
                    Text("Protected with \(manager.securityManager.biometryDisplayName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { manager.showingImportPicker = true }) {
                    Text("Import Profile")
                }
                .buttonStyle(.bordered)
                
                Button(action: { showingWithdrawConfirmation = true }) {
                    Text("Pause Learning")
                }
                .buttonStyle(.bordered)
                
                Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                    Label("Delete All Data", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color.secondary.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(manager.consentManager.hasConsented ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(manager.consentManager.hasConsented ? "Active" : "Inactive")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(16)
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Learning Progress")
                .font(.headline)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                statCard(value: "\(manager.currentProfile?.postOrganizationChanges.count ?? 0)", label: "Corrections", icon: "arrow.left.arrow.right", color: .blue)
                statCard(value: "\(manager.currentProfile?.historyReverts.count ?? 0)", label: "Reverts", icon: "arrow.uturn.backward", color: .orange)
                statCard(value: "\(manager.currentProfile?.steeringPrompts.count ?? 0)", label: "Feedback", icon: "text.bubble", color: .purple)
                statCard(value: "\(manager.currentProfile?.inferredRules.count ?? 0)", label: "Rules", icon: "lightbulb.fill", color: .green)
            }
        }
    }
    
    private func statCard(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(12)
    }
}

// MARK: - Supporting Views

struct ActionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(color.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct InsightCard: View {
    let rule: InferredRule
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(.yellow)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.explanation)
                    .font(.subheadline)
                Text("Priority: \(rule.priority)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(8)
    }
}

struct PreferenceGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            content
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct PreferenceRow: View {
    let icon: String
    let text: String
    let color: Color
    var priority: Int?
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
            Spacer()
            if let priority = priority {
                Text("\(priority)%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ActivityGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let count: Int
    @ViewBuilder let content: Content
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(color)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                content
                    .transition(.opacity)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(12)
    }
}

struct ActivityRow: View {
    let change: DirectoryChange
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: change.wasAIOrganized ? "arrow.triangle.2.circlepath" : "folder")
                .foregroundColor(change.wasAIOrganized ? .blue : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(URL(fileURLWithPath: change.originalPath).lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent)
                        .foregroundColor(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent)
                        .foregroundColor(.accentColor)
                }
                .font(.caption)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct RevertRow: View {
    let revert: RevertEvent
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.uturn.backward.circle")
                .foregroundColor(.orange)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("\(revert.operationCount) files reverted")
                    .font(.subheadline)
                if let reason = revert.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(revert.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct InstructionRow: View {
    let instruction: UserInstruction
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "quote.bubble")
                .foregroundColor(.purple)
                .frame(width: 20)
            
            Text(instruction.instruction)
                .font(.subheadline)
                .lineLimit(2)
            
            Spacer()
            
            Text(instruction.timestamp, style: .relative)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    LearningsView()
}
