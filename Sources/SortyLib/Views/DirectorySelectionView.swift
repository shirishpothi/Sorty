//
//  DirectorySelectionView.swift
//  Sorty
//
//  Folder selection with drag-drop support and enhanced animations
//

import SwiftUI
import UniformTypeIdentifiers

struct DirectorySelectionView: View {
    @Binding var selectedDirectory: URL?
    @State private var isTargeted = false
    @State private var isHovering = false
    @State private var iconBounce = false
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 32) {
                dropZone
                
                VStack(spacing: 8) {
                    Text("Select a directory to organize")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)

                    Text("Drag and drop a folder here, or click to browse")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)

                Button {
                    HapticFeedbackManager.shared.tap()
                    selectDirectory()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                        Text("Browse for Folder")
                    }
                    .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                .accessibilityIdentifier("BrowseForFolderButton")
                .accessibilityLabel("Browse for Folder")
                .accessibilityHint("Opens a file picker to select a directory")
            }
            
            Spacer()
            
            quickTips
                .padding(.bottom, 40)
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Directory Selection Area")
        .accessibilityHint("Drag and drop a folder here or use the Browse button")
    }
    
    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [8, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
                .frame(width: 200, height: 200)
                .scaleEffect(isTargeted ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
            
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 80, height: 80)
                        .scaleEffect(isTargeted ? 1.1 : 1.0)
                    
                    Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(isTargeted ? Color.accentColor : .blue)
                        .scaleEffect(iconBounce ? 1.1 : 1.0)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isTargeted)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: iconBounce)
                
                Text(isTargeted ? "Drop to select" : "Drop folder here")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            }
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.9)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    iconBounce = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        iconBounce = false
                    }
                }
            }
        }
        .onTapGesture {
            HapticFeedbackManager.shared.tap()
            selectDirectory()
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Click to browse for a folder")
    }
    
    private var quickTips: some View {
        HStack(spacing: 24) {
            QuickTipItem(
                icon: "hand.draw",
                title: "Drag & Drop",
                description: "Drop any folder directly"
            )
            
            Divider()
                .frame(height: 40)
            
            QuickTipItem(
                icon: "cursorarrow.click.2",
                title: "Right-Click",
                description: "Use Finder extension"
            )
            
            Divider()
                .frame(height: 40)
            
            QuickTipItem(
                icon: "keyboard",
                title: "Keyboard",
                description: "⌘O to browse"
            )
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            HapticFeedbackManager.shared.success()
            selectedDirectory = url
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.hasDirectoryPath {
                DispatchQueue.main.async {
                    HapticFeedbackManager.shared.success()
                    selectedDirectory = url
                }
            }
        }

        return true
    }
}

struct QuickTipItem: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(description)")
    }
}

extension UTType {
    static var fileURL: UTType {
        UTType(exportedAs: "public.file-url")
    }
}
