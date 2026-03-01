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
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @State private var isTargeted = false
    @State private var isHovering = false
    @State private var iconBounce = false
    @State private var hasAppeared = false

    var body: some View {
        WorkflowContainer(currentStep: .selectFolder) {
            Spacer()
                .frame(minHeight: 40, maxHeight: .infinity)
            
            VStack(spacing: 32) {
                VStack(spacing: 10) {
                    Text("Select a directory to organize")
                        .font(.title)
                        .fontWeight(.bold)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)

                    Text("Drag and drop a folder here, or click to browse")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                
                dropZone
                
                Button {
                    HapticFeedbackManager.shared.tap()
                    selectDirectory()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .medium))
                        Text("Browse for Folder")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.onboardingPill)
                .keyboardShortcut("o", modifiers: .command)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                .accessibilityIdentifier("BrowseForFolderButton")
                
                if settingsViewModel.config.enableSmartRename {
                    VStack(spacing: 16) {
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                            Text("ORGANIZATION MODE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 1)
                        }

                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(OrganizationMode.allCases, id: \.self) { mode in
                                OrganizationModeCard(
                                    mode: mode,
                                    isSelected: settingsViewModel.config.mode == mode
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        settingsViewModel.config.mode = mode
                                    }
                                    HapticFeedbackManager.shared.tap()
                                }
                            }
                        }
                        .frame(maxWidth: 520)
                    }
                    .padding(.top, 8)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: hasAppeared)
                }
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
                .frame(minHeight: 40, maxHeight: .infinity)
            
            quickTips
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
        }
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
        let dropZoneHeight: CGFloat = settingsViewModel.config.enableSmartRename ? 120 : 150
        let dropZoneCornerRadius: CGFloat = 16
        let dropZoneContent = VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.blue.opacity(0.08))
                    .frame(width: 64, height: 64)
                    .scaleEffect(isTargeted ? 1.1 : 1.0)

                Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(isTargeted ? Color.accentColor : .blue)
                    .scaleEffect(iconBounce ? 1.1 : 1.0)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isTargeted)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: iconBounce)

            Text(isTargeted ? "Drop to select" : "Drop folder here")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
        }
        .frame(width: 220, height: dropZoneHeight)

        return Group {
            if #available(macOS 26.0, *) {
                dropZoneContent
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: dropZoneCornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.1) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .strokeBorder(
                                isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                                style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [10])
                            )
                    }
            } else {
                dropZoneContent
                    .background {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .fill(isTargeted ? Color.accentColor.opacity(0.08) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .strokeBorder(
                                isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                                style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [10])
                            )
                    }
            }
        }
            .scaleEffect(isTargeted ? 1.05 : 1.0)
            .shadow(color: isTargeted ? .accentColor.opacity(0.2) : .clear, radius: 12, y: 4)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(hasAppeared ? 1 : 0.9)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    iconBounce = true
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
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
        HStack(spacing: 32) {
            QuickTipItemCompact(
                icon: "hand.draw",
                title: "Drag & Drop",
                description: "Drop any folder"
            ) {
                HapticFeedbackManager.shared.tap()
                selectDirectory()
            }

            if FeatureFlags.finderSyncEnabled {
                QuickTipItemCompact(
                    icon: "cursorarrow.click.2",
                    title: "Right-Click",
                    description: "Finder extension"
                )
            } else {
                QuickTipItemCompact(
                    icon: "menubar.rectangle",
                    title: "Menu Bar",
                    description: "Open menu"
                ) {
                    openMenuBarTip()
                }
            }

            QuickTipItemCompact(
                icon: "keyboard",
                title: "Keyboard",
                description: "⌘O to browse"
            ) {
                HapticFeedbackManager.shared.tap()
                selectDirectory()
            }
        }
        .padding(.bottom, 24)
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

    private func openMenuBarTip() {
        HapticFeedbackManager.shared.tap()
        if !UserDefaults.standard.bool(forKey: "showMenuBarIcon") {
            UserDefaults.standard.set(true, forKey: "showMenuBarIcon")
        }
        MenuBarHelper.shared.showMenu()
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil),
               url.hasDirectoryPath {
                Task { @MainActor in
                    HapticFeedbackManager.shared.success()
                    selectedDirectory = url
                }
            }
        }

        return true
    }
}

struct QuickTipItemCompact: View {
    let icon: String
    let title: String
    let description: String
    var action: (() -> Void)? = nil

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(isHovering ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .scaleEffect(isHovering ? 1.03 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovering)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { action?() }
    }
}

struct OrganizationModeCard: View {
    let mode: OrganizationMode
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? .white.opacity(0.2) : Color.accentColor.opacity(0.1))
                        .frame(width: 30, height: 30)

                    Image(systemName: mode.iconName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .accentColor)
                }

                VStack(spacing: 2) {
                    Text(mode.displayName)
                        .font(.caption)
                        .fontWeight(.bold)

                    Text(mode.subtitle)
                        .font(.system(size: 9))
                        .fontWeight(.medium)
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(isHovering ? 0.12 : 0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(isSelected ? .white.opacity(0.2) : .clear, lineWidth: 1)
                    }
            }
            .foregroundColor(isSelected ? .white : .primary)
            .scaleEffect(isHovering ? 1.02 : 1.0)
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(mode.description)
    }
}

extension UTType {
    static var fileURL: UTType {
        UTType(exportedAs: "public.file-url")
    }
}
