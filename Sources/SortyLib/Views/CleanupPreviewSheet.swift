//
//  CleanupPreviewSheet.swift
//  Sorty
//
//  Preview dialog for cleanup actions
//  Allows users to review specific files before they are modified or deleted
//

import SwiftUI

public struct CleanupPreviewSheet: View {
    let opportunity: CleanupOpportunity
    let onConfirm: ([CleanupOpportunity.AffectedFile]) -> Void
    let onCancel: () -> Void
    
    @State private var selectedFileIDs: Set<UUID> = []
    @State private var dontShowAgain: Bool = false
    
    public init(
        opportunity: CleanupOpportunity,
        onConfirm: @escaping ([CleanupOpportunity.AffectedFile]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.opportunity = opportunity
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _selectedFileIDs = State(initialValue: Set(opportunity.affectedFiles.map { $0.id }))
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding()
                .background(.ultraThinMaterial)
            
            Divider()
            
            // File List
            List {
                Section {
                    ForEach(opportunity.affectedFiles) { file in
                        FileRow(
                            file: file,
                            isSelected: selectedFileIDs.contains(file.id),
                            toggleSelection: {
                                if selectedFileIDs.contains(file.id) {
                                    selectedFileIDs.remove(file.id)
                                } else {
                                    selectedFileIDs.insert(file.id)
                                }
                            }
                        )
                    }
                } header: {
                    HStack {
                        Text("\(selectedFileIDs.count) files selected")
                        Spacer()
                        Button(selectedFileIDs.count == opportunity.affectedFiles.count ? "Deselect All" : "Select All") {
                            if selectedFileIDs.count == opportunity.affectedFiles.count {
                                selectedFileIDs.removeAll()
                            } else {
                                selectedFileIDs = Set(opportunity.affectedFiles.map { $0.id })
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .listStyle(.inset)
            
            Divider()
            
            // Footer
            footer
                .padding()
                .background(.ultraThinMaterial)
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: opportunity.type.icon)
                .font(.system(size: 32))
                .foregroundStyle(opportunity.type.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(opportunity.action?.rawValue ?? opportunity.type.rawValue)
                    .font(.title3.bold())
                
                Text(opportunity.detailedReason.isEmpty ? opportunity.description : opportunity.detailedReason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
    }
    
    private var footer: some View {
        VStack(spacing: 16) {
            if let action = opportunity.action {
                Toggle("Don't show preview for '\(action.rawValue)' again", isOn: $dontShowAgain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button {
                    confirm()
                } label: {
                    Text("Confirm \(opportunity.action?.rawValue ?? "Cleanup")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedFileIDs.isEmpty)
            }
        }
    }
    
    private func confirm() {
        // Persist "Don't show again" preference if checked
        if dontShowAgain, let action = opportunity.action {
            UserDefaults.standard.set(true, forKey: "skipPreview_\(action.rawValue)")
        }
        
        let selectedFiles = opportunity.affectedFiles.filter { selectedFileIDs.contains($0.id) }
        onConfirm(selectedFiles)
    }
}

private struct FileRow: View {
    let file: CleanupOpportunity.AffectedFile
    let isSelected: Bool
    let toggleSelection: () -> Void
    
    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in toggleSelection() }
            ))
            .labelsHidden()
            
            VStack(alignment: .leading, spacing: 2) {
                Text(file.name)
                    .font(.body)
                    .truncationMode(.middle)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                    
                    if !file.reason.isEmpty {
                        Text("•")
                        Text(file.reason)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection()
        }
    }
}
