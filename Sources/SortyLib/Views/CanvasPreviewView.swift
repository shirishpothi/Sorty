//
//  CanvasPreviewView.swift
//  Sorty
//
//  Interactive Canvas Preview - A visual, node-based map of proposed organization
//  Users can drag file nodes between folder nodes to refine the AI's plan
//

import SwiftUI
import Combine

// MARK: - Canvas Data Models

struct CanvasNode: Identifiable, Equatable {
    let id: UUID
    var position: CGPoint
    var size: CGSize
    let type: NodeType

    enum NodeType: Equatable {
        case folder(FolderSuggestion)
        case file(FileItem, parentFolderId: UUID?)
        case unorganized
    }

    static func == (lhs: CanvasNode, rhs: CanvasNode) -> Bool {
        lhs.id == rhs.id && lhs.position == rhs.position
    }
}

struct CanvasConnection: Identifiable {
    let id: UUID
    let fromNodeId: UUID
    let toNodeId: UUID
    let type: ConnectionType

    enum ConnectionType {
        case folderToFile
        case folderToSubfolder
    }
}

// MARK: - Canvas View Model

@MainActor
class CanvasViewModel: ObservableObject {
    @Published var nodes: [CanvasNode] = []
    @Published var connections: [CanvasConnection] = []
    @Published var selectedNodeId: UUID?
    @Published var draggedNodeId: UUID?
    @Published var dropTargetId: UUID?
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGPoint = .zero
    @Published var hasChanges: Bool = false

    private var originalPlan: OrganizationPlan?

    func loadPlan(_ plan: OrganizationPlan, canvasSize: CGSize) {
        originalPlan = plan
        nodes = []
        connections = []

        let padding: CGFloat = 50
        let folderWidth: CGFloat = 200
        let folderHeight: CGFloat = 150
        let fileNodeSize = CGSize(width: 120, height: 60)

        var currentX: CGFloat = padding
        var currentY: CGFloat = padding
        let maxWidth = max(canvasSize.width - padding * 2, 800)

        // Create folder nodes
        for (_, suggestion) in plan.suggestions.enumerated() {
            let folderId = suggestion.id

            // Position folders in a grid
            if currentX + folderWidth > maxWidth {
                currentX = padding
                currentY += folderHeight + 100
            }

            let position = CGPoint(x: currentX + folderWidth / 2, y: currentY + folderHeight / 2)

            let folderNode = CanvasNode(
                id: folderId,
                position: position,
                size: CGSize(width: folderWidth, height: folderHeight),
                type: .folder(suggestion)
            )
            nodes.append(folderNode)

            // Create file nodes for this folder
            var fileY = position.y + folderHeight / 2 + 50
            for file in suggestion.files {
                let fileNode = CanvasNode(
                    id: file.id,
                    position: CGPoint(x: position.x, y: fileY),
                    size: fileNodeSize,
                    type: .file(file, parentFolderId: folderId)
                )
                nodes.append(fileNode)

                // Create connection
                connections.append(CanvasConnection(
                    id: UUID(),
                    fromNodeId: folderId,
                    toNodeId: file.id,
                    type: .folderToFile
                ))

                fileY += fileNodeSize.height + 20
            }

            currentX += folderWidth + 80
        }

        // Create unorganized section if needed
        if !plan.unorganizedFiles.isEmpty {
            currentY += folderHeight + 150
            currentX = padding

            let unorganizedId = UUID()
            let unorganizedNode = CanvasNode(
                id: unorganizedId,
                position: CGPoint(x: currentX + folderWidth / 2, y: currentY),
                size: CGSize(width: folderWidth, height: 80),
                type: .unorganized
            )
            nodes.append(unorganizedNode)

            var fileX = currentX + folderWidth + 50
            for file in plan.unorganizedFiles {
                let fileNode = CanvasNode(
                    id: file.id,
                    position: CGPoint(x: fileX, y: currentY),
                    size: fileNodeSize,
                    type: .file(file, parentFolderId: nil)
                )
                nodes.append(fileNode)

                connections.append(CanvasConnection(
                    id: UUID(),
                    fromNodeId: unorganizedId,
                    toNodeId: file.id,
                    type: .folderToFile
                ))

                fileX += fileNodeSize.width + 30
            }
        }
    }

