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
    @State private var selectedCategory: SettingsCategory = .rules
    @State private var contentOpacity: Double = 0

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 200)
            Divider()
            contentView
        }
        .navigationTitle("Settings")
        .opacity(contentOpacity)
        .onAppear {
            if let section = appState.selectedSettingsSection {
                selectedCategory = section
            }
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.3)) {
                    contentOpacity = 1.0
                }
            }
        }
        .onChange(of: appState.selectedSettingsSection) { _, newSection in
            if let section = newSection {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selectedCategory = section
                }
            }
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(SettingsCategoryGroup.allCases, id: \.self) { group in
                sectionHeader(group.rawValue)
                ForEach(SettingsCategory.categories(for: group)) { category in
                    if category != .finder || FeatureFlags.finderSyncEnabled {
                        SidebarButton(
                            title: category.rawValue,
                            icon: category.icon,
                            color: category.color,
                            isSelected: selectedCategory == category
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedCategory = category
                            }
                            HapticFeedbackManager.shared.selection()
                        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                categoryHeader
                categoryContent
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
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
