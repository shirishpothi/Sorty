//
//  ExclusionRulesView.swift
//  Sorty
//
//  Modern exclusion rules management with grouped cards and improved UX
//

import SwiftUI
import UniformTypeIdentifiers

private enum DateAgeUnit: CaseIterable, Hashable, Identifiable {
    case days
    case weeks
    case months
    case years

    var id: Self { self }

    var label: String {
        switch self {
        case .days: "days ago"
        case .weeks: "weeks ago"
        case .months: "months ago"
        case .years: "years ago"
        }
    }

    var daysMultiplier: Double {
        switch self {
        case .days: 1
        case .weeks: 7
        case .months: 30
        case .years: 365
        }
    }
}

struct ExclusionRulesView: View {
    @EnvironmentObject var rulesManager: ExclusionRulesManager
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var learningsManager: LearningsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingAddRule = false
    @State private var showingLearningExclusionImporter = false
    @State private var searchText = ""
    @State private var newNLException = ""
    @State private var isImprovingException = false
    @State private var showImproveExceptionRequest = false
    @State private var improveExceptionRequestMessage = ""
    @State private var learningExclusionSliverTrigger = 0
    @State private var isShowingLearningExclusionsInfo = false
    @State private var isShowingNaturalLanguageExceptionsInfo = false
    @State private var isLearningExclusionsExpanded = true
    @FocusState private var isNLExceptionFocused: Bool

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var filteredRules: [ExclusionRule] {
        if !isSearching {
            return rulesManager.rules
        }
        return rulesManager.rules.filter {
            $0.displayDescription.localizedCaseInsensitiveContains(trimmedSearchText)
                || $0.type.rawValue.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var groupedRules: [(String, [ExclusionRule])] {
        let groups: [(String, [ExclusionRuleType])] = [
            ("Files & Folders", [.fileExtension, .fileName, .folderName, .pathContains, .fileType]),
            ("Conditions", [.fileSize, .creationDate, .modificationDate, .regex, .customScript]),
            ("macOS", [.hiddenFiles, .systemFiles]),
        ]

        return groups.compactMap { (title, types) in
            let rules = filteredRules.filter { types.contains($0.type) }
            return rules.isEmpty ? nil : (title, rules)
        }
    }

    private var filteredLearningExclusionPatterns: [String] {
        let patterns = learningsManager.currentProfile?.learningExclusionPatterns ?? []
        guard isSearching else { return patterns }
        return patterns.filter { $0.localizedCaseInsensitiveContains(trimmedSearchText) }
    }

    private var filteredNaturalLanguageExceptions: [(index: Int, exception: String)] {
        let exceptions = rulesManager.naturalLanguageExceptions.enumerated().map {
            (index: $0.offset, exception: $0.element)
        }
        guard isSearching else { return exceptions }
        return exceptions.filter {
            $0.exception.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private var hasSearchResults: Bool {
        !groupedRules.isEmpty || !filteredLearningExclusionPatterns.isEmpty
            || !filteredNaturalLanguageExceptions.isEmpty
    }

    var body: some View {
        Group {
            if rulesManager.rules.count > 1 {
                content
                    .searchable(text: $searchText, prompt: "Search rules")
            } else {
                content
            }
        }
        .onChange(of: rulesManager.rules.count) { _, count in
            if count <= 1 {
                searchText = ""
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if rulesManager.rules.isEmpty {
                ZStack(alignment: .topLeading) {
                    EmptyExclusionRulesView(onAddRule: {
                        HapticFeedbackManager.shared.tap()
                        showingAddRule = true
                    })
                    .transition(TransitionStyles.scaleAndFade)
                    .animatedAppearance(delay: 0.08)

                    emptyHeaderView
                        .padding(.horizontal, 32)
                        .animatedAppearance(delay: 0.03)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Header
                headerView
                    .animatedAppearance(delay: 0.03)

                Divider()

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 20) {
                            if !isSearching {
                                naturalLanguageExceptionsCard
                                    .animatedAppearance(delay: 0.05)
                            }

                            // Grouped rules
                            ForEach(Array(groupedRules.enumerated()), id: \.1.0) { index, group in
                                RuleGroupCard(
                                    title: group.0,
                                    rules: group.1,
                                    rulesManager: rulesManager,
                                    highlightedRuleID: appState.highlightedExclusionRuleID,
                                    infoText: group.0 == "Files & Folders"
                                        ? "Matching files and folders are left untouched and aren't used for learnings."
                                        : nil,
                                    naturalLanguageExceptions: group.0 == "Files & Folders"
                                        ? filteredNaturalLanguageExceptions : [],
                                    onRemoveNaturalLanguageException: { index in
                                        withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82)) {
                                            rulesManager.removeNaturalLanguageException(at: index)
                                        }
                                    }
                                )
                                .animatedAppearance(delay: Double(index) * 0.05)
                            }

                            if !hasSearchResults && isSearching {
                                VStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                    Text("No rules match '\(trimmedSearchText)'")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 40)
                            }

                            if !isSearching || !filteredLearningExclusionPatterns.isEmpty {
                                learningExclusionsCard
                                    .animatedAppearance(delay: 0.12)
                            }

                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        .padding(.bottom, 20)
                    }
                    .transition(TransitionStyles.slideFromRight)
                    .onAppear {
                        scrollToHighlightedRule(using: proxy)
                    }
                    .onChange(of: appState.highlightedExclusionRuleID) { _, _ in
                        scrollToHighlightedRule(using: proxy)
                    }
                }
                .animation(.pageTransition, value: rulesManager.rules.isEmpty)
            }
        }
        .emptyStateWorkflowGradient(isVisible: rulesManager.rules.isEmpty)
        .animation(.pageTransition, value: rulesManager.rules.isEmpty)
        .navigationTitle("Exclusions")
        .sheet(isPresented: $showingAddRule) {
            AddExclusionRuleView(rulesManager: rulesManager)
                .modalBounce()
        }
        .fileImporter(
            isPresented: $showingLearningExclusionImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handleLearningExclusionImport(result)
        }
    }

    private func scrollToHighlightedRule(using proxy: ScrollViewProxy) {
        guard let ruleID = appState.highlightedExclusionRuleID else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(ruleID, anchor: .center)
            }
            try? await Task.sleep(for: .seconds(3))
            if appState.highlightedExclusionRuleID == ruleID {
                appState.highlightedExclusionRuleID = nil
            }
        }
    }

    private var headerView: some View {
        HStack {
            HStack(spacing: 12) {
                if appState.navigatedFromSettings {
                    GlassyBackButton {
                        HapticFeedbackManager.shared.tap()
                        appState.navigatedFromSettings = false
                        appState.openSettingsWindow(section: .rules)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Exclusions")
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        Text("\(rulesManager.enabledRulesCount) active")
                            .foregroundStyle(.green)
                            .numericTextTransition(
                                animationValue: rulesManager.enabledRulesCount
                            )
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(
                            "\(rulesManager.rules.count - rulesManager.enabledRulesCount) disabled"
                        )
                        .foregroundStyle(.secondary)
                        .numericTextTransition(
                            animationValue: rulesManager.rules.count
                                - rulesManager.enabledRulesCount
                        )
                    }
                    .font(.caption)
                }
            }
            .animatedAppearance(delay: 0.05)

            Spacer()

            if !rulesManager.rules.isEmpty {
                Button {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        rulesManager.clearAllRules()
                    }
                } label: {
                    Label("Remove All", systemImage: "trash")
                }
                .buttonStyle(.tintedPill(.red, size: .small))
                .controlSize(.small)
                .accessibilityIdentifier("ClearAllExclusionsButton")
            }

            Button {
                HapticFeedbackManager.shared.tap()
                showingAddRule = true
            } label: {
                Label("Add Manually", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.onboardingPill)
            .onboardingBeamBorder(variant: .featured)
            .accessibilityIdentifier("AddExclusionRuleButton")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var emptyHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Exclusions")
                    .font(.largeTitle.bold())

                Text(
                    "Keep protected files, folders, and patterns out of organization and learnings"
                )
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Natural Language Exceptions

    private var learningExclusionsCard: some View {
        SettingsCard(
            title: "Learning Exclusions",
            icon: "eye.slash",
            color: .orange,
            count: filteredLearningExclusionPatterns.count,
            isExpanded: $isLearningExclusionsExpanded,
            headerAccessory: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onHover { isShowingLearningExclusionsInfo = $0 }
                    .popover(
                        isPresented: $isShowingLearningExclusionsInfo,
                        arrowEdge: .trailing
                    ) {
                        Text(
                            "Folders here are still organized, but they won't teach Sorty anything."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(width: 280, alignment: .leading)
                        .systemLiquidGlassPopover(cornerRadius: 12)
                    }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if let patterns = learningsManager.currentProfile?.learningExclusionPatterns,
                    !patterns.isEmpty
                {
                    HStack {
                        Spacer()

                        Button {
                            presentLearningExclusionImporter()
                        } label: {
                            Label("Add Folder", systemImage: "plus")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.onboardingPill(size: .small))
                        .accessibilityIdentifier("AddLearningExclusionFolderButton")
                    }
                }

                if !filteredLearningExclusionPatterns.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(filteredLearningExclusionPatterns, id: \.self) { pattern in
                            LearningExclusionRow(pattern: pattern, manager: learningsManager)
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(.orange.opacity(0.6))
                            .milestoneEmptyStateSliver(
                                trigger: learningExclusionSliverTrigger,
                                tint: .orange
                            )
                            .onScrollVisibilityChange(threshold: 0.6) { isVisible in
                                guard isVisible else { return }
                                learningExclusionSliverTrigger += 1
                            }
                            .accessibilityHidden(true)
                        Text("No folders excluded")
                            .font(.subheadline.bold())
                        Text(
                            "Exclude folders that should still be organized but shouldn't teach Sorty anything."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                        Button {
                            presentLearningExclusionImporter()
                        } label: {
                            Label("Exclude Folder", systemImage: "plus")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.onboardingPill(size: .small))
                        .accessibilityIdentifier("EmptyStateAddLearningExclusionFolderButton")
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .systemLiquidGlassBackground(cornerRadius: 12)
                }
            }
        }
    }

    private var naturalLanguageExceptionsCard: some View {
        SettingsCard(
            title: "Describe an Exception",
            icon: "sparkles",
            color: .purple,
            count: 0,
            isExpanded: nil,
            headerAccessory: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .onHover { isShowingNaturalLanguageExceptionsInfo = $0 }
                    .popover(
                        isPresented: $isShowingNaturalLanguageExceptionsInfo,
                        arrowEdge: .trailing
                    ) {
                        Text("Tell Sorty what to leave alone. It will ask for clarification when the request could mean different things.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(width: 280, alignment: .leading)
                            .systemLiquidGlassPopover(cornerRadius: 12)
                    }
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Use ordinary language — you can combine names, folders, file kinds, and context.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 10) {
                    TextField("e.g. Leave unfinished client proposals and anything in Archive alone", text: $newNLException, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .focused($isNLExceptionFocused)
                        .onSubmit {
                            Task { await reviewAndAddException() }
                        }

                    Button {
                        Task { await reviewAndAddException() }
                    } label: {
                        if isImprovingException {
                            SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                        } else {
                            Label("Review & Add", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .onboardingBeamBorder(
                        variant: .featured,
                        active: !newNLException.trimmingCharacters(in: .whitespaces).isEmpty,
                        size: .small
                    )
                    .disabled(
                        newNLException.trimmingCharacters(in: .whitespaces).isEmpty
                            || isImprovingException
                    )
                    .help("Let Sorty review the exception before saving it")
                    .alert("Sorty needs more detail", isPresented: $showImproveExceptionRequest) {
                        Button("Edit Exception") {
                            isNLExceptionFocused = true
                        }
                    } message: {
                        Text(
                            "\(improveExceptionRequestMessage)\n\nEdit the exception above, then click Review & Add again."
                        )
                    }
                }

                Text("Saved exceptions appear in Files & Folders with a sparkle badge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func presentLearningExclusionImporter() {
        HapticFeedbackManager.shared.tap()
        showingLearningExclusionImporter = true
    }

    private func handleLearningExclusionImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                var addedCount = 0
                for url in urls {
                    let hasScopedAccess = url.startAccessingSecurityScopedResource()
                    defer { if hasScopedAccess { url.stopAccessingSecurityScopedResource() } }
                    let before =
                        learningsManager.currentProfile?.learningExclusionPatterns.count ?? 0
                    await learningsManager.addLearningExclusion(url.path)
                    if (learningsManager.currentProfile?.learningExclusionPatterns.count ?? 0)
                        > before
                    {
                        addedCount += 1
                    }
                }
                if addedCount > 0 {
                    HapticFeedbackManager.shared.success()
                } else {
                    HapticFeedbackManager.shared.error()
                }
            }
        case .failure(let error):
            DebugLogger.log("Learning exclusion import failed: \(error)")
            HapticFeedbackManager.shared.error()
        }
    }

    private func reviewAndAddException() async {
        let original = newNLException.trimmingCharacters(in: .whitespaces)
        guard !original.isEmpty else { return }
        isImprovingException = true
        defer { isImprovingException = false }

        do {
            let client = try AIClientFactory.createClient(config: settingsViewModel.config)
            let outcome = try await ImproveInstructionsTool.run(
                client: client,
                originalInstructions: original,
                workflow: "exclusion rule"
            )

            switch outcome {
            case .replacement(let replacement):
                let reviewedException = String(replacement.prefix(200))
                withAnimation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.82)) {
                    rulesManager.addNaturalLanguageException(reviewedException)
                }
                newNLException = ""
                showImproveExceptionRequest = false
                HapticFeedbackManager.shared.success()
            case .needsUserInput(let message):
                improveExceptionRequestMessage = message
                showImproveExceptionRequest = true
                HapticFeedbackManager.shared.tap()
            }
        } catch {
            HapticFeedbackManager.shared.error()
        }
    }
}

// MARK: - Empty State View

struct EmptyExclusionRulesView: View {
    let onAddRule: () -> Void
    @State private var hasAppeared = false
    @State private var beamHasAppeared = false

    var body: some View {
        VStack(spacing: 24) {
            EmptyStateHeroIcon(systemName: "eye.slash.circle")
                .opacity(hasAppeared ? 1 : 0)
                .scaleEffect(hasAppeared ? 1 : 0.8)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.7).delay(0.1), value: hasAppeared)

            VStack(spacing: 8) {
                Text("Nothing is excluded")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(
                    "Choose folders or simple rules for anything Sorty should leave untouched."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)

            Button {
                onAddRule()
            } label: {
                Label("Add Exclusion", systemImage: "plus")
            }
            .buttonStyle(.onboardingPill)
            .onboardingBeamBorder(variant: .featured, active: beamHasAppeared)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 15)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                hasAppeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                beamHasAppeared = true
            }
        }
    }
}

