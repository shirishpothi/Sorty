//
//  OrganizeView.swift
//  FileOrganizer
//
//  Main organization workflow view with improved layout
//  Enhanced with micro-animations, haptic feedback, and state transitions
//

import SwiftUI

struct OrganizeView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var appState: AppState

    @State private var previousState: OrganizationState?

    var body: some View {
        VStack(spacing: 0) {
            // Header with selected directory
            if let directory = appState.selectedDirectory {
                DirectoryHeader(url: directory) {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.pageTransition) {
                        appState.selectedDirectory = nil
                        organizer.reset()
                    }
                }
                .transition(TransitionStyles.slideFromBottom)
            }

            // Main content area with animated transitions
            ZStack {
                if appState.selectedDirectory == nil {
                    DirectorySelectionView(selectedDirectory: $appState.selectedDirectory)
                        .transition(TransitionStyles.scaleAndFade)
                } else {
                    stateContent
                        .id(stateIdentifier)
                        .transition(TransitionStyles.scaleAndFade)
                }
            }
            .animation(.pageTransition, value: stateIdentifier)
        }
        .navigationTitle("Organize Files")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if organizer.state == .ready {
                    Button {
                        HapticFeedbackManager.shared.tap()
                        Task {
                            try? await organizer.regeneratePreview()
                        }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                }
            }
        }
        .onAppear {
            configureOrganizer()
        }
        .onChange(of: settingsViewModel.config.provider) { oldValue, newValue in
            configureOrganizer()
        }
        .onChange(of: organizer.state) { oldValue, newValue in
            handleStateChange(to: newValue)
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        Group {
            if case .idle = organizer.state {
                ReadyToOrganizeView(onStart: startOrganization)
            } else if case .scanning = organizer.state {
                AnalysisView()
            } else if case .organizing = organizer.state {
                AnalysisView()
            } else if case .ready = organizer.state, let plan = organizer.currentPlan {
                PreviewView(plan: plan, baseURL: appState.selectedDirectory!)
            } else if case .completed = organizer.state {
                OrganizationResultView()
            } else if case .error(let error) = organizer.state {
                ErrorView(error: error) {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.pageTransition) {
                        organizer.reset()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var stateIdentifier: String {
        switch organizer.state {
        case .idle: return "idle"
        case .scanning: return "scanning"
        case .organizing: return "organizing"
        case .ready: return "ready"
        case .applying: return "applying"
        case .completed: return "completed"
        case .error: return "error"
        }
    }

    private func handleStateChange(to newState: OrganizationState) {
        switch newState {
        case .completed:
            HapticFeedbackManager.shared.success()
        case .error:
            HapticFeedbackManager.shared.error()
        case .ready:
            HapticFeedbackManager.shared.success()
        case .scanning, .organizing:
            HapticFeedbackManager.shared.selection()
        default:
            break
        }
    }

    private func configureOrganizer() {
        Task {
            do {
                try await organizer.configure(with: settingsViewModel.config)
            } catch {
                organizer.state = .error(error)
            }
        }
    }

    private func startOrganization() {
        guard let directory = appState.selectedDirectory else { return }

        HapticFeedbackManager.shared.tap()

        Task {
            do {
                try await organizer.organize(directory: directory)
            } catch {
                organizer.state = .error(error)
            }
        }
    }
}

// MARK: - Directory Header

struct DirectoryHeader: View {
    let url: URL
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent)
                    .font(.headline)
                Text(url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("Change Folder", action: onClear)
                .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
    }
}

// MARK: - Ready to Organize View

struct ReadyToOrganizeView: View {
    let onStart: () -> Void
    @EnvironmentObject var organizer: FolderOrganizer

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(.purple.gradient)

            VStack(spacing: 8) {
                Text("Ready to Organize")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("AI will analyze your files and suggest an organized folder structure")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            // Custom Instructions
            VStack(alignment: .leading, spacing: 8) {
                Text("Additional Instructions (Optional)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("E.g. Group by project, Separate raw photos...", text: $organizer.customInstructions)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 400)
                    .accessibilityIdentifier("CustomInstructionsTextField")
            }
            .padding(.bottom, 8)

            Button(action: onStart) {
                Label("Start Organization", systemImage: "play.fill")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityIdentifier("StartOrganizationButton")
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(error.localizedDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
        }
    }
}
