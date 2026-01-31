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
                .frame(height: 24)
            
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("Select a directory to organize")
                        .font(.title2)
                        .fontWeight(.bold)
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)

                    Text("Drag and drop a folder here, or click to browse")
                        .font(.body)
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
                            .font(.system(size: 14, weight: .medium))
                        Text("Browse for Folder")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.onboardingPill)
                .keyboardShortcut("o", modifiers: .command)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 10)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                .accessibilityIdentifier("BrowseForFolderButton")

                OrganizeSelectionButton()
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.32), value: hasAppeared)
                
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
                        
                        HStack(spacing: 12) {
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
                        .frame(maxWidth: 480)
                    }
                    .padding(.top, 8)
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.35), value: hasAppeared)
                }
            }
            .frame(maxWidth: .infinity)
            
            Spacer()
            
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
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 2, dash: isTargeted ? [] : [10])
                )
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.secondary.opacity(0.05))
                )
                .frame(width: 180, height: 120)
                .scaleEffect(isTargeted ? 1.05 : 1.0)
                .shadow(color: isTargeted ? .accentColor.opacity(0.2) : .clear, radius: 12, y: 4)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isTargeted)
            
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isTargeted ? Color.accentColor.opacity(0.1) : Color.blue.opacity(0.08))
                        .frame(width: 54, height: 54)
                        .scaleEffect(isTargeted ? 1.1 : 1.0)
                    
                    Image(systemName: isTargeted ? "folder.fill.badge.plus" : "folder.badge.plus")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(isTargeted ? Color.accentColor : .blue)
                        .scaleEffect(iconBounce ? 1.1 : 1.0)
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.6), value: isTargeted)
                .animation(.spring(response: 0.3, dampingFraction: 0.5), value: iconBounce)
                
                Text(isTargeted ? "Drop to select" : "Drop folder")
                    .font(.system(size: 13, weight: .medium))
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
        HStack(spacing: 32) {
            QuickTipItemCompact(
                icon: "hand.draw",
                title: "Drag & Drop",
                description: "Drop any folder"
            )
            
            QuickTipItemCompact(
                icon: "cursorarrow.click.2",
                title: "Right-Click",
                description: "Finder extension"
            )
            
            QuickTipItemCompact(
                icon: "keyboard",
                title: "Keyboard",
                description: "⌘O to browse"
            )
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

struct QuickTipItemCompact: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct OrganizationModeCard: View {
    let mode: OrganizationMode
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? .white.opacity(0.2) : Color.accentColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Image(systemName: mode.iconName)
                        .font(.system(size: 16, weight: .medium))
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
            .padding(.vertical, 12)
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

// MARK: - Organize Selection Button

struct OrganizeSelectionButton: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var automationManager: AutomationManager
    @State private var isHovering = false
    @State private var selectionCount: Int = 0
    @State private var isCheckingSelection = false
    @State private var lastCheckTime: Date = .distantPast
    
    // Throttle checks to prevent excessive Apple Events
    private let minimumCheckInterval: TimeInterval = 1.0
    
    var body: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            Task {
                try? await organizer.organizeSelectedFiles()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                if selectionCount > 0 {
                    Text("Organize \(selectionCount) Selected")
                } else {
                    Text("Organize Finder Selection")
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(.accentColor)
        .disabled(automationManager.automationStatus != .granted || selectionCount == 0)
        .opacity(isEnabled ? 1.0 : 0.6)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(helpText)
        .onAppear {
            setupNotificationMonitoring()
            checkSelectionThrottled()
        }
        .onDisappear {
            removeNotificationMonitoring()
        }
    }
    
    private var isEnabled: Bool {
        automationManager.automationStatus == .granted && selectionCount > 0
    }
    
    private var helpText: String {
        if automationManager.automationStatus != .granted {
            return "Automation permission required. Enable in System Settings > Privacy & Security > Automation."
        } else if selectionCount == 0 {
            return "Select files in Finder to organize them"
        } else {
            return "Click to organize \(selectionCount) selected files"
        }
    }
    
    private func checkSelectionThrottled() {
        guard automationManager.automationStatus == .granted else {
            selectionCount = 0
            return
        }
        
        // Throttle to avoid excessive Apple Events
        let now = Date()
        guard now.timeIntervalSince(lastCheckTime) >= minimumCheckInterval else {
            return
        }
        lastCheckTime = now
        
        isCheckingSelection = true
        if let selection = FinderAutomation.getSelectedFiles() {
            selectionCount = selection.count
        } else {
            selectionCount = 0
        }
        isCheckingSelection = false
    }
    
    private func setupNotificationMonitoring() {
        // Monitor when Finder becomes active to check selection
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == "com.apple.finder" {
                Task { @MainActor in
                    checkSelectionThrottled()
                }
            }
        }
        
        // Also check when this window becomes key (user returns to Sorty)
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                checkSelectionThrottled()
            }
        }
    }
    
    private func removeNotificationMonitoring() {
        NotificationCenter.default.removeObserver(self)
    }
}
