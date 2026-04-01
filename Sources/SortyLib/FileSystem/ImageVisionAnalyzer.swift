//
//  ImageVisionAnalyzer.swift
//  Sorty
//
//  Handles image preprocessing for AI Multimodal (Vision) analysis.
//  Resizes images and converts to Base64 for API consumption.
//

import Foundation
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import CryptoKit
import PDFKit

public final class ImageVisionAnalyzer: Sendable {
    private let maxDimension: CGFloat = 1024.0
    private let compressionQuality: CGFloat = 0.8

    private static var visionCacheDirectory: URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("Sorty")
            .appendingPathComponent("VisionCache", isDirectory: true)
    }

    public init() {}
    
    /// Prepares an image for AI Vision analysis
    /// - Parameter url: Local URL of the image
    /// - Returns: Base64 encoded JPEG data if successful
    public func prepareImageForVision(at url: URL) async -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            DebugLogger.log("ImageVisionAnalyzer: file not found at \(url.path)")
            return nil
        }

        if let cached = cachedImageData(for: url) {
            return cached
        }

        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                DebugLogger.log("ImageVisionAnalyzer: failed to create image source for \(url.lastPathComponent)")
                return nil
            }
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                DebugLogger.log("ImageVisionAnalyzer: failed to decode CGImage for \(url.lastPathComponent)")
                return nil
            }
            
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            
            // Calculate aspect-fit dimensions
            var targetSize = CGSize(width: width, height: height)
            if width > self.maxDimension || height > self.maxDimension {
                if width > height {
                    targetSize = CGSize(width: self.maxDimension, height: (height / width) * self.maxDimension)
                } else {
                    targetSize = CGSize(width: (width / height) * self.maxDimension, height: self.maxDimension)
                }
            }
            
            // Resize and compress
            guard let resizedImage = self.resize(cgImage, to: targetSize) else {
                DebugLogger.log("ImageVisionAnalyzer: failed to resize image \(url.lastPathComponent)")
                return nil
            }
            guard let jpegData = self.convertToJPEG(resizedImage) else {
                DebugLogger.log("ImageVisionAnalyzer: failed to convert image to JPEG \(url.lastPathComponent)")
                return nil
            }

            self.persistCache(jpegData, for: url)
            return jpegData
        }.value
    }
    
    /// Prepares multiple images in parallel
    public func prepareImagesForVision(urls: [URL]) async -> [URL: Data] {
        await withTaskGroup(of: (URL, Data?).self) { group in
            for url in urls {
                group.addTask {
                    let data = await self.prepareImageForVision(at: url)
                    return (url, data)
                }
            }
            
            var results: [URL: Data] = [:]
            for await (url, data) in group {
                if let data = data {
                    results[url] = data
                }
            }
            return results
        }
    }

    /// Prepares supported files for multimodal analysis.
    /// Images are resized/compressed, while PDFs are rendered into per-page JPEG assets.
    public func prepareFilesForVision(
        files: [FileItem],
        baseDirectoryURL: URL? = nil,
        pdfPageLimit: Int = 2
    ) async -> [String: Data] {
        await withTaskGroup(of: [String: Data].self) { group in
            for file in files {
                group.addTask {
                    guard let url = file.url else { return [:] }
                    let ext = file.extension.lowercased()
                    let attachmentName = self.attachmentLabel(for: file, baseDirectoryURL: baseDirectoryURL)

                    if ["jpg", "jpeg", "png", "heic", "webp", "tiff", "tif", "bmp", "gif"].contains(ext),
                       let data = await self.prepareImageForVision(at: url) {
                        return [attachmentName: data]
                    }

                    if ext == "pdf" {
                        return await self.preparePDFForVision(at: url, displayName: attachmentName, maxPages: pdfPageLimit)
                    }

                    return [:]
                }
            }

            var results: [String: Data] = [:]
            for await partial in group {
                results.merge(partial) { _, new in new }
            }
            return results
        }
    }

    private func attachmentLabel(for file: FileItem, baseDirectoryURL: URL?) -> String {
        guard let baseDirectoryURL else {
            return file.displayName
        }

        let filePath = file.path
        let basePath = baseDirectoryURL.path
        let resolvedFilePath = URL(fileURLWithPath: filePath).resolvingSymlinksInPath().path
        let resolvedBasePath = baseDirectoryURL.resolvingSymlinksInPath().path

        if resolvedFilePath.hasPrefix(resolvedBasePath + "/") {
            return String(resolvedFilePath.dropFirst(resolvedBasePath.count + 1))
        }
        if filePath.hasPrefix(basePath + "/") {
            return String(filePath.dropFirst(basePath.count + 1))
        }

        return file.displayName
    }

    public func clearVisionCache() {
        Self.clearSharedCache()
    }

    public static func clearSharedCache() {
        guard let directory = visionCacheDirectory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
    
    private func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        
        context?.interpolationQuality = .medium
        context?.draw(image, in: CGRect(origin: .zero, size: size))
        
        return context?.makeImage()
    }
    
    private func convertToJPEG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        
        return data as Data
    }

    private func preparePDFForVision(
        at url: URL,
        displayName: String,
        maxPages: Int
    ) async -> [String: Data] {
        await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else {
                DebugLogger.log("ImageVisionAnalyzer: failed to open PDF \(url.lastPathComponent)")
                return [:]
            }

            let pagesToRender = min(document.pageCount, maxPages)
            guard pagesToRender > 0 else {
                return [:]
            }

            var rendered: [String: Data] = [:]
            for pageIndex in 0..<pagesToRender {
                guard let page = document.page(at: pageIndex),
                      let image = self.renderPDFPage(page),
                      let jpegData = self.convertToJPEG(image) else {
                    continue
                }
                rendered["\(displayName) [Page \(pageIndex + 1)]"] = jpegData
            }

            return rendered
        }.value
    }

    private func renderPDFPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let scale = min(maxDimension / max(bounds.width, bounds.height), 2.0)
        let renderSize = CGSize(
            width: max(1, bounds.width * scale),
            height: max(1, bounds.height * scale)
        )

        guard let context = CGContext(
            data: nil,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: renderSize))
        context.saveGState()
        context.translateBy(x: 0, y: renderSize.height)
        context.scaleBy(x: scale, y: -scale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        return context.makeImage()
    }

    private func cachedImageData(for url: URL) -> Data? {
        guard let cacheURL = cacheFileURL(for: url),
              FileManager.default.fileExists(atPath: cacheURL.path),
              let data = try? Data(contentsOf: cacheURL) else {
            return nil
        }
        return data
    }

    private func persistCache(_ data: Data, for url: URL) {
        guard let cacheURL = cacheFileURL(for: url),
              let cacheDirectory = Self.visionCacheDirectory else {
            return
        }

        do {
            if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
                try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            }
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            DebugLogger.log("ImageVisionAnalyzer: failed to write cache for \(url.lastPathComponent) (\(error.localizedDescription))")
        }
    }

    private func cacheFileURL(for url: URL) -> URL? {
        guard let key = cacheKey(for: url),
              let directory = Self.visionCacheDirectory else {
            return nil
        }
        return directory.appendingPathComponent("\(key).jpg")
    }

    private func cacheKey(for url: URL) -> String? {
        do {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modTime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            let fileSize = values.fileSize ?? 0
            let input = "\(url.path)|\(modTime)|\(fileSize)"
            let digest = SHA256.hash(data: Data(input.utf8))
            return digest.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            DebugLogger.log("ImageVisionAnalyzer: failed to compute cache key for \(url.lastPathComponent) (\(error.localizedDescription))")
            return nil
        }
    }
}