    func moveFile(_ fileId: UUID, to folderId: UUID) {
        guard let fileIndex = nodes.firstIndex(where: { $0.id == fileId }),
              let folderIndex = nodes.firstIndex(where: { $0.id == folderId }) else {
            return
        }

        let folderNode = nodes[folderIndex]

        // Update the file's parent
        if case .file(let file, _) = nodes[fileIndex].type {
            nodes[fileIndex] = CanvasNode(
                id: fileId,
                position: nodes[fileIndex].position,
                size: nodes[fileIndex].size,
                type: .file(file, parentFolderId: folderId)
            )

            // Update connections
            connections.removeAll { $0.toNodeId == fileId }
            connections.append(CanvasConnection(
                id: UUID(),
                fromNodeId: folderId,
                toNodeId: fileId,
                type: .folderToFile
            ))

            // Reposition file near folder
            let newPosition = CGPoint(
                x: folderNode.position.x + CGFloat.random(in: -50...50),
                y: folderNode.position.y + folderNode.size.height / 2 + 60
            )
            nodes[fileIndex].position = newPosition

            hasChanges = true
        }
    }

    func updateNodePosition(_ nodeId: UUID, position: CGPoint) {
        if let index = nodes.firstIndex(where: { $0.id == nodeId }) {
            nodes[index].position = position
        }
    }

    func generateUpdatedPlan() -> OrganizationPlan? {
        guard var plan = originalPlan else { return nil }

        // Rebuild suggestions based on current node state
        var updatedSuggestions: [FolderSuggestion] = []
        var unorganizedFiles: [FileItem] = []

        // Get all folder nodes
        let folderNodes = nodes.filter {
            if case .folder(_) = $0.type { return true }
            return false
        }

        for folderNode in folderNodes {
            if case .folder(var suggestion) = folderNode.type {
                // Find all files connected to this folder
                var filesInFolder: [FileItem] = []

                for node in nodes {
                    if case .file(let file, let parentId) = node.type,
                       parentId == folderNode.id {
                        filesInFolder.append(file)
                    }
                }

                suggestion.files = filesInFolder
                updatedSuggestions.append(suggestion)
            }
        }

        // Find unorganized files
        for node in nodes {
            if case .file(let file, let parentId) = node.type,
               parentId == nil {
                unorganizedFiles.append(file)
            }
        }

        plan.suggestions = updatedSuggestions
        plan.unorganizedFiles = unorganizedFiles

        return plan
    }

    func resetChanges() {
        if let plan = originalPlan {
            loadPlan(plan, canvasSize: CGSize(width: 1000, height: 800))
        }
        hasChanges = false
    }
}

// MARK: - Canvas Preview View

struct CanvasPreviewView: View {
    let plan: OrganizationPlan
    let baseURL: URL
    let onApply: (OrganizationPlan) -> Void
    let onCancel: () -> Void

    @StateObject private var viewModel = CanvasViewModel()
    @State private var canvasSize: CGSize = .zero
    @GestureState private var magnificationState: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            CanvasToolbar(
                viewModel: viewModel,
                onApply: {
                    if let updatedPlan = viewModel.generateUpdatedPlan() {
                        onApply(updatedPlan)
                    }
                },
                onCancel: onCancel
            )

            Divider()

            // Canvas
            GeometryReader { geometry in
                ZStack {
                    // Background grid
                    CanvasGrid()

                    // Connections
                    ForEach(viewModel.connections) { connection in
                        ConnectionLine(
                            connection: connection,
                            nodes: viewModel.nodes
                        )
                    }

                    // Nodes
                    ForEach(viewModel.nodes) { node in
                        NodeView(
                            node: node,
                            isSelected: viewModel.selectedNodeId == node.id,
                            isDragging: viewModel.draggedNodeId == node.id,
                            isDropTarget: viewModel.dropTargetId == node.id,
                            onSelect: {
                                viewModel.selectedNodeId = node.id
                            },
                            onDragChanged: { position in
                                viewModel.draggedNodeId = node.id
                                viewModel.updateNodePosition(node.id, position: position)

                                // Check for drop targets
                                if case .file(_, _) = node.type {
                                    viewModel.dropTargetId = findDropTarget(at: position, excluding: node.id)
                                }
                            },
                            onDragEnded: {
                                if case .file(_, _) = node.type,
                                   let targetId = viewModel.dropTargetId {
                                    viewModel.moveFile(node.id, to: targetId)
                                }
                                viewModel.draggedNodeId = nil
                                viewModel.dropTargetId = nil
                            }
                        )
                    }
                }
                .scaleEffect(viewModel.scale * magnificationState)
                .offset(x: viewModel.offset.x, y: viewModel.offset.y)
                .gesture(
                    MagnificationGesture()
                        .updating($magnificationState) { value, state, _ in
                            state = value
                        }
                        .onEnded { value in
                            viewModel.scale *= value
                            viewModel.scale = max(0.3, min(viewModel.scale, 3.0))
                        }
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if viewModel.draggedNodeId == nil {
                                viewModel.offset = CGPoint(
                                    x: viewModel.offset.x + value.translation.width,
                                    y: viewModel.offset.y + value.translation.height
                                )
                            }
                        }
                )
                .onTapGesture {
                    viewModel.selectedNodeId = nil
                }
                .onAppear {
                    // Guard against re-layout: only set once when zero
                    if canvasSize == .zero {
                        canvasSize = geometry.size
                        viewModel.loadPlan(plan, canvasSize: geometry.size)
                    }
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .clipped()

            // Legend
            CanvasLegend()
        }
    }

    private func findDropTarget(at position: CGPoint, excluding nodeId: UUID) -> UUID? {
        for node in viewModel.nodes {
            guard node.id != nodeId else { continue }

            if case .folder(_) = node.type {
                let frame = CGRect(
                    x: node.position.x - node.size.width / 2,
                    y: node.position.y - node.size.height / 2,
                    width: node.size.width,
                    height: node.size.height
                )

                if frame.contains(position) {
                    return node.id
                }
            }
        }
        return nil
    }
}

