//
//  OptimizedPreviewTree.swift
//  Sorty
//
//  Optimized flat-list rendering for large organization previews.
//  Uses a flattened data structure to avoid recursive view creation
//  and improve scrolling performance.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Flattened Row Model

struct FlattenedRow: Identifiable, Equatable {
    let id: String
    let depth: Int
    let type: RowType
    let isExpanded: Bool
    
    enum RowType: Equatable {
        case folder(FolderSuggestion)
        case file(FileItem, parentFolderID: UUID)
        case unorganizedHeader
        case unorganizedFile(FileItem)
    }
    
    static func == (lhs: FlattenedRow, rhs: FlattenedRow) -> Bool {
        lhs.id == rhs.id && lhs.depth == rhs.depth && lhs.isExpanded == rhs.isExpanded && lhs.type == rhs.type
    }
}

// MARK: - Preview Store

@MainActor
class PreviewStore: ObservableObject {
    @Published private(set) var flattenedRows: [FlattenedRow] = []
    @Published private(set) var plan: OrganizationPlan
    @Published var expandedFolders: Set<String> = []
    
    private var folderIDToPath: [UUID: String] = [:]
    
    init(plan: OrganizationPlan) {
        self.plan = plan
        expandAllFolders()
        rebuildFlattenedRows()
    }
    
    func toggleFolder(id: String) {
        if expandedFolders.contains(id) {
            expandedFolders.remove(id)
        } else {
            expandedFolders.insert(id)
        }
        rebuildFlattenedRows()
    }
    
    func moveFile(fileID: UUID, toFolderID: UUID) {
        guard let file = findFile(by: fileID) else { return }
        
        var updatedPlan = plan
        
        updatedPlan.suggestions = updatedPlan.suggestions.map { folder in
            removeFileFromFolder(file, from: folder)
        }
        updatedPlan.unorganizedFiles.removeAll { $0.id == fileID }
        
        updatedPlan.suggestions = updatedPlan.suggestions.map { folder in
            addFileToFolder(file, to: folder, targetId: toFolderID)
        }
        
        let finalPlan = OrganizationPlan(
            id: updatedPlan.id,
            suggestions: updatedPlan.suggestions,
            unorganizedFiles: updatedPlan.unorganizedFiles,
            unorganizedDetails: updatedPlan.unorganizedDetails,
            notes: updatedPlan.notes,
            timestamp: Date(),
            version: updatedPlan.version + 1,
            generationStats: updatedPlan.generationStats
        )
        
        plan = finalPlan
        rebuildFlattenedRows()
    }
    
    func moveFileToUnorganized(fileID: UUID) {
        guard let file = findFile(by: fileID) else { return }
        
        var updatedPlan = plan
        
        updatedPlan.suggestions = updatedPlan.suggestions.map { folder in
            removeFileFromFolder(file, from: folder)
        }
        
        if !updatedPlan.unorganizedFiles.contains(where: { $0.id == fileID }) {
            updatedPlan.unorganizedFiles.append(file)
        }
        
        let finalPlan = OrganizationPlan(
            id: updatedPlan.id,
            suggestions: updatedPlan.suggestions,
            unorganizedFiles: updatedPlan.unorganizedFiles,
            unorganizedDetails: updatedPlan.unorganizedDetails,
            notes: updatedPlan.notes,
            timestamp: Date(),
            version: updatedPlan.version + 1,
            generationStats: updatedPlan.generationStats
        )
        
        plan = finalPlan
        rebuildFlattenedRows()
    }
    
    func updatePlan(_ newPlan: OrganizationPlan) {
        plan = newPlan
        expandAllFolders()
        rebuildFlattenedRows()
    }
    
    func rebuildFlattenedRows() {
        var rows: [FlattenedRow] = []
        folderIDToPath = [:]
        
        for suggestion in plan.suggestions {
            flattenFolder(suggestion, depth: 0, parentPath: "", into: &rows)
        }
        
        if !plan.unorganizedFiles.isEmpty {
            rows.append(FlattenedRow(
                id: "unorganized-header",
                depth: 0,
                type: .unorganizedHeader,
                isExpanded: true
            ))
            
            for file in plan.unorganizedFiles {
                rows.append(FlattenedRow(
                    id: "unorganized-\(file.id.uuidString)",
                    depth: 1,
                    type: .unorganizedFile(file),
                    isExpanded: false
                ))
            }
        }
        
        flattenedRows = rows
    }
    
    // MARK: - Private Helpers
    
