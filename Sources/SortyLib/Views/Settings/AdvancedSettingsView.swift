//
//  AdvancedSettingsView.swift
//  Sorty
//
//  Advanced settings section
//

import SwiftUI

struct AdvancedSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var automationManager: AutomationManager
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @State private var showFinderRecommendationInfo = false
    
    var body: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Menu Bar", icon: "menubar.rectangle", color: .blue) {
                SettingsToggle(
                    isOn: $showMenuBarExtra,
                    title: "Show Menu Bar Icon",
                    description: "Display Sorty icon in the menu bar for quick access"
                )
            }
            .animatedAppearance(delay: 0.0)

            SettingsCard(title: "Finder Workflow", icon: "folder.badge.gearshape", color: .mint) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggle(
                        isOn: $automationManager.autoSelectOrganizedFolders,
                        title: "Automatically reveal organized folders",
                        description: "Open Finder and highlight newly organized folders after each completed run"
                    )
                    .accessibilityIdentifier("FinderAutoRevealToggle")

                    if !automationManager.autoSelectOrganizedFolders {
                        Button {
                            showFinderRecommendationInfo.toggle()
                        } label: {
                            Label("Recommendation", systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("FinderAutoRevealRecommendationInfo")
                        .popover(isPresented: $showFinderRecommendationInfo, arrowEdge: .top) {
                            Text("Recommended for most users: keep this off and use \"View in Finder\" when needed.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(width: 300, alignment: .leading)
                        }
                    }
                }
            }
            .animatedAppearance(delay: 0.03)
            
            SettingsCard(title: "Streaming", icon: "waveform", color: .purple) {
                SettingsToggle(
                    isOn: $viewModel.config.enableStreaming,
                    title: "Enable Streaming",
                    description: "Stream AI responses for faster feedback"
                )
            }
            .animatedAppearance(delay: 0.05)
            
            SettingsCard(title: "Timeouts", icon: "clock", color: .orange) {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Request Timeout")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(viewModel.config.requestTimeout))s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.config.requestTimeout, in: 30...600, step: 10)
                        Text("Time to wait for initial response")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Resource Timeout")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(viewModel.config.resourceTimeout))s")
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $viewModel.config.resourceTimeout, in: 60...1800, step: 60)
                        Text("Maximum total request duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .animatedAppearance(delay: 0.1)
            
            SettingsCard(title: "Token Limits", icon: "number", color: .blue) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Max Tokens")
                            .font(.subheadline)
                        Spacer()
                        TextField("Auto", value: $viewModel.config.maxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                    }
                    Text("Leave empty for model default")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .animatedAppearance(delay: 0.15)
            
            SettingsCard(title: "Developer", icon: "hammer", color: .gray) {
                VStack(spacing: 12) {
                    SettingsToggle(
                        isOn: $viewModel.config.showStatsForNerds,
                        title: "Stats for Nerds",
                        description: "Show detailed generation metrics"
                    )
                    
                    Divider()
                    
                    Button {
                        if let logURL = LogManager.shared.exportLogs() {
                            NSWorkspace.shared.activateFileViewerSelecting([logURL])
                        }
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export Debug Logs")
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .animatedAppearance(delay: 0.2)
        }
    }
}

#Preview {
    AdvancedSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(AutomationManager())
        .frame(width: 500, height: 500)
}
