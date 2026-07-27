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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTargeted = false
    @State private var isHovering = false
    @State private var isBrowseHovering = false
    @State private var isBrowseBeamPressed = false

    @State private var iconBounce = false
    @State private var hasAppeared = false

    init(selectedDirectory: Binding<URL?>, startsVisible: Bool = false) {
        _selectedDirectory = selectedDirectory
        _hasAppeared = State(initialValue: startsVisible)
    }

    var body: some View {
        WorkflowContainer(currentStep: .selectFolder) {
            Spacer()
                .frame(minHeight: 40, maxHeight: .infinity)

            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Text(headlineText)
                        .font(.title)
                        .fontWeight(.bold)
                        .id(headlineText)
                        .transition(.blurReplace)
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: headlineText)
                        .opacity(hasAppeared ? 1 : 0)

                    Text("Drag and drop a folder here, or click to browse")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .opacity(hasAppeared ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.2).delay(0.05), value: hasAppeared)

                dropZone

                Button {
                    HapticFeedbackManager.shared.tap()
                    triggerBrowseBeamPress()
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
                .onboardingBeamBorder(
                    variant: .info,
                    active: hasAppeared,
                    isIntensified: isBrowseHovering || isBrowseBeamPressed,
                    includesInteriorGlow: isBrowseHovering || isBrowseBeamPressed
                )
                .contentShape(Capsule())
                .scaleEffect(isBrowseHovering ? 1.03 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.84), value: isBrowseHovering)
                .onHover { hovering in
                    let wasHovering = isBrowseHovering
                    if hovering && !wasHovering {
                        HapticFeedbackManager.shared.selection()
                    }
                    isBrowseHovering = hovering
                }
                .keyboardShortcut("o", modifiers: .command)
                .opacity(hasAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(0.1), value: hasAppeared)
                .accessibilityIdentifier("BrowseForFolderButton")

                if settingsViewModel.config.enableSmartRename {
                    organizationModePicker
                        .opacity(hasAppeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.2).delay(0.12), value: hasAppeared)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()
                .frame(minHeight: 40, maxHeight: .infinity)

            quickTips
                .opacity(hasAppeared ? 1 : 0)
                .animation(.easeOut(duration: 0.2).delay(0.15), value: hasAppeared)
        }
        .siriDropZone(isTargeted: $isTargeted) { providers in
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

    private var headlineText: String {
        guard settingsViewModel.config.enableSmartRename else {
            return "Select a directory to organize"
        }
        switch settingsViewModel.config.mode {
        case .organize:
            return "Select a directory to organize"
        case .organizeAndRename:
            return "Select a directory to organize & rename"
        case .renameOnly:
            return "Select a directory to rename"
        }
    }

    private var organizationModePicker: some View {
        HStack(spacing: 4) {
            ForEach(OrganizationMode.allCases, id: \.self) { mode in
                OrganizationModeSegment(
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
        .padding(4)
        .systemLiquidGlassBackground(cornerRadius: 999)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Organization mode")
    }

    private var dropZone: some View {
        let dropZoneHeight: CGFloat = settingsViewModel.config.enableSmartRename ? 140 : 150
        let dropZoneCornerRadius: CGFloat = 16
        let folderAccent = SortyDesignSystem.Colors.resolvedAccent
        let dropZoneContent = VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isTargeted ? folderAccent.opacity(0.16) : folderAccent.opacity(0.08))
                    .frame(width: 64, height: 64)
                    .scaleEffect(isTargeted ? 1.1 : 1.0)

                Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(isTargeted ? folderAccent : folderAccent.opacity(0.9))
                    .symbolReplaceTransition(animationValue: isTargeted)
                    .animatedEmptyStateIcon()
                    .scaleEffect(iconBounce ? 1.1 : 1.0)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isTargeted)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: iconBounce)

            Text(isTargeted ? "Drop to select" : "Drop folder here")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isTargeted ? SortyDesignSystem.Colors.resolvedAccent : .secondary)
                .numericTextTransition(animationValue: isTargeted)
        }
        .frame(width: 220, height: dropZoneHeight)

        return Group {
            if #available(macOS 26.0, *) {
                dropZoneContent
                    .systemLiquidGlassBackground(cornerRadius: dropZoneCornerRadius, clear: true)
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .fill(isTargeted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.08) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .strokeBorder(
                                isTargeted ? SortyDesignSystem.Colors.resolvedAccent : Color.secondary.opacity(0.3),
                                lineWidth: 1
                            )
                    }
            } else {
                dropZoneContent
                    .background {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .fill(
                                isTargeted
                                    ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.08)
                                    : Color.secondary.opacity(0.05))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .fill(isTargeted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.08) : .clear)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: dropZoneCornerRadius, style: .continuous)
                            .strokeBorder(
                                isTargeted ? SortyDesignSystem.Colors.resolvedAccent : Color.secondary.opacity(0.3),
                                lineWidth: 1
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
                    try? await Task.sleep(nanoseconds: 150_000_000)  // 0.15s
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
            withAnimation(workflowNavigationAnimation) {
                selectedDirectory = url
            }
        }
    }

    private var workflowNavigationAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.1)
            : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private func triggerBrowseBeamPress() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) {
            isBrowseBeamPressed = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            selectDirectory()
            withAnimation(.easeOut(duration: 0.24)) {
                isBrowseBeamPressed = false
            }
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

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) {
            item, error in
            if let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil),
                url.hasDirectoryPath
            {
                Task { @MainActor in
                    HapticFeedbackManager.shared.success()
                    withAnimation(workflowNavigationAnimation) {
                        selectedDirectory = url
                    }
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
                .foregroundStyle(isHovering ? SortyDesignSystem.Colors.resolvedAccent : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 11, weight: .bold))
                Text(LocalizedStringKey(description))
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

struct OrganizationModeSegment: View {
    let mode: OrganizationMode
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: mode.iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .symbolReplaceTransition(animationValue: mode)
                Text(mode.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize()
                    .numericTextTransition(animationValue: mode)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(
                        isSelected
                            ? SortyDesignSystem.Colors.resolvedAccent
                            : (isHovering ? Color.secondary.opacity(0.12) : Color.clear)
                    )
            }
            .foregroundColor(isSelected ? .white : .primary)
            .contentShape(Capsule())
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && !isHovering {
                HapticFeedbackManager.shared.selection()
            }
            isHovering = hovering
        }
        .help(mode.description)
        .accessibilityLabel(mode.displayName)
        .accessibilityHint(mode.description)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

extension UTType {
    static var fileURL: UTType {
        UTType(exportedAs: "public.file-url")
    }
}