    private func expandAllFolders() {
        expandedFolders.removeAll()
        for suggestion in plan.suggestions {
            collectAllFolderPaths(suggestion, parentPath: "")
        }
    }
    
    private func collectAllFolderPaths(_ folder: FolderSuggestion, parentPath: String) {
        let path = parentPath.isEmpty ? folder.id.uuidString : "\(parentPath)/\(folder.id.uuidString)"
        expandedFolders.insert(path)
        for subfolder in folder.subfolders {
            collectAllFolderPaths(subfolder, parentPath: path)
        }
    }
    
    private func flattenFolder(_ folder: FolderSuggestion, depth: Int, parentPath: String, into rows: inout [FlattenedRow]) {
        let path = parentPath.isEmpty ? folder.id.uuidString : "\(parentPath)/\(folder.id.uuidString)"
        let isExpanded = expandedFolders.contains(path)
        
        folderIDToPath[folder.id] = path
        
        rows.append(FlattenedRow(
            id: path,
            depth: depth,
            type: .folder(folder),
            isExpanded: isExpanded
        ))
        
        if isExpanded {
            for file in folder.files {
                rows.append(FlattenedRow(
                    id: "\(path)/file-\(file.id.uuidString)",
                    depth: depth + 1,
                    type: .file(file, parentFolderID: folder.id),
                    isExpanded: false
                ))
            }
            
            for subfolder in folder.subfolders {
                flattenFolder(subfolder, depth: depth + 1, parentPath: path, into: &rows)
            }
        }
    }
    
    private func findFile(by id: UUID) -> FileItem? {
        for suggestion in plan.suggestions {
            if let file = findFileInFolder(id, in: suggestion) {
                return file
            }
        }
        return plan.unorganizedFiles.first { $0.id == id }
    }
    
    private func findFileInFolder(_ id: UUID, in folder: FolderSuggestion) -> FileItem? {
        if let file = folder.files.first(where: { $0.id == id }) {
            return file
        }
        for subfolder in folder.subfolders {
            if let file = findFileInFolder(id, in: subfolder) {
                return file
            }
        }
        return nil
    }
    
    private func removeFileFromFolder(_ file: FileItem, from folder: FolderSuggestion) -> FolderSuggestion {
        var updatedFolder = folder
        updatedFolder.files.removeAll { $0.id == file.id }
        updatedFolder.subfolders = updatedFolder.subfolders.map { subfolder in
            removeFileFromFolder(file, from: subfolder)
        }
        return updatedFolder
    }
    
    private func addFileToFolder(_ file: FileItem, to folder: FolderSuggestion, targetId: UUID) -> FolderSuggestion {
        var updatedFolder = folder
        
        if folder.id == targetId {
            if !updatedFolder.files.contains(where: { $0.id == file.id }) {
                updatedFolder.files.append(file)
            }
        } else {
            updatedFolder.subfolders = updatedFolder.subfolders.map { subfolder in
                addFileToFolder(file, to: subfolder, targetId: targetId)
            }
        }
        
        return updatedFolder
    }
}

// MARK: - Optimized Preview Tree View

struct OptimizedPreviewTree: View {
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.flattenedRows) { row in
                    FlattenedRowView(
                        row: row,
                        store: store,
                        dragDropManager: dragDropManager,
                        onPlanChanged: onPlanChanged
                    )
                    .id(row.id)
                }
            }
            .padding()
        }
    }
}

// MARK: - Flattened Row View

struct FlattenedRowView: View {
    let row: FlattenedRow
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    
    var body: some View {
        switch row.type {
        case .folder(let suggestion):
            FlatFolderRowView(
                suggestion: suggestion,
                depth: row.depth,
                isExpanded: row.isExpanded,
                rowID: row.id,
                store: store,
                dragDropManager: dragDropManager,
                onPlanChanged: onPlanChanged
            )
        case .file(let file, let parentFolderID):
            FlatFileRowView(
                file: file,
                depth: row.depth,
                parentFolderID: parentFolderID,
                dragDropManager: dragDropManager
            )
        case .unorganizedHeader:
            FlatUnorganizedHeaderView(
                fileCount: store.plan.unorganizedFiles.count,
                store: store,
                dragDropManager: dragDropManager,
                onPlanChanged: onPlanChanged
            )
        case .unorganizedFile(let file):
            FlatUnorganizedFileRowView(
                file: file,
                dragDropManager: dragDropManager
            )
        }
    }
}

// MARK: - Flat Folder Row View

