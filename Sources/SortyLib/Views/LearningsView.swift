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
    var cornerRadius: CGFloat = 12
    @Environment(\.colorScheme) var colorScheme
    
    func body(content: Content) -> some View {
        let style = SortyDesignSystem.CardStyles.CardStyle(
            backgroundColor: Color(NSColor.controlBackgroundColor),
            cornerRadius: cornerRadius,
            strokeColor: SortyDesignSystem.Colors.glassBorder,
            strokeWidth: 1,
            padding: 0,
            useUltraThinMaterial: true
        )
        
        return content.sortyCardStyle(style)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = 12) -> some View {
        self.modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Main View

struct LearningsView: View {
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var manager: LearningsManager
    @EnvironmentObject var appState: AppState
    
    @State private var showingConsentSheet = false
    @State private var showingHoningSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingWithdrawConfirmation = false
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
        WorkflowContainer(currentStep: .configure) {
            Spacer()

            Image(systemName: manager.securityManager.biometryType == .touchID ? "touchid" :
                  manager.securityManager.biometryType == .faceID ? "faceid" : "lock.shield.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Authentication required to access Learnings")
    }
    
    // MARK: - Onboarding
    
    private var onboardingView: some View {
        WorkflowContainer(currentStep: .configure) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 60))
                .foregroundStyle(.purple)
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
            .padding(16)
            .liquidGlassCard(cornerRadius: 20)
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    switch selectedTab {
                    case .overview:
                        overviewSection
                            .animatedAppearance(delay: 0.05)
                    case .preferences:
                        preferencesSection
                            .animatedAppearance(delay: 0.05)
                    case .activity:
                        activitySection
                            .animatedAppearance(delay: 0.05)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
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
                Task {
                    let didClear = await manager.clearAllData()
                    if didClear {
                        withAnimation(.spring()) {
                            appState.hasCompletedOnboarding = false
                        }
                    }
                }
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
        HStack(spacing: 16) {
            // Back button when navigated from settings
            if appState.navigatedFromSettings {
                GlassyBackButton {
                    HapticFeedbackManager.shared.tap()
                    appState.navigatedFromSettings = false
                    appState.currentView = .settings
                    appState.selectedSettingsSection = .help
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundStyle(.blue.gradient)
                    Text("The Learnings")
                        .font(.title2.bold())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("The Learnings")

                Text("Passively learning from your organization habits")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Glass pill tab selector
            HStack(spacing: 0) {
                ForEach(Array(LearningsTab.allCases.enumerated()), id: \.offset) { index, tab in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedTab = tab
                        }
                        HapticFeedbackManager.shared.selection()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.caption)
                            Text(tab.rawValue)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                        .background(
                            selectedTab == tab
                                ? Color.accentColor.opacity(0.15)
                                : Color.clear
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                    .accessibilityLabel(tab.rawValue)
                    .accessibilityHint(tab.accessibilityHint)
                    
                    if index < LearningsTab.allCases.count - 1 {
                        Text(index == 0 ? "  " : "•")
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.4))
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(4)
            .liquidGlassCard(cornerRadius: 20)
            .accessibilityLabel("Learnings navigation")
            .accessibilityIdentifier("LearningsTabPicker")

            LearningStrengthControl(manager: manager)

            statusBadge
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Learnings controls")
    }

    // MARK: - Overview Section

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            LearningsImpactCard(manager: manager, onStartHoning: { showingHoningSheet = true })
            
            OrganizationBreakdownCard(manager: manager)

            statsSection

            VStack(alignment: .leading, spacing: 16) {
                Text("Quick Actions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                HStack(spacing: 16) {
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
            .padding(16)
            .liquidGlassCard(cornerRadius: 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick actions")

            if let profile = manager.currentProfile, !profile.inferredRules.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
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
                .padding(16)
                .liquidGlassCard(cornerRadius: 16)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Top learned patterns: \(profile.inferredRules.count) rules")
            }
        }
    }
    
    // MARK: - Preferences Section
    
    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let profile = manager.currentProfile {
                // Rule Suggestions Inbox
                let pendingRules = manager.getPendingRules()
                if !pendingRules.isEmpty {
                    RuleSuggestionsSection(rules: pendingRules, manager: manager)
                }
                
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
                
                // Learning Exclusions
                if !profile.learningExclusionPatterns.isEmpty {
                    AccessiblePreferenceGroup(
                        title: "Learning Exclusions",
                        subtitle: "Paths excluded from learning",
                        icon: "eye.slash.fill",
                        color: .gray
                    ) {
                        ForEach(profile.learningExclusionPatterns, id: \.self) { pattern in
                            HStack(spacing: 12) {
                                Image(systemName: "folder.badge.minus")
                                    .foregroundColor(.secondary)
                                    .frame(width: 24)
                                Text(pattern)
                                    .font(.subheadline.bold())
                                Spacer()
                                Button {
                                    Task {
                                        HapticFeedbackManager.shared.tap()
                                        await manager.removeLearningExclusion(pattern)
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove exclusion for \(pattern)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                // Add Learning Exclusion button
                AddExclusionView(manager: manager)
                
                if profile.honingAnswers.isEmpty && profile.inferredRules.isEmpty && profile.steeringPrompts.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                            .opacity(0.8)
                            .accessibilityHidden(true)
                        
                        VStack(spacing: 8) {
                            Text("No Preferences Yet")
                                .font(.title2.bold())
                            Text("Preferences will appear here as you organize files and provide feedback.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 350)
                        }
                        
                        Button(action: { 
                            HapticFeedbackManager.shared.tap()
                            showingHoningSheet = true 
                        }) {
                            Label("Start Honing Now", systemImage: "wand.and.stars")
                                .font(.headline)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .liquidGlassCard(cornerRadius: 12)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement(children: .combine)
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
        VStack(alignment: .leading, spacing: 20) {
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
                
                if !profile.cancelledOrganizations.isEmpty {
                    AccessibleActivityGroup(
                        title: "Cancelled",
                        subtitle: "Organizations you cancelled before applying",
                        icon: "xmark.octagon.fill",
                        color: .orange,
                        count: profile.cancelledOrganizations.count
                    ) {
                        ForEach(profile.cancelledOrganizations.suffix(10).reversed()) { cancelled in
                            AccessibleCancelledRow(cancelled: cancelled)
                        }
                    }
                }
                
                if !profile.regeneratedOrganizations.isEmpty {
                    AccessibleActivityGroup(
                        title: "Regenerated",
                        subtitle: "Organizations you regenerated with new instructions",
                        icon: "arrow.triangle.2.circlepath",
                        color: .blue,
                        count: profile.regeneratedOrganizations.count
                    ) {
                        ForEach(profile.regeneratedOrganizations.suffix(10).reversed()) { regen in
                            AccessibleRegeneratedRow(regenerated: regen)
                        }
                    }
                }
                
                if !profile.rejections.isEmpty {
                    AccessibleActivityGroup(
                        title: "Rejected Placements",
                        subtitle: "Files you removed or corrected after AI organization",
                        icon: "xmark.circle.fill",
                        color: .red,
                        count: profile.rejections.count
                    ) {
                        ForEach(profile.rejections.suffix(10).reversed()) { rejection in
                            AccessibleRejectionRow(rejection: rejection)
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
                
                let hasActivity = !profile.postOrganizationChanges.isEmpty ||
                    !profile.historyReverts.isEmpty ||
                    !profile.rejections.isEmpty ||
                    !profile.additionalInstructionsHistory.isEmpty ||
                    !profile.cancelledOrganizations.isEmpty ||
                    !profile.regeneratedOrganizations.isEmpty
                
                if !hasActivity {
                    LearningsEmptyStateView()
                }
            }
            
            Divider()
            
            dataManagementSection
        }
    }
    
    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data & Privacy")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            
            VStack(spacing: 16) {
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
                .padding(16)
                .liquidGlassCard(cornerRadius: 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Security: Your data is encrypted locally and protected with \(manager.securityManager.biometryDisplayName)")
                
                Divider()
                
                HStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.blue)
                        .font(.title3.bold())
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Data Retention")
                            .font(.headline)
                        Text("How long to keep learning data")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $manager.dataRetentionDays) {
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                        Text("Forever").tag(0)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .accessibilityLabel("Data retention period")
                }
                .padding(16)
                .liquidGlassCard(cornerRadius: 12)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Import & Export")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            HapticFeedbackManager.shared.tap()
                            exportProfile()
                        }) {
                            Label("Export Profile", systemImage: "square.and.arrow.up")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityLabel("Export learning profile")
                        
                        Button(action: {
                            HapticFeedbackManager.shared.tap()
                            manager.showingImportPicker = true
                        }) {
                            Label("Import Profile", systemImage: "square.and.arrow.down")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityLabel("Import learning profile")
                    }
                }
                .padding(16)
                .liquidGlassCard(cornerRadius: 12)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Learning Controls")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "cpu")
                            .foregroundColor(.purple)
                            .font(.body.bold())
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use AI for analysis")
                                .font(.caption.bold())
                            Text("Spend AI credits on pattern analysis & rule induction")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $manager.useAIForLearnings)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(12)
                    .liquidGlassCard(cornerRadius: 10)
                    
                    HStack(spacing: 12) {
                        Image(systemName: "pause.circle")
                            .foregroundColor(.orange)
                            .font(.body.bold())
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Session-based Learning")
                                .font(.caption.bold())
                            Text("Temporarily pause learning from file moves")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !manager.sessionLearningPaused },
                            set: { manager.sessionLearningPaused = !$0 }
                        ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    .padding(12)
                    .liquidGlassCard(cornerRadius: 10)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            HapticFeedbackManager.shared.tap()
                            showingWithdrawConfirmation = true
                        }) {
                            Label("Pause Learning", systemImage: "pause.circle.fill")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityLabel("Pause learning")
                        .accessibilityHint("Learning will stop but data is preserved")
                        
                        Button(role: .destructive, action: {
                            HapticFeedbackManager.shared.error()
                            showingDeleteConfirmation = true
                        }) {
                            Label("Delete All Data", systemImage: "trash.fill")
                                .font(.caption.bold())
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .accessibilityLabel("Delete all learning data")
                        .accessibilityHint("Permanently deletes all learning data")
                    }
                }
                .padding(16)
                .liquidGlassCard(cornerRadius: 12)
            }
            .padding(16)
            .liquidGlassCard(cornerRadius: 16)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SortyDesignSystem.Colors.primary, SortyDesignSystem.Colors.primary.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Learning Progress")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
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
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Learning Influence")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("Organization Personalization")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.bottom, 10)

            Divider()
                .opacity(0.4)
                .padding(.bottom, 14)

            VStack(alignment: .leading, spacing: 16) {
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
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.blue)
                            Text("Higher confidence")
                                .font(.caption2.bold())
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Text("Full personalization")
                                .font(.caption2.bold())
                                .fixedSize(horizontal: true, vertical: false)
                            Image(systemName: "wand.and.stars")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
                
                Divider()
                    .opacity(0.3)
                
                Text("Current: \(Int(manager.learningStrength * 100))% – \(strengthDescription)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(14)
        .frame(width: 320)
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
    var onStartHoning: (() -> Void)?
    
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
                
                if impact.correctionsAfterAI > 0 {
                    HighCorrectionRateInsight(impact: impact, manager: manager, onStartHoning: onStartHoning)
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
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
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
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
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
        .padding(12)
        .liquidGlassCard(cornerRadius: 12)
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
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Text(value)
                .font(.title3.bold())
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .liquidGlassCard(cornerRadius: 12)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
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
            
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: 12)
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
        .accessibilityElement(children: .contain)
    }
}

struct RuleRow: View {
    let rule: InferredRule
    @ObservedObject var manager: LearningsManager
    @State private var showingEvidence = false
    
    private var confidenceColor: Color {
        if rule.failureRate > 0.3 { return .red }
        if rule.failureRate > 0.15 { return .orange }
        return .green
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.body.bold())
                    .foregroundColor(rule.isEnabled ? confidenceColor : .gray)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.explanation)
                        .font(.subheadline.bold())
                        .foregroundColor(rule.isEnabled ? .primary : .secondary)
                    
                    HStack(spacing: 8) {
                        Text("\(rule.successCount) SUCCESS")
                            .font(.caption2.bold())
                            .foregroundColor(.green)
                        if rule.failureCount > 0 {
                            Text("\(rule.failureCount) CORRECTION")
                                .font(.caption2.bold())
                                .foregroundColor(.orange)
                        }
                        
                        // Scope badge
                        if case .folder = rule.scope {
                            Text(rule.scope.displayName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        } else if case .activePersona = rule.scope {
                            Text(rule.scope.displayName)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                Spacer()
                
                // Evidence button
                if rule.evidenceDescription != nil || !rule.evidenceIds.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showingEvidence.toggle()
                        }
                        HapticFeedbackManager.shared.tap()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show rule evidence")
                }
                
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
            
            // Evidence lineage panel
            if showingEvidence, let evidence = rule.evidenceDescription {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    Text(evidence)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 36)
                .padding(.vertical, 8)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.explanation). \(rule.scope.displayName). Priority \(rule.priority) percent. \(rule.successCount) successes, \(rule.failureCount) failures. \(rule.isEnabled ? "Enabled" : "Disabled")")
        .accessibilityHint("Toggle to enable or disable this rule")
    }
}

struct RuleSuggestionsSection: View {
    let rules: [InferredRule]
    @ObservedObject var manager: LearningsManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.headline)
                    .foregroundColor(.orange)
                Text("Rule Suggestions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                
                Spacer()
                
                Text("\(rules.count) PENDING")
                    .font(.caption2.bold())
                    .foregroundColor(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }
            
            Text("These rules were inferred with lower confidence. Review and approve or reject them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            VStack(spacing: 12) {
                ForEach(rules) { rule in
                    PendingRuleRow(rule: rule, manager: manager)
                }
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Rule suggestions: \(rules.count) pending")
    }
}

struct PendingRuleRow: View {
    let rule: InferredRule
    @ObservedObject var manager: LearningsManager
    @State private var showingEvidence = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.body.bold())
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.explanation)
                        .font(.subheadline.bold())
                    
                    HStack(spacing: 8) {
                        Text(rule.scope.displayName.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                        
                        if let confidence = rule.initialConfidence {
                            Text("CONFIDENCE: \(confidence.rawValue.uppercased())")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(confidence == .high ? .green : (confidence == .medium ? .orange : .red))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                Spacer()
            }
            
            // Evidence lineage
            if let evidence = rule.evidenceDescription {
                Button {
                    withAnimation { showingEvidence.toggle() }
                    HapticFeedbackManager.shared.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.caption2)
                        Text(showingEvidence ? "Hide Evidence" : "Show Evidence")
                            .font(.caption2.bold())
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                
                if showingEvidence {
                    Text(evidence)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.05))
                        .cornerRadius(8)
                        .transition(.opacity)
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task {
                        HapticFeedbackManager.shared.success()
                        await manager.approveRule(ruleId: rule.id)
                    }
                } label: {
                    Label("Accept", systemImage: "checkmark.circle.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)
                
                Button {
                    Task {
                        HapticFeedbackManager.shared.error()
                        await manager.rejectRule(ruleId: rule.id)
                    }
                } label: {
                    Label("Reject", systemImage: "xmark.circle.fill")
                        .font(.caption.bold())
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suggested rule: \(rule.explanation)")
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
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
        .accessibilityElement(children: .contain)
    }
}

struct AccessibleActivityRow: View {
    let change: DirectoryChange
    
    private var fileName: String {
        URL(fileURLWithPath: change.originalPath).lastPathComponent
    }
    
    private var fileURL: URL {
        URL(fileURLWithPath: change.newPath)
    }
    
    private var srcFolder: String {
        URL(fileURLWithPath: change.originalPath).deletingLastPathComponent().lastPathComponent
    }
    
    private var dstFolder: String {
        URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                FileThumbnailView(url: fileURL, size: CGSize(width: 28, height: 28))
                
                if change.wasAIOrganized {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                        .padding(2)
                        .background(Circle().fill(.blue))
                        .offset(x: 4, y: 4)
                }
            }
            .frame(width: 28)
            
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

struct AccessibleRejectionRow: View {
    let rejection: LabeledExample
    
    private var fileName: String {
        URL(fileURLWithPath: rejection.srcPath).lastPathComponent
    }
    
    private var folderName: String {
        URL(fileURLWithPath: rejection.srcPath).deletingLastPathComponent().lastPathComponent
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.circle.fill")
                .font(.body.bold())
                .foregroundColor(.red)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(fileName)
                    .font(.headline)
                    .lineLimit(1)
                Text(folderName.isEmpty ? "Removed from original location" : "From \(folderName)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Text(rejection.timestamp, style: .relative)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fileName) rejected after organization")
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
            .padding(16)
            .liquidGlassCard(cornerRadius: 16)
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

// MARK: - Organization Breakdown Card

struct OrganizationBreakdownCard: View {
    @ObservedObject var manager: LearningsManager
    
    private var impact: LearningsImpactSummary? {
        manager.computeImpactSummary()
    }
    
    var body: some View {
        if let impact = impact, (impact.acceptedOrganizations + impact.rejectedOrganizations + impact.cancelledOrganizations + impact.regeneratedOrganizations) > 0 {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "chart.pie.fill")
                        .font(.headline)
                        .foregroundColor(.accentColor)
                    Text("Organization Outcomes")
                        .font(.title3.bold())
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    BreakdownMetric(
                        value: "\(impact.acceptedOrganizations)",
                        label: "Accepted",
                        icon: "checkmark.circle.fill",
                        color: .green
                    )
                    BreakdownMetric(
                        value: "\(impact.rejectedOrganizations)",
                        label: "Rejected",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                    BreakdownMetric(
                        value: "\(impact.cancelledOrganizations)",
                        label: "Cancelled",
                        icon: "xmark.octagon.fill",
                        color: .orange
                    )
                    BreakdownMetric(
                        value: "\(impact.regeneratedOrganizations)",
                        label: "Regenerated",
                        icon: "arrow.triangle.2.circlepath",
                        color: .blue
                    )
                }
            }
            .padding(16)
            .liquidGlassCard(cornerRadius: 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Organization outcomes breakdown")
        }
    }
}

struct BreakdownMetric: View {
    let value: String
    let label: String
    let icon: String
    let color: Color
    
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
        .padding(.vertical, 12)
        .liquidGlassCard(cornerRadius: 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Empty State View (matches HistoryEmptyStateView pattern)

struct LearningsEmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 96, height: 96)
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
            }
            .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("No Activity Yet")
                    .font(.title2.bold())
                
                Text("Your organization activity will appear here as you use the app.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 350)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No activity yet. Your organization activity will appear here.")
    }
}

// MARK: - Cancelled Row

struct AccessibleCancelledRow: View {
    let cancelled: CancelledOrganization
    
    private var folderName: String {
        URL(fileURLWithPath: cancelled.folderPath).lastPathComponent
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "xmark.octagon.fill")
                .font(.body.bold())
                .foregroundColor(.orange)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(folderName)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text("\(cancelled.fileCount) files")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                    Text("at \(cancelled.cancelledAtStage)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(cancelled.timestamp, style: .relative)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folderName) cancelled at \(cancelled.cancelledAtStage), \(cancelled.fileCount) files")
    }
}

// MARK: - Regenerated Row

struct AccessibleRegeneratedRow: View {
    let regenerated: RegeneratedOrganization
    
    private var folderName: String {
        URL(fileURLWithPath: regenerated.folderPath).lastPathComponent
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.body.bold())
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(folderName)
                    .font(.headline)
                    .lineLimit(1)
                if let instruction = regenerated.guidingInstruction {
                    Text(instruction)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Regenerated \(regenerated.regenerationCount) time\(regenerated.regenerationCount == 1 ? "" : "s")")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Text(regenerated.timestamp, style: .relative)
                .font(.caption2.bold())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folderName) regenerated\(regenerated.guidingInstruction.map { ", instruction: \($0)" } ?? "")")
    }
}

// MARK: - High Correction Rate Insight

enum InsightAction {
    case addSteering(String)
    case startHoning
    case none
}

struct ActionableInsight: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let detail: String
    let action: InsightAction
    let actionLabel: String?
    
    init(icon: String, color: Color, title: String, detail: String, action: InsightAction = .none, actionLabel: String? = nil) {
        self.icon = icon
        self.color = color
        self.title = title
        self.detail = detail
        self.action = action
        self.actionLabel = actionLabel
    }
}

struct HighCorrectionRateInsight: View {
    let impact: LearningsImpactSummary
    @ObservedObject var manager: LearningsManager
    var onStartHoning: (() -> Void)?
    
    private var adjustmentCount: Int {
        impact.correctionsAfterAI
    }
    
    private var badgeText: String {
        if adjustmentCount == 0 { return "No adjustments" }
        return "\(adjustmentCount) adjustment\(adjustmentCount == 1 ? "" : "s")"
    }
    
    private var badgeColor: Color {
        if adjustmentCount == 0 { return .green }
        if adjustmentCount <= 5 { return .orange }
        return .red
    }
    
    private var insights: [ActionableInsight] {
        var results: [ActionableInsight] = []
        
        if let profile = manager.currentProfile {
            let correctionsByExtension = Dictionary(grouping: profile.postOrganizationChanges.filter { $0.wasAIOrganized }) { change in
                URL(fileURLWithPath: change.newPath).pathExtension.lowercased()
            }
            if let topType = correctionsByExtension.max(by: { $0.value.count < $1.value.count }),
               topType.value.count >= 3 {
                let suggestedInstruction = "Keep .\(topType.key) files in their current location"
                results.append(ActionableInsight(
                    icon: "doc.badge.arrow.up",
                    color: .blue,
                    title: ".\(topType.key) files frequently corrected (\(topType.value.count)×)",
                    detail: "Add a steering instruction to improve how these files are handled.",
                    action: .addSteering(suggestedInstruction),
                    actionLabel: "Add Instruction"
                ))
            }
            
            if impact.reverts > 2 && impact.revertRate > 0.3 {
                results.append(ActionableInsight(
                    icon: "arrow.uturn.backward.circle",
                    color: .orange,
                    title: "Frequent full reverts (\(impact.reverts) of \(impact.runsWithLearnings) runs)",
                    detail: "Entire organizations are being undone. A honing session can help the AI understand your preferences.",
                    action: .startHoning,
                    actionLabel: "Start Honing"
                ))
            }
            
            let destinationFolders = profile.postOrganizationChanges.compactMap { change -> String? in
                let folder = URL(fileURLWithPath: change.newPath).deletingLastPathComponent().lastPathComponent
                return folder.isEmpty ? nil : folder
            }
            let folderCounts = Dictionary(grouping: destinationFolders) { $0 }.mapValues { $0.count }
            if let topFolder = folderCounts.max(by: { $0.value < $1.value }),
               topFolder.value >= 3 {
                let suggestedInstruction = "Prefer placing files in \(topFolder.key) when appropriate"
                results.append(ActionableInsight(
                    icon: "folder.badge.questionmark",
                    color: .purple,
                    title: "Files frequently moved to \"\(topFolder.key)\" (\(topFolder.value)×)",
                    detail: "You often move files here after organization. Add this as a preference.",
                    action: .addSteering(suggestedInstruction),
                    actionLabel: "Add Preference"
                ))
            }
            
            let cancelledCount = profile.cancelledOrganizations.count
            let regeneratedCount = profile.regeneratedOrganizations.count
            if cancelledCount + regeneratedCount > 3 {
                results.append(ActionableInsight(
                    icon: "arrow.triangle.2.circlepath",
                    color: .red,
                    title: "\(cancelledCount + regeneratedCount) cancelled or regenerated plans",
                    detail: "The AI needs more context about your preferences.",
                    action: .startHoning,
                    actionLabel: "Refine Preferences"
                ))
            }
        }
        
        if results.isEmpty {
            results.append(ActionableInsight(
                icon: "lightbulb",
                color: .orange,
                title: "\(adjustmentCount) file\(adjustmentCount == 1 ? "" : "s") adjusted after AI organization",
                detail: "Run a Honing Session to teach your preferences and reduce future adjustments.",
                action: .startHoning,
                actionLabel: "Start Honing"
            ))
        }
        
        return results
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Improvement Opportunities")
                    .font(.subheadline.bold())
                Spacer()
                Text(badgeText)
                    .font(.caption.bold())
                    .foregroundColor(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.12))
                    .clipShape(Capsule())
                    .help("Number of files you moved or corrected after AI organization")
            }
            
            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: insight.icon)
                        .font(.caption)
                        .foregroundColor(insight.color)
                        .frame(width: 20, height: 20)
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(insight.title)
                            .font(.caption.bold())
                        Text(insight.detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    Spacer()
                    
                    if let actionLabel = insight.actionLabel {
                        Button(action: { performAction(insight.action) }) {
                            Text(actionLabel)
                                .font(.caption2.bold())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Improvement opportunities")
    }
    
    private func performAction(_ action: InsightAction) {
        HapticFeedbackManager.shared.tap()
        switch action {
        case .addSteering(let prompt):
            manager.recordSteeringPrompt(prompt, folderPath: nil, sessionId: nil)
        case .startHoning:
            onStartHoning?()
        case .none:
            break
        }
    }
}

struct AddExclusionView: View {
    @ObservedObject var manager: LearningsManager
    @State private var newExclusion = ""
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
                HapticFeedbackManager.shared.tap()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text("Add Learning Exclusion")
                        .font(.caption.bold())
                }
            }
            .buttonStyle(.plain)
            
            if isExpanded {
                HStack(spacing: 8) {
                    TextField("Folder name or path pattern...", text: $newExclusion)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                    
                    Button {
                        guard !newExclusion.isEmpty else { return }
                        Task {
                            HapticFeedbackManager.shared.success()
                            await manager.addLearningExclusion(newExclusion)
                            newExclusion = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(newExclusion.isEmpty)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                
                Text("Example: \"Temp\", \"/Downloads/Temp\", or a folder name")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .liquidGlassCard(cornerRadius: 16)
    }
}

#Preview {
    LearningsView()
}
