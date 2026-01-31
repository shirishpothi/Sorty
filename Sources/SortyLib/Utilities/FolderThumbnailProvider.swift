//
//  FolderThumbnailProvider.swift
//  Sorty
//
//  Provides Finder-style thumbnails for folders using QuickLook.
//  Shows folder content previews similar to Finder's icon view.
//

import SwiftUI
import Combine
@preconcurrency import QuickLookThumbnailing

/// Provides cached thumbnails for folders using QuickLook
@MainActor
public class FolderThumbnailProvider: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = FolderThumbnailProvider()
    
    // MARK: - Properties
    
    private let cache = NSCache<NSURL, AnyObject>()
    
    /// Wrapper for thumbnail generation tasks to avoid Sendable issues
    private final class ThumbnailTask: @unchecked Sendable {
        let task: Task<NSImage, Never>
        init(_ task: Task<NSImage, Never>) { self.task = task }
    }
    
    /// Pending thumbnail generation tasks to avoid duplicates
    private var pendingTasks: [URL: ThumbnailTask] = [:]
    
    // MARK: - Initialization
    
    private init() {
        cache.countLimit = 200  // Cache up to 200 folder thumbnails
    }
    
    // MARK: - Public API
    
    /// Get a thumbnail for a folder at the given URL
    public func thumbnail(for url: URL, size: CGSize = CGSize(width: 40, height: 40)) async -> NSImage {
        // Check cache first
        if let cached = cache.object(forKey: url as NSURL) as? NSImage {
            return cached
        }
        
        // Check if we're already generating this thumbnail
        if let existingTask = pendingTasks[url] {
            return await existingTask.task.value
        }
        
        // Create generation task
        let task = Task<NSImage, Never> { @MainActor in
            let image = await self.generateThumbnail(for: url, size: size)
            self.cache.setObject(image, forKey: url as NSURL)
            self.pendingTasks.removeValue(forKey: url)
            return image
        }
        
        pendingTasks[url] = ThumbnailTask(task)
        return await task.value
    }
    
    /// Clear the thumbnail cache
    public func clearCache() {
        cache.removeAllObjects()
        for wrapper in pendingTasks.values {
            wrapper.task.cancel()
        }
        pendingTasks.removeAll()
    }
    
    // MARK: - Thumbnail Generation
    
    private func generateThumbnail(for url: URL, size: CGSize) async -> NSImage {
        // Try QuickLook first - it can generate folder previews
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: scale,
            representationTypes: .all
        )
        
        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return thumbnail.nsImage
        } catch {
            // QuickLook failed, try composite thumbnail
            if let composite = await generateCompositeThumbnail(for: url, size: size) {
                return composite
            }
            
            // Fall back to system folder icon
            return NSWorkspace.shared.icon(forFile: url.path)
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
        return await composeFolder(with: miniThumbnails, size: size)
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
    
    /// Compose thumbnails into a folder-style preview
    private func composeFolder(with thumbnails: [NSImage], size: CGSize) async -> NSImage {
        let folderIcon = await MainActor.run { NSWorkspace.shared.icon(forFile: "/tmp") }
        
        return await MainActor.run {
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
                
                // Draw with rounded corners and shadow
                let path = NSBezierPath(roundedRect: drawRect, xRadius: 2, yRadius: 2)
                
                // Shadow
                NSShadow().set()
                let shadow = NSShadow()
                shadow.shadowOffset = NSSize(width: 0, height: -1)
                shadow.shadowBlurRadius = 2
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
                shadow.set()
                
                path.addClip()
                thumbnail.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
                
                NSGraphicsContext.restoreGraphicsState()
            }
            
            image.unlockFocus()
            return image
        }
    }
}
