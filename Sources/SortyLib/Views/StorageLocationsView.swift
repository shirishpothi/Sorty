//
//  StorageLocationsView.swift
//  Sorty
//
//  Configuration sheet and shared UI for storage locations - directories where
//  files can be moved TO. Managed inline on the Ready to Organize page.
//

import SwiftUI

// MARK: - Storage Location Config View

struct StorageLocationConfigView: View {
    let location: StorageLocation
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String
    @State private var description: String

    init(location: StorageLocation) {
        self.location = location
        _name = State(initialValue: location.name)
        _description = State(initialValue: location.description ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 12) {
                    FolderThumbnailView(url: location.url, size: CGSize(width: 28, height: 28))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(location.name)
                                .font(.headline)

                            StorageProviderBadge(provider: location.capabilityProfile.provider)
                        }
                        PrivacySensitivePathText(path: location.path)
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
                .buttonStyle(.sortyProminent)
            }
            .padding()
            .background(.ultraThinMaterial)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Basic Info Section
                    SettingsCard(title: "Display Name", icon: "textformat", color: .blue) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Location name", text: $name)
                                .textFieldStyle(.roundedBorder)
                            
                            Text("A friendly name for this storage location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    // Description Section
                    SettingsCard(title: "Description for Sorty", icon: "text.bubble", color: .purple) {
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
                            
                            Text("Describe what types of files belong here. Sorty uses this to decide which files to move to this location.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            // Example suggestions
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Examples:")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                DescriptionExampleButton(
                                    text: "Archive for completed projects older than 6 months",
                                    description: $description
                                )
                                DescriptionExampleButton(
                                    text: "Storage for large media files and raw footage",
                                    description: $description
                                )
                                DescriptionExampleButton(
                                    text: "Backup location for important documents",
                                    description: $description
                                )
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 450, height: 460)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func save() {
        var updated = location
        updated.name = name.isEmpty ? location.url.lastPathComponent : name
        updated.description = description.isEmpty ? nil : description
        
        withAnimation {
            storageLocationsManager.updateLocation(updated)
        }
        dismiss()
    }
}

private struct DescriptionExampleButton: View {
    let text: String
    @Binding var description: String
    @State private var isHovered = false

    var body: some View {
        Button {
            HapticFeedbackManager.shared.selection()
            description = text
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.turn.down.right")
                    .accessibilityHidden(true)
                Text("\"\(text)\"")
            }
            .font(.caption2)
            .foregroundStyle(isHovered ? Color.accentColor : Color.secondary.opacity(0.65))
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(isHovered ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .help("Use this description")
        .accessibilityLabel("Use example description: \(text)")
        .onHover { isHovered = $0 }
    }
}

private struct StorageProviderBadge: View {
    let provider: StorageProviderKind

    var body: some View {
        Label(label, systemImage: symbolName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .systemLiquidGlassBackground(cornerRadius: 999)
            .fixedSize()
            .help(accessibilityDescription)
            .accessibilityLabel(accessibilityDescription)
    }

    private var label: String {
        switch provider {
        case .googleDrive: return "Cloud · Google Drive"
        case .dropbox: return "Cloud · Dropbox"
        case .oneDrive: return "Cloud · OneDrive"
        case .box: return "Cloud · Box"
        case .iCloudDrive: return "Cloud · iCloud"
        case .fileProvider: return "Cloud"
        case .externalVolume: return "External Drive"
        case .local: return "Local"
        }
    }

    private var symbolName: String {
        switch provider {
        case .googleDrive, .dropbox, .oneDrive, .box, .fileProvider:
            return "externaldrive.fill.badge.icloud"
        case .iCloudDrive:
            return "icloud.fill"
        case .externalVolume:
            return "externaldrive.fill"
        case .local:
            return "internaldrive.fill"
        }
    }

    private var tint: Color {
        switch provider {
        case .googleDrive: return .blue
        case .dropbox: return .indigo
        case .oneDrive: return .cyan
        case .box: return .purple
        case .iCloudDrive: return .blue
        case .fileProvider: return .teal
        case .externalVolume: return .orange
        case .local: return .secondary
        }
    }

    private var accessibilityDescription: String {
        switch provider {
        case .externalVolume:
            return "External drive storage location"
        case .local:
            return "Local storage location"
        default:
            return "Cloud storage location using \(provider.displayName)"
        }
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
