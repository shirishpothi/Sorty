//
//  LiquidGlassDuplicateButton.swift
//  Sorty
//
//  Liquid glass style button for displaying duplicate file information.
//  Shows other duplicate files in a dropdown and provides quick actions via context menu.
//

import SwiftUI

/// Information about a file's duplicate status
public struct DuplicateInfo: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let file: FileItem
    public let duplicates: [FileItem]
    public let isExactMatch: Bool
    public let similarity: Double

    public init(file: FileItem, duplicates: [FileItem], isExactMatch: Bool = true, similarity: Double = 1.0) {
        self.id = file.id
        self.file = file
        self.duplicates = duplicates
        self.isExactMatch = isExactMatch
        self.similarity = similarity
    }

    public var duplicateCount: Int {
        duplicates.count
    }

    public var formattedSimilarity: String {
        if isExactMatch { return "Exact Match" }
        return "\(Int(similarity * 100))% Similar"
    }
}

struct LiquidGlassDuplicateButton: View {
    let duplicateInfo: DuplicateInfo
    var handoffDirectory: URL? = nil
    var onFileSelected: ((FileItem) -> Void)? = nil
    @Binding var highlightedFileID: UUID?
    @EnvironmentObject var appState: AppState

    @State private var showPopover = false
    @State private var hoveredFileID: UUID? = nil

    private var accentColor: Color {
        duplicateInfo.isExactMatch ? .red : .orange
    }

    private var activeFileID: UUID {
        guard let highlightedFileID else { return duplicateInfo.file.id }
        if highlightedFileID == duplicateInfo.file.id { return highlightedFileID }
        if duplicateInfo.duplicates.contains(where: { $0.id == highlightedFileID }) { return highlightedFileID }
        return duplicateInfo.file.id
    }

    private var isHighlightedInGroup: Bool {
        guard let highlightedFileID else { return false }
        if highlightedFileID == duplicateInfo.file.id { return true }
        return duplicateInfo.duplicates.contains(where: { $0.id == highlightedFileID })
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(showPopover ? 0.5 : 0.3),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(showPopover || isHighlightedInGroup ? accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("\(duplicateInfo.duplicateCount) duplicate\(duplicateInfo.duplicateCount == 1 ? "" : "s") found")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            duplicatePopoverContent
        }
    }

    // MARK: - Popover Content

    private var duplicatePopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Duplicates")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(duplicateInfo.formattedSimilarity)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Text("\(duplicateInfo.duplicateCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(accentColor))
            }
            .padding(.bottom, 10)

            Divider()
                .opacity(0.4)
                .padding(.bottom, 10)

            Button {
                handoffToDuplicates()
            } label: {
                Label("Handle in Duplicates", systemImage: "arrowshape.turn.up.right.circle.fill")
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            // Current file
            VStack(alignment: .leading, spacing: 6) {
                Text("This File")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                duplicateFileRow(file: duplicateInfo.file)
            }
            .padding(.bottom, 12)

            // Other duplicates
            VStack(alignment: .leading, spacing: 6) {
                Text("Other Copies")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                ForEach(duplicateInfo.duplicates) { duplicate in
                    duplicateFileRow(file: duplicate)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 280, maxWidth: 360)
    }

    @ViewBuilder
    private func duplicateFileRow(file: FileItem) -> some View {
        let isSelected = activeFileID == file.id

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                highlightedFileID = file.id
            }
            onFileSelected?(file)
        } label: {
            HStack(spacing: 10) {
                FileThumbnailView(url: URL(fileURLWithPath: file.path), size: CGSize(width: 24, height: 24))

                VStack(alignment: .leading, spacing: 2) {
                    Text(file.displayName)
                        .font(.callout)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                if isSelected {
                    Text("Current")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (hoveredFileID == file.id ? Color.secondary.opacity(0.1) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredFileID = isHovering ? file.id : nil
        }
        .contextMenu {
            fileContextMenu(for: file)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func fileContextMenu(for file: FileItem) -> some View {
        Button {
            NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }

        Button {
            appState.handoffToDuplicates(
                forFilePaths: [file.path],
                preferredDirectory: handoffDirectory,
                autoStart: true
            )
        } label: {
            Label("Handle in Duplicates", systemImage: "arrowshape.turn.up.right.circle")
        }

        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        } label: {
            Label("Quick Look", systemImage: "eye")
        }

        Button {
            do {
                try FileManager.default.trashItem(at: URL(fileURLWithPath: file.path), resultingItemURL: nil)
                NotificationManager.shared.show(.info(title: "Success", message: "Moved duplicate to Trash"))
            } catch {
                NotificationManager.shared.showError(message: "Could not move to Trash: \(error.localizedDescription)")
            }
        } label: {
            Label("Move to Trash", systemImage: "trash")
        }
    }

    private func handoffToDuplicates() {
        let allPaths = [duplicateInfo.file.path] + duplicateInfo.duplicates.map(\.path)
        appState.handoffToDuplicates(
            forFilePaths: allPaths,
            preferredDirectory: handoffDirectory,
            autoStart: true
        )
        showPopover = false
        HapticFeedbackManager.shared.selection()
    }
}

// MARK: - Previews

#Preview("Liquid Glass Duplicate Button") {
    let file1 = FileItem(path: "/test/document.pdf", name: "document", extension: "pdf", size: 1024000)
    let file2 = FileItem(path: "/test/copy/document.pdf", name: "document", extension: "pdf", size: 1024000)
    let file3 = FileItem(path: "/backup/document.pdf", name: "document", extension: "pdf", size: 1024000)

    let info = DuplicateInfo(file: file1, duplicates: [file2, file3])

    LiquidGlassDuplicateButton(duplicateInfo: info, highlightedFileID: .constant(nil))
        .padding()
        .environmentObject(AppState())
}

#Preview("Liquid Glass Duplicate - Semantic") {
    let file1 = FileItem(path: "/test/photo_001.jpg", name: "photo_001", extension: "jpg", size: 2048000)
    let file2 = FileItem(path: "/test/photo_001_copy.jpg", name: "photo_001_copy", extension: "jpg", size: 1900000)

    let info = DuplicateInfo(file: file1, duplicates: [file2], isExactMatch: false, similarity: 0.95)

    LiquidGlassDuplicateButton(duplicateInfo: info, highlightedFileID: .constant(nil))
        .padding()
        .environmentObject(AppState())
}
