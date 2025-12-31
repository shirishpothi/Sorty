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
                    .buttonStyle(.hapticBounce)
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

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.subtleBounce, value: isHovered)

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
                .buttonStyle(.hapticBounce)
                .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.bar)
        .overlay(Divider(), alignment: .bottom)
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Ready to Organize View

struct ReadyToOrganizeView: View {
    let onStart: () -> Void
    @EnvironmentObject var organizer: FolderOrganizer

    @State private var iconScale: CGFloat = 1.0
    @State private var iconRotation: Double = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 64))
                .foregroundStyle(.purple.gradient)
                .scaleEffect(iconScale)
                .rotationEffect(.degrees(iconRotation))
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6).repeatForever(autoreverses: true)) {
                        iconScale = 1.1
                    }
                    withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                        iconRotation = 5
                    }
                }

            VStack(spacing: 8) {
                Text("Ready to Organize")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)

                Text("AI will analyze your files and suggest an organized folder structure")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
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
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            Button(action: onStart) {
                Label("Start Organization", systemImage: "play.fill")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut("r", modifiers: .command)
            .accessibilityIdentifier("StartOrganizationButton")
            .bounceTap(scale: 0.95)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.9)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
                appeared = true
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    let onRetry: () -> Void

    @State private var shakeOffset: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)
                .offset(x: shakeOffset)
                .onAppear {
                    // Shake animation on appear
                    withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                        shakeOffset = 10
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.1, dampingFraction: 0.3)) {
                            shakeOffset = -10
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.spring(response: 0.1, dampingFraction: 0.5)) {
                            shakeOffset = 0
                        }
                    }
                }

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
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)

            Button("Try Again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .bounceTap(scale: 0.95)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.9)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2)) {
                appeared = true
            }
        }
    }
}
