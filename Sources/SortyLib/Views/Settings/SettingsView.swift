//
//  SettingsView.swift
//  Sorty
//
//  Lightweight settings container with sidebar navigation
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @AppStorage("finderIntegrationEnabled") private var finderIntegrationEnabled = false
    @State private var selectedCategory: SettingsCategory = .rules
    @State private var contentOpacity: Double = 0
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 200)
                .animatedAppearance(delay: 0.03)
            Divider()
            contentView
                .animatedAppearance(delay: 0.08)
        }
        .navigationTitle("Settings")
        .opacity(contentOpacity)
        .onAppear {
            if let section = appState.selectedSettingsSection {
                selectedCategory = section
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
        .onChange(of: appState.selectedSettingsSection) { _, newSection in
            if let section = newSection, section != selectedCategory {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedCategory = section
                }
                if section != .rules {
                    appState.settingsFocusTarget = nil
                }
            }
        }
        .onChange(of: searchText) { _, _ in
            guard !filteredCategories.contains(selectedCategory) else { return }
            if let firstCategory = filteredCategories.first {
                selectedCategory = firstCategory
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Search settings", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search settings")
                .accessibilityHint("Finds matching setting features and sections")
                .help("Search settings by section name, feature name, or keyword")

            if filteredCategories.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No matching settings")
                        .font(.subheadline.weight(.medium))
                    Text("Try broader search terms.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
            } else {
                ForEach(visibleGroups, id: \.self) { group in
                    sectionHeader(group.rawValue)
                    ForEach(filteredCategories(for: group)) { category in
                        SidebarButton(
                            title: category.rawValue,
                            icon: category.icon,
                            color: category.color,
                            isSelected: selectedCategory == category
                        ) {
                            appState.settingsFocusTarget = nil
                            appState.selectedSettingsSection = category
                            HapticFeedbackManager.shared.selection()
                        }
                        .help("\(category.rawValue) settings")
                        .accessibilityHint("Open \(category.rawValue) settings")
                    }
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private var contentView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if isSearching {
                        searchResultsHeader
                            .animatedAppearance(delay: 0.03)
                        searchResultsContent
                            .animatedAppearance(delay: 0.08)
                    } else {
                        categoryHeader
                            .animatedAppearance(delay: 0.03)
                        Group {
                            categoryContent
                                .settingsFocusTarget(appState.settingsFocusTarget)
                        }
                        .id(selectedCategory)
                        .animatedAppearance(delay: 0.08)
                    }
                }
                .padding(24)
            }
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
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var availableCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter(isCategoryEnabled)
    }
    
    private var filteredCategories: [SettingsCategory] {
        guard isSearching else {
            return availableCategories
        }

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
    
    private var visibleGroups: [SettingsCategoryGroup] {
        SettingsCategoryGroup.allCases.filter { !filteredCategories(for: $0).isEmpty }
    }
    
    private func filteredCategories(for group: SettingsCategoryGroup) -> [SettingsCategory] {
        filteredCategories.filter { $0.group == group }
    }
    
    private func isCategoryEnabled(_ category: SettingsCategory) -> Bool {
        category != .finder || finderIntegrationEnabled
    }

    private var categoryHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedCategory.icon)
                .font(.title2)
                .foregroundStyle(selectedCategory.color)
                .frame(width: 32, height: 32)
                .background(selectedCategory.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(selectedCategory.rawValue)
                .font(.title2.bold())
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
                                .buttonStyle(.sortyBordered)
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
    private var categoryContent: some View {
        switch selectedCategory {
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
        .frame(width: 900, height: 700)
}

#Preview("Settings - Provider") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.provider))
        .frame(width: 900, height: 700)
}

#Preview("Settings - Strategy") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.strategy))
        .frame(width: 900, height: 700)
}

#Preview("Settings - Notifications") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.notifications))
        .frame(width: 900, height: 700)
}

#Preview("Settings - Advanced") {
    SettingsView()
        .environmentObject(SettingsViewModel.preview)
        .environmentObject(SettingsPreviewObjects.appStateWithSection(.advanced))
        .frame(width: 900, height: 700)
}
