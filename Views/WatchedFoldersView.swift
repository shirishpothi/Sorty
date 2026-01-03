//
//  WatchedFoldersView.swift
//  FileOrganizer
//
//  Settings view for managing watched folders
//  Enhanced with haptic feedback, micro-animations, and modal bounces
//

import SwiftUI
import UniformTypeIdentifiers

struct WatchedFoldersView: View {
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @State private var showingFolderPicker = false
    @State private var selectedFolderForEdit: WatchedFolder?
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watched Folders")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Automatically organize new files as they arrive")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .animatedAppearance(delay: 0.05)

                Spacer()

                Button {
                    HapticFeedbackManager.shared.tap()
                    showingFolderPicker = true
                } label: {
                    Label("Add Folder", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("AddWatchedFolderButton")
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Folder List
            ZStack {
                if watchedFoldersManager.folders.isEmpty {
                    EmptyWatchedFoldersView()
                        .transition(TransitionStyles.scaleAndFade)
                } else {
                    List {
                        ForEach(Array(watchedFoldersManager.folders.enumerated()), id: \.element.id) { index, folder in
                            WatchedFolderRow(folder: folder)
                                .contextMenu {
                                    Button("Remove") {
                                        HapticFeedbackManager.shared.tap()
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            watchedFoldersManager.removeFolder(folder)
                                        }
                                    }
                                }
                                .animatedAppearance(delay: Double(index) * 0.05)
                        }
                        .onDelete { indexSet in
                            HapticFeedbackManager.shared.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                for index in indexSet {
                                    watchedFoldersManager.removeFolder(watchedFoldersManager.folders[index])
                                }
                            }
                        }
                    }
                    .listStyle(.inset)
                    .transition(TransitionStyles.slideFromRight)
                }
            }
            .animation(.pageTransition, value: watchedFoldersManager.folders.isEmpty)
        }
        .fileImporter(
            isPresented: $showingFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    HapticFeedbackManager.shared.success()
                    let folder = WatchedFolder(path: url.path)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        watchedFoldersManager.addFolder(folder)
                    }
                }
            case .failure(let error):
                HapticFeedbackManager.shared.error()
                DebugLogger.log("Failed to select folder: \(error)")
            }
        }
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
        }
    }
}

// MARK: - Empty State View

struct EmptyWatchedFoldersView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "eye.slash")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No Watched Folders")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Add folders like Downloads or Desktop to automatically organize new files")
                .font(.caption)
                .foregroundColor(.secondary.opacity(0.6))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Watched Folder Row

struct WatchedFolderRow: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @State private var showingConfig = false

    var body: some View {
        HStack(spacing: 12) {
            // Folder Icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(folder.isEnabled ? Color.blue.opacity(0.1) : Color.gray.opacity(0.1))
                    .frame(width: 40, height: 40)

                Image(systemName: "folder.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(folder.isEnabled ? .blue : .gray)
            }

            // Folder Info
            VStack(alignment: .leading, spacing: 4) {
                Text(folder.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(folder.isEnabled ? .primary : .secondary)

                Text(folder.path)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let lastTriggered = folder.lastTriggered {
                    Text("Last organized: \(lastTriggered, style: .relative) ago")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }

            Spacer()

            // Controls
            VStack(alignment: .trailing, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { folder.isEnabled },
                    set: { _ in
                        HapticFeedbackManager.shared.selection()
                        watchedFoldersManager.toggleEnabled(for: folder)
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                if folder.isEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: folder.autoOrganize ? "wand.and.stars" : "wand.and.stars.inverse")
                            .font(.system(size: 10))
                        Text(folder.autoOrganize ? "Auto" : "Manual")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(folder.autoOrganize ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(folder.autoOrganize ? Color.green.opacity(0.1) : Color.clear)
                    .cornerRadius(4)
                    .onTapGesture {
                        HapticFeedbackManager.shared.tap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            watchedFoldersManager.toggleAutoOrganize(for: folder)
                        }
                    }
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                Button {
                    HapticFeedbackManager.shared.tap()
                    showingConfig = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingConfig) {
                    WatchedFolderConfigView(folder: folder)
                        .modalBounce()
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: folder.isEnabled)
        }
        .padding(.vertical, 8)
        .opacity(folder.exists ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .overlay {
            if !folder.exists {
                HStack {
                    Spacer()
                    Text("Folder not found")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(4)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Watched Folder Config View

struct WatchedFolderConfigView: View {
    let folder: WatchedFolder
    @EnvironmentObject var watchedFoldersManager: WatchedFoldersManager
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var customPrompt: String
    @State private var temperature: Double
    @State private var autoOrganize: Bool
    @State private var appeared = false

    init(folder: WatchedFolder) {
        self.folder = folder
        _customPrompt = State(initialValue: folder.customPrompt ?? "")
        _temperature = State(initialValue: folder.temperature ?? 0.7)
        _autoOrganize = State(initialValue: folder.autoOrganize)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(NSColor.windowBackgroundColor).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Liquid Glass Card for Strategy
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Strategy")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Toggle(isOn: $autoOrganize) {
                                VStack(alignment: .leading) {
                                    Text("Auto-Organize")
                                        .font(.headline)
                                    Text("Smart Drop: Only moves new files into existing folders")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .onChange(of: autoOrganize) { _, _ in
                                HapticFeedbackManager.shared.selection()
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
                        .animatedAppearance(delay: 0.1)

                        // Custom Instructions
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Instructions")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $customPrompt)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 100)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)

                            Text("Overrides generic instructions for this folder.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
                        .animatedAppearance(delay: 0.15)

                        // Temperature
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text("Creativity")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f", temperature))
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                                    .contentTransition(.numericText())
                            }

                            Slider(value: $temperature, in: 0...1) {
                                Text("Temperature")
                            } minimumValueLabel: {
                                Text("Focused").font(.caption)
                            } maximumValueLabel: {
                                Text("Creative").font(.caption)
                            }
                            .onChange(of: temperature) { _, _ in
                                HapticFeedbackManager.shared.selection()
                            }
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
                        .animatedAppearance(delay: 0.2)

                        // Calibrate Action
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Maintenance")
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Button {
                                HapticFeedbackManager.shared.tap()
                                appState.calibrateAction?(folder)
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: "tuningfork")
                                    Text("Calibrate Folder")
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)

                            Text("Runs a full organization to set the baseline structure.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.05), radius: 10, y: 5)
                        .animatedAppearance(delay: 0.25)
                    }
                    .padding()
                }
            }
            .navigationTitle(folder.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticFeedbackManager.shared.tap()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        HapticFeedbackManager.shared.success()
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        var updated = folder
        updated.customPrompt = customPrompt.isEmpty ? nil : customPrompt
        updated.temperature = temperature
        updated.autoOrganize = autoOrganize
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            watchedFoldersManager.updateFolder(updated)
        }
        dismiss()
    }
}

#Preview {
    WatchedFoldersView()
        .environmentObject(WatchedFoldersManager())
        .frame(width: 500, height: 400)
}
