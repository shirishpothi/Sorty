//
//  SettingsView.swift
//  Sorty
//
//  Native macOS settings container with tabbed navigation
//

import SwiftUI

public struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState
    @AppStorage("finderIntegrationEnabled") private var finderIntegrationEnabled = false
    @State private var selectedTab: SettingsTab = .organization
    @State private var selectedCategory: SettingsCategory = .rules

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                settingsTabContent(tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                    .tag(tab)
            }
        }
        .frame(width: 620, height: 720)
        .tint(.accentColor)
        .navigationTitle("Settings")
        .onAppear {
            if let section = appState.selectedSettingsSection {
                selectCategory(section, animated: false)
            }
        }
        .onChange(of: appState.selectedSettingsSection) { _, newSection in
            guard let section = newSection, section != selectedCategory else { return }
            selectCategory(section, animated: true)
        }
    }

    private func settingsTabContent(_ tab: SettingsTab) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(availableCategories(in: tab)) { category in
                        categoryHeader(for: category)
                            .id(category.rawValue)
                            .accessibilityAddTraits(.isHeader)

                        categoryContent(for: category)
                            .settingsFocusTarget(appState.settingsFocusTarget)

                        if category != availableCategories(in: tab).last {
                            SettingsSectionDivider()
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                scrollToSelectedCategory(in: tab, using: proxy)
            }
            .onChange(of: appState.settingsFocusTarget) { _, _ in
                scrollToFocusedSetting(using: proxy)
            }
            .onChange(of: selectedCategory) { _, _ in
                scrollToSelectedCategory(in: tab, using: proxy)
            }
        }
    }

    private func availableCategories(in tab: SettingsTab) -> [SettingsCategory] {
        tab.categories.filter(isCategoryEnabled)
    }

    private func isCategoryEnabled(_ category: SettingsCategory) -> Bool {
        category != .finder || finderIntegrationEnabled
    }

    private func selectCategory(_ category: SettingsCategory, animated: Bool) {
        let updateSelection = {
            selectedTab = category.tab
            selectedCategory = category
        }
        if animated {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                updateSelection()
            }
            HapticFeedbackManager.shared.selection()
        } else {
            updateSelection()
        }
        if category != .rules {
            appState.settingsFocusTarget = nil
        }
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
        guard selectedCategory == .rules else { return }
        guard let target = appState.settingsFocusTarget else { return }

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                proxy.scrollTo(target.rawValue, anchor: .top)
            }
        }
    }

    private func scrollToSelectedCategory(in tab: SettingsTab, using proxy: ScrollViewProxy) {
        guard selectedCategory.tab == tab else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                proxy.scrollTo(selectedCategory.rawValue, anchor: .top)
            }
        }
    }
}

private extension SettingsCategory {
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
