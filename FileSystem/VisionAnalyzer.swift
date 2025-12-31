//
//  VisionAnalyzer.swift
//  FileOrganizer
//
//  Semantic Content Analysis using Apple Vision for OCR
//  Extracts text from images for AI-powered organization
//

import Foundation
import Vision
import AppKit
import CoreImage

/// Result of OCR analysis on an image
public struct OCRResult: Sendable {
    public let text: String
    public let confidence: Float
    public let boundingBoxes: [CGRect]
    public let wordCount: Int

    public init(text: String, confidence: Float, boundingBoxes: [CGRect] = [], wordCount: Int = 0) {
        self.text = text
        self.confidence = confidence
        self.boundingBoxes = boundingBoxes
        self.wordCount = wordCount
    }

    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Preview of the text content (first 300 chars)
    public var preview: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 300 {
            return String(trimmed.prefix(300)) + "..."
        }
        return trimmed
    }

    /// Extract key phrases that might indicate document type
    public var detectedKeywords: [String] {
        let keywords = [
            "invoice", "receipt", "tax", "irs", "statement", "bill",
            "contract", "agreement", "report", "memo", "letter",
            "certificate", "license", "passport", "id", "identification",
            "resume", "cv", "application", "form", "prescription",
            "medical", "insurance", "bank", "account", "payment",
            "internal", "revenue", "service"
        ]

        let lowercased = text.lowercased()
        return keywords.filter { lowercased.contains($0) }


    }
}

/// Actor that performs OCR analysis using Apple Vision framework
public actor VisionAnalyzer {
    private let maxTextLength = 2000
    private let minimumConfidence: Float = 0.3

    public init() {}

    /// Perform OCR on an image file
    public func analyzeImage(at url: URL) async -> OCRResult? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        // Check if file is an image
        let imageExtensions = ["jpg", "jpeg", "png", "heic", "tiff", "tif", "bmp", "gif"]
        guard imageExtensions.contains(url.pathExtension.lowercased()) else {
            return nil
        }

        // Load image
        guard let cgImage = loadCGImage(from: url) else {
            return nil
        }

        return await performOCR(on: cgImage)
    }

    /// Perform OCR on CGImage data
    public func analyzeImage(_ cgImage: CGImage) async -> OCRResult? {
        return await performOCR(on: cgImage)
    }

    /// Perform OCR on raw image data
    public func analyzeImageData(_ data: Data) async -> OCRResult? {
        guard let image = NSImage(data: data),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return await performOCR(on: cgImage)
    }

    // MARK: - Private Methods

    private func loadCGImage(from url: URL) -> CGImage? {
        // Try using CGImageSource for better format support
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            // Fallback to NSImage
            if let image = NSImage(contentsOf: url) {
                return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            return nil
        }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func performOCR(on cgImage: CGImage) async -> OCRResult? {
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    DebugLogger.log("OCR error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                var allText: [String] = []
                var boundingBoxes: [CGRect] = []
                var totalConfidence: Float = 0
                var observationCount = 0

                for observation in observations {
                    guard let topCandidate = observation.topCandidates(1).first else {
                        continue
                    }

                    // Only include text above minimum confidence
                    if topCandidate.confidence >= self.minimumConfidence {
                        allText.append(topCandidate.string)
                        boundingBoxes.append(observation.boundingBox)
                        totalConfidence += topCandidate.confidence
                        observationCount += 1
                    }
                }

                guard !allText.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let combinedText = allText.joined(separator: " ")
                let truncatedText = String(combinedText.prefix(self.maxTextLength))
                let avgConfidence = totalConfidence / Float(max(observationCount, 1))
                let wordCount = combinedText.split(separator: " ").count

                let result = OCRResult(
                    text: truncatedText,
                    confidence: avgConfidence,
                    boundingBoxes: boundingBoxes,
                    wordCount: wordCount
                )

                continuation.resume(returning: result)
            }

            // Configure the request for better accuracy
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "en-GB"] // Can be expanded

            // Perform the request
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

            do {
                try handler.perform([request])
            } catch {
                DebugLogger.log("Failed to perform OCR: \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }

    /// Batch analyze multiple images
    public func analyzeImages(at urls: [URL], progressHandler: ((Int, Int) -> Void)? = nil) async -> [URL: OCRResult] {
        var results: [URL: OCRResult] = [:]

        for (index, url) in urls.enumerated() {
            if let result = await analyzeImage(at: url) {
                results[url] = result
            }
            progressHandler?(index + 1, urls.count)

            // Yield periodically to allow UI updates
            if index % 5 == 0 {
                await Task.yield()
            }
        }

        return results
    }

    /// Extract image dimensions for duplicate comparison
    public func getImageDimensions(at url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            return nil
        }
        return (width, height)
    }

    /// Generate a perceptual hash for near-duplicate detection
    /// Uses a simplified average hash algorithm
    public func generatePerceptualHash(at url: URL) async -> String? {
        guard let cgImage = loadCGImage(from: url) else {
            return nil
        }

        // Resize to 8x8 and convert to grayscale for hash
        guard let resized = resizeImage(cgImage, to: CGSize(width: 8, height: 8)),
              let grayscale = convertToGrayscale(resized) else {
            return nil
        }

        // Calculate average pixel value
        let pixelData = getPixelValues(from: grayscale)
        guard pixelData.count == 64 else { return nil }

        let average = pixelData.reduce(0, +) / Double(pixelData.count)

        // Generate hash: 1 if pixel > average, 0 otherwise
        var hash = ""
        for pixel in pixelData {
            hash += pixel > average ? "1" : "0"
        }

        // Convert binary to hex for compact storage
        return binaryToHex(hash)
    }

    // MARK: - Image Processing Helpers

    private func resizeImage(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )

        context?.interpolationQuality = .low
        context?.draw(image, in: CGRect(origin: .zero, size: size))

        return context?.makeImage()
    }

    private func convertToGrayscale(_ image: CGImage) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )

        context?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        return context?.makeImage()
    }

    private func getPixelValues(from image: CGImage) -> [Double] {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }

        var values: [Double] = []
        let length = CFDataGetLength(data)

        for i in 0..<min(length, 64) {
            values.append(Double(bytes[i]))
        }

        return values
    }

    private func binaryToHex(_ binary: String) -> String {
        var hex = ""
        var index = binary.startIndex

        while index < binary.endIndex {
            let endIndex = binary.index(index, offsetBy: min(4, binary.distance(from: index, to: binary.endIndex)))
            let chunk = String(binary[index..<endIndex])
            if let value = Int(chunk, radix: 2) {
                hex += String(format: "%x", value)
            }
            index = endIndex
        }

        return hex
    }
}