struct FlatFolderRowView: View {
    let suggestion: FolderSuggestion
    let depth: Int
    let isExpanded: Bool
    let rowID: String
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    
    @State private var isDropTarget = false
    @State private var showReasoning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button {
                    store.toggleFolder(id: rowID)
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .frame(width: 20)
                
                Image(systemName: "folder.fill")
                    .foregroundColor(isDropTarget ? .purple : .blue)
                
                Text(suggestion.folderName)
                    .fontWeight(.medium)
                
                Text("(\(suggestion.totalFileCount) files)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !suggestion.reasoning.isEmpty {
                    Button {
                        showReasoning.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(showReasoning ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View AI reasoning for this folder")
                }
            }
            .padding(.leading, CGFloat(depth * 20))
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDropTarget ? Color.purple.opacity(0.1) : Color.clear)
                    .strokeBorder(isDropTarget ? Color.purple : Color.clear, lineWidth: 2)
            )
            .onDrop(of: [.text], delegate: OptimizedFileDropDelegate(
                targetFolderID: suggestion.id,
                store: store,
                draggedFile: $dragDropManager.draggedFile,
                isTargeted: $isDropTarget,
                onPlanChanged: onPlanChanged
            ))
            
            if showReasoning && !suggestion.reasoning.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AI Reasoning")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                    
                    Text(suggestion.reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color.purple.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.purple.opacity(0.1), lineWidth: 1)
                        )
                }
                .padding(.leading, CGFloat((depth + 1) * 20))
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Flat File Row View

struct FlatFileRowView: View {
    let file: FileItem
    let depth: Int
    let parentFolderID: UUID
    @ObservedObject var dragDropManager: DragDropManager
    
    @State private var isDragging = false
    
    var body: some View {
        HStack {
            Image(systemName: "doc")
                .foregroundColor(.secondary)
            Text(file.displayName)
            Spacer()
            Text(file.formattedSize)
                .foregroundColor(.secondary)
            
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.leading, CGFloat(depth * 20))
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        )
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
}

// MARK: - Flat Unorganized Header View

struct FlatUnorganizedHeaderView: View {
    let fileCount: Int
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    
    @State private var isDropTarget = false
    
    var body: some View {
        HStack {
            Image(systemName: "questionmark.folder")
                .foregroundColor(.orange)
            Text("Unorganized Files")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(fileCount) files")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTarget ? Color.orange.opacity(0.1) : Color.clear)
                .strokeBorder(isDropTarget ? Color.orange : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.text], delegate: OptimizedUnorganizedDropDelegate(
            store: store,
            draggedFile: $dragDropManager.draggedFile,
            isTargeted: $isDropTarget,
            onPlanChanged: onPlanChanged
        ))
    }
}

// MARK: - Flat Unorganized File Row View

struct FlatUnorganizedFileRowView: View {
    let file: FileItem
    @ObservedObject var dragDropManager: DragDropManager
    
    @State private var isDragging = false
    
    var body: some View {
        HStack {
            Image(systemName: "doc")
                .foregroundColor(.secondary)
            Text(file.displayName)
            Spacer()
            Text(file.formattedSize)
                .foregroundColor(.secondary)
            
            Image(systemName: "line.3.horizontal")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.leading, 20)
        .padding(.vertical, 2)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isDragging ? Color.accentColor.opacity(0.1) : Color.clear)
        )
        .opacity(isDragging ? 0.5 : 1.0)
        .onDrag {
            isDragging = true
            dragDropManager.startDrag(file)
            return NSItemProvider(object: file.id.uuidString as NSString)
        }
    }
}

// MARK: - Optimized Drop Delegates

struct OptimizedFileDropDelegate: DropDelegate {
    let targetFolderID: UUID
    @ObservedObject var store: PreviewStore
    @Binding var draggedFile: FileItem?
    @Binding var isTargeted: Bool
    let onPlanChanged: () -> Void
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        guard draggedFile != nil else { return false }
        return true
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        
        store.moveFile(fileID: file.id, toFolderID: targetFolderID)
        onPlanChanged()
        draggedFile = nil
        isTargeted = false
        
        return true
    }
}

struct OptimizedUnorganizedDropDelegate: DropDelegate {
    @ObservedObject var store: PreviewStore
    @Binding var draggedFile: FileItem?
    @Binding var isTargeted: Bool
    let onPlanChanged: () -> Void
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        return !store.plan.unorganizedFiles.contains { $0.id == file.id }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        
        store.moveFileToUnorganized(fileID: file.id)
        onPlanChanged()
        draggedFile = nil
        isTargeted = false
        
        return true
    }
}
