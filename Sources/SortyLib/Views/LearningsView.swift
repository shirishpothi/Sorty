//
//  LearningsView.swift
//  Sorty
//
//  Passive Learning Dashboard - observes user behavior to build preferences
//  Enhanced with full accessibility, impact metrics, and transparent learning controls
//

import SwiftUI
import LocalAuthentication
import AppKit
import UniformTypeIdentifiers

// MARK: - Liquid Glass Styles

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.1 : 0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 4)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 20) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Main View

struct LearningsView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var manager: LearningsManager
    
    @State private var showingConsentSheet = false
    @State private var showingHoningSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingWithdrawConfirmation = false
    @State private var showingImportPicker = false
    @State private var selectedTab: LearningsTab = .overview
    
    enum LearningsTab: String, CaseIterable {
        case overview = "Overview"
        case preferences = "Preferences"
        case activity = "Activity"
        
        var accessibilityHint: String {
            switch self {
            case .overview: return "View learning impact and quick actions"
            case .preferences: return "View and manage your organization preferences"
            case .activity: return "View your organization history and corrections"
            }
        }
        
        var icon: String {
            switch self {
            case .overview: return "chart.bar.fill"
            case .preferences: return "slider.horizontal.3"
            case .activity: return "clock.arrow.circlepath"
            }
        }
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
        .frame(minWidth: 700, minHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Learnings Dashboard")
        .onAppear {
            Task {
                await manager.unlock()
            }
        }
    }
    
    // MARK: - Authentication Gate
    
    private var authenticationGateView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: manager.securityManager.biometryType == .touchID ? "touchid" : 
                  manager.securityManager.biometryType == .faceID ? "faceid" : "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.linearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(32)
                .liquidGlassCard(cornerRadius: 30)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("Authentication Required")
                    .font(.title2.bold())
                
                Text("Use \(manager.securityManager.biometryDisplayName) to access your learning data.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            Button(action: {
                Task { 
                    HapticFeedbackManager.shared.tap()
                    await manager.unlock() 
                }
            }) {
                Label("Unlock with \(manager.securityManager.biometryDisplayName)", systemImage: "lock.open.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return)
            .accessibilityLabel("Unlock Learnings")
            .accessibilityHint("Authenticate to view your learning data")
            
            if let error = manager.securityManager.error {
                Text(error)
                    .font(.caption.bold())
                    .foregroundColor(.red)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
                    .accessibilityLabel("Authentication error: \(error)")
            }
            
            Spacer()
        }
        .padding(40)
        .background(Color(NSColor.windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Authentication required to access Learnings")
    }
    
    // MARK: - Onboarding
    
    private var onboardingView: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(32)
                .liquidGlassCard(cornerRadius: 30)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("The Learnings")
                    .font(.largeTitle.bold())
                
                Text("A passive learning system that watches how you organize files and learns your preferences over time.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "eye.fill", title: "Watches", description: "Observes when you modify directories after AI organization")
                featureRow(icon: "arrow.uturn.backward.circle.fill", title: "Learns from Reverts", description: "Understands when AI suggestions weren't right")
                featureRow(icon: "text.bubble.fill", title: "Remembers Instructions", description: "Captures your additional guidance and preferences")
                featureRow(icon: "sparkles", title: "Improves Over Time", description: "Uses learnings to make better future suggestions")
            }
            .padding(24)
            .liquidGlassCard(cornerRadius: 24)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Learnings features")
            
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("Encrypted locally • Biometric Protection • Delete anytime")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .cornerRadius(20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Privacy: Data is encrypted locally with biometric protection. You can delete anytime.")
            
            Button(action: {
                Task {
                    HapticFeedbackManager.shared.success()
                    await manager.grantConsent()
                    manager.completeInitialSetup()
                }
            }) {
                Label("Enable Learning", systemImage: "checkmark.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.return)
            .accessibilityLabel("Enable Learning")
            .accessibilityHint("Start learning from your organization habits")
            
            Spacer()
        }
        .padding(40)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundColor(.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(10)
                .accessibilityHidden(true)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
    
    // MARK: - Dashboard (Main View)
    
    private var dashboardView: some View {
        VStack(spacing: 0) {
            dashboardHeader
            
            Divider()
            
            HStack(spacing: 12) {
                ForEach(LearningsTab.allCases, id: \.self) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Navigation tabs")
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch selectedTab {
                    case .overview:
                        overviewSection
                            .animatedAppearance(delay: 0.1)
                    case .preferences:
                        preferencesSection
                            .animatedAppearance(delay: 0.1)
                    case .activity:
                        activitySection
                            .animatedAppearance(delay: 0.1)
                    }
                }
                .padding(32)
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
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundStyle(.blue.gradient)
                    Text("The Learnings")
                        .font(.title2.bold())
                }
                Text("Passively learning from your organization habits")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("The Learnings: Passively learning from your organization habits")
            
            Spacer()
            
            LearningStrengthControl(manager: manager)
            
            statusBadge
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
    }

    private func tabButton(_ tab: LearningsTab) -> some View {
        Button(action: { 
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = tab 
                HapticFeedbackManager.shared.selection()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.title2)
                Text(tab.rawValue)
                    .font(selectedTab == tab ? .body.bold() : .body)
            }
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.white.opacity(0.001))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel(tab.rawValue)
        .accessibilityHint(tab.accessibilityHint)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            LearningsImpactCard(manager: manager)

            statsSection

            VStack(alignment: .leading, spacing: 20) {
                Text("Quick Actions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 20) {
                    ActionCard(
                        icon: "wand.and.stars",
                        title: "Refine Preferences",
                        description: "Answer questions to improve accuracy",
                        color: .purple
                    ) {
                        showingHoningSheet = true
                    }

                    ActionCard(
                        icon: "arrow.clockwise.circle.fill",
                        title: "Re-analyze Patterns",
                        description: "Update rules from recent activity",
                        color: .blue
                    ) {
                        Task {
                            await manager.analyze(rootPaths: [], examplePaths: [])
                        }
                    }
                }
            }
            .padding(24)
            .liquidGlassCard(cornerRadius: 20)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick actions")

            if let profile = manager.currentProfile, !profile.inferredRules.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        Image(systemName: "sparkles")
                            .font(.headline)
                            .foregroundColor(.yellow)
                        Text("Top Learned Patterns")
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        Spacer()

                        Text("\(profile.inferredRules.count) TOTAL")
                            .font(.caption2.bold())
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }

                    VStack(spacing: 12) {
                        ForEach(profile.inferredRules.sorted { $0.priority > $1.priority }.prefix(5)) { rule in
                            RuleRow(rule: rule, manager: manager)
                        }
                    }
                }
                .padding(24)
                .liquidGlassCard(cornerRadius: 20)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Top learned patterns: \(profile.inferredRules.count) rules")
            }
        }
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let profile = manager.currentProfile {
                if let behaviorPrefs = manager.behaviorPreferences {
                    BehaviorPreferencesCard(preferences: behaviorPrefs)
                }
                
                if !profile.honingAnswers.isEmpty {
                    AccessiblePreferenceGroup(
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
                
                if !profile.inferredRules.isEmpty {
                    AccessiblePreferenceGroup(
                        title: "Learned Patterns",
                        subtitle: "Inferred from your behavior (\(profile.inferredRules.filter { $0.isEnabled }.count) active)",
                        icon: "wand.and.stars",
                        color: .purple
                    ) {
                        ForEach(profile.inferredRules.sorted { $0.priority > $1.priority }.prefix(10)) { rule in
                            RuleRow(rule: rule, manager: manager)
                        }
                    }
                }
                
                if !profile.steeringPrompts.isEmpty {
                    AccessiblePreferenceGroup(
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
                
                if profile.honingAnswers.isEmpty && profile.inferredRules.isEmpty && profile.steeringPrompts.isEmpty {
                    VStack(spacing: 20) {
                        Spacer(minLength: 20)
                        ContentUnavailableView(
                            "No Preferences Yet",
                            systemImage: "brain.head.profile",
                            description: Text("Preferences will appear here as you organize files and provide feedback.")
                        )
                        .padding(.bottom, 20)
                        
                        Button(action: { 
                            HapticFeedbackManager.shared.tap()
                            showingHoningSheet = true 
                        }) {
                            Label("Start Honing Now", systemImage: "wand.and.stars")
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .liquidGlassCard(cornerRadius: 16)
                        
                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .liquidGlassCard(cornerRadius: 32)
                    .accessibilityLabel("No preferences recorded yet")
                } else {
                    HStack {
                        Spacer()
                        Button(action: { 
                            HapticFeedbackManager.shared.tap()
                            showingHoningSheet = true 
                        }) {
                            Label("Refine Preferences", systemImage: "wand.and.stars")
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .liquidGlassCard(cornerRadius: 16)
                        .accessibilityLabel("Refine preferences")
                        .accessibilityHint("Answer questions to improve organization accuracy")
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - Activity Section
    
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let profile = manager.currentProfile {
                if !profile.postOrganizationChanges.isEmpty {
                    AccessibleActivityGroup(
                        title: "Recent Corrections",
                        subtitle: "Files you moved after AI organization",
                        icon: "arrow.left.arrow.right",
                        color: .blue,
                        count: profile.postOrganizationChanges.count
                    ) {
                        ForEach(profile.postOrganizationChanges.suffix(10).reversed()) { change in
                            AccessibleActivityRow(change: change)
                        }
                    }
                }
                
                if !profile.historyReverts.isEmpty {
                    AccessibleActivityGroup(
                        title: "Reverts",
                        subtitle: "Organization sessions you undid",
                        icon: "arrow.uturn.backward",
                        color: .orange,
                        count: profile.historyReverts.count
                    ) {
                        ForEach(profile.historyReverts.suffix(10).reversed()) { revert in
                            AccessibleRevertRow(revert: revert)
                        }
                    }
                }
                
                if !profile.additionalInstructionsHistory.isEmpty {
                    AccessibleActivityGroup(
                        title: "Instructions Given",
                        subtitle: "Custom instructions you've provided",
                        icon: "text.bubble",
                        color: .purple,
                        count: profile.additionalInstructionsHistory.count
                    ) {
                        ForEach(profile.additionalInstructionsHistory.suffix(10).reversed()) { instruction in
                            AccessibleInstructionRow(instruction: instruction)
                        }
                    }
                }
                
                if profile.postOrganizationChanges.isEmpty && profile.historyReverts.isEmpty && profile.additionalInstructionsHistory.isEmpty {
                    VStack(spacing: 20) {
                        Spacer(minLength: 20)
                        ContentUnavailableView(
                            "No Activity Yet",
                            systemImage: "clock",
                            description: Text("Your organization activity will appear here as you use the app.")
                        )
                        Spacer(minLength: 20)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(32)
                    .liquidGlassCard(cornerRadius: 32)
                    .accessibilityLabel("No organization activity recorded yet")
                }
            }
            
            Divider()
            
            dataManagementSection
        }
        .fileImporter(
            isPresented: $showingImportPicker,
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
        VStack(alignment: .leading, spacing: 20) {
            Text("Data & Privacy")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                        .font(.title2.bold())
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your data is encrypted locally")
                            .font(.headline)
                        Text("Protected with \(manager.securityManager.biometryDisplayName)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(20)
                .liquidGlassCard(cornerRadius: 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Security: Your data is encrypted locally and protected with \(manager.securityManager.biometryDisplayName)")
                
                Divider()
                
                HStack(spacing: 12) {
                    Button(action: { 
                        HapticFeedbackManager.shared.tap()
                        exportProfile() 
                    }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .liquidGlassCard(cornerRadius: 12)
                    
                    Button(action: { 
                        HapticFeedbackManager.shared.tap()
                        showingImportPicker = true 
                    }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .liquidGlassCard(cornerRadius: 12)
                    
                    Spacer()
                    
                    Button(action: { 
                        HapticFeedbackManager.shared.tap()
                        showingWithdrawConfirmation = true 
                    }) {
                        Label("Pause", systemImage: "pause.circle.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .liquidGlassCard(cornerRadius: 16)
                    
                    Button(role: .destructive, action: { 
                        HapticFeedbackManager.shared.error()
                        showingDeleteConfirmation = true 
                    }) {
                        Label("Delete", systemImage: "trash.fill")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .liquidGlassCard(cornerRadius: 16)
                }
            }
            .padding(24)
            .liquidGlassCard(cornerRadius: 24)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Data and privacy settings")
    }
    
    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(manager.consentManager.hasConsented ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(manager.consentManager.hasConsented ? "Active" : "Inactive")
                .font(.caption.bold())
                .foregroundColor(manager.consentManager.hasConsented ? .primary : .secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlassCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Learning status: \(manager.consentManager.hasConsented ? "Active" : "Inactive")")
    }
    
    // MARK: - Stats Section
    
    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Learning Progress")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                AccessibleStatCard(
                    value: "\(manager.currentProfile?.postOrganizationChanges.count ?? 0)",
                    label: "Corrections",
                    icon: "arrow.left.arrow.right",
                    color: .blue,
                    hint: "Files you manually moved after AI organization"
                )
                AccessibleStatCard(
                    value: "\(manager.currentProfile?.historyReverts.count ?? 0)",
                    label: "Reverts",
                    icon: "arrow.uturn.backward",
                    color: .orange,
                    hint: "Organization sessions you completely undid"
                )
                AccessibleStatCard(
                    value: "\(manager.currentProfile?.steeringPrompts.count ?? 0)",
                    label: "Feedback",
                    icon: "text.bubble.fill",
                    color: .purple,
                    hint: "Instructions you provided after organization"
                )
                AccessibleStatCard(
                    value: "\(manager.currentProfile?.inferredRules.filter { $0.isEnabled }.count ?? 0)",
                    label: "Active Rules",
                    icon: "lightbulb.fill",
                    color: .green,
                    hint: "Patterns learned and currently applied"
                )
            }
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Learning progress statistics")
    }
}

// MARK: - Learning Strength Control

struct LearningStrengthControl: View {
    @ObservedObject var manager: LearningsManager
    @State private var showingPopover = false
    
    var body: some View {
        Button(action: { 
            HapticFeedbackManager.shared.tap()
            showingPopover.toggle() 
        }) {
            HStack(spacing: 8) {
                Image(systemName: strengthIcon)
                    .foregroundColor(strengthColor)
                    .font(.caption.bold())
                Text(strengthLabel)
                    .font(.caption.bold())
                Image(systemName: "chevron.down")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .liquidGlassCard(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            LearningStrengthPopover(manager: manager)
        }
        .accessibilityLabel("Learning strength: \(strengthLabel)")
        .accessibilityHint("Tap to adjust how strongly learnings influence organization")
    }
    
    private var strengthIcon: String {
        switch manager.learningStrength {
        case 0..<0.33: return "dial.low"
        case 0.33..<0.66: return "dial.medium"
        default: return "dial.high"
        }
    }
    
    private var strengthColor: Color {
        switch manager.learningStrength {
        case 0..<0.33: return .blue
        case 0.33..<0.66: return .orange
        default: return .green
        }
    }
    
    private var strengthLabel: String {
        switch manager.learningStrength {
        case 0..<0.33: return "Conservative"
        case 0.33..<0.66: return "Balanced"
        default: return "Aggressive"
        }
    }
}

struct LearningStrengthPopover: View {
    @ObservedObject var manager: LearningsManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Learning Influence")
                .font(.headline)
            
            Text("Controls how much learned patterns affect organization decisions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Conservative")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("Aggressive")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $manager.learningStrength, in: 0...1, step: 0.1)
                    .accentColor(.accentColor)
                    .accessibilityLabel("Learning strength slider")
                    .accessibilityValue("\(Int(manager.learningStrength * 100)) percent")
                
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.blue)
                    Text("Higher confidence")
                        .font(.caption2.bold())
                    Spacer()
                    Text("Full personalization")
                        .font(.caption2.bold())
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.green)
                }
                .foregroundColor(.secondary)
            }
            .padding()
            .liquidGlassCard(cornerRadius: 16)
            
            Divider()
            
            Text("Current: \(Int(manager.learningStrength * 100))% – \(strengthDescription)")
                .font(.caption.bold())
                .foregroundColor(.accentColor)
        }
        .padding(24)
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var strengthDescription: String {
        switch manager.learningStrength {
        case 0..<0.33: return "Only high-confidence patterns will be applied"
        case 0.33..<0.66: return "Balanced mix of learned and default behavior"
        default: return "Maximum personalization based on all learned patterns"
        }
    }
}

// MARK: - Impact Summary Card

struct LearningsImpactCard: View {
    @ObservedObject var manager: LearningsManager
    
    private var impact: LearningsImpactSummary? {
        manager.computeImpactSummary()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                Text("Learning Impact")
                    .font(.title3.bold())
                Spacer()
                
                if let impact = impact, impact.totalRuns > 0 {
                    ImpactBadge(impact: impact)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Learning impact summary")
            
            if let impact = impact, impact.totalRuns > 0 {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 20) {
                    ImpactMetric(
                        value: "\(impact.runsWithLearnings)/\(impact.totalRuns)",
                        label: "Runs Used",
                        icon: "play.circle.fill",
                        color: .blue,
                        hint: "Organization runs that used learnings"
                    )
                    ImpactMetric(
                        value: "\(impact.filesRoutedByLearnings)",
                        label: "Files Routed",
                        icon: "folder.fill.badge.gearshape",
                        color: .green,
                        hint: "Files organized using learned patterns"
                    )
                    ImpactMetric(
                        value: String(format: "%.0f%%", impact.successRate * 100),
                        label: "Success Rate",
                        icon: impact.successRate >= 0.8 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                        color: impact.successRate >= 0.8 ? .green : (impact.successRate >= 0.5 ? .orange : .red),
                        hint: "Percentage of learnings-based moves that weren't corrected"
                    )
                }
                
                if impact.correctionRate > 0.3 {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("High correction rate detected. Consider refining your preferences.")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .liquidGlassCard(cornerRadius: 16)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Warning: High correction rate. Consider refining preferences.")
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("Organize some files to see how learnings affect results.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .liquidGlassCard(cornerRadius: 20)
                .accessibilityLabel("No impact data yet. Organize some files to see results.")
            }
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }
}

struct ImpactBadge: View {
    let impact: LearningsImpactSummary
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: badgeIcon)
                .font(.caption2.bold())
            Text(badgeText.uppercased())
                .font(.caption2.bold())
        }
        .foregroundColor(badgeColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .liquidGlassCard(cornerRadius: 20)
        .accessibilityLabel("Impact rating: \(badgeText)")
    }
    
    private var badgeIcon: String {
        if impact.successRate >= 0.8 { return "star.fill" }
        if impact.successRate >= 0.5 { return "star.leadinghalf.filled" }
        return "star"
    }
    
    private var badgeText: String {
        if impact.successRate >= 0.8 { return "Excellent" }
        if impact.successRate >= 0.5 { return "Good" }
        return "Needs Work"
    }
    
    private var badgeColor: Color {
        if impact.successRate >= 0.8 { return .green }
        if impact.successRate >= 0.5 { return .orange }
        return .red
    }
}

struct ImpactMetric: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    let hint: String
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(color)
            Text(value)
                .font(.title2.bold())
            Text(label.uppercased())
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .liquidGlassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint(hint)
    }
}

// MARK: - Behavior Preferences Card

struct BehaviorPreferencesCard: View {
    let preferences: BehaviorPreferences
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "brain")
                    .font(.headline)
                    .foregroundColor(.purple)
                Text("Your Organization Philosophy")
                    .font(.title3.bold())
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                BehaviorPill(
                    icon: "trash.slash.fill",
                    text: preferences.deletionVsArchive.displayName,
                    color: .blue
                )
                BehaviorPill(
                    icon: "folder.fill",
                    text: preferences.folderDepthPreference.displayName,
                    color: .green
                )
                BehaviorPill(
                    icon: "calendar.badge.clock",
                    text: preferences.dateVsContentPreference.displayName,
                    color: .orange
                )
                BehaviorPill(
                    icon: "doc.on.doc.fill",
                    text: preferences.duplicateKeeperStrategy.displayName,
                    color: .purple
                )
            }
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Your organization philosophy preferences")
    }
}

struct BehaviorPill: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.bold())
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline.bold())
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .liquidGlassCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

// MARK: - Enhanced Insight Card with Stats

struct EnhancedInsightCard: View {
    let rule: InferredRule
    @ObservedObject var manager: LearningsManager
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: rule.isEnabled ? "lightbulb.fill" : "lightbulb.slash")
                .font(.headline)
                .foregroundColor(rule.isEnabled ? .yellow : .gray)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(rule.explanation)
                    .font(.subheadline.bold())
                    .foregroundColor(rule.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 16) {
                    Label("\(rule.successCount) applied", systemImage: "checkmark.circle.fill")
                        .font(.caption2.bold())
                        .foregroundColor(.green)
                    
                    if rule.failureCount > 0 {
                        Label("\(rule.failureCount) corrected", systemImage: "xmark.circle.fill")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                    }
                    
                    Text("PRIORITY: \(rule.priority)")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    Task {
                        HapticFeedbackManager.shared.selection()
                        await manager.setRuleEnabled(ruleId: rule.id, enabled: newValue)
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.8)
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.explanation). Applied \(rule.successCount) times, corrected \(rule.failureCount) times. \(rule.isEnabled ? "Enabled" : "Disabled")")
        .accessibilityHint("Toggle to enable or disable this pattern")
    }
}

// MARK: - Accessible Supporting Views

struct AccessibleStatCard: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    let hint: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundColor(color)
            Text(value)
                .font(.title3.bold())
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .liquidGlassCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityHint(hint)
    }
}