// MARK: - Hamming Distance for Perceptual Hash Comparison

public extension String {
    /// Calculate Hamming distance between two hex hashes
    /// Lower distance = more similar images
    func hammingDistance(to other: String) -> Int? {
        guard self.count == other.count else { return nil }

        // Convert hex to binary for comparison
        guard let selfBinary = hexToBinary(self),
              let otherBinary = hexToBinary(other) else {
            return nil
        }

        var distance = 0
        for (a, b) in zip(selfBinary, otherBinary) {
            if a != b {
                distance += 1
            }
        }

        return distance
    }

    private func hexToBinary(_ hex: String) -> String? {
        var binary = ""
        for char in hex {
            guard let value = Int(String(char), radix: 16) else {
                return nil
            }
            binary += String(value, radix: 2).padding(toLength: 4, withPad: "0", startingAt: 0)
        }
        return binary
    }
}

// MARK: - Similarity Threshold

public enum ImageSimilarity: Sendable {
    case identical      // Hamming distance 0
    case nearIdentical  // Hamming distance 1-5
    case similar        // Hamming distance 6-10
    case different      // Hamming distance > 10

    public static func from(hammingDistance: Int) -> ImageSimilarity {
        switch hammingDistance {
        case 0:
            return .identical
        case 1...5:
            return .nearIdentical
        case 6...10:
            return .similar
        default:
            return .different
        }
    }

    public var description: String {
        switch self {
        case .identical:
            return "Identical"
        case .nearIdentical:
            return "Near-Identical"
        case .similar:
            return "Similar"
        case .different:
            return "Different"
        }
    }
}
