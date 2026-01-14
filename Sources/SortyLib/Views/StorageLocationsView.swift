//
//  StorageLocationsView.swift
//  Sorty
//
//  View for managing storage locations - directories where files can be moved TO
//  but won't be reorganized themselves. These serve as destination bins.
//

import SwiftUI
import UniformTypeIdentifiers

struct StorageLocationsView: View {
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    @State private var showingFolderPicker = false
    @State private var selectedLocationForEdit: StorageLocation?
    @State private var contentOpacity: Double = 0
    @State private var suggestedLocationName: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()

            // Location Grid/List
            ZStack {
                if storageLocationsManager.locations.isEmpty {
                    EmptyStorageLocationsView(
                        onAddLocation: {
                            HapticFeedbackManager.shared.tap()
                            suggestedLocationName = nil
                            showingFolderPicker = true
                        },
                        onAddSuggestedLocation: { name, _ in
                            HapticFeedbackManager.shared.tap()
                            suggestedLocationName = name
                            showingFolderPicker = true
                        }
                    )
                    .transition(TransitionStyles.scaleAndFade)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(storageLocationsManager.locations.enumerated()), id: \.element.id) { index, location in
                                StorageLocationCard(location: location)
                                    .animatedAppearance(delay: Double(index) * 0.05)
                            }
                        }
                        .padding(20)
                    }
                    .transition(TransitionStyles.slideFromRight)
                }
            }
            .animation(.pageTransition, value: storageLocationsManager.locations.isEmpty)
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
                    
                    do {
                        try storageLocationsManager.addLocation(url: url, customName: suggestedLocationName)
                        suggestedLocationName = nil
                    } catch {
                        HapticFeedbackManager.shared.error()
                        DebugLogger.log("Failed to add storage location: \(error)")
                    }
                }
            case .failure(let error):
                HapticFeedbackManager.shared.error()
                DebugLogger.log("Failed to select folder: \(error)")
            }
            suggestedLocationName = nil
        }
        .opacity(contentOpacity)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                contentOpacity = 1.0
            }
            // Restore security-scoped access on appear
            storageLocationsManager.restoreSecurityScopedAccess()
        }
    }
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Storage Locations")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack(spacing: 8) {
                    let enabledCount = storageLocationsManager.enabledLocations.count
                    let totalCount = storageLocationsManager.locations.count
                    
                    Text("\(enabledCount) active")
                        .foregroundStyle(enabledCount > 0 ? .green : .secondary)
                    
                    if totalCount > enabledCount {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text("\(totalCount - enabledCount) disabled")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
            .animatedAppearance(delay: 0.05)

            Spacer()

            Button {
                HapticFeedbackManager.shared.tap()
                showingFolderPicker = true
            } label: {
                Label("Add Location", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("AddStorageLocationButton")
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Empty State View

struct EmptyStorageLocationsView: View {
    let onAddLocation: () -> Void
    let onAddSuggestedLocation: (String, String) -> Void  // (suggestedName, icon)
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("No Storage Locations")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Add directories like Archives, Projects, or external drives as destinations for files during organization")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
            }
            
            // Info box
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("How it works")
                        .font(.subheadline.bold())
                }
                
                Text("Storage locations are destination-only folders. Files can be moved TO them during organization, but files already inside won't be reorganized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: 400)
            .background(Color.blue.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // Suggestion cards
            VStack(spacing: 8) {
                Text("Common storage locations:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    StorageSuggestionPill(name: "Archives", icon: "archivebox") {
                        onAddSuggestedLocation("Archives", "archivebox")
                    }
                    StorageSuggestionPill(name: "Projects", icon: "folder.badge.gearshape") {
                        onAddSuggestedLocation("Projects", "folder.badge.gearshape")
                    }
                    StorageSuggestionPill(name: "Backups", icon: "externaldrive") {
                        onAddSuggestedLocation("Backups", "externaldrive")
                    }
                }
            }

            Button {
                onAddLocation()
            } label: {
                Label("Add Storage Location", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct StorageSuggestionPill: View {
    let name: String
    let icon: String
    let onTap: () -> Void
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.tap()
            onTap()
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
                Text(name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isHovered ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .help("Click to add '\(name)' as a storage location")
    }
}

// MARK: - Storage Location Card

struct StorageLocationCard: View {
    let location: StorageLocation
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    @State private var showingConfig = false
    @State private var isHovered = false
    
    private var statusColor: Color {
        if !location.exists { return .red }
        if location.accessStatus == .lost { return .orange }
        if location.accessStatus == .stale { return .yellow }
        if !location.isEnabled { return .secondary }
        return .green
    }
    
    private var statusIcon: String {
        if !location.exists { return "exclamationmark.triangle.fill" }
        if location.accessStatus == .lost { return "lock.slash.fill" }
        if location.accessStatus == .stale { return "exclamationmark.circle.fill" }
        if !location.isEnabled { return "pause.circle.fill" }
        return "checkmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 16) {
            // Folder Icon with Status
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(location.isEnabled ? .purple : .secondary)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 14))
                    .foregroundStyle(statusColor)
                    .background(
                        Circle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(width: 18, height: 18)
                    )
                    .offset(x: 4, y: 4)
            }
            .frame(width: 48, height: 48)

            // Location Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(location.name)
                        .font(.headline)
                        .foregroundColor(location.isEnabled ? .primary : .secondary)
                }

                Text(location.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                // Description and status row
                HStack(spacing: 12) {
                    if let description = location.description, !description.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "text.quote")
                                .font(.caption2)
                            Text(description)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    if !location.exists {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("Folder not found")
                                .font(.caption2)
                        }
                        .foregroundStyle(.red)
                    } else if location.accessStatus == .lost {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.slash.fill")
                                .font(.caption2)
                            Text("Access Lost")
                                .font(.caption2)
                        }
                        .foregroundStyle(.orange)
                        .help("App Sandbox access to this folder was lost. Try removing and re-adding it.")
                    } else if location.accessStatus == .stale {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption2)
                            Text("Needs Refresh")
                                .font(.caption2)
                        }
                        .foregroundStyle(.yellow)
                    }
                }
            }

            Spacer()

            // Controls
            HStack(spacing: 12) {
                if isHovered {
                    // Quick Actions
                    HStack(spacing: 8) {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
                        } label: {
                            Image(systemName: "folder")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Reveal in Finder")
                        
                        Button {
                            HapticFeedbackManager.shared.tap()
                            showingConfig = true
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Configure")
                        
                        Button {
                            HapticFeedbackManager.shared.tap()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                storageLocationsManager.removeLocation(location)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Remove")
                    }
                    .transition(.scale.combined(with: .opacity))
                }
                
                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { location.isEnabled },
                    set: { _ in
                        HapticFeedbackManager.shared.selection()
                        storageLocationsManager.toggleEnabled(for: location)
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: location.isEnabled)
        }
        .padding(16)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(location.exists ? Color.white.opacity(0.1) : Color.red.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 3, x: 0, y: 1)
        .opacity(location.exists ? 1.0 : 0.8)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: location.path)
            }
            Button("Configure...") {
                showingConfig = true
            }
            Divider()
            Button("Remove", role: .destructive) {
                HapticFeedbackManager.shared.tap()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    storageLocationsManager.removeLocation(location)
                }
            }
        }
        .sheet(isPresented: $showingConfig) {
            StorageLocationConfigView(location: location)
                .modalBounce()
        }
    }
}

