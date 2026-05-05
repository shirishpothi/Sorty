//
//  SettingsView.swift
//  Sorty
//
//  Native macOS settings container with source-list navigation
//

import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @AppStorage("finderIntegrationEnabled") private var finderIntegrationEnabled = false
    @State private var selectedCategory: SettingsCategory = .rules
    @State private var searchText = ""

    public init() {}

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var selectedCategoryBinding: Binding<SettingsCategory?> {
        Binding(
            get: { selectedCategory },
            set: { newCategory in
                guard let newCategory else { return }
                selectCategory(newCategory)
            }
        )
    }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                SettingsSearchField(text: $searchText)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)

                List(selection: selectedCategoryBinding) {
                    if isSearching {
                        ForEach(filteredCategories) { category in
                            sidebarRow(for: category)
                        }
                    } else {
                        ForEach(SettingsCategoryGroup.allCases, id: \.self) { group in
                            let categories = availableCategories.filter { $0.group == group }
                            if !categories.isEmpty {
                                Section(group.rawValue) {
                                    ForEach(categories) { category in
                                        sidebarRow(for: category)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 270)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            categoryDetail(selectedCategory)
        }
        .frame(minWidth: 960, idealWidth: 1080, minHeight: 640, idealHeight: 720)
        .navigationTitle(isSearching ? "Search Results" : selectedCategory.rawValue)
        .onAppear {
            if let section = appState.selectedSettingsSection {
                selectedCategory = section
            }
        }
        .onChange(of: appState.selectedSettingsSection) { _, newSection in
            guard let section = newSection, section != selectedCategory else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedCategory = section
            }
            if section != .rules {
                appState.settingsFocusTarget = nil
            }
        }
        .onChange(of: searchText) { _, _ in
            guard !filteredCategories.contains(selectedCategory) else { return }
            if let firstCategory = filteredCategories.first {
                selectedCategory = firstCategory
            }
        }
    }

    private func categoryDetail(_ category: SettingsCategory) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isSearching {
                        searchResultsHeader
                        searchResultsContent
                    } else {
                        categoryHeader(for: category)
                        categoryContent(for: category)
                            .settingsFocusTarget(appState.settingsFocusTarget)
                    }
                }
                .padding(.horizontal, 34)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                scrollToFocusedSetting(using: proxy)
            }
            .onChange(of: appState.settingsFocusTarget) { _, _ in
                scrollToFocusedSetting(using: proxy)
            }
            .onChange(of: selectedCategory) { _, _ in
                scrollToFocusedSetting(using: proxy)
            }
        }
    }

    private var availableCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter(isCategoryEnabled)
    }

    private var filteredCategories: [SettingsCategory] {
        guard isSearching else { return availableCategories }
        let matchedCategorySet = Set(searchResults.map(\.category))
        return availableCategories.filter { matchedCategorySet.contains($0) || $0.matchesSearch(query: trimmedSearchText) }
    }

    private var searchResults: [SettingsFeatureMatch] {
        guard isSearching else { return [] }

        let query = trimmedSearchText
        return availableCategories
            .flatMap { category in
                let matches = category.featureMatches(query: query)
                if !matches.isEmpty {
                    return matches
                }

                if category.matchesSearch(query: query) {
                    let fallback = SettingsFeatureSnippet(
                        title: category.rawValue,
                        summary: "Open this section to review settings related to \"\(query)\"."
                    )
                    return [SettingsFeatureMatch(category: category, snippet: fallback, score: 1)]
                }
                return []
            }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.category.rawValue != $1.category.rawValue {
                    return $0.category.rawValue < $1.category.rawValue
                }
                return $0.snippet.title < $1.snippet.title
            }
    }

    private func isCategoryEnabled(_ category: SettingsCategory) -> Bool {
        category != .finder || finderIntegrationEnabled
    }

    private func sidebarRow(for category: SettingsCategory) -> some View {
        SettingsSidebarRow(
            category: category,
            isSearching: isSearching,
            matchCount: matchCount(for: category)
        )
        .tag(category)
        .help("\(category.rawValue) settings")
        .accessibilityHint("Open \(category.rawValue) settings")
        .accessibilityIdentifier("SettingsSidebarRow_\(category.rawValue)")
    }

    private func selectCategory(_ category: SettingsCategory) {
        guard selectedCategory != category else { return }
        appState.settingsFocusTarget = nil
        appState.selectedSettingsSection = category
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            selectedCategory = category
        }
        HapticFeedbackManager.shared.selection()
    }

    private func matchCount(for category: SettingsCategory) -> Int? {
        guard isSearching else { return nil }
        let count = searchResults.filter { $0.category == category }.count
        return count > 0 ? count : nil
    }

    private func categoryHeader(for category: SettingsCategory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.icon)
                .font(.title2)
                .foregroundStyle(category.color)
                .frame(width: 32, height: 32)
                .background(category.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.title2.bold())
                Text(category.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.bottom, 4)
    }

    private var searchResultsHeader: some View {
        let uniqueCategoryCount = Set(searchResults.map(\.category)).count

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Search Results")
                    .font(.title2.bold())
            }

            Text("\"\(trimmedSearchText)\" matched \(searchResults.count) \(searchResults.count == 1 ? "setting" : "settings") in \(uniqueCategoryCount) \(uniqueCategoryCount == 1 ? "section" : "sections").")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if searchResults.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("No matching settings")
                    .font(.headline)
                Text("Try a broader term like \"tags\", \"notifications\", or \"automation\".")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(searchResults) { result in
                    SettingsCard(
                        title: result.snippet.title,
                        icon: result.category.icon,
                        color: result.category.color
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(result.snippet.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 8) {
                                Label(result.category.rawValue, systemImage: result.category.icon)
                                    .font(.caption)
                                    .foregroundStyle(result.category.color)

                                Spacer()

                                Button {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        selectedCategory = result.category
                                        searchText = ""
                                    }
                                    appState.selectedSettingsSection = result.category
                                    appState.settingsFocusTarget = result.category.focusTarget(for: result.snippet)
                                    HapticFeedbackManager.shared.selection()
                                } label: {
                                    Label("Open Section", systemImage: "arrow.right.circle")
                                        .font(.caption)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .minimumHitTarget()
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categoryContent(for category: SettingsCategory) -> some View {
        switch category {
        case .rules:
            OrganizationRulesSettingsView()
                .environmentObject(appState)
                .environmentObject(viewModel)
        case .provider:
            AIProviderSettingsView().environmentObject(viewModel)
        case .strategy:
            OrganizationStrategySettingsView().environmentObject(viewModel)
        case .tuning:
            ParameterTuningSettingsView().environmentObject(viewModel)
        case .automation:
            AutomationSettingsView()
                .environmentObject(viewModel)
                .environmentObject(appState)
        case .finder:
            FeatureFlags.finderSyncEnabled ? AnyView(FinderIntegrationSettingsView()) : AnyView(finderDisabledView)
        case .notifications:
            NotificationsSettingsView()
        case .advanced:
            AdvancedSettingsView().environmentObject(viewModel)
        case .troubleshooting:
            TroubleshootingSettingsView().environmentObject(viewModel)
        case .help:
            HelpSettingsView().environmentObject(appState)
        case .experimental:
            ExperimentalSettingsView()
        }
    }

    private var finderDisabledView: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Finder Integration is currently disabled")
                .font(.headline)
            Text("Enable via Terminal:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("defaults write com.sorty.app finderIntegrationEnabled -bool true")
                .font(.system(.caption, design: .monospaced))
                .padding(10)
                .background(Color.black.opacity(0.05))
                .cornerRadius(8)
                .textSelection(.enabled)
            Text("Then relaunch Sorty.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private func scrollToFocusedSetting(using proxy: ScrollViewProxy) {
        guard !isSearching, selectedCategory == .rules else { return }
        guard let target = appState.settingsFocusTarget else { return }

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                proxy.scrollTo(target.rawValue, anchor: .top)
            }
        }
    }
}

private struct SettingsSidebarRow: View {
    let category: SettingsCategory
    let isSearching: Bool
    let matchCount: Int?

    var body: some View {
        Label {
            HStack(spacing: 8) {
                Text(category.shortTitle)
                    .lineLimit(1)

                Spacer(minLength: 4)

                if isSearching, let matchCount {
                    Text("\(matchCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        } icon: {
            Image(systemName: category.icon)
                .foregroundStyle(category.color)
                .frame(width: 16)
        }
    }
}

private struct SettingsSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14)

            TextField("Search Settings", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityLabel("Search settings")
                .accessibilityHint("Finds matching setting features and sections")

            if !text.isEmpty {
                Button {
                    text = ""
                    HapticFeedbackManager.shared.selection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear settings search")
                .accessibilityIdentifier("SettingsSearchClearButton")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary.opacity(isFocused ? 0.24 : isHovered ? 0.18 : 0.10), lineWidth: 1)
        )
        .onHover { hovering in
            if hovering && !isHovered {
                HapticFeedbackManager.shared.selection()
            }
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .accessibilityIdentifier("SettingsSearchField")
    }
}

private extension SettingsCategory {
    var shortTitle: String {
        switch self {
        case .provider: return "Provider"
        case .strategy: return "Strategy"
        case .rules: return "Rules"
        case .tuning: return "Tuning"
        case .automation: return "Automation"
        case .finder: return "Finder"
        case .notifications: return "Notifications"
        case .advanced: return "Advanced"
        case .troubleshooting: return "Troubleshoot"
        case .help: return "Help"
        case .experimental: return "Experimental"
        }
    }

    var description: String {
        switch self {
        case .provider: return "Models, keys, and endpoints"
        case .strategy: return "Scanning, naming, and AI behavior"
        case .rules: return "Destinations, prompts, and limits"
        case .tuning: return "Quality, token, and timeout controls"
        case .automation: return "Watched folders and background work"
        case .finder: return "Quick actions and Finder services"
        case .notifications: return "Alerts, sounds, and delivery"
        case .advanced: return "Privacy and technical preferences"
        case .troubleshooting: return "Repair, reset, and diagnostics"
        case .help: return "Guides, links, and support"
        case .experimental: return "Flags and beta features"
        }
    }
}

// MARK: - Previews

@MainActor
private enum SettingsPreviewObjects {
    static var appStateWithSection: (_ section: SettingsCategory) -> AppState {
        { section in
            let state = AppState()
            state.selectedSettingsSection = section
            return state
        }
    }
}

#Preview("Settings - Rules") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.rules))
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .frame(width: 900, height: 700)
}

#Preview("Settings - Provider") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.provider))
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .frame(width: 900, height: 700)
}

#Preview("Settings - Strategy") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.strategy))
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .frame(width: 900, height: 700)
}

#Preview("Settings - Notifications") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.notifications))
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .frame(width: 900, height: 700)
}

#Preview("Settings - Advanced") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.advanced))
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .frame(width: 900, height: 700)
}
