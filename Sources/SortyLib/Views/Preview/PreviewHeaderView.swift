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
    
    @State private var isNotesExpanded = false
    
    var body: some View {
        HStack {
            if let onBack = onBack {
                Button {
                    HapticFeedbackManager.shared.tap()
                    onBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("PreviewBackButton")
                .accessibilityLabel("Go back")
                .accessibilityHint("Press Escape to go back")
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Preview \(version)")
                        .font(.headline)
                    
                    if hasEdits {
                        Text("(Edited)")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                if !notes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isNotesExpanded.toggle()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: isNotesExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(.purple)
                                Text("AI Reasoning")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.purple)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.purple.opacity(0.08))
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("AI reasoning")
                        .accessibilityHint(isNotesExpanded ? "Tap to collapse" : "Tap to expand reasoning")
                        
                        if isNotesExpanded {
                            Text(notes)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(6)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .top)),
                                    removal: .opacity
                                ))
                        }
                    }
                }
            }
            
            Spacer()
            
            // Drag hint
            if isDragging {
                HStack(spacing: 4) {
                    Image(systemName: "hand.draw")
                        .font(.caption)
                    Text("Drop on a folder")
                        .font(.caption)
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(6)
            }
            
            Text("\(totalFiles) files • \(totalFolders) folders")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if renameCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "wand.and.stars")
                    Text("\(renameCount) renames")
                }
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(4)
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

#Preview("Preview Header - With Edits") {
    PreviewHeaderView(
        version: 3,
        hasEdits: true,
        notes: "Custom organization",
        totalFiles: 156,
        totalFolders: 12,
        renameCount: 8,
        isDragging: true
    )
    .frame(width: 800)
}
