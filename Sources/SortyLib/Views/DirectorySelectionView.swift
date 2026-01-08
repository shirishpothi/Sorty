//
//  DirectorySelectionView.swift
//  Sorty
//
//  Folder selection with drag-drop support
//

import SwiftUI
import UniformTypeIdentifiers

struct DirectorySelectionView: View {
    @Binding var selectedDirectory: URL?
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 30) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Select a directory to organize")
                .font(.title2)
                .fontWeight(.medium)

            Text("Drag and drop a folder here, or click to browse")
                .font(.body)
                .foregroundColor(.secondary)

            Button("Browse for Folder") {
                selectDirectory()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("BrowseForFolderButton")
            .accessibilityLabel("Browse for Folder")
            .accessibilityHint("Opens a file picker to select a directory")
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.blue.opacity(0.1) : Color.clear)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Directory Selection Area")
        .accessibilityHint("Drag and drop a folder here or use the Browse button")
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
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
                    selectedDirectory = url
                }
            }
        }

        return true
    }
}

extension UTType {
    static var fileURL: UTType {
        UTType(exportedAs: "public.file-url")
    }
}
