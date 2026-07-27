//
//  PreviewHeaderView.swift
//  Sorty
//
//  Header component for the preview view with title, stats, and drag hints
//

import SwiftUI

struct PreviewHeaderView: View {
    let version: Int
    let hasEdits: Bool
    let notes: String
    let totalFiles: Int
    let totalFolders: Int
    let renameCount: Int
    let isDragging: Bool
    var onBack: (() -> Void)? = nil
    var totalVersions: Int = 1
    var isViewingHistory: Bool = false
    var onPreviousVersion: (() -> Void)? = nil
    var onNextVersion: (() -> Void)? = nil

    @State private var showNotesPopover = false

    var body: some View {
        HStack {
            if let onBack = onBack {
                GlassyBackButton(action: onBack)
                    .keyboardShortcut(.escape, modifiers: [])
                    .accessibilityIdentifier("PreviewBackButton")
                    .accessibilityHint("Press Escape to go back")
            }

            HStack(spacing: 6) {
                // Version navigation
                if totalVersions > 1 {
                    Button {
                        HapticFeedbackManager.shared.selection()
                        onPreviousVersion?()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(version <= 1)
                }

                Text(version == 1 ? "Preview" : "Preview \(version)")
                    .font(.headline)
                    .numericTextTransition(animationValue: version)

                if totalVersions > 1 {
                    Button {
                        HapticFeedbackManager.shared.selection()
                        onNextVersion?()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isViewingHistory)
                }

                if isViewingHistory {
                    Text("(History)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }

                if hasEdits {
                    Text("(Edited)")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(4)
                }

                if !notes.isEmpty {
                    Button {
                        showNotesPopover.toggle()
                    } label: {
                        ZStack {
                            Image(systemName: "brain")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(showNotesPopover ? Color.purple : Color.secondary)
                        }
                        .frame(width: 22, height: 22)
                        .systemLiquidGlassBackground(cornerRadius: 11)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(showNotesPopover ? 0.5 : 0.3),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .help("View AI reasoning")
                    .accessibilityLabel("AI reasoning")
                    .accessibilityHint("Show plan reasoning popover")
                    .popover(isPresented: $showNotesPopover, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 8) {
                                ZStack {
                                    Circle()
                                        .fill(Color.purple.opacity(0.12))
                                        .frame(width: 28, height: 28)

                                    Image(systemName: "brain")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.purple)
                                }

                                Text("AI Reasoning")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.primary)

                                Spacer()
                            }
                            .padding(.bottom, 10)

                            Divider()
                                .opacity(0.4)
                                .padding(.bottom, 10)

                            FormattedReasoningText(
                                text: notes,
                                font: .callout,
                                secondaryFont: .caption,
                                foregroundStyle: .primary
                            )
                        }
                        .padding(14)
                        .frame(minWidth: 240, maxWidth: 340)
                        .systemLiquidGlassPopover(cornerRadius: 12)
                    }
                }
            }

            Spacer()

            // Drag hint
            if isDragging {
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw")
                        .font(.caption)
                    Text("Drop in a folder")
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .systemLiquidGlassBackground(cornerRadius: 6)
            }

            Text("\(totalFiles) files • \(totalFolders) folders")
                .font(.caption)
                .foregroundColor(.secondary)
                .numericTextTransition(
                    animationValue: "\(totalFiles)-\(totalFolders)"
                )

            if renameCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("\(renameCount) renames")
                        .numericTextTransition(animationValue: renameCount)
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .systemLiquidGlassBackground(cornerRadius: 4)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preview header showing \(totalFiles) files in \(totalFolders) folders")
    }
}

// MARK: - Previews

#Preview("Preview Header - Standard") {
    PreviewHeaderView(
        version: 1,
        hasEdits: false,
        notes: "Organized by file type",
        totalFiles: 42,
        totalFolders: 5,
        renameCount: 0,
        isDragging: false
    )
    .frame(width: 800)
}

#Preview("Preview Header - With History") {
    PreviewHeaderView(
        version: 3,
        hasEdits: true,
        notes: "Custom organization",
        totalFiles: 156,
        totalFolders: 12,
        renameCount: 8,
        isDragging: true,
        totalVersions: 3,
        isViewingHistory: false
    )
    .frame(width: 800)
}