// MARK: - Canvas Toolbar

struct CanvasToolbar: View {
    @ObservedObject var viewModel: CanvasViewModel
    let onApply: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Title and info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3.topleft.filled")
                        .foregroundStyle(.purple)

                    Text("Canvas Preview")
                        .font(.headline)

                    if viewModel.hasChanges {
                        Text("Modified")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange)
                            .cornerRadius(4)
                    }
                }

                Text("Drag files between folders to customize")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Zoom controls
            HStack(spacing: 8) {
                Button {
                    withAnimation {
                        viewModel.scale = max(0.3, viewModel.scale - 0.2)
                    }
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Text("\(Int(viewModel.scale * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 50)

                Button {
                    withAnimation {
                        viewModel.scale = min(3.0, viewModel.scale + 0.2)
                    }
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                Button {
                    withAnimation {
                        viewModel.scale = 1.0
                        viewModel.offset = .zero
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.borderless)
                .help("Reset view")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)

            Divider()
                .frame(height: 24)

            // Actions
            if viewModel.hasChanges {
                Button("Reset") {
                    viewModel.resetChanges()
                }
                .buttonStyle(.bordered)
            }

            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Button("Apply Changes", action: onApply)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.hasChanges)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Canvas Grid

struct CanvasGrid: View {
    let gridSize: CGFloat = 50

    var body: some View {
        Canvas { context, size in
            let rows = Int(size.height / gridSize) + 1
            let cols = Int(size.width / gridSize) + 1

            for row in 0...rows {
                let y = CGFloat(row) * gridSize
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.secondary.opacity(0.1)))
            }

            for col in 0...cols {
                let x = CGFloat(col) * gridSize
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.secondary.opacity(0.1)))
            }
        }
    }
}

// MARK: - Connection Line

struct ConnectionLine: View {
    let connection: CanvasConnection
    let nodes: [CanvasNode]

    var body: some View {
        if let fromNode = nodes.first(where: { $0.id == connection.fromNodeId }),
           let toNode = nodes.first(where: { $0.id == connection.toNodeId }) {

            Path { path in
                path.move(to: fromNode.position)

                // Create a curved line
                let midY = (fromNode.position.y + toNode.position.y) / 2
                path.addCurve(
                    to: toNode.position,
                    control1: CGPoint(x: fromNode.position.x, y: midY),
                    control2: CGPoint(x: toNode.position.x, y: midY)
                )
            }
            .stroke(
                connection.type == .folderToFile ? Color.blue.opacity(0.3) : Color.purple.opacity(0.3),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 5])
            )
        }
    }
}

// MARK: - Node View

struct NodeView: View {
    let node: CanvasNode
    let isSelected: Bool
    let isDragging: Bool
    let isDropTarget: Bool
    let onSelect: () -> Void
    let onDragChanged: (CGPoint) -> Void
    let onDragEnded: () -> Void

    @State private var dragOffset: CGSize = .zero

    var body: some View {
        Group {
            switch node.type {
            case .folder(let suggestion):
                FolderNodeView(
                    suggestion: suggestion,
                    isSelected: isSelected,
                    isDropTarget: isDropTarget
                )

            case .file(let file, _):
                FileNodeView(
                    file: file,
                    isSelected: isSelected,
                    isDragging: isDragging
                )

            case .unorganized:
                UnorganizedNodeView(isSelected: isSelected)
            }
        }
        .position(x: node.position.x + dragOffset.width, y: node.position.y + dragOffset.height)
        .onTapGesture {
            onSelect()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if case .file(_, _) = node.type {
                        dragOffset = value.translation
                        let newPosition = CGPoint(
                            x: node.position.x + value.translation.width,
                            y: node.position.y + value.translation.height
                        )
                        onDragChanged(newPosition)
                    }
                }
                .onEnded { _ in
                    if case .file(_, _) = node.type {
                        dragOffset = .zero
                        onDragEnded()
                    }
                }
        )
    }
}

