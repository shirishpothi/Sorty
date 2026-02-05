//
//  FolderThumbnailView.swift
//  Sorty
//
//  SwiftUI view component for displaying folder thumbnails.
//  Shows Finder-style folder previews with content thumbnails.
//

import SwiftUI

/// A view that displays a folder thumbnail with async loading
public struct FolderThumbnailView: View {
    let url: URL
    let size: CGSize
    
    @State private var thumbnail: NSImage?
    @State private var isLoading = true
    
    public init(url: URL, size: CGSize = CGSize(width: 40, height: 40)) {
        self.url = url
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else if isLoading {
                // Show Sorty folder icon while loading
                SortyFolderIcon(size: size.width)
            } else {
                // Fallback folder icon
                SortyFolderIcon(size: size.width)
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: url) {
            isLoading = true
            thumbnail = await FolderThumbnailProvider.shared.thumbnail(for: url, size: size)
            withAnimation(.easeOut(duration: 0.2)) {
                isLoading = false
            }
        }
    }
}

/// Compact folder thumbnail for tree views
public struct CompactFolderThumbnail: View {
    let url: URL?
    let folderName: String
    let size: CGFloat
    let fileCount: Int
    
    @State private var thumbnail: NSImage?
    
    public init(url: URL?, folderName: String, size: CGFloat = 20, fileCount: Int = 0) {
        self.url = url
        self.folderName = folderName
        self.size = size
        self.fileCount = fileCount
    }
    
    public var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else if url == nil {
                SortyFolderIcon(size: size)
            } else {
                SortyFolderIcon(size: size)
            }
        }
        .task(id: url) {
            guard let url = url else { return }
            thumbnail = await FolderThumbnailProvider.shared.thumbnail(
                for: url,
                size: CGSize(width: size, height: size)
            )
        }
    }
}

/// Actual macOS folder icon for new folders (using cached system icon)
private struct SortyFolderIcon: View {
    let size: CGFloat

    var body: some View {
        if let nsImage = SortyResources.image(named: "SortyFolder") {
            Image(nsImage: nsImage)
                .renderingMode(.original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "folder.fill")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.blue)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FolderThumbnailView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FolderThumbnailView(
                url: URL(fileURLWithPath: NSHomeDirectory() + "/Downloads"),
                size: CGSize(width: 64, height: 64)
            )
            
            FolderThumbnailView(
                url: URL(fileURLWithPath: NSHomeDirectory() + "/Documents"),
                size: CGSize(width: 40, height: 40)
            )
            
            CompactFolderThumbnail(
                url: URL(fileURLWithPath: NSHomeDirectory() + "/Desktop"),
                folderName: "Desktop"
            )
        }
        .padding()
    }
}
#endif
