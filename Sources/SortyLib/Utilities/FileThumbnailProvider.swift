import SwiftUI
import Combine
@preconcurrency import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Provides cached thumbnails for files using QuickLook and NSWorkspace
@MainActor
public class FileThumbnailProvider: ObservableObject {
    public static let shared = FileThumbnailProvider()
    
    private let cache = NSCache<NSString, NSImage>()
    private var processingKeys: Set<String> = []
    private var continuations: [String: [CheckedContinuation<NSImage, Never>]] = [:]
    
    private init() {
        cache.countLimit = 500 // Cache up to 500 thumbnails
    }
    
    /// Get a thumbnail for a file at the given URL
    public func thumbnail(for url: URL, size: CGSize = CGSize(width: 40, height: 40)) async -> NSImage {
        let key = cacheKey(for: url, size: size)
        if let cached = cache.object(forKey: key as NSString) {
            return cached
        }
        
        if processingKeys.contains(key) {
            return await withCheckedContinuation { continuation in
                continuations[key, default: []].append(continuation)
            }
        }
        
        processingKeys.insert(key)
        let image = await generateThumbnail(for: url, size: size)
        cache.setObject(image, forKey: key as NSString)
        
        if let waitingContinuations = continuations.removeValue(forKey: key) {
            for cont in waitingContinuations {
                cont.resume(returning: image)
            }
        }
        processingKeys.remove(key)
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
        
        if !FileManager.default.fileExists(atPath: url.path) {
            return fallbackIcon(for: url)
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
    
    private func cacheKey(for url: URL, size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return "\(url.path)|\(width)x\(height)"
    }
    
    private func fallbackIcon(for url: URL) -> NSImage {
        if url.hasDirectoryPath {
            return NSWorkspace.shared.icon(for: .folder)
        }
        let ext = url.pathExtension
        if !ext.isEmpty {
            return NSWorkspace.shared.icon(forFileType: ext)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
    
    /// Clear the thumbnail cache
    public func clearCache() {
        cache.removeAllObjects()
        processingKeys.removeAll()
        for (_, waitingContinuations) in continuations {
            for cont in waitingContinuations {
                cont.resume(returning: NSImage(size: NSSize(width: 1, height: 1)))
            }
        }
        continuations.removeAll()
    }
}