struct AccessiblePreferenceGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundColor(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(subtitle)")
            .accessibilityAddTraits(.isHeader)
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(16)
            .liquidGlassCard(cornerRadius: 16)
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }
}

struct RuleRow: View {
    let rule: InferredRule
    @ObservedObject var manager: LearningsManager
    
    private var confidenceColor: Color {
        if rule.failureRate > 0.3 { return .red }
        if rule.failureRate > 0.15 { return .orange }
        return .green
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.body.bold())
                .foregroundColor(rule.isEnabled ? confidenceColor : .gray)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.explanation)
                    .font(.subheadline.bold())
                    .foregroundColor(rule.isEnabled ? .primary : .secondary)
                
                HStack(spacing: 12) {
                    Text("\(rule.successCount) SUCCESS")
                        .font(.caption2.bold())
                        .foregroundColor(.green)
                    if rule.failureCount > 0 {
                        Text("\(rule.failureCount) CORRECTION")
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            Text("\(rule.priority)%")
                .font(.caption2.bold().monospaced())
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlassCard(cornerRadius: 6)
            
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { newValue in
                    Task { 
                        HapticFeedbackManager.shared.selection()
                        await manager.setRuleEnabled(ruleId: rule.id, enabled: newValue) 
                    }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.7)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.explanation). Priority \(rule.priority) percent. \(rule.successCount) successes, \(rule.failureCount) failures. \(rule.isEnabled ? "Enabled" : "Disabled")")
        .accessibilityHint("Toggle to enable or disable this rule")
    }
}

