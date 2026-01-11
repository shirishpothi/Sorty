//
//  OrganizeView.swift
//  Sorty
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

            CompactPersonaPicker()
                .padding(.trailing, 8)

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
    @State private var hasAppeared = false
    @State private var isTextFieldFocused = false
    @FocusState private var textFieldFocus: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                iconSection
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                VStack(spacing: 8) {
                    Text("Ready to Organize")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("AI will analyze your files and suggest an organized folder structure")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 450)
                }
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                
                instructionsField
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)

                Button {
                    HapticFeedbackManager.shared.tap()
                    onStart()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                        Text("Start Organization")
                    }
                    .frame(minWidth: 180)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut("r", modifiers: .command)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
                .accessibilityIdentifier("StartOrganizationButton")
            }
            
            Spacer()
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
        }
    }
    
    private var iconSection: some View {
        ZStack {
            Circle()
                .fill(Color.purple.opacity(0.1))
                .frame(width: 100, height: 100)
            
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.purple)
        }
    }
    
    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Additional Instructions")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("(Optional)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if organizer.customInstructions.isEmpty && !textFieldFocus {
                        Text("e.g. \"Group by project\", \"Separate RAW photos\", \"Keep documents by year\"...")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .allowsHitTesting(false)
                    }
                    
                    TextEditor(text: $organizer.customInstructions)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .focused($textFieldFocus)
                        .onChange(of: textFieldFocus) { _, newValue in
                            withAnimation(.smoothEase) {
                                isTextFieldFocused = newValue
                            }
                        }
                }
                .frame(maxWidth: 450, minHeight: 60, maxHeight: 80)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(
                            isTextFieldFocused ? Color.accentColor : Color(NSColor.separatorColor),
                            lineWidth: isTextFieldFocused ? 2 : 1
                        )
                )
                .accessibilityIdentifier("CustomInstructionsTextField")
                .accessibilityLabel("Additional instructions for organization")
                .accessibilityHint("Optional text field to provide custom instructions to the AI")
                
                Text("These instructions will guide the AI in organizing your files")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 24)
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