// MARK: - Storage Location Config View

struct StorageLocationConfigView: View {
    let location: StorageLocation
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var description: String
    @State private var isEnabled: Bool

    init(location: StorageLocation) {
        self.location = location
        _name = State(initialValue: location.name)
        _description = State(initialValue: location.description ?? "")
        _isEnabled = State(initialValue: location.isEnabled)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    Image(systemName: "externaldrive.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(location.name)
                            .font(.headline)
                        Text(location.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button("Done") {
                    HapticFeedbackManager.shared.success()
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Basic Info Section
                    ConfigSection(title: "Display Name", icon: "textformat", color: .blue) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Location name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("A friendly name for this storage location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Description Section
                    ConfigSection(title: "Description for AI", icon: "text.bubble", color: .purple) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $description)
                                .font(.system(.body, design: .default))
                                .frame(height: 80)
                                .scrollContentBackground(.hidden)
                                .padding(10)
                                .background(Color(NSColor.textBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                            
                            Text("Describe what types of files belong here. The AI uses this to decide which files to move to this location.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            // Example suggestions
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Examples:")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text("\"Archive for completed projects older than 6 months\"")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text("\"Storage for large media files and raw footage\"")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text("\"Backup location for important documents\"")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.top, 4)
                        }
                    }
                    
                    // Status Section
                    ConfigSection(title: "Status", icon: "checkmark.circle", color: .green) {
                        Toggle(isOn: $isEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Enabled")
                                    .font(.subheadline)
                                Text("When enabled, AI can suggest moving files to this location")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    
                    // Info Section
                    ConfigSection(title: "How It Works", icon: "questionmark.circle", color: .orange) {
                        VStack(alignment: .leading, spacing: 12) {
                            InfoRow(icon: "arrow.right.circle", text: "Files can be moved TO this location")
                            InfoRow(icon: "xmark.circle", text: "Files already here will NOT be reorganized")
                            InfoRow(icon: "brain", text: "AI uses the description to match appropriate files")
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 450, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func save() {
        var updated = location
        updated.name = name.isEmpty ? location.url.lastPathComponent : name
        updated.description = description.isEmpty ? nil : description
        updated.isEnabled = isEnabled
        
        withAnimation {
            storageLocationsManager.updateLocation(updated)
        }
        dismiss()
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    StorageLocationsView()
        .environmentObject(StorageLocationsManager())
        .frame(width: 600, height: 500)
}