struct RuleExamplePill: View {
    let icon: String
    let text: String
    var useSystemFolderIcon: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    private static let folderIcon: NSImage = {
        NSWorkspace.shared.icon(forFile: "/tmp")
    }()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if useSystemFolderIcon {
                    AppKitImageView(image: Self.folderIcon, size: CGSize(width: 12, height: 12))
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                Text(text)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(isHovered ? 0.18 : 0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovered in
            guard hovered != isHovered else { return }
            if hovered {
                HapticFeedbackManager.shared.selection()
            }
            isHovered = hovered
        }
        .help("Add \(text) exclusion rule")
    }
}

// MARK: - Rule Group Card

struct RuleGroupCard: View {
    let title: String
    let rules: [ExclusionRule]
    @ObservedObject var rulesManager: ExclusionRulesManager
    let highlightedRuleID: UUID?
    let infoText: String?
    let naturalLanguageExceptions: [(index: Int, exception: String)]
    let onRemoveNaturalLanguageException: (Int) -> Void

    @State private var isExpanded = true
    @State private var isShowingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button(action: toggleExpanded) {
                    HStack(spacing: 8) {
                        Text(LocalizedStringKey(title))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text("\(rules.count + naturalLanguageExceptions.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .numericTextTransition(
                                animationValue: rules.count + naturalLanguageExceptions.count
                            )
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .buttonStyle(.plain)

                if let infoText {
                    Button {
                        isShowingInfo.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isShowingInfo, arrowEdge: .trailing) {
                        Text(infoText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(14)
                            .frame(width: 280, alignment: .leading)
                            .systemLiquidGlassPopover(cornerRadius: 12)
                    }
                    .accessibilityLabel("About \(title)")
                    .help("About \(title)")
                }

                Button(action: toggleExpanded) {
                    HStack {
                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                VStack(spacing: 0) {
                    ForEach(naturalLanguageExceptions, id: \.index) { item in
                        NaturalLanguageExceptionRow(
                            exception: item.exception,
                            onDelete: { onRemoveNaturalLanguageException(item.index) }
                        )

                        Divider()
                            .padding(.leading, 52)
                    }

                    ForEach(rules) { rule in
                        ExclusionRuleRow(
                            rule: rule,
                            rulesManager: rulesManager,
                            isHighlighted: rule.id == highlightedRuleID
                        )
                        .id(rule.id)

                        if rule.id != rules.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .systemLiquidGlassBackground(cornerRadius: 12)
    }

    private func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
        HapticFeedbackManager.shared.tap()
    }
}

private struct NaturalLanguageExceptionRow: View {
    let exception: String
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 28, height: 28)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(exception)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                Label("AI-reviewed exception", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
            }

            Spacer()

            if isHovered {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Exclusion Rule Row

struct ExclusionRuleRow: View {
    let rule: ExclusionRule
    @ObservedObject var rulesManager: ExclusionRulesManager
    let isHighlighted: Bool
    @State private var isHovered = false

    private static let systemFolderIcon: NSImage = {
        NSWorkspace.shared.icon(forFile: "/tmp")
    }()

    private var isFolderExclusion: Bool {
        rule.type == .pathContains && rule.pattern.hasPrefix("/")
    }

    var body: some View {
        HStack(spacing: 12) {
            // Type icon - use system folder icon for folder rules
            ruleIcon
                .frame(width: 28, height: 28)
                .background((rule.isEnabled ? colorForType(rule.type) : .secondary).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(rule.displayDescription)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(rule.isEnabled ? .primary : .secondary)

                    if rule.isBuiltIn {
                        Text("Built-in")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 6) {
                    Text(isFolderExclusion ? "Folder" : rule.type.friendlyName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !isFolderExclusion,
                       let description = rule.description,
                       !description.isEmpty {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(LocalizedStringKey(description))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            if isHovered {
                Button {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        rulesManager.removeRule(rule)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            Toggle(
                "",
                isOn: Binding(
                    get: { rule.isEnabled },
                    set: { newValue in
                        HapticFeedbackManager.shared.selection()
                        var updatedRule = rule
                        updatedRule.isEnabled = newValue
                        rulesManager.updateRule(updatedRule)
                    }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
            .accessibilityLabel(
                rule.isEnabled
                    ? "Disable rule: \(rule.displayDescription)"
                    : "Enable rule: \(rule.displayDescription)")
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHighlighted ? Color.accentColor.opacity(0.14) : (isHovered ? Color.primary.opacity(0.03) : Color.clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        .contextMenu {
            Button(role: .destructive) {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    rulesManager.removeRule(rule)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityAction(named: Text("Delete")) {
            HapticFeedbackManager.shared.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                rulesManager.removeRule(rule)
            }
        }
    }

    @ViewBuilder
    private var ruleIcon: some View {
        if rule.type == .folderName || isFolderExclusion {
            AppKitImageView(
                image: Self.systemFolderIcon,
                size: CGSize(width: 16, height: 16),
                opacity: rule.isEnabled ? 1.0 : 0.5
            )
            .frame(width: 16, height: 16)
        } else {
            Image(systemName: iconForType(rule.type))
                .font(.system(size: 14))
                .foregroundStyle(rule.isEnabled ? colorForType(rule.type) : .secondary)
        }
    }

    private func iconForType(_ type: ExclusionRuleType) -> String {
        switch type {
        case .fileExtension: return "doc.badge.gearshape"
        case .fileName: return "doc"
        case .folderName: return "folder"
        case .pathContains: return "arrow.triangle.branch"
        case .regex: return "text.magnifyingglass"
        case .fileSize: return "scalemass"
        case .creationDate: return "calendar.badge.plus"
        case .modificationDate: return "calendar.badge.clock"
        case .hiddenFiles: return "eye.slash"
        case .systemFiles: return "gearshape.2"
        case .fileType: return "doc.on.doc"
        case .customScript: return "applescript"
        }
    }

    private func colorForType(_ type: ExclusionRuleType) -> Color {
        switch type {
        case .fileExtension, .fileName, .folderName, .pathContains, .regex:
            return .blue
        case .fileSize, .creationDate, .modificationDate:
            return .orange
        case .hiddenFiles, .systemFiles, .fileType:
            return .purple
        case .customScript:
            return .green
        }
    }
}

// MARK: - Add Exclusion Rule View

private enum ExclusionIntent: String, CaseIterable, Identifiable {
    case folder
    case fileKind
    case name
    case properties
    case advanced

    var id: Self { self }

    var title: String {
        switch self {
        case .folder: "A specific folder"
        case .fileKind: "A kind of file"
        case .name: "Files or folders by name"
        case .properties: "Files by size or age"
        case .advanced: "Advanced rule"
        }
    }

    var explanation: String {
        switch self {
        case .folder: "Leave one folder and everything inside it untouched."
        case .fileKind: "Ignore a familiar category, or one specific file extension."
        case .name: "Match text in a file name or an exact folder name."
        case .properties: "Ignore files above or below a size, or based on their age."
        case .advanced: "Hidden files, macOS files, path fragments, and regular expressions."
        }
    }

    var icon: String {
        switch self {
        case .folder: "folder.badge.minus"
        case .fileKind: "doc.on.doc"
        case .name: "text.magnifyingglass"
        case .properties: "slider.horizontal.3"
        case .advanced: "gearshape.2"
        }
    }
}

private enum FileKindChoice: String, CaseIterable, Identifiable {
    case category = "File category"
    case fileExtension = "File extension"

    var id: Self { self }
}

private enum NameMatchChoice: String, CaseIterable, Identifiable {
    case fileName = "File name contains"
    case folderName = "Folder name is"

    var id: Self { self }
}

private enum PropertyChoice: String, CaseIterable, Identifiable {
    case fileSize = "File size"
    case modificationDate = "Last modified"
    case creationDate = "Date created"

    var id: Self { self }
}

private enum AdvancedRuleChoice: String, CaseIterable, Identifiable {
    case hiddenFiles = "Hidden files"
    case systemFiles = "macOS system files"
    case pathContains = "Path contains text"
    case regex = "Regular expression"

    var id: Self { self }
}

struct AddExclusionRuleView: View {
    @ObservedObject var rulesManager: ExclusionRulesManager
    @Environment(\.dismiss) var dismiss
    @State private var selectedIntent: ExclusionIntent?
    @State private var fileKindChoice: FileKindChoice = .category
    @State private var nameMatchChoice: NameMatchChoice = .fileName
    @State private var propertyChoice: PropertyChoice = .fileSize
    @State private var advancedChoice: AdvancedRuleChoice = .hiddenFiles
    @State private var pattern: String = ""
    @State private var description: String = ""
    @State private var numericValue: Double = 100
    @State private var comparisonGreater: Bool = true
    @State private var dateAgeUnit: DateAgeUnit = .days
    @State private var selectedFileTypeCategory: FileTypeCategory = .images
    @State private var selectedFolderURL: URL?
    @State private var showingFolderPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let selectedIntent {
                        configurationView(for: selectedIntent)
                    } else {
                        intentPicker
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 600)
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                return
            }
            HapticFeedbackManager.shared.selection()
            selectedFolderURL = url.standardizedFileURL
        }
    }

    private var header: some View {
        HStack {
            if selectedIntent == nil {
                Button("Cancel") {
                    HapticFeedbackManager.shared.tap()
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
            } else {
                Button {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedIntent = nil
                        selectedFolderURL = nil
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .keyboardShortcut(.escape, modifiers: [])
            }

            Spacer()

            Text(selectedIntent == nil ? "Add an Exclusion" : "Set Up Exclusion")
                .font(.headline)

            Spacer()

            if selectedIntent != nil {
                Button("Add Exclusion") {
                    HapticFeedbackManager.shared.success()
                    addRule()
                }
                .buttonStyle(.onboardingPill)
                .onboardingBeamBorder(variant: .warning, active: isValidInput)
                .disabled(!isValidInput)
                .keyboardShortcut(.return, modifiers: [.command])
            } else {
                Button("Cancel") {}
                    .hidden()
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var intentPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What should Sorty leave alone?")
                    .font(.title3.weight(.semibold))

                Text("Choose the closest match. You’ll only see the settings that apply.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 4)

            ForEach(ExclusionIntent.allCases) { intent in
                Button {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedIntent = intent
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: intent.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                            .frame(width: 34, height: 34)
                            .background(SortyDesignSystem.Colors.resolvedAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(intent.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(intent.explanation)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 8)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .systemLiquidGlassBackground(cornerRadius: 12)
            }
        }
    }

    @ViewBuilder
    private func configurationView(for intent: ExclusionIntent) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Label(intent.title, systemImage: intent.icon)
                    .font(.title3.weight(.semibold))
                Text(intent.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                switch intent {
                case .folder:
                    folderConfiguration
                case .fileKind:
                    fileKindConfiguration
                case .name:
                    nameConfiguration
                case .properties:
                    propertyConfiguration
                case .advanced:
                    advancedConfiguration
                }
            }
            .padding(16)
            .systemLiquidGlassBackground(cornerRadius: 12)

            if intent != .folder {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Label (optional)")
                        .font(.subheadline.weight(.semibold))
                    TextField("e.g. Old video exports", text: $description)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(16)
                .systemLiquidGlassBackground(cornerRadius: 12)
            }
        }
    }

    private var folderConfiguration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folder")
                .font(.subheadline.weight(.semibold))

            Text("Sorty will leave this folder and everything inside it untouched.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let selectedFolderURL {
                HStack(spacing: 10) {
                    FolderThumbnailView(
                        url: selectedFolderURL,
                        size: CGSize(width: 28, height: 28)
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedFolderURL.lastPathComponent)
                            .font(.subheadline.weight(.medium))
                        PrivacySensitivePathText(
                            path: selectedFolderURL.deletingLastPathComponent().path
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Spacer()

                    Button("Change") {
                        showingFolderPicker = true
                    }
                    .buttonStyle(.sortyBordered(size: .small))
                }
            } else {
                Button {
                    HapticFeedbackManager.shared.tap()
                    showingFolderPicker = true
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.minus")
                }
                .buttonStyle(.onboardingPill)
                .accessibilityIdentifier("ChooseExclusionFolderButton")
            }
        }
    }

    private var fileKindConfiguration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Match", selection: $fileKindChoice) {
                ForEach(FileKindChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            if fileKindChoice == .category {
                Picker("Category", selection: $selectedFileTypeCategory) {
                    ForEach(FileTypeCategory.allCases) { category in
                        Label(category.rawValue, systemImage: category.icon).tag(category)
                    }
                }
                .pickerStyle(.menu)

                Text(categorySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                labeledPatternField(
                    title: "Extension",
                    placeholder: "pdf",
                    help: "Enter it with or without the dot."
                )
            }
        }
    }

    private var nameConfiguration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Match", selection: $nameMatchChoice) {
                ForEach(NameMatchChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            labeledPatternField(
                title: nameMatchChoice == .fileName ? "Text in the file name" : "Folder name",
                placeholder: nameMatchChoice == .fileName ? "draft" : "node_modules",
                help: nameMatchChoice == .fileName
                    ? "Any file whose name contains this text will be left alone."
                    : "Every folder with exactly this name, including its contents, will be left alone."
            )
        }
    }

    private var propertyConfiguration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Property", selection: $propertyChoice) {
                ForEach(PropertyChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.segmented)

            if propertyChoice == .fileSize {
                Picker("Exclude files", selection: $comparisonGreater) {
                    Text("Larger than").tag(true)
                    Text("Smaller than").tag(false)
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField("Size", value: $numericValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                    Text("MB")
                        .foregroundStyle(.secondary)
                }
            } else {
                Picker("Exclude files", selection: $comparisonGreater) {
                    Text("Older than").tag(true)
                    Text("Newer than").tag(false)
                }
                .pickerStyle(.segmented)

                HStack {
                    TextField("Age", value: $numericValue, format: .number)
                        .textFieldStyle(.roundedBorder)

                    Picker("Age unit", selection: $dateAgeUnit) {
                        ForEach(DateAgeUnit.allCases) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    private var advancedConfiguration: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Rule", selection: $advancedChoice) {
                ForEach(AdvancedRuleChoice.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                }
            }
            .pickerStyle(.menu)

            switch advancedChoice {
            case .hiddenFiles:
                explanationRow("Files and folders whose names begin with a period will be left alone.")
            case .systemFiles:
                explanationRow("Common macOS metadata and system-generated files will be left alone.")
            case .pathContains:
                labeledPatternField(
                    title: "Text in the path",
                    placeholder: "/backups/",
                    help: "Matches this text anywhere in the full path."
                )
            case .regex:
                labeledPatternField(
                    title: "Regular expression",
                    placeholder: "^temp_.*\\.log$",
                    help: "Matches against the file or folder name."
                )
            }
        }
    }

    private func labeledPatternField(title: String, placeholder: String, help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            TextField(placeholder, text: $pattern)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("ExclusionRulePatternField")
            Text(help)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func explanationRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var categorySummary: String {
        let examples = selectedFileTypeCategory.extensions.prefix(6).map { ".\($0)" }
        guard !examples.isEmpty else {
            return "Files not covered by the standard categories."
        }
        return "Includes \(examples.joined(separator: ", "))\(selectedFileTypeCategory.extensions.count > 6 ? ", and more." : ".")"
    }

    private var selectedRuleType: ExclusionRuleType? {
        switch selectedIntent {
        case .folder: .pathContains
        case .fileKind: fileKindChoice == .category ? .fileType : .fileExtension
        case .name: nameMatchChoice == .fileName ? .fileName : .folderName
        case .properties:
            switch propertyChoice {
            case .fileSize: .fileSize
            case .modificationDate: .modificationDate
            case .creationDate: .creationDate
            }
        case .advanced:
            switch advancedChoice {
            case .hiddenFiles: .hiddenFiles
            case .systemFiles: .systemFiles
            case .pathContains: .pathContains
            case .regex: .regex
            }
        case nil: nil
        }
    }

    private var isValidInput: Bool {
        guard let selectedIntent, let selectedRuleType else { return false }

        if selectedIntent == .folder {
            return selectedFolderURL != nil
        }

        switch selectedRuleType {
        case .hiddenFiles, .systemFiles, .fileType:
            return true
        case .fileSize, .creationDate, .modificationDate:
            return numericValue > 0
        case .customScript:
            return false
        default:
            return !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func addRule() {
        guard let selectedIntent, let selectedRuleType else { return }

        if selectedIntent == .folder, let selectedFolderURL {
            let normalizedPath = selectedFolderURL.standardizedFileURL.path
            let folderName = selectedFolderURL.lastPathComponent
            save(
                ExclusionRule(
                    type: .pathContains,
                    pattern: normalizedPath,
                    description: folderName.isEmpty ? "Protected folder" : folderName
                )
            )
            return
        }

        let trimmedPattern = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        let rule: ExclusionRule

        switch selectedRuleType {
        case .fileSize, .creationDate, .modificationDate:
            rule = ExclusionRule(
                type: selectedRuleType,
                description: description.isEmpty ? nil : description,
                numericValue: selectedRuleType == .fileSize
                    ? numericValue
                    : numericValue * dateAgeUnit.daysMultiplier,
                comparisonGreater: comparisonGreater
            )
        case .fileType:
            rule = ExclusionRule(
                type: .fileType,
                description: description.isEmpty ? nil : description,
                fileTypeCategory: selectedFileTypeCategory
            )
        default:
            rule = ExclusionRule(
                type: selectedRuleType,
                pattern: trimmedPattern,
                description: description.isEmpty ? nil : description
            )
        }

        save(rule)
    }

    private func save(_ rule: ExclusionRule) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            rulesManager.addRule(rule)
        }
        dismiss()
    }
}

// FlowLayout is now defined globally in AnalysisView.swift

#Preview {
    ExclusionRulesView()
        .environmentObject(ExclusionRulesManager())
        .frame(width: 600, height: 550)
}
