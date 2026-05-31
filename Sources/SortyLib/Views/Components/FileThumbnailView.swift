import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A view that displays a file thumbnail with fallback and async loading
public struct FileThumbnailView: View {
    let url: URL
    let size: CGSize
    let utTypeHint: UTType?

    @State private var thumbnail: NSImage?
    @State private var isLoading = true

    public init(url: URL, size: CGSize = CGSize(width: 20, height: 20), utTypeHint: UTType? = nil) {
        self.url = url
        self.size = size
        self.utTypeHint = utTypeHint
    }

    /// Computed placeholder - avoids stale @State across LazyVStack view recycling
    private var placeholder: NSImage {
        Self.resolveIcon(for: url, utTypeHint: utTypeHint)
    }

    public var body: some View {
        AppKitImageView(
            image: thumbnail ?? placeholder,
            size: size,
            cornerRadius: 3,
            opacity: thumbnail == nil && isLoading ? 0.6 : 1
        )
        .frame(width: size.width, height: size.height)
        .task(id: "\(url.path)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))") {
            let currentURL = url
            isLoading = true
            let newThumbnail = await FileThumbnailProvider.shared.thumbnail(for: currentURL, size: size)
            if url == currentURL {
                thumbnail = newThumbnail
                isLoading = false
            }
        }
        .onChange(of: url) { _, _ in
            thumbnail = nil
            isLoading = true
        }
    }

    /// Cached fallback icon to avoid repeated NSWorkspace lookups
    private static let fallbackIcon: NSImage = {
        NSWorkspace.shared.icon(for: .data).copy() as! NSImage
    }()

    /// Resolve the system icon for a URL once, returning a copied image to avoid
    /// shared reference invalidation during view recycling
    private static func resolveIcon(for url: URL, utTypeHint: UTType?) -> NSImage {
        // Optimized: Avoid synchronous disk I/O in view body
        let ext = url.pathExtension
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType).copy() as! NSImage
        }
        if !ext.isEmpty {
            // Using UTType is preferred over deprecated icon(forFileType:)
            if let utType = UTType(tag: ext, tagClass: .filenameExtension, conformingTo: nil) {
                return NSWorkspace.shared.icon(for: utType).copy() as! NSImage
            }
        }
        if let hint = utTypeHint {
            return NSWorkspace.shared.icon(for: hint).copy() as! NSImage
        }
        
        return fallbackIcon
    }
}
