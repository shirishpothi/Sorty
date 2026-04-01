//
//  LearningsView.swift
//  Sorty
//
//  Passive Learning Dashboard — single scrollable page
//

import SwiftUI
import LocalAuthentication
import AppKit
import UniformTypeIdentifiers

// MARK: - Liquid Glass Styles (used by LearningsHoningView)

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
    @EnvironmentObject var exclusionRules: ExclusionRulesManager

    @State private var showingHoningSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingWithdrawConfirmation = false
    @State private var activeFileImporter: ActiveFileImporter?
    @State private var isShowingFileImporter = false
    @State private var showLearningsModelPicker = false
    @State private var advancedExpanded = false
    @State private var isQuickRefreshingLearnings = false
    @State private var showingStatusPopover = false
    @State private var hoveredStatusPopoverAction: StatusPopoverAction?

    private enum StatusPopoverAction {
        case pauseResume
        case withdrawConsent
        case deleteData
    }


    private enum ActiveFileImporter: Int, Identifiable {
        case modelDirectories
        case learningExclusions
        case learningsProfile

        var id: Int { rawValue }

        var allowedContentTypes: [UTType] {
            switch self {
            case .modelDirectories: return [.folder]
            case .learningExclusions: return [.folder]
            case .learningsProfile: return [UTType(filenameExtension: "learnings", conformingTo: .json) ?? .json]
            }
        }

        var allowsMultipleSelection: Bool {
            switch self {
            case .modelDirectories: return true
            case .learningExclusions: return true
            case .learningsProfile: return false
            }
        }
    }

    var body: some View {
        ZStack {
            if manager.isLocked {
                authenticationGateView
                    .transition(.opacity)
            } else if !manager.consentManager.hasConsented {
                onboardingView
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                dashboardView
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: manager.isLocked)
        .animation(.easeInOut(duration: 0.36), value: manager.consentManager.hasConsented)
        .frame(minWidth: 700, minHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Learnings Dashboard")
        .onAppear {
            Task { await manager.unlock() }
            if settingsViewModel.availableModels.isEmpty {
                settingsViewModel.updateAvailableModels()
            }
            exclusionRules.removeLegacyLearningsLinkedRules()
        }
        .navigationTitle("Learnings")
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
                .background(Color.blue.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 24))
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
            .buttonStyle(.onboardingPill)
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
                .background(Color.purple.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 24))
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
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
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
                      HapticFeedbackManager.shared.light()
                      await manager.grantConsent()
                      manager.completeInitialSetup()
                      HapticFeedbackManager.shared.success()
                  }
            }) {
                Label("Enable Learning", systemImage: "checkmark.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.onboardingPill)
            .keyboardShortcut(.return)
              .onHover { hovering in
                  if hovering {
                      HapticFeedbackManager.shared.selection()
                  }
              }
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
                Text(title).font(.headline)
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }

    // MARK: - Dashboard

    private var dashboardView: some View {
        VStack(spacing: 0) {
            dashboardHeader
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    whatSortyHasLearnedSection
                        .animatedAppearance(delay: 0.05)

                    recentActivitySection
                        .animatedAppearance(delay: 0.10)

                    settingsSection
                        .animatedAppearance(delay: 0.15)

                    advancedSection
                        .animatedAppearance(delay: 0.20)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 32)
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
        .modelSelectionOverlay(
            isPresented: $showLearningsModelPicker,
            currentProvider: usesDedicatedLearningsModel
                ? (manager.learningsModelSelection?.provider ?? settingsViewModel.config.provider)
                : settingsViewModel.config.provider,
            currentModel: usesDedicatedLearningsModel
                ? effectiveLearningsModel
                : settingsViewModel.config.model,
            onSelect: { provider, model in
                HapticFeedbackManager.shared.selection()
                if provider == settingsViewModel.config.provider && model == settingsViewModel.config.model {
                    manager.clearLearningsModelOverride()
                } else {
                    manager.setLearningsModelOverride(provider: provider, model: model)
                }
            }
        )
        .alert("Delete All Learning Data?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
              Button("Delete", role: .destructive) {
                  HapticFeedbackManager.shared.error()
                  Task {
                      let didClear = await manager.clearAllData()
                      if didClear {
                          HapticFeedbackManager.shared.success()
                          withAnimation(.spring()) {
                              appState.hasCompletedOnboarding = false
                          }
                      } else {
                          HapticFeedbackManager.shared.error()
                      }
                  }
              }
        } message: {
            Text("This will permanently delete all your learning data and preferences. This cannot be undone.")
        }
        .alert("Withdraw Consent?", isPresented: $showingWithdrawConfirmation) {
            Button("Cancel", role: .cancel) { }
              Button("Withdraw", role: .destructive) {
                  HapticFeedbackManager.shared.light()
                  Task {
                      await manager.withdrawConsent()
                      HapticFeedbackManager.shared.success()
                  }
              }
        } message: {
            Text("Learning will stop but your existing data will be preserved. You can re-enable learning later.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .startHoningSession)) { _ in
            if !manager.isLocked && manager.consentManager.hasConsented {
                showingHoningSheet = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .pauseLearning)) { _ in
            showingWithdrawConfirmation = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportLearningsProfile)) { _ in
            exportProfile()
        }
        .onChange(of: manager.showingImportPicker) { showing in
            guard showing else { return }
            manager.showingImportPicker = false
            activeFileImporter = .learningsProfile
            isShowingFileImporter = true
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: activeFileImporter?.allowedContentTypes ?? [.data],
            allowsMultipleSelection: activeFileImporter?.allowsMultipleSelection ?? false
        ) { result in
            guard let importer = activeFileImporter else { return }
            activeFileImporter = nil
            isShowingFileImporter = false
            switch importer {
            case .modelDirectories: handleModelDirectoryImport(result)
            case .learningExclusions: handleLearningExclusionImport(result)
            case .learningsProfile: handleProfileImport(result)
            }
        }
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
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

                HStack(spacing: 10) {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        showingHoningSheet = true
                    } label: {
                        Label("Refine", systemImage: "wand.and.stars")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .onHover { hovering in
                        if hovering {
                            HapticFeedbackManager.shared.selection()
                        }
                    }
    
                    Button {
                        toggleSessionLearningPaused()
                    } label: {
                        Label(
                            manager.sessionLearningPaused ? "Resume" : "Pause",
                            systemImage: manager.sessionLearningPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.caption.bold())
                    }
                    .buttonStyle(.tintedPill(manager.sessionLearningPaused ? .green : .red, size: .small))
                      .onHover { hovering in
                          if hovering {
                              HapticFeedbackManager.shared.selection()
                          }
                      }
    
                    Menu {
                        Section("Learnings Controls") {
                            Button {
                                restoreLearningsDefaults()
                            } label: {
                                Label("Reset Learnings Defaults", systemImage: "arrow.uturn.backward")
                            }

                            Button {
                                presentLearningsModelPicker()
                            } label: {
                                Label("Model Settings…", systemImage: "gearshape")
                            }

                            Button {
                                refreshLearningsInsights()
                            } label: {
                                Label(isQuickRefreshingLearnings ? "Refreshing…" : "Refresh Learnings", systemImage: "arrow.clockwise")
                            }
                            .disabled(isQuickRefreshingLearnings)
                        }

                        Divider()

                        Button {
                            exportProfile()
                        } label: {
                            Label("Export Profile…", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            presentFileImporter(.learningsProfile)
                        } label: {
                            Label("Import Profile…", systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button(role: .destructive) {
                            HapticFeedbackManager.shared.error()
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete All Data…", systemImage: "trash")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticFeedbackManager.shared.light()
                    })
                    .frame(width: 34)
                    .accessibilityLabel("Learnings settings")
                    .onHover { hovering in
                        if hovering {
                            HapticFeedbackManager.shared.selection()
                        }
                    }
    
                    statusBadge
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Learnings quick controls")
            }

        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Learnings header")
    }

    private func restoreLearningsDefaults() {
        HapticFeedbackManager.shared.tap()
        manager.sessionLearningPaused = false
        if advancedExpanded {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                advancedExpanded = false
            }
        }
        manager.clearLearningsModelOverride()
        HapticFeedbackManager.shared.success()
    }

    private func presentLearningsModelPicker() {
        HapticFeedbackManager.shared.tap()
        showLearningsModelPicker = true
    }

    private func refreshLearningsInsights() {
        guard !isQuickRefreshingLearnings else { return }

        HapticFeedbackManager.shared.tap()
        isQuickRefreshingLearnings = true

        Task {
            manager.configure(with: settingsViewModel.config)
            await manager.synthesizeLearnings()

            await MainActor.run {
                isQuickRefreshingLearnings = false

                if let error = manager.error, !error.isEmpty {
                    HapticFeedbackManager.shared.error()
                } else {
                    HapticFeedbackManager.shared.success()
                }
            }
        }
    }

    private func toggleSessionLearningPaused() {
        HapticFeedbackManager.shared.light()
        let isPausing = !manager.sessionLearningPaused
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            manager.sessionLearningPaused.toggle()
        }
        if isPausing {
            HapticFeedbackManager.shared.selection()
        } else {
            HapticFeedbackManager.shared.success()
        }
    }
    private var statusBadge: some View {
        Button {
            HapticFeedbackManager.shared.light()
            withAnimation(.easeInOut(duration: 0.18)) {
                showingStatusPopover.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.caption.bold())
                    .foregroundColor(manager.consentManager.hasConsented ? .primary : .secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
        .popover(isPresented: $showingStatusPopover, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    showingStatusPopover = false
                    toggleSessionLearningPaused()
                } label: {
                    Label(
                        manager.sessionLearningPaused ? "Resume Learning" : "Pause Learning",
                        systemImage: manager.sessionLearningPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.subheadline)
                }
                .buttonStyle(.plain)
                .frame(width: 204, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(hoveredStatusPopoverAction == .pauseResume ? 0.12 : 0.0))
                )
                .offset(x: hoveredStatusPopoverAction == .pauseResume ? 1 : 0)
                .animation(.easeInOut(duration: 0.14), value: hoveredStatusPopoverAction)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        hoveredStatusPopoverAction = hovering ? .pauseResume : nil
                    }
                    if hovering {
                        HapticFeedbackManager.shared.tap()
                    }
                }

                Divider()

                Button {
                    showingStatusPopover = false
                    HapticFeedbackManager.shared.light()
                    showingWithdrawConfirmation = true
                } label: {
                    Label("Withdraw Consent", systemImage: "hand.raised")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .frame(width: 204, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(hoveredStatusPopoverAction == .withdrawConsent ? 0.12 : 0.0))
                )
                .offset(x: hoveredStatusPopoverAction == .withdrawConsent ? 1 : 0)
                .animation(.easeInOut(duration: 0.14), value: hoveredStatusPopoverAction)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        hoveredStatusPopoverAction = hovering ? .withdrawConsent : nil
                    }
                    if hovering {
                        HapticFeedbackManager.shared.tap()
                    }
                }

                Divider()

                Button(role: .destructive) {
                    showingStatusPopover = false
                    HapticFeedbackManager.shared.error()
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete All Data", systemImage: "trash")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .frame(width: 204, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(hoveredStatusPopoverAction == .deleteData ? 0.12 : 0.0))
                )
                .offset(x: hoveredStatusPopoverAction == .deleteData ? 1 : 0)
                .animation(.easeInOut(duration: 0.14), value: hoveredStatusPopoverAction)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.14)) {
                        hoveredStatusPopoverAction = hovering ? .deleteData : nil
                    }
                    if hovering {
                        HapticFeedbackManager.shared.tap()
                    }
                }
            }
            .padding(8)
            .frame(width: 220)
              .onDisappear {
                  hoveredStatusPopoverAction = nil
              }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Learning status quick actions")
            .systemLiquidGlassPopover(cornerRadius: 12)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Learning status: \(statusLabel). Open quick actions")
        .accessibilityAddTraits(.isButton)
    }

    private var statusColor: Color {
        if manager.sessionLearningPaused { return .orange }
        return manager.consentManager.hasConsented ? .green : .gray
    }

    private var statusLabel: String {
        if manager.sessionLearningPaused { return "Paused" }
        return manager.consentManager.hasConsented ? "Active" : "Inactive"
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(heroAccentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: heroIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(heroAccentColor)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(heroTitle)
                        .font(.headline)
                    if let subtitle = heroSubtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let error = manager.error, !error.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Learning status summary")
    }

    private var heroIcon: String {
        guard let profile = manager.currentProfile, profile.sessions.count > 0 else {
            return "sparkles"
        }
        let recentSessions = profile.sessions.prefix(5)
        let recentClean = recentSessions.filter { $0.acceptedWithoutCorrections }.count
        if recentClean == recentSessions.count && recentSessions.count >= 2 {
            return "checkmark.seal.fill"
        }
        return "brain.head.profile"
    }

    private var heroAccentColor: Color {
        guard let profile = manager.currentProfile, profile.sessions.count > 0 else {
            return .blue
        }
        let recentSessions = profile.sessions.prefix(5)
        let recentClean = recentSessions.filter { $0.acceptedWithoutCorrections }.count
        if recentClean == recentSessions.count && recentSessions.count >= 2 {
            return .green
        }
        return .purple
    }

    private var heroTitle: String {
        guard let profile = manager.currentProfile else {
            return "Ready to Learn"
        }
        let sessionCount = profile.sessions.count
        guard sessionCount > 0 else {
            return "Ready to Learn"
        }
        return "Learned from \(sessionCount) session\(sessionCount == 1 ? "" : "s")"
    }

    private var heroSubtitle: String? {
        guard let profile = manager.currentProfile else {
            return "Organize some folders and Sorty will pick up your preferences."
        }
        let sessionCount = profile.sessions.count
        guard sessionCount > 0 else {
            return "Organize some folders and Sorty will pick up your preferences."
        }
        let recentSessions = profile.sessions.prefix(5)
        let recentClean = recentSessions.filter { $0.acceptedWithoutCorrections }.count
        let ruleCount = profile.inferredRules.filter { $0.isEnabled }.count

        if recentClean == recentSessions.count && recentSessions.count >= 2 {
            return "Your last \(recentSessions.count) runs needed no corrections."
        } else if ruleCount > 0 {
            return "\(ruleCount) learned pattern\(ruleCount == 1 ? " is" : "s are") actively applied."
        }
        return nil
    }

    // MARK: - What Sorty Has Learned

    private var whatSortyHasLearnedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("What Sorty Has Learned")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    HapticFeedbackManager.shared.tap()
                    showingHoningSheet = true
                } label: {
                    Label("Refine", systemImage: "wand.and.stars")
                        .font(.caption.bold())
                }
                .buttonStyle(.onboardingPill(size: .small))
                .onHover { hovering in
                    if hovering {
                        HapticFeedbackManager.shared.selection()
                    }
                }
                .accessibilityLabel("Refine preferences with a honing session")
            }

            if let profile = manager.currentProfile {
                let topRules = profile.inferredRules
                    .filter { $0.isEnabled }
                    .sorted { $0.priority > $1.priority }
                    .prefix(5)

                if topRules.isEmpty {
                    emptyLearningsPlaceholder
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(topRules.enumerated()), id: \.element.id) { index, rule in
                            LearningInsightRow(rule: rule, manager: manager)
                                .animatedAppearance(delay: Double(index) * 0.05)
                            if index < topRules.count - 1 {
                                Divider().padding(.leading, 36)
                            }
                        }
                    }
                }
            } else {
                emptyLearningsPlaceholder
            }
        }
    }

    private var emptyLearningsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
                .opacity(0.5)
                .accessibilityHidden(true)
            Text("No patterns learned yet")
                .font(.subheadline.bold())
            Text("Organize some folders, and Sorty will pick up your preferences from corrections and feedback.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No patterns learned yet. Organize folders to start learning.")
    }

    // MARK: - Recent Activity (Session Timeline)

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if let profile = manager.currentProfile, !profile.sessions.isEmpty {
                let recentSessions = Array(profile.sessions.prefix(10))
                VStack(spacing: 0) {
                    ForEach(Array(recentSessions.enumerated()), id: \.element.id) { index, session in
                        SessionTimelineRow(session: session)
                            .animatedAppearance(delay: Double(index) * 0.04)
                        if index < recentSessions.count - 1 {
                            Divider().padding(.leading, 36)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                        .opacity(0.5)
                        .accessibilityHidden(true)
                    Text("No activity yet")
                        .font(.subheadline.bold())
                    Text("Your organization activity will appear here as you use the app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("No activity yet.")
            }
        }
    }

    // MARK: - Settings (Inline)

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                settingsToggleRow(
                    icon: "pause.circle",
                    iconColor: .orange,
                    title: "Pause Learning",
                    subtitle: "Temporarily stop collecting signals",
                    isOn: Binding(
                        get: { manager.sessionLearningPaused },
                        set: { manager.sessionLearningPaused = $0 }
                    )
                )

                Divider().padding(.leading, 40)

                settingsToggleRow(
                    icon: "cpu",
                    iconColor: .purple,
                    title: "Use AI for Analysis",
                    subtitle: "Spend AI credits on pattern analysis",
                    isOn: $manager.useAIForLearnings
                )

                Divider().padding(.leading, 40)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.blue)
                            .font(.body.bold())
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Learnings Model")
                                .font(.subheadline)
                            Text(usesDedicatedLearningsModel
                                 ? "Dedicated to learnings analysis"
                                 : "Using the same model as organization")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            HapticFeedbackManager.shared.tap()
                            if usesDedicatedLearningsModel {
                                manager.clearLearningsModelOverride()
                            }
                        } label: {
                            Text(usesDedicatedLearningsModel ? "Reset to Default" : "Using Default")
                                .font(.caption2)
                                .foregroundStyle(usesDedicatedLearningsModel ? .blue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(!usesDedicatedLearningsModel)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)

                    ModelSelectorRow(
                        provider: usesDedicatedLearningsModel
                            ? (manager.learningsModelSelection?.provider ?? settingsViewModel.config.provider)
                            : settingsViewModel.config.provider,
                        model: usesDedicatedLearningsModel
                            ? effectiveLearningsModel
                            : settingsViewModel.config.model,
                        onTap: {
                            HapticFeedbackManager.shared.tap()
                            showLearningsModelPicker = true
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .modelSelectorTriggerBounds()
                }

                Divider().padding(.leading, 40)

                HStack(spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundColor(.blue)
                        .font(.body.bold())
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Data Retention")
                            .font(.subheadline)
                        Text("How long to keep learning data")
                            .font(.caption)
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
                    .labelsHidden()
                    .onChange(of: manager.dataRetentionDays) { _ in
                        HapticFeedbackManager.shared.selection()
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .background(Color.secondary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button(action: {
                    HapticFeedbackManager.shared.tap()
                    showingWithdrawConfirmation = true
                }) {
                    Label("Withdraw Consent", systemImage: "hand.raised")
                        .font(.caption.bold())
                }
                .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                  .onHover { hovering in
                      if hovering {
                          HapticFeedbackManager.shared.selection()
                      }
                  }
                .accessibilityHint("Learning will stop but data is preserved")

                Button(role: .destructive, action: {
                    HapticFeedbackManager.shared.error()
                    showingDeleteConfirmation = true
                }) {
                    Label("Delete All Data", systemImage: "trash")
                        .font(.caption.bold())
                }
                .buttonStyle(.tintedPill(.red, size: .small))
                  .onHover { hovering in
                      if hovering {
                          HapticFeedbackManager.shared.selection()
                      }
                  }
                .accessibilityHint("Permanently deletes all learning data")
            }
        }
    }

    private func settingsToggleRow(icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.body.bold())
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    // MARK: - Advanced

    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    advancedExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Advanced")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(advancedExpanded ? 90 : 0))
                        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: advancedExpanded)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Advanced settings")
            .accessibilityHint(advancedExpanded ? "Collapse" : "Expand")

            if advancedExpanded {
                VStack(alignment: .leading, spacing: 24) {
                    referenceDirectoriesSection
                        .animatedAppearance(delay: 0.03)
                    learningExclusionsSection
                        .animatedAppearance(delay: 0.08)
                }
                .padding(.top, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                .clipped()
            }
        }
    }

    private var referenceDirectoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reference Directories")
                        .font(.subheadline.bold())
                    Text("Well-organized folders used as structure examples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !manager.modelDirectories.isEmpty {
                    Text("\(manager.modelDirectories.filter(\.isEnabled).count) active")
                        .font(.caption.bold())
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.teal.opacity(0.1))
                        .clipShape(Capsule())
                        .contentTransition(.numericText())
                    Button {
                        presentFileImporter(.modelDirectories)
                    } label: {
                        Label("Add Folder", systemImage: "plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .accessibilityIdentifier("AddModelDirectoryButton")
                }
            }

            if manager.modelDirectories.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 28))
                        .foregroundStyle(.teal.opacity(0.6))
                        .accessibilityHidden(true)
                    Text("No reference directories")
                        .font(.subheadline.bold())
                    Text("Add well-organized folders as examples. Sorty will learn your preferred naming and structure.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Button {
                        presentFileImporter(.modelDirectories)
                    } label: {
                        Label("Add Folder", systemImage: "plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .accessibilityIdentifier("EmptyStateAddModelDirectoryButton")
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 6) {
                    ForEach(manager.modelDirectories) { directory in
                        ModelDirectoryRow(directory: directory, manager: manager)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 16)
    }

    private var learningExclusionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Learning Exclusions")
                        .font(.subheadline.bold())
                    Text("Folders excluded from learning (still organized)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let patterns = manager.currentProfile?.learningExclusionPatterns, !patterns.isEmpty {
                    Button {
                        presentFileImporter(.learningExclusions)
                    } label: {
                        Label("Add Folder", systemImage: "plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .accessibilityIdentifier("AddLearningExclusionFolderButton")
                }
            }

            if let patterns = manager.currentProfile?.learningExclusionPatterns, !patterns.isEmpty {
                VStack(spacing: 6) {
                    ForEach(patterns, id: \.self) { pattern in
                        LearningExclusionRow(pattern: pattern, manager: manager)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange.opacity(0.6))
                        .accessibilityHidden(true)
                    Text("No folders excluded")
                        .font(.subheadline.bold())
                    Text("Exclude folders that should still be organized but shouldn't teach Sorty anything.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                    Button {
                        presentFileImporter(.learningExclusions)
                    } label: {
                        Label("Exclude Folder", systemImage: "plus")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .accessibilityIdentifier("EmptyStateAddLearningExclusionFolderButton")
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassCard(cornerRadius: 16)
    }

    // MARK: - Helpers

    private var learningsModelOptions: [String] {
        let configured = settingsViewModel.availableModels
        let fallback = settingsViewModel.config.provider.recommendedModels
        let options = configured.isEmpty ? fallback : configured
        let currentModel = settingsViewModel.config.model
        return ([currentModel] + options).orderedDeduplicated()
    }

    private var effectiveLearningsModel: String {
        manager.effectiveAIConfig(from: settingsViewModel.config).model
    }

    private func presentFileImporter(_ importer: ActiveFileImporter) {
        HapticFeedbackManager.shared.tap()
        activeFileImporter = importer
        isShowingFileImporter = true
    }

    private var usesDedicatedLearningsModel: Bool {
        guard let selection = manager.learningsModelSelection else { return false }
        return selection.provider == settingsViewModel.config.provider
    }

    private var learningsModelPickerSelection: Binding<String> {
        Binding(
            get: {
                usesDedicatedLearningsModel ? effectiveLearningsModel : "__main__"
            },
            set: { newValue in
                HapticFeedbackManager.shared.selection()
                if newValue == "__main__" || newValue == settingsViewModel.config.model {
                    manager.clearLearningsModelOverride()
                } else {
                    manager.setLearningsModelOverride(
                        provider: settingsViewModel.config.provider,
                        model: newValue
                    )
                }
            }
        )
    }

    // MARK: - Export / Import

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

    private func handleModelDirectoryImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var addedCount = 0
            for url in urls {
                let hasScopedAccess = url.startAccessingSecurityScopedResource()
                defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }
                if manager.addModelDirectory(url: url) { addedCount += 1 }
            }
            if addedCount > 0 { HapticFeedbackManager.shared.success() } else { HapticFeedbackManager.shared.error() }
        case .failure(let error):
            DebugLogger.log("Model directory import failed: \(error)")
            HapticFeedbackManager.shared.error()
        }
    }

    private func handleLearningExclusionImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                var addedCount = 0
                for url in urls {
                    let hasScopedAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }
                    let before = manager.currentProfile?.learningExclusionPatterns.count ?? 0
                    await manager.addLearningExclusion(url.path)
                    if (manager.currentProfile?.learningExclusionPatterns.count ?? 0) > before {
                        addedCount += 1
                    }
                }
                if addedCount > 0 { HapticFeedbackManager.shared.success() } else { HapticFeedbackManager.shared.error() }
            }
        case .failure(let error):
            DebugLogger.log("Learning exclusion import failed: \(error)")
            HapticFeedbackManager.shared.error()
        }
    }

    private func handleProfileImport(_ result: Result<[URL], Error>) {
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

// MARK: - Learning Insight Row

private struct LearningInsightRow: View {
    let rule: InferredRule
    @ObservedObject var manager: LearningsManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.isEnabled ? "checkmark.circle.fill" : "circle")
                .font(.body.bold())
                .foregroundColor(rule.isEnabled ? confidenceColor : .gray)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.explanation)
                    .font(.subheadline)
                    .foregroundColor(rule.isEnabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    if rule.successCount > 0 {
                        Text("\(rule.successCount) applied")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    if rule.failureCount > 0 {
                        Text("\(rule.failureCount) corrected")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    if case .folder = rule.scope {
                        Text(rule.scope.displayName)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                    }
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
            .scaleEffect(0.7)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(isHovered ? 0.06 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            if hovering { HapticFeedbackManager.shared.selection() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rule.explanation). \(rule.isEnabled ? "Enabled" : "Disabled")")
    }

    private var confidenceColor: Color {
        if rule.failureRate > 0.3 { return .red }
        if rule.failureRate > 0.15 { return .orange }
        return .green
    }
}

// MARK: - Session Timeline Row

private struct SessionTimelineRow: View {
    let session: OrganizationSession
    @State private var isHovered = false
    @State private var isExpanded = false

    private var folderName: String {
        URL(fileURLWithPath: session.folderPath).lastPathComponent
    }

    private var reactionIcon: String {
        switch session.reaction {
        case .accepted: return "checkmark.circle.fill"
        case .corrected: return "pencil.circle.fill"
        case .reverted: return "arrow.uturn.backward.circle.fill"
        case .cancelled: return "xmark.octagon.fill"
        case .regenerated: return "arrow.triangle.2.circlepath"
        case .inProgress: return "clock.fill"
        }
    }

    private var reactionColor: Color {
        switch session.reaction {
        case .accepted: return .green
        case .corrected: return .blue
        case .reverted: return .orange
        case .cancelled: return .red
        case .regenerated: return .purple
        case .inProgress: return .secondary
        }
    }

    private var reactionLabel: String {
        switch session.reaction {
        case .accepted: return "Accepted"
        case .corrected: return "Corrected"
        case .reverted: return "Reverted"
        case .cancelled: return "Cancelled"
        case .regenerated: return "Regenerated"
        case .inProgress: return "In progress"
        }
    }

    private var sessionDate: Date {
        session.completedAt ?? session.timestamp
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                guard !session.events.isEmpty else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
                HapticFeedbackManager.shared.tap()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: reactionIcon)
                        .font(.body.bold())
                        .foregroundColor(reactionColor)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(folderName)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(reactionLabel)
                                .font(.caption2.bold())
                                .foregroundColor(reactionColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(reactionColor.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        HStack(spacing: 8) {
                            if session.filesMoved.count > 0 {
                                Text("\(session.filesMoved.count) files")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !session.userCorrections.isEmpty {
                                Text("\(session.userCorrections.count) correction\(session.userCorrections.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Spacer()

                    Text(sessionDate, style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if !session.events.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(isHovered ? 0.06 : 0))
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
                if hovering { HapticFeedbackManager.shared.selection() }
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(session.events.suffix(5)) { event in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 5, height: 5)
                            Text(event.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer()
                            Text(event.timestamp, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.leading, 48)
                .padding(.trailing, 12)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(folderName), \(reactionLabel), \(sessionDate.formatted(date: .abbreviated, time: .shortened))")
    }
}

// MARK: - Model Directory Row

struct ModelDirectoryRow: View {
    let directory: ReferenceModelDirectory
    @ObservedObject var manager: LearningsManager
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directory.isAccessible ? "folder.fill" : "folder.badge.questionmark")
                .font(.body.bold())
                .foregroundColor(directory.isAccessible ? (directory.isEnabled ? .teal : .secondary) : .orange)
                .frame(width: 24)
                .onTapGesture {
                    guard directory.isAccessible else { return }
                    HapticFeedbackManager.shared.tap()
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(directory.displayName)
                    .font(.subheadline.bold())
                    .foregroundColor(directory.isEnabled ? .primary : .secondary)
                PrivacySensitivePathText(path: directory.path)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if !directory.isAccessible {
                Text("Missing")
                    .font(.caption2.bold())
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .clipShape(Capsule())
            }

            if directory.isAccessible {
                Button {
                    HapticFeedbackManager.shared.tap()
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: directory.path)
                } label: {
                    Label("Open", systemImage: "arrow.up.right.square")
                        .font(.caption.bold())
                }
                .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                .accessibilityIdentifier("OpenModelDirectoryButton_\(directory.id)")
            }

            Toggle("", isOn: Binding(
                get: { directory.isEnabled },
                set: { _ in
                    HapticFeedbackManager.shared.selection()
                    manager.toggleModelDirectory(id: directory.id)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.8)
            .accessibilityIdentifier("ModelDirectoryToggle_\(directory.id)")

            Button {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    manager.removeModelDirectory(id: directory.id)
                }
            } label: {
                Label("Remove", systemImage: "xmark")
                    .font(.caption.bold())
            }
            .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
            .accessibilityLabel("Remove \(directory.displayName)")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(isHovered ? 0.08 : 0.03))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            if hovering { HapticFeedbackManager.shared.selection() }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Learning Exclusion Row

struct LearningExclusionRow: View {
    let pattern: String
    @ObservedObject var manager: LearningsManager
    @EnvironmentObject private var exclusionRules: ExclusionRulesManager
    @State private var isHovered = false

    private var displayName: String {
        let lastComponent = URL(fileURLWithPath: pattern).lastPathComponent
        return lastComponent.isEmpty ? pattern : lastComponent
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye.slash.fill")
                .font(.body.bold())
                .foregroundColor(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.subheadline.bold())
                PrivacySensitivePathText(path: pattern)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                HapticFeedbackManager.shared.tap()
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: pattern)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
                    .font(.caption.bold())
            }
            .buttonStyle(.onboardingPill(isSecondary: true, size: .small))

            Button {
                HapticFeedbackManager.shared.tap()
                Task {
                    await manager.removeLearningExclusion(pattern)
                    exclusionRules.removeLegacyLearningsLinkedRules(matchingLearningPattern: pattern)
                }
            } label: {
                Label("Remove", systemImage: "xmark")
                    .font(.caption.bold())
            }
            .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
            .accessibilityLabel("Remove learnings exclusion for \(displayName)")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(isHovered ? 0.08 : 0.03))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
            if hovering { HapticFeedbackManager.shared.selection() }
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    LearningsView()
}
