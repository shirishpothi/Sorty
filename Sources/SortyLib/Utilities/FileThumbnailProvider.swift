import SwiftUI
import Combine
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Provides cached thumbnails for files using QuickLook and NSWorkspace
@MainActor
public class FileThumbnailProvider: ObservableObject {
    public static let shared = FileThumbnailProvider()
    
    private let cache = NSCache<NSURL, AnyObject>()
    
    private init() {
        cache.countLimit = 500 // Cache up to 500 thumbnails
    }
    
    /// Get a thumbnail for a file at the given URL
    public func thumbnail(for url: URL, size: CGSize = CGSize(width: 40, height: 40)) async -> NSImage {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) as? NSImage {
            return cached
        }
        
        // Generate thumbnail
        let image = await generateThumbnail(for: url, size: size)
        cache.setObject(image as AnyObject, forKey: url as NSURL)
        return image
    }
    
    private func generateThumbnail(for url: URL, size: CGSize) async -> NSImage {
        // Handle audio files with custom waveform generator
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .audio) {
            if let waveform = await AudioWaveformGenerator.shared.generateWaveform(for: url, size: size) {
                return waveform
            }
        }
        
        // Try QuickLook first for rich thumbnails (images, PDFs, etc.)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .thumbnail
        )
        
        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return thumbnail.nsImage
        } catch {
            // Fall back to system icon from NSWorkspace
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }
    
    /// Clear the thumbnail cache
    public func clearCache() {
        cache.removeAllObjects()
    }
}
