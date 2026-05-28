//
//  FolderThumbnailProvider.swift
//  Sorty
//
//  Provides Finder-style thumbnails for folders using QuickLook.
//  Shows folder content previews similar to Finder's icon view.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
@preconcurrency import QuickLookThumbnailing

/// A wrapper to make NSImage sendable for use with continuations
/// This is safe because NSImage is thread-safe for reading once created
private struct SendableImage: @unchecked Sendable {
    let image: NSImage
}

/// Provides cached thumbnails for folders using QuickLook
@MainActor
public class FolderThumbnailProvider: ObservableObject {

    // MARK: - Singleton

    public static let shared = FolderThumbnailProvider()

    // MARK: - Properties

    private let cache = NSCache<NSURL, AnyObject>()

    /// Track URLs currently being processed to avoid duplicate generation
    private var processingURLs: Set<URL> = []

    /// Continuations for URLs being processed (to resume awaiting callers)
    /// Using SendableImage wrapper to satisfy Swift 6 Sendable requirements
    private var continuations: [URL: [CheckedContinuation<SendableImage, Never>]] = [:]
    
    // MARK: - Initialization
    
    private init() {
        cache.countLimit = 80
        cache.totalCostLimit = 8 * 1024 * 1024
    }
    
    // MARK: - Public API
    
    /// Get a thumbnail for a folder at the given URL
    public func thumbnail(for url: URL, size: CGSize = CGSize(width: 40, height: 40)) async -> NSImage {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) as? NSImage {
            return cached
        }
        
        // Check if we're already generating this thumbnail
        if processingURLs.contains(url) {
            // Wait for existing generation to complete
            let sendableImage = await withCheckedContinuation { continuation in
                continuations[url, default: []].append(continuation)
            }
            return sendableImage.image
        }
        
        // Mark as processing
        processingURLs.insert(url)
        
        // Generate thumbnail
        let image = await generateThumbnail(for: url, size: size)
        cache.setObject(image, forKey: url as NSURL, cost: imageCost(image))
        
        // Resume any waiting continuations with SendableImage wrapper
        if let waitingContinuations = continuations.removeValue(forKey: url) {
            let sendableImage = SendableImage(image: image)
            for cont in waitingContinuations {
                cont.resume(returning: sendableImage)
            }
        }
        
        // Remove from processing set
        processingURLs.remove(url)
        
        return image
    }
    
    /// Clear the thumbnail cache
    public func clearCache() {
        cache.removeAllObjects()
        processingURLs.removeAll()
        // Resume any waiting continuations with empty images (they'll get regenerated)
        let emptyImage = SendableImage(image: NSImage(size: NSSize(width: 1, height: 1)))
        for (_, waitingContinuations) in continuations {
            for cont in waitingContinuations {
                cont.resume(returning: emptyImage)
            }
        }
        continuations.removeAll()
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateThumbnail(for url: URL, size: CGSize) async -> NSImage {
        // Check if the URL is a directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return NSWorkspace.shared.icon(forFile: url.path).copy() as! NSImage
        }

        // For directories: skip QuickLook (it only returns a generic folder icon)
        // and go straight to composite thumbnail showing actual folder contents
        if isDir.boolValue {
            let icon = NSWorkspace.shared.icon(forFile: url.path).copy() as! NSImage
            icon.size = size
            return icon
        }

        // For files: use QuickLook for rich thumbnails (images, PDFs, etc.)
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
            return NSWorkspace.shared.icon(forFile: url.path).copy() as! NSImage
        }
    }
    
    /// Generate a composite thumbnail showing folder contents preview
    private func generateCompositeThumbnail(for folderURL: URL, size: CGSize) async -> NSImage? {
        // Get first few previewable files in the folder
        let previewFiles = await getPreviewableFiles(in: folderURL, limit: 4)
        
        guard !previewFiles.isEmpty else { return nil }
        
        // Generate mini thumbnails for each file
        var miniThumbnails: [NSImage] = []
        let miniSize = CGSize(width: size.width * 0.4, height: size.height * 0.4)
        
        for fileURL in previewFiles.prefix(4) {
            let thumbnail = await FileThumbnailProvider.shared.thumbnail(for: fileURL, size: miniSize)
            miniThumbnails.append(thumbnail)
        }
        
        guard !miniThumbnails.isEmpty else { return nil }
        
        // Compose into folder icon
        return composeFolder(with: miniThumbnails, size: size)
    }
    
    /// Get previewable files from a folder
    private func getPreviewableFiles(in folderURL: URL, limit: Int) async -> [URL] {
        return await Task.detached(priority: .utility) {
            var files: [URL] = []
            
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return files }
            
            // Prioritize images and documents
            let priorityExtensions = Set(["jpg", "jpeg", "png", "gif", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx"])
            
            while let fileURL = enumerator.nextObject() as? URL {
                guard files.count < limit else { break }
                
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                guard isFile else { continue }
                
                let ext = fileURL.pathExtension.lowercased()
                if priorityExtensions.contains(ext) {
                    files.append(fileURL)
                }
                
                // Stop early if we have enough priority files
                if files.count >= limit {
                    break
                }
            }
            
            // If we don't have enough priority files, add any files
            if files.count < limit {
                // Re-create enumerator since we can't reset it
                if let newEnumerator = FileManager.default.enumerator(
                    at: folderURL,
                    includingPropertiesForKeys: [.isRegularFileKey, .contentTypeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) {
                    while let fileURL = newEnumerator.nextObject() as? URL {
                        guard files.count < limit else { break }
                        
                        let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                        guard isFile else { continue }
                        
                        if !files.contains(fileURL) {
                            files.append(fileURL)
                        }
                    }
                }
            }
            
            return files
        }.value
    }
    
    /// Compose thumbnails into a folder-style preview - runs synchronously on MainActor
    private func composeFolder(with thumbnails: [NSImage], size: CGSize) -> NSImage {
        let folderIcon = NSWorkspace.shared.icon(forFile: "/tmp").copy() as! NSImage
        
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw base folder icon (slightly smaller)
        let folderRect = NSRect(x: 0, y: 0, width: size.width, height: size.height)
        folderIcon.draw(in: folderRect, from: .zero, operation: .sourceOver, fraction: 0.3)
        
        // Calculate grid positions for mini thumbnails
        let gridSize = thumbnails.count <= 1 ? 1 : 2
        let cellWidth = size.width * 0.35
        let cellHeight = size.height * 0.35
        let startX = (size.width - cellWidth * CGFloat(min(gridSize, thumbnails.count))) / 2
        let startY = (size.height - cellHeight * CGFloat(gridSize)) / 2 + size.height * 0.05
        
        for (index, thumbnail) in thumbnails.prefix(4).enumerated() {
            let row = index / gridSize
            let col = index % gridSize
            
            let x = startX + CGFloat(col) * cellWidth + cellWidth * 0.1
            let y = startY + CGFloat(1 - row) * cellHeight + cellHeight * 0.1
            
            let drawRect = NSRect(x: x, y: y, width: cellWidth * 0.8, height: cellHeight * 0.8)
            
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            
            // Draw with rounded corners and shadow
            let path = NSBezierPath(roundedRect: drawRect, xRadius: 2, yRadius: 2)
            
            // Shadow
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.set()
            
            path.addClip()
            thumbnail.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
        
        image.unlockFocus()
        return image
    }

    private func imageCost(_ image: NSImage) -> Int {
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixels = max(1, Int(image.size.width * scale * image.size.height * scale))
        return pixels * 4
    }
}