struct AccessibleActivityGroup<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let count: Int
    @ViewBuilder let content: Content
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: { 
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle() 
                    HapticFeedbackManager.shared.tap()
                }
            }) {
                HStack(spacing: 16) {
                    Image(systemName: icon)
                        .font(.headline)
                        .foregroundColor(color)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.headline)
                        Text(subtitle)
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(count)")
                        .font(.title2.bold())
                        .foregroundColor(color)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title), \(count) items")
            .accessibilityHint(isExpanded ? "Collapse to hide items" : "Expand to show items")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityAddTraits(.isButton)
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(16)
                .liquidGlassCard(cornerRadius: 16)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(24)
        .liquidGlassCard(cornerRadius: 24)
        .accessibilityElement(children: .contain)
    }
}

struct AccessibleActivityRow: View {
    let change: DirectoryChange
    
    private var fileName: String {
        URL(fileURLWithPath: change.originalPath).lastPathComponent
    }
    
    private var srcFolder: String {
        URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent
    }
    
    private var dstFolder: String {
        URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: change.wasAIOrganized ? "arrow.triangle.2.circlepath" : "folder.fill")
                .font(.body.bold())
                .foregroundColor(change.wasAIOrganized ? .blue : .secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(srcFolder)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(dstFolder)
                        .foregroundColor(.accentColor)
                }
                .font(.subheadline.bold())
            }
            
            Spacer()
            
            Text(change.timestamp, style: .relative)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fileName) moved from \(srcFolder) to \(dstFolder)")
        .accessibilityHint(change.wasAIOrganized ? "This was a correction of AI organization" : "This was a manual move")
    }
}

