//
//  PreviewActionsView.swift
//  Sorty
//
//  Action buttons component with Apply, Cancel, Reset, and Regeneration controls
//

import SwiftUI

struct PreviewActionsView: View {
    let isApplying: Bool
    let hasEdits: Bool
    let hasCustomInstructions: Bool
    let isRedoingWithModel: Bool
    let shouldDisableButtons: Bool
    
    let onCancel: () -> Void
    let onReset: () -> Void
    let onRegenerate: () -> Void
    let onChooseModel: () -> Void
    let onApply: () -> Void
    
    @State private var isHoveringCancel = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Left side: Cancel and Reset
            cancelAndResetSection
            
            Spacer()
            
            // Center: Regeneration controls
            regenerationSection
            
            Spacer()
            
            // Right side: Apply
            applyButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var cancelAndResetSection: some View {
        HStack(spacing: 8) {
            // Prominent Cancel Button with keyboard shortcut
            Button {
                HapticFeedbackManager.shared.tap()
                onCancel()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                    Text("Cancel")
                }
            }
            .buttonStyle(.sortySecondary)
            .keyboardShortcut(.cancelAction)
            .keyboardShortcut(".", modifiers: .command)  // Cmd+.
            .accessibilityIdentifier("PreviewCancelButton")
            .accessibilityLabel("Cancel organization")
            .accessibilityHint("Press Command+Period to cancel")
            
            if hasEdits {
                Button {
                    HapticFeedbackManager.shared.tap()
                    onReset()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text("Reset")
                    }
                }
                .buttonStyle(.sortySecondary(color: .orange))
                .accessibilityIdentifier("ResetEditsButton")
                .accessibilityLabel("Reset all manual edits")
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
    }
    
    private var regenerationSection: some View {
        HStack(spacing: 6) {
            // Regenerate button
            Button {
                HapticFeedbackManager.shared.tap()
                onRegenerate()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11))
                    Text("Regenerate")
                        .font(.system(size: 12))
                    if hasCustomInstructions {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(minWidth: 90)
            }
            .buttonStyle(.sortySecondary(size: .small))
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(shouldDisableButtons || isRedoingWithModel)
            .accessibilityIdentifier("RegenerateButton")
            .accessibilityLabel("Regenerate with current model")
            .accessibilityHint("Press Command+Shift+R to regenerate")
            
            // Choose Model button
            Button {
                HapticFeedbackManager.shared.tap()
                onChooseModel()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 10))
                    Text("Model")
                        .font(.system(size: 11))
                }
                .frame(minWidth: 90)
            }
            .buttonStyle(.sortySecondary(size: .small))
            .disabled(shouldDisableButtons || isRedoingWithModel)
            .accessibilityIdentifier("ChooseModelButton")
            .accessibilityLabel("Choose a different model")
        }
    }
    
    private var applyButton: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            onApply()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                Text("Apply")
                Text("↩")
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.8))
            }
        }
        .buttonStyle(.sortyPrimary)
        .keyboardShortcut(.defaultAction)
        .disabled(shouldDisableButtons)
        .accessibilityIdentifier("ApplyOrganizationButton")
        .accessibilityLabel("Apply this organization to your files")
        .accessibilityHint("Press Return to apply")
    }
}

// MARK: - Progress Actions View (shown during organization)

struct PreviewProgressView: View {
    let progress: Double
    let stage: String
    let estimatedTimeRemaining: TimeInterval?
    let onCancel: () -> Void
    
    @State private var showCancelTooltip = false
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(LinearProgressViewStyle())
                    .accentColor(.purple)
                    .frame(maxWidth: .infinity)
                
                // Time estimate
                if let estimatedTime = estimatedTimeRemaining, estimatedTime > 0 {
                    Text(formatTime(estimatedTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .help("Estimated time remaining")
                }
                
                // Prominent Cancel Button during operation
                Button {
                    HapticFeedbackManager.shared.tap()
                    onCancel()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 12))
                        Text("Stop")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityIdentifier("CancelOrganizationProgressButton")
                .accessibilityLabel("Stop organization")
                .accessibilityHint("Press Command+Period to stop the organization")
            }
            
            HStack {
                HStack(spacing: 6) {
                    Text(stage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if showsAILoadingIndicator {
                        LoadingDotsView(dotCount: 3, dotSize: 4, color: .secondary)
                    }
                }
                
                Spacer()
                
                // Keyboard shortcut hint
                HStack(spacing: 2) {
                    Text("⌘")
                        .font(.caption2)
                    Text(".")
                        .font(.caption2)
                    Text("to stop")
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var showsAILoadingIndicator: Bool {
        let lowercased = stage.lowercased()
        return lowercased.contains("ai") ||
               lowercased.contains("receiving") ||
               lowercased.contains("analyzing") ||
               lowercased.contains("reasoning")
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: "%.0fs", interval)
        } else {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        }
    }
}

// MARK: - Compact Instructions Row

struct PreviewInstructionsRow: View {
    @Binding var instructions: String
    @FocusState var isFocused: Bool
    let onInstructionsChanged: (String) -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.bubble")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            
            TextField(
                "Guiding instructions for regeneration...",
                text: $instructions,
                axis: .horizontal
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($isFocused)
            .onChange(of: instructions) { oldValue, newValue in
                if !newValue.isEmpty && newValue != oldValue {
                    onInstructionsChanged(newValue)
                }
            }
            .accessibilityIdentifier("CompactInstructionsTextField")
            .accessibilityLabel("Guiding instructions")
            .accessibilityHint("Enter instructions to guide AI regeneration")
            
            if !instructions.isEmpty {
                Button {
                    instructions = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear instructions")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }
}

// MARK: - Previews

#Preview("Preview Actions - Standard") {
    PreviewActionsView(
        isApplying: false,
        hasEdits: false,
        hasCustomInstructions: false,
        isRedoingWithModel: false,
        shouldDisableButtons: false,
        onCancel: {},
        onReset: {},
        onRegenerate: {},
        onChooseModel: {},
        onApply: {}
    )
    .frame(width: 800)
}

#Preview("Preview Actions - With Edits") {
    PreviewActionsView(
        isApplying: false,
        hasEdits: true,
        hasCustomInstructions: true,
        isRedoingWithModel: false,
        shouldDisableButtons: false,
        onCancel: {},
        onReset: {},
        onRegenerate: {},
        onChooseModel: {},
        onApply: {}
    )
    .frame(width: 800)
}

#Preview("Preview Progress") {
    PreviewProgressView(
        progress: 0.45,
        stage: "Moving files...",
        estimatedTimeRemaining: 125,  // 2m 5s
        onCancel: {}
    )
    .frame(width: 800)
}

#Preview("Preview Instructions Row") {
    @Previewable @State var instructions = "Group by date"
    
    PreviewInstructionsRow(
        instructions: $instructions,
        onInstructionsChanged: { _ in }
    )
    .frame(width: 800)
}
