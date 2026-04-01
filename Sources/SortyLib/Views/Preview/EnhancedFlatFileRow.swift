//
//  EnhancedFlatFileRow.swift
//  Sorty
//
//  Enhanced file row with improved keyboard navigation for inline rename
//  and smart truncation for insight pills
//

import SwiftUI
import UniformTypeIdentifiers

struct EnhancedFlatFileRow: View {
    let file: FileItem
    let depth: Int
    let parentFolderID: UUID
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    let previousFieldID: String?
    let nextFieldID: String?
    
    @State private var isDragging = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @FocusState private var isFocused: Bool
    
    private var renameMapping: FileRenameMapping? {
        store.renameMappings[file.id]
    }

    private var fileTags: [String] {
        store.tagMappings[file.id] ?? []
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                FileThumbnailView(url: URL(fileURLWithPath: file.path), size: CGSize(width: 20, height: 20))
                
                if isEditingName {
                    renameTextField
                } else {
                    fileNameView
                }
                
                Spacer()
                
                renameIndicator

                if !fileTags.isEmpty {
                    TagDotsView(tags: fileTags)
                }
                
                Text(file.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            
            if let mapping = renameMapping, mapping.hasRename, !isEditingName {
                renamePill(mapping: mapping)
            }
        }
        .padding(.leading, CGFloat(depth * 20))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isEditingName ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .contextMenu {
            contextMenuContent
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .onDrag {
            isDragging = true
            dragDropManager.startDrag(file)
            return NSItemProvider(object: file.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            isDragging = false
            return false
        }
    }
    
    // MARK: - Subviews
    
    private var renameTextField: some View {
        TextField("New name", text: $editedName)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit {
                saveRename()
                moveFocusToNext()
            }
            .onExitCommand {
                cancelRename()
            }
            .onAppear {
                isFocused = true
            }
            // Note: Tab/Shift+Tab navigation would require focus management
            // via a coordinator pattern for proper implementation
    }
    
    private var fileNameView: some View {
        Text(file.displayName)
            .lineLimit(1)
            .strikethrough(renameMapping?.hasRename ?? false, color: .secondary)
            .foregroundColor((renameMapping?.hasRename ?? false) ? .secondary : .primary)
    }
    
    private var renameIndicator: some View {
        Group {
            if let mapping = renameMapping, mapping.hasRename {
                Image(systemName: "wand.and.stars")
                    .font(.caption)
                    .foregroundColor(.purple)
                    .help(mapping.renameReason ?? "AI suggested rename")
            }
        }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        } label: {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        
        Button {
            NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
        } label: {
            Label("Reveal in Finder", systemImage: "folder")
        }
        
        if let mapping = renameMapping, mapping.hasRename {
            Divider()
            
            Button {
                if let suggestedName = mapping.suggestedName {
                    startEditing(initialValue: suggestedName)
                }
            } label: {
                Label("Edit Rename", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                store.rejectRename(fileID: file.id, folderID: parentFolderID)
                onPlanChanged()
            } label: {
                Label("Keep Original Name", systemImage: "arrow.uturn.backward")
            }
        }
        
        Divider()
        
        Button(role: .destructive) {
            store.moveFileToUnorganized(fileID: file.id)
            onPlanChanged()
        } label: {
            Label("Revert Organization", systemImage: "arrow.uturn.backward")
        }
    }
    
    private func renamePill(mapping: FileRenameMapping) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.right")
                .font(.caption2)
                .foregroundColor(.purple)
            
            Text(mapping.suggestedName ?? "")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.purple)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            Button {
                startEditing(initialValue: mapping.suggestedName ?? "")
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit suggested name")
            
            Button {
                store.rejectRename(fileID: file.id, folderID: parentFolderID)
                onPlanChanged()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.plain)
            .help("Keep original name")
        }
        .padding(.leading, 20)
        .transition(.opacity)
    }
    
    // MARK: - Actions
    
    private func startEditing(initialValue: String) {
        editedName = initialValue
        isEditingName = true
    }
    
    private func saveRename() {
        if !editedName.isEmpty {
            store.updateRename(fileID: file.id, folderID: parentFolderID, newName: editedName)
            onPlanChanged()
        }
        isEditingName = false
    }
    
    private func cancelRename() {
        isEditingName = false
    }
    
    private func moveFocusToNext() {
        // This would be handled by a focus manager in the parent view
        // For now, we just end editing
        isEditingName = false
    }
    
    private func moveFocusToPrevious() {
        // This would be handled by a focus manager in the parent view
        // For now, we just end editing
        isEditingName = false
    }
}

// MARK: - Truncated Insight Pill

struct TruncatedInsightPill: View {
    let text: String
    let maxWidth: CGFloat = 200
    
    @State private var isTruncated = false
    @State private var showTooltip = false
    
    var body: some View {
        HStack(spacing: 4) {
            Text(truncatedText)
                .font(.caption)
                .foregroundColor(.purple)
                .lineLimit(1)
                .background(
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            isTruncated = geometry.size.width > maxWidth
                        }
                    }
                )
            
            if isTruncated || text.count > 50 {
                Button {
                    showTooltip.toggle()
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.caption)
                        .foregroundColor(.purple.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(text)
                .popover(isPresented: $showTooltip) {
                    Text(text)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: 300)
                        .systemLiquidGlassPopover(cornerRadius: 12)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.1))
        )
    }
    
    private var truncatedText: String {
        if text.count > 50 {
            return String(text.prefix(50)) + "..."
        }
        return text
    }
}

// MARK: - Previews

#Preview("Enhanced File Row") {
    let file = FileItem(path: "/test/document.pdf", name: "document", extension: "pdf", size: 1024)
    let store = PreviewStore(plan: OrganizationPlan())
    
    EnhancedFlatFileRow(
        file: file,
        depth: 1,
        parentFolderID: UUID(),
        store: store,
        dragDropManager: DragDropManager(),
        onPlanChanged: {},
        previousFieldID: nil,
        nextFieldID: nil
    )
    .frame(width: 400)
    .padding()
}

#Preview("Truncated Insight Pill") {
    VStack(spacing: 10) {
        TruncatedInsightPill(text: "Short text")
        TruncatedInsightPill(text: "This is a very long insight text that should be truncated with an expandable option to view the full content")
    }
    .padding()
}
