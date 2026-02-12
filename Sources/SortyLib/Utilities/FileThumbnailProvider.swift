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
    private var waveformCache: [String: NSImage] = [:]
    
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
        // Handle audio files with custom waveform generator (only for larger sizes)
        if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType,
           type.conforms(to: .audio) {
            if size.width >= 32 && size.height >= 32 {
                let waveformKey = "\(url.path)|\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
                if let cachedWaveform = waveformCache[waveformKey] {
                    return cachedWaveform
                }
                if let waveform = await AudioWaveformGenerator.shared.generateWaveform(for: url, size: size) {
                    waveformCache[waveformKey] = waveform
                    return waveform
                }
            }
            let icon = NSWorkspace.shared.icon(for: type).copy() as! NSImage
            icon.size = size
            return icon
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
            // Fall back to system icon from NSWorkspace, copying to avoid shared reference invalidation
            return NSWorkspace.shared.icon(forFile: url.path).copy() as! NSImage
        }
    }
    
    private func cacheKey(for url: URL, size: CGSize) -> String {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        return "\(url.path)|\(width)x\(height)"
    }
    
    private func fallbackIcon(for url: URL) -> NSImage {
        // Prioritize extension-based icon lookup before directory check
        // This ensures moved files still get proper icons
        // Copy icons to avoid shared reference invalidation during view recycling
        let ext = url.pathExtension
        if !ext.isEmpty, let utType = UTType(filenameExtension: ext) {
            return NSWorkspace.shared.icon(for: utType).copy() as! NSImage
        }
        if !ext.isEmpty {
            return NSWorkspace.shared.icon(forFileType: ext).copy() as! NSImage
        }
        if url.hasDirectoryPath {
            return NSWorkspace.shared.icon(for: .folder).copy() as! NSImage
        }
        return NSWorkspace.shared.icon(for: .data).copy() as! NSImage
    }
    
    /// Clear the thumbnail cache
    public func clearCache() {
        cache.removeAllObjects()
        processingKeys.removeAll()
        waveformCache.removeAll()
        for (_, waitingContinuations) in continuations {
            for cont in waitingContinuations {
                cont.resume(returning: NSImage(size: NSSize(width: 1, height: 1)))
            }
        }
        continuations.removeAll()
    }
}
