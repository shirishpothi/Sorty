//
//  LearningsView.swift
//  Sorty
//
//  Passive Learning Dashboard — single scrollable page
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Liquid Glass Styles

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 12
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content.systemLiquidGlassBackground(cornerRadius: cornerRadius)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingDeleteConfirmation = false
    @State private var showingWithdrawConfirmation = false
    @State private var activeFileImporter: ActiveFileImporter?
    @State private var isShowingFileImporter = false
    @State private var showLearningsModelPicker = false
    @State private var isQuickRefreshingLearnings = false
    @State private var showingStatusPopover = false
    @State private var hoveredStatusPopoverAction: StatusPopoverAction?
    @State private var emptyLearningsHasAppeared = false
    @State private var pendingControlAction: PendingControlAction?

    private enum StatusPopoverAction {
        case pauseResume
        case withdrawConsent
        case deleteData
    }

    private enum PendingControlAction: Equatable {
        case pauseResume
        case withdrawConsent
        case deleteData

        var title: String {
            switch self {
            case .pauseResume: return "Updating Learning"
            case .withdrawConsent: return "Withdrawing Consent"
            case .deleteData: return "Deleting Learnings Data"
            }
        }

        var message: String {
            switch self {
            case .pauseResume: return "Applying your learning collection setting..."
            case .withdrawConsent: return "Stopping future learning and saving the consent change..."
            case .deleteData: return "Removing your learnings profile, consent, model overrides, and local learning settings..."
            }
        }

        var icon: String {
            switch self {
            case .pauseResume: return "pause.circle.fill"
            case .withdrawConsent: return "hand.raised.fill"
            case .deleteData: return "trash.circle.fill"
            }
        }

        var iconColor: Color {
            switch self {
            case .pauseResume: return .orange
            case .withdrawConsent: return .orange
            case .deleteData: return .red
            }
        }
    }

    private enum ActiveFileImporter: Int, Identifiable {
        case modelDirectories
        case learningsProfile

        var id: Int { rawValue }

        var allowedContentTypes: [UTType] {
            switch self {
            case .modelDirectories: return [.folder]
            case .learningsProfile:
                return [UTType(filenameExtension: "learnings", conformingTo: .json) ?? .json]
            }
        }

        var allowsMultipleSelection: Bool {
            switch self {
            case .modelDirectories: return true
            case .learningsProfile: return false
            }
        }
    }

    var body: some View {
        ZStack {
            if !manager.consentManager.hasConsented {
                onboardingView
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                dashboardView
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
            }
        }
        .animation(.easeInOut(duration: 0.36), value: manager.consentManager.hasConsented)
        .frame(minWidth: 700, minHeight: 600)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Learnings Dashboard")
        .onAppear {
            manager.isLocked = false
            if settingsViewModel.availableModels.isEmpty {
                settingsViewModel.updateAvailableModels()
            }
            exclusionRules.removeLegacyLearningsLinkedRules()
        }
        .navigationTitle("Learnings")
    }

    // MARK: - Onboarding

    private var onboardingView: some View {
        WorkflowContainer(currentStep: .configure) {
            Spacer()

            EmptyStateHeroIcon(systemName: "brain.head.profile")

            VStack(spacing: 8) {
                Text("The Learnings")
                    .font(.largeTitle.bold())
                Text(
                    "A passive learning system that watches how you organize files and learns your preferences over time."
                )
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
            }

            VStack(alignment: .leading, spacing: 14) {
                featureRow(
                    icon: "eye.fill", title: "Watches",
                    description: "Observes when you modify directories after Sorty organization")
                featureRow(
                    icon: "arrow.uturn.backward.circle.fill", title: "Learns from Reverts",
                    description: "Understands when Sorty suggestions weren't right")
                featureRow(
                    icon: "text.bubble.fill", title: "Remembers Instructions",
                    description: "Captures your additional guidance and preferences")
                featureRow(
                    icon: "sparkles", title: "Improves Over Time",
                    description: "Uses learnings to make better future suggestions")
            }
            .padding(16)
            .systemLiquidGlassBackground(cornerRadius: 16)
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Learnings features")

            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(.green)
                Text("Encrypted locally • On-device only • Delete anytime")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.1))
            .cornerRadius(20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Privacy: Data is encrypted locally with biometric protection. You can delete anytime."
            )

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
            .onboardingBeamBorder(variant: .featured)
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
                .systemLiquidGlassBackground(cornerRadius: 10)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title)).font(.headline)
                Text(LocalizedStringKey(description)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }

    // MARK: - Dashboard

    private var dashboardView: some View {
        VStack(spacing: 0) {
            dashboardHeader
                .animatedAppearance(delay: 0.03)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    whatSortyHasLearnedSection
                        .animatedAppearance(delay: 0.08)

                    referenceDirectoriesSection
                        .animatedAppearance(delay: 0.12)

                    settingsSection
                        .animatedAppearance(delay: 0.16)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .modelSelectionOverlay(
            isPresented: $showLearningsModelPicker,
            currentProvider: usesDedicatedLearningsModel
                ? (manager.learningsModelSelection?.provider ?? settingsViewModel.config.provider)
                : settingsViewModel.config.provider,
            currentModel: usesDedicatedLearningsModel
                ? effectiveLearningsModel
                : settingsViewModel.config.model,
            contextMessage: usesDedicatedLearningsModel
                ? "Organization uses \(organizationModelDisplay)."
                : "Learnings uses the organization model (\(organizationModelDisplay)). Picking a different model creates a dedicated override for learnings analysis.",
            resetActionTitle: usesDedicatedLearningsModel ? "Use Organization Model" : nil,
            onReset: {
                manager.clearLearningsModelOverride()
            },
            onSelect: { provider, model in
                HapticFeedbackManager.shared.selection()
                if provider == settingsViewModel.config.provider
                    && model == settingsViewModel.config.model
                {
                    manager.clearLearningsModelOverride()
                } else {
                    manager.setLearningsModelOverride(provider: provider, model: model)
                }
            }
        )
        .alert("Delete All Learning Data?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                cancelPendingControlAction()
            }
            Button("Delete", role: .destructive) {
                deleteAllLearningData()
            }
        } message: {
            if pendingControlAction == .deleteData {
                Text("Deleting learning data...")
            } else {
                Text(
                    "This will permanently delete all your learning data and preferences. This cannot be undone."
                )
            }
        }
        .alert("Withdraw Consent?", isPresented: $showingWithdrawConfirmation) {
            Button("Cancel", role: .cancel) {
                cancelPendingControlAction()
            }
            Button("Withdraw", role: .destructive) {
                withdrawConsent()
            }
        } message: {
            Text(
                "Sorty will stop learning from your organization activity. Your existing learning data and preferences will stay saved, and you can turn learning back on at any time."
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .pauseLearning)) { notification in
            guard notification.targetsWindowSession(appState.windowSessionID) else { return }
            pauseSessionLearning()
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportLearningsProfile)) {
            notification in
            guard notification.targetsWindowSession(appState.windowSessionID) else { return }
            requestSensitiveAction(
                reason: "Authenticate to export your learnings profile."
            ) {
                exportProfile()
            }
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
                        appState.openSettingsWindow(section: .help)
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
                        toggleSessionLearningPaused()
                    } label: {
                        if pendingControlAction == .pauseResume {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(
                                manager.sessionLearningPaused ? "Resume" : "Pause",
                                systemImage: manager.sessionLearningPaused ? "play.fill" : "pause.fill"
                            )
                            .font(.caption.bold())
                        }
                    }
                    .buttonStyle(
                        .tintedPill(manager.sessionLearningPaused ? .green : .red, size: .small)
                    )
                    .disabled(pendingControlAction != nil)
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
                                Label(
                                    "Reset Learnings Defaults", systemImage: "arrow.uturn.backward")
                            }

                            Button {
                                presentLearningsModelPicker()
                            } label: {
                                Label("Model Settings…", systemImage: "gearshape")
                            }

                            Button {
                                refreshLearningsInsights()
                            } label: {
                                Label(
                                    isQuickRefreshingLearnings
                                        ? "Refreshing…" : "Refresh Learnings",
                                    systemImage: "arrow.clockwise")
                            }
                            .disabled(isQuickRefreshingLearnings)
                        }

                        Divider()

                        Button {
                            requestSensitiveAction(
                                reason: "Authenticate to export your learnings profile."
                            ) {
                                exportProfile()
                            }
                        } label: {
                            Label("Export Profile…", systemImage: "square.and.arrow.up")
                        }

                        Button {
                            requestSensitiveAction(
                                reason: "Authenticate to import a learnings profile."
                            ) {
                                presentFileImporter(.learningsProfile)
                            }
                        } label: {
                            Label("Import Profile…", systemImage: "square.and.arrow.down")
                        }

                        Divider()

                        Button(role: .destructive) {
                            confirmDeleteAllLearningData()
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
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            HapticFeedbackManager.shared.light()
                        }
                    )
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
                .systemLiquidGlassBackground(cornerRadius: 999)
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Learnings header")
    }

    private func restoreLearningsDefaults() {
        HapticFeedbackManager.shared.tap()
        manager.sessionLearningPaused = false
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
        setSessionLearningPaused(!manager.sessionLearningPaused)
    }

    private func pauseSessionLearning() {
        setSessionLearningPaused(true)
    }

    private func setSessionLearningPaused(_ isPaused: Bool) {
        requestSensitiveAction(
            reason: "Authenticate to change learning collection for this session.",
            pendingAction: .pauseResume
        ) {
            HapticFeedbackManager.shared.light()
            let isPausing = isPaused && !manager.sessionLearningPaused
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                manager.sessionLearningPaused = isPaused
            }
            if isPausing {
                HapticFeedbackManager.shared.selection()
            } else {
                HapticFeedbackManager.shared.success()
            }
            finishPendingControlAction(
                title: isPaused ? "Learning Paused" : "Learning Resumed",
                message: isPaused
                    ? "Sorty will stop collecting learning signals for this session."
                    : "Sorty is collecting learning signals again.",
                icon: isPaused ? "pause.circle.fill" : "play.circle.fill",
                iconColor: isPaused ? .orange : .green
            )
        }
    }

    private func confirmWithdrawConsent() {
        guard pendingControlAction == nil else { return }
        HapticFeedbackManager.shared.light()
        showPendingControlAction(.withdrawConsent)
        showingWithdrawConfirmation = true
    }

    private func confirmDeleteAllLearningData() {
        requestSensitiveAction(
            reason: "Authenticate to delete all learning data.",
            pendingAction: .deleteData
        ) {
            HapticFeedbackManager.shared.error()
            showingDeleteConfirmation = true
        }
    }

    private func withdrawConsent() {
        showPendingControlAction(.withdrawConsent)
        HapticFeedbackManager.shared.light()
        Task { @MainActor in
            await manager.withdrawConsent()
            HapticFeedbackManager.shared.success()
            finishPendingControlAction(
                title: "Consent Withdrawn",
                message: "Learning is off. Your existing learnings data is still saved.",
                icon: "hand.raised.fill",
                iconColor: .green
            )
        }
    }

    private func deleteAllLearningData() {
        showPendingControlAction(.deleteData)
        HapticFeedbackManager.shared.error()
        Task { @MainActor in
            let didClear = await manager.clearAllData()
            if didClear {
                HapticFeedbackManager.shared.success()
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.72)) {
                    appState.hasCompletedOnboarding = false
                }
                finishPendingControlAction(
                    title: "Learnings Data Deleted",
                    message: "Your learnings profile, consent, and learning settings were removed.",
                    icon: "checkmark.circle.fill",
                    iconColor: .green
                )
            } else {
                HapticFeedbackManager.shared.error()
                finishPendingControlAction(
                    title: "Delete Failed",
                    message: manager.error ?? "Sorty could not delete all learnings data.",
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .red
                )
            }
        }
    }

    private func showPendingControlAction(_ action: PendingControlAction) {
        pendingControlAction = action
        NotificationManager.shared.showHUDInfo(
            title: action.title,
            message: action.message,
            icon: action.icon,
            iconColor: action.iconColor,
            identifier: "learnings-control-action",
            isPersistent: true
        )
    }

    private func cancelPendingControlAction() {
        guard pendingControlAction != nil else { return }
        pendingControlAction = nil
        NotificationManager.shared.dismissHUD(identifier: "learnings-control-action")
    }

    private func finishPendingControlAction(
        title: String,
        message: String,
        icon: String,
        iconColor: Color
    ) {
        pendingControlAction = nil
        NotificationManager.shared.showHUDInfo(
            title: title,
            message: message,
            icon: icon,
            iconColor: iconColor,
            identifier: "learnings-control-action"
        )
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
                    .numericTextTransition(animationValue: statusLabel)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .opacity(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .systemLiquidGlassBackground(cornerRadius: 999)
            .clipShape(Capsule())
            .contentShape(Capsule())
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
                    if pendingControlAction == .pauseResume {
                        Label("Updating Learning", systemImage: "hourglass")
                            .font(.subheadline)
                    } else {
                        Label(
                            manager.sessionLearningPaused ? "Resume Learning" : "Pause Learning",
                            systemImage: manager.sessionLearningPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                .disabled(pendingControlAction != nil)
                .frame(width: 204, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            Color.secondary.opacity(
                                hoveredStatusPopoverAction == .pauseResume ? 0.12 : 0.0))
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
                    confirmWithdrawConsent()
                } label: {
                    Label(
                        pendingControlAction == .withdrawConsent ? "Withdrawing Consent" : "Withdraw Consent",
                        systemImage: pendingControlAction == .withdrawConsent ? "hourglass" : "hand.raised"
                    )
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .disabled(pendingControlAction != nil)
                .frame(width: 204, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            Color.secondary.opacity(
                                hoveredStatusPopoverAction == .withdrawConsent ? 0.12 : 0.0))
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
                    confirmDeleteAllLearningData()
                } label: {
                    Label(
                        pendingControlAction == .deleteData ? "Deleting Data" : "Delete All Data",
                        systemImage: pendingControlAction == .deleteData ? "hourglass" : "trash"
                    )
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .disabled(pendingControlAction != nil)
                .frame(width: 204, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            Color.secondary.opacity(
                                hoveredStatusPopoverAction == .deleteData ? 0.12 : 0.0))
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
                        .symbolReplaceTransition(animationValue: heroIcon)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(heroTitle)
                        .font(.headline)
                        .numericTextTransition(animationValue: heroTitle)
                    if let subtitle = heroSubtitle {
                        Text(LocalizedStringKey(subtitle))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .numericTextTransition(animationValue: subtitle)
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
                .systemLiquidGlassBackground(cornerRadius: 8)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .systemLiquidGlassBackground(cornerRadius: 14)
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
            return
                "\(ruleCount) learned pattern\(ruleCount == 1 ? " is" : "s are") actively applied."
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
            Image("LearningsEmptyState")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 92, height: 92)
                .accessibilityIgnoresInvertColors()
                .opacity(emptyLearningsHasAppeared ? 1 : 0)
                .scaleEffect(emptyLearningsHasAppeared ? 1 : 0.8)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.5, dampingFraction: 0.7).delay(0.1),
                    value: emptyLearningsHasAppeared
                )
                .accessibilityHidden(true)
            Text("No patterns learned yet")
                .font(.subheadline.bold())
                .opacity(emptyLearningsHasAppeared ? 1 : 0)
                .offset(y: emptyLearningsHasAppeared ? 0 : 8)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.12)
                        : .spring(response: 0.5, dampingFraction: 0.8).delay(0.2),
                    value: emptyLearningsHasAppeared)
            Text(
                "Organize some folders, and Sorty will pick up your preferences from corrections and feedback."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 360)
            .opacity(emptyLearningsHasAppeared ? 1 : 0)
            .offset(y: emptyLearningsHasAppeared ? 0 : 10)
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.12)
                    : .spring(response: 0.5, dampingFraction: 0.8).delay(0.3),
                value: emptyLearningsHasAppeared)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No patterns learned yet. Organize folders to start learning.")
        .task {
            guard !emptyLearningsHasAppeared else { return }
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else { return }
            emptyLearningsHasAppeared = true
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
                        set: { setSessionLearningPaused($0) }
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

                HStack(spacing: 12) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.blue)
                        .font(.body.bold())
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Learnings Model")
                            .font(.subheadline)
                        Text(
                            usesDedicatedLearningsModel
                                ? "Dedicated model for learnings analysis"
                                : "Same model as organization"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ModelSelectorCompactButton(
                        provider: usesDedicatedLearningsModel
                            ? (manager.learningsModelSelection?.provider
                                ?? settingsViewModel.config.provider)
                            : settingsViewModel.config.provider,
                        label: usesDedicatedLearningsModel ? effectiveLearningsModel : "Default",
                        onTap: {
                            showLearningsModelPicker = true
                        }
                    )
                    .modelSelectorTriggerBounds()
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)

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
                    .tint(.primary)
                    .frame(width: 120)
                    .labelsHidden()
                    .onChange(of: manager.dataRetentionDays) { _ in
                        HapticFeedbackManager.shared.selection()
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
            }
            .systemLiquidGlassBackground(cornerRadius: 12)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 12) {
                Button(action: {
                    confirmWithdrawConsent()
                }) {
                    Label("Withdraw Consent", systemImage: "hand.raised")
                        .font(.caption.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .systemLiquidGlassBackground(cornerRadius: 999)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        HapticFeedbackManager.shared.selection()
                    }
                }
                .accessibilityHint("Learning will stop but data is preserved")

                Button(
                    role: .destructive,
                    action: {
                        confirmDeleteAllLearningData()
                    }
                ) {
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

    private func settingsToggleRow(
        icon: String, iconColor: Color, title: String, subtitle: String, isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .font(.body.bold())
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline)
                Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
    }

    private var referenceDirectoriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Teach Sorty with example folders")
                        .font(.subheadline.bold())
                    Text(
                        "Point Sorty at folders that are already organized well. It will learn naming conventions, hierarchy depth, and media-style patterns, then apply similar rules during non-destructive previews."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if !manager.modelDirectories.isEmpty {
                    Text("\(manager.modelDirectories.filter(\.isEnabled).count) active")
                        .font(.caption.bold())
                        .foregroundStyle(.teal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .systemLiquidGlassBackground(cornerRadius: 999)
                        .clipShape(Capsule())
                        .numericTextTransition(
                            animationValue: manager.modelDirectories.filter(\.isEnabled).count
                        )
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
                    Image("TeachSortyExampleFolders")
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    Text("No reference directories")
                        .font(.subheadline.bold())
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
                .systemLiquidGlassBackground(cornerRadius: 12)
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

    // MARK: - Helpers

    private var effectiveLearningsModel: String {
        manager.effectiveAIConfig(from: settingsViewModel.config).model
    }

    private var organizationModelDisplay: String {
        let provider = settingsViewModel.config.provider
        let model = settingsViewModel.config.model
        return "\(provider.displayName) / \(model.isEmpty ? provider.defaultModel : model)"
    }

    private func presentFileImporter(_ importer: ActiveFileImporter) {
        HapticFeedbackManager.shared.tap()
        activeFileImporter = importer
        isShowingFileImporter = true
    }

    private func requestSensitiveAction(
        reason: String,
        pendingAction: PendingControlAction? = nil,
        onSuccess: @escaping @MainActor () -> Void
    ) {
        if let pendingAction {
            guard self.pendingControlAction == nil else { return }
            showPendingControlAction(pendingAction)
        }

        if !FeatureFlags.sensitiveActionAuthenticationEnabled {
            onSuccess()
            return
        }

        Task { @MainActor in
            let didAuthenticate = await SecurityManager.shared.authenticateForSensitiveAction(
                reason: reason)
            guard didAuthenticate else {
                HapticFeedbackManager.shared.error()
                if pendingAction != nil {
                    finishPendingControlAction(
                        title: "Authentication Cancelled",
                        message: "No changes were made.",
                        icon: "xmark.circle.fill",
                        iconColor: .orange
                    )
                }
                return
            }
            onSuccess()
        }
    }

    private var usesDedicatedLearningsModel: Bool {
        guard let selection = manager.learningsModelSelection else { return false }
        return selection.provider == settingsViewModel.config.provider
    }

    // MARK: - Export / Import

    private func exportProfile() {
        guard manager.currentProfile != nil else { return }
        let panel = NSSavePanel()
        let learningsType = UTType(filenameExtension: "learnings", conformingTo: .json) ?? .json
        panel.allowedContentTypes = [learningsType]
        panel.nameFieldStringValue =
            "learnings_profile_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).learnings"
        panel.message = "Export Learning Profile"

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let summary = try manager.exportProfile(to: url)
                HapticFeedbackManager.shared.success()
                NotificationManager.shared.showHUDInfo(
                    title: "Learning Profile Exported",
                    message: "Saved \(summary.totalRecordCount) learning records with profile settings and integrity metadata.",
                    icon: "checkmark.circle.fill",
                    iconColor: .green
                )
                NSWorkspace.shared.open(url)
            } catch {
                DebugLogger.log("Failed to export profile: \(error)")
                HapticFeedbackManager.shared.error()
                manager.error = "Export failed: \(error.localizedDescription)"
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
            if addedCount > 0 {
                HapticFeedbackManager.shared.success()
            } else {
                HapticFeedbackManager.shared.error()
            }
        case .failure(let error):
            DebugLogger.log("Model directory import failed: \(error)")
            HapticFeedbackManager.shared.error()
        }
    }

    private func handleProfileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task {
                do {
                    let importResult = try await manager.importProfile(from: url)
                    HapticFeedbackManager.shared.success()
                    var details = [
                        "Merged \(importResult.importedRecordCount) records with \(importResult.previousRecordCount) existing records.",
                        "The profile now contains \(importResult.resultingRecordCount) records."
                    ]
                    if importResult.restoredSettingCount > 0 {
                        details.append("Restored \(importResult.restoredSettingCount) learning settings.")
                    }
                    if importResult.omittedByRetentionPolicy > 0 {
                        details.append(
                            "\(importResult.omittedByRetentionPolicy) older records were omitted by your retention policy."
                        )
                    }
                    if importResult.wasLegacyProfile {
                        details.append("The legacy profile was upgraded to the current format.")
                    }
                    NotificationManager.shared.showHUDInfo(
                        title: "Learning Profile Imported",
                        message: details.joined(separator: " "),
                        icon: "checkmark.circle.fill",
                        iconColor: .green
                    )
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
                .symbolReplaceTransition(animationValue: rule.isEnabled)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.explanation)
                    .font(.subheadline)
                    .foregroundColor(rule.isEnabled ? .primary : .secondary)

                HStack(spacing: 8) {
                    if rule.successCount > 0 {
                        Text("\(rule.successCount) applied")
                            .font(.caption2)
                            .foregroundColor(.green)
                            .numericTextTransition(animationValue: rule.successCount)
                    }
                    if rule.failureCount > 0 {
                        Text("\(rule.failureCount) corrected")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .numericTextTransition(animationValue: rule.failureCount)
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

            Toggle(
                "",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { newValue in
                        Task {
                            HapticFeedbackManager.shared.selection()
                            await manager.setRuleEnabled(ruleId: rule.id, enabled: newValue)
                        }
                    }
                )
            )
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

// MARK: - Model Directory Row

struct ModelDirectoryRow: View {
    let directory: ReferenceModelDirectory
    @ObservedObject var manager: LearningsManager
    @State private var isHovered = false

    private var statusText: String {
        guard directory.isAccessible else {
            return "Folder is missing or unavailable"
        }
        guard directory.isEnabled else {
            return "Paused - not used in previews"
        }
        guard let snapshot = directory.scanSnapshot else {
            return "Queued for scanning - used once Sorty reads the structure"
        }
        return
            "Used in previews - scanned \(snapshot.totalFolderCount) folders and \(snapshot.totalFileCount) files"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: directory.isAccessible ? "folder.fill" : "folder.badge.questionmark")
                .font(.body.bold())
                .symbolReplaceTransition(animationValue: directory.isAccessible)
                .foregroundColor(
                    directory.isAccessible ? (directory.isEnabled ? .teal : .secondary) : .orange
                )
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
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(
                        directory.isEnabled && directory.isAccessible ? .teal : .secondary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .numericTextTransition(
                        animationValue: statusText,
                        animation: .easeInOut(duration: 0.28)
                    )
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
                .systemLiquidGlassButton()
                .accessibilityIdentifier("OpenModelDirectoryButton_\(directory.id)")
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { directory.isEnabled },
                    set: { _ in
                        HapticFeedbackManager.shared.selection()
                        manager.toggleModelDirectory(id: directory.id)
                    }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .scaleEffect(0.8)
            .accessibilityLabel("Use \(directory.displayName) in previews")
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
            .systemLiquidGlassButton()
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
                    exclusionRules.removeLegacyLearningsLinkedRules(
                        matchingLearningPattern: pattern)
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
