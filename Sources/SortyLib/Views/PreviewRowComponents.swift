import Foundation
import SwiftUI

struct FlatFolderRowHeaderContent: View {
    let folderName: String
    let fileCount: Int
    let isExpanded: Bool
    let isDropTarget: Bool
    let reduceMotion: Bool

    private var displayName: String {
        folderName.hasPrefix("/")
            ? URL(fileURLWithPath: folderName).lastPathComponent
            : folderName
    }

    var body: some View {
        Group {
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 20)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(
                    reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75),
                    value: isExpanded
                )
                .accessibilityHidden(true)

            CompactFolderThumbnail(
                url: nil,
                folderName: folderName,
                size: 16,
                fileCount: fileCount
            )
            .opacity(isDropTarget ? 0.7 : 1.0)

            Text(displayName)
                .fontWeight(.medium)

            Text("(\(fileCount) files)")
                .font(.caption)
                .foregroundColor(.secondary)
                .numericTextTransition(animationValue: fileCount)
        }
    }
}

struct FlatFolderRowContextMenu: View {
    let isStorageDestination: Bool
    let onRevert: () -> Void
    let onChangeStorage: () -> Void
    let onReveal: () -> Void

    var body: some View {
        Button(role: .destructive, action: onRevert) {
            Label("Revert Organization", systemImage: "arrow.uturn.backward")
        }

        if isStorageDestination {
            Divider()
            Button("Change Storage Location…", action: onChangeStorage)
            Button("Show in Finder", action: onReveal)
        }
    }
}

struct FlatFileRowContent: View {
    private enum Column {
        static let sizeWidth: CGFloat = 60
        static let dragHandleWidth: CGFloat = 12
    }

    let file: FileItem
    let renameMapping: FileRenameMapping?
    let renameHelpText: String?
    let fileTags: [String]
    let fileComment: String?
    let duplicateInfo: DuplicateInfo?
    let parentSuggestion: FolderSuggestion?
    let handoffDirectory: URL?
    let learningsManager: LearningsManager
    @Binding var isEditingName: Bool
    @Binding var editedName: String
    @Binding var isRegeneratingName: Bool
    @Binding var highlightedFileID: UUID?
    let isFocused: FocusState<Bool>.Binding
    let onSave: () -> Void
    let onCancel: () -> Void
    let onStartEditing: (String) -> Void
    let onRegenerate: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                FileThumbnailView(
                    url: URL(fileURLWithPath: file.path),
                    size: CGSize(width: 20, height: 20)
                )

                if isEditingName {
                    TextField("New name", text: $editedName)
                        .textFieldStyle(.plain)
                        .focused(isFocused)
                        .onSubmit(onSave)
                        .onExitCommand(perform: onCancel)
                        .font(.body)
                } else {
                    Text(file.displayName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(renameMapping?.hasRename == true ? .secondary : .primary)
                        .strikethrough(
                            renameMapping?.hasRename == true,
                            color: .red.opacity(0.72)
                        )
                }

                Spacer(minLength: 12)

                HStack(spacing: 6) {
                    if !fileTags.isEmpty {
                        TagDotsView(tags: fileTags)
                    }

                    if let parentSuggestion {
                        LiquidGlassLearningsButton(
                            file: file,
                            suggestion: parentSuggestion,
                            learningsManager: learningsManager
                        )
                    }

                    if let fileComment, !fileComment.isEmpty {
                        CommentBubbleButton(comment: fileComment)
                    }

                    if let duplicateInfo {
                        LiquidGlassDuplicateButton(
                            duplicateInfo: duplicateInfo,
                            handoffDirectory: handoffDirectory,
                            highlightedFileID: $highlightedFileID
                        )
                    }

                    Text(file.formattedSize)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: Column.sizeWidth, alignment: .leading)

                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.6))
                        .frame(width: Column.dragHandleWidth)
                        .accessibilityHidden(true)
                }
            }

            if let renameMapping, renameMapping.hasRename, !isEditingName {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    RenameNameChangeView(
                        originalName: file.displayName,
                        suggestedName: renameMapping.suggestedName ?? "",
                        helpText: renameHelpText ?? "",
                        isRegenerating: isRegeneratingName,
                        showsOriginalName: false
                    )

                    Spacer(minLength: 12)

                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundColor(.purple)
                        .help(renameMapping.renameReason ?? "Sorty suggested rename")

                    RenameActionGlassCluster(
                        isRegenerating: isRegeneratingName,
                        onEdit: { onStartEditing(renameMapping.suggestedName ?? "") },
                        onRegenerate: onRegenerate,
                        onReject: onReject
                    )
                }
                .padding(.leading, 28)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct FlatFileRowContextMenu: View {
    let hasRename: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRegenerate: () -> Void
    let onRejectRename: () -> Void
    let onRevertOrganization: () -> Void

    var body: some View {
        Button(action: onOpen) {
            Label("Open", systemImage: "arrow.up.right.square")
        }
        Button(action: onReveal) {
            Label("Reveal in Finder", systemImage: "folder")
        }
        Divider()
        if hasRename {
            Button(action: onRegenerate) {
                Label("Regenerate Name", systemImage: "arrow.triangle.2.circlepath")
            }
            Button(role: .destructive, action: onRejectRename) {
                Label("Revert Name", systemImage: "arrow.uturn.backward")
            }
        }
        Button(role: .destructive, action: onRevertOrganization) {
            Label("Revert Organization", systemImage: "questionmark.folder")
        }
    }
}

struct FlatFileRowSurface: View {
    let content: FlatFileRowContent
    let depth: Int
    let isHighlighted: Bool
    let isEditingName: Bool
    @Binding var isDragging: Bool
    let hasRename: Bool
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onRegenerate: () -> Void
    let onRejectRename: () -> Void
    let onRevertOrganization: () -> Void
    let onBeginDrag: () -> NSItemProvider
    let onDisappear: () -> Void

    private var fillColor: Color {
        if isHighlighted {
            return SortyDesignSystem.Colors.resolvedAccent.opacity(0.12)
        }
        return isDragging
            ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.1)
            : .clear
    }

    private var strokeColor: Color {
        isHighlighted || isEditingName
            ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.3)
            : .clear
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
        }
        .padding(.leading, CGFloat(depth * 16))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(fillColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(strokeColor, lineWidth: 1))
        .contentShape(Rectangle())
        .contextMenu {
            FlatFileRowContextMenu(
                hasRename: hasRename,
                onOpen: onOpen,
                onReveal: onReveal,
                onRegenerate: onRegenerate,
                onRejectRename: onRejectRename,
                onRevertOrganization: onRevertOrganization
            )
        }
        .onTapGesture(count: 2, perform: onOpen)
        .opacity(isDragging ? 0.5 : 1.0)
        .onDrag(onBeginDrag)
        .onDrop(of: [.text], isTargeted: nil) { _ in
            isDragging = false
            return false
        }
        .onDisappear(perform: onDisappear)
    }
}

private struct RenameActionGlassCluster: View {
    let isRegenerating: Bool
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            RenameGlassIconButton(systemImage: "pencil", help: "Edit suggested name", action: onEdit)
            Button(action: onRegenerate) {
                if isRegenerating {
                    SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRegenerating)
            .help("Regenerate name with the selected AI model")

            RenameGlassIconButton(systemImage: "xmark.circle", help: "Keep original name", action: onReject)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .systemLiquidGlassBackground(cornerRadius: 10)
    }
}

private struct RenameGlassIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