struct AccessibleRevertRow: View {
    let revert: RevertEvent
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.body.bold())
                .foregroundColor(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(revert.operationCount) files reverted")
                    .font(.subheadline.bold())
                if let reason = revert.reason {
                    Text(reason)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(revert.timestamp, style: .relative)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reverted \(revert.operationCount) files\(revert.reason.map { ", reason: \($0)" } ?? "")")
    }
}

struct AccessibleInstructionRow: View {
    let instruction: UserInstruction
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .font(.body.bold())
                .foregroundColor(.purple)
                .frame(width: 24)
            
            Text(instruction.instruction)
                .font(.subheadline.bold())
                .lineLimit(2)
            
            Spacer()
            
            Text(instruction.timestamp, style: .relative)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Instruction: \(instruction.instruction)")
    }
}

// MARK: - Legacy Supporting Views (kept for compatibility)

struct ActionCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.tap()
            action()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2.bold())
                    .foregroundColor(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .liquidGlassCard(cornerRadius: 20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(description)
    }
}

struct PreferenceRow: View {
    let icon: String
    let text: String
    let color: Color
    var priority: Int?
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body.bold())
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline.bold())
            Spacer()
            if let priority = priority {
                Text("\(priority)%")
                    .font(.caption2.bold().monospaced())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassCard(cornerRadius: 6)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text + (priority.map { ", priority \($0) percent" } ?? ""))
    }
}

#Preview {
    LearningsView()
}