// MARK: - Folder Node View

struct FolderNodeView: View {
    let suggestion: FolderSuggestion
    let isSelected: Bool
    let isDropTarget: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(isDropTarget ? 0.4 : 0.2),
                                Color.blue.opacity(isDropTarget ? 0.3 : 0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDropTarget ? Color.green : (isSelected ? Color.blue : Color.blue.opacity(0.3)),
                        lineWidth: isDropTarget ? 3 : (isSelected ? 2 : 1)
                    )

                VStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.blue)

                    Text(suggestion.folderName)
                        .font(.headline)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text("\(suggestion.totalFileCount) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
            .frame(width: 180, height: 130)
        }
        .shadow(color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.1), radius: isSelected ? 10 : 5)
        .scaleEffect(isDropTarget ? 1.05 : 1.0)
        .animation(.spring(response: 0.3), value: isDropTarget)
    }
}

// MARK: - File Node View

struct FileNodeView: View {
    let file: FileItem
    let isSelected: Bool
    let isDragging: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForExtension(file.extension))
                .foregroundStyle(colorForExtension(file.extension))

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.caption)
                    .lineLimit(1)

                Text(file.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: isDragging ? .purple.opacity(0.3) : .black.opacity(0.1), radius: isDragging ? 8 : 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    isDragging ? Color.purple : (isSelected ? Color.blue : Color.clear),
                    lineWidth: isDragging ? 2 : 1
                )
        )
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .animation(.spring(response: 0.3), value: isDragging)
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.fill"
        case "jpg", "jpeg", "png", "gif", "heic": return "photo.fill"
        case "mp4", "mov", "avi": return "film.fill"
        case "mp3", "wav", "m4a": return "music.note"
        case "zip", "rar", "7z": return "archivebox.fill"
        case "swift", "py", "js": return "chevron.left.forwardslash.chevron.right"
        default: return "doc.fill"
        }
    }

    private func colorForExtension(_ ext: String) -> Color {
        switch ext.lowercased() {
        case "pdf": return .red
        case "jpg", "jpeg", "png", "gif", "heic": return .purple
        case "mp4", "mov", "avi": return .pink
        case "mp3", "wav", "m4a": return .orange
        case "zip", "rar", "7z": return .brown
        case "swift": return .orange
        case "py": return .blue
        case "js": return .yellow
        default: return .gray
        }
    }
}

// MARK: - Unorganized Node View

struct UnorganizedNodeView: View {
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder.fill")
                .font(.system(size: 24))
                .foregroundStyle(.orange)

            Text("Unorganized")
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? Color.orange : Color.orange.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .shadow(color: isSelected ? .orange.opacity(0.3) : .black.opacity(0.1), radius: isSelected ? 8 : 4)
    }
}

// MARK: - Canvas Legend

struct CanvasLegend: View {
    var body: some View {
        HStack(spacing: 24) {
            LegendItem(icon: "folder.fill", color: .blue, label: "Folders")
            LegendItem(icon: "doc.fill", color: .gray, label: "Files (drag to move)")
            LegendItem(icon: "questionmark.folder.fill", color: .orange, label: "Unorganized")

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "hand.draw")
                    .foregroundColor(.secondary)
                Text("Drag files to folders to reorganize")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct LegendItem: View {
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePlan = OrganizationPlan(
        suggestions: [
            FolderSuggestion(
                folderName: "Documents",
                description: "Text documents",
                files: [
                    FileItem(path: "/test/doc1.pdf", name: "doc1", extension: "pdf", size: 1024),
                    FileItem(path: "/test/doc2.txt", name: "doc2", extension: "txt", size: 512)
                ],
                reasoning: "PDF and text files"
            ),
            FolderSuggestion(
                folderName: "Images",
                description: "Image files",
                files: [
                    FileItem(path: "/test/img1.jpg", name: "img1", extension: "jpg", size: 2048)
                ],
                reasoning: "Image files grouped together"
            )
        ],
        unorganizedFiles: [
            FileItem(path: "/test/misc.dat", name: "misc", extension: "dat", size: 256)
        ]
    )

    CanvasPreviewView(
        plan: samplePlan,
        baseURL: URL(fileURLWithPath: "/test"),
        onApply: { _ in },
        onCancel: { }
    )
    .frame(width: 1000, height: 700)
}
