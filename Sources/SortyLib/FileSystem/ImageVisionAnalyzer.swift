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

public final class ImageVisionAnalyzer: Sendable {
    private let maxDimension: CGFloat = 1024.0
    private let compressionQuality: CGFloat = 0.8
    
    public init() {}
    
    /// Prepares an image for AI Vision analysis
    /// - Parameter url: Local URL of the image
    /// - Returns: Base64 encoded JPEG data if successful
    public func prepareImageForVision(at url: URL) async -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
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
            guard let resizedImage = self.resize(cgImage, to: targetSize) else { return nil }
            return self.convertToJPEG(resizedImage)
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
}
