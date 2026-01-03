//
//  ContentAnalyzer.swift
//  FileOrganizer
//
//  Extracts content from files for deep scanning (PDF text, EXIF data, DOCX text, OCR)
//

import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers

/// Metadata extracted from file content
public struct ContentMetadata: Codable, Hashable, Sendable {
    public var textPreview: String?          // First ~200 chars of text content
    public var documentTitle: String?         // Title from document metadata
    public var exifData: [String: String]?    // Camera, date, GPS for images
    public var pageCount: Int?               // For documents
    public var author: String?               // Author metadata
    public var creationDate: Date?           // Document creation date
    public var keywords: [String]?           // Keywords/tags if available
    public var ocrText: String?              // OCR extracted text from images
    public var ocrConfidence: Float?         // OCR confidence score
    public var detectedKeywords: [String]?   // Keywords detected in OCR text

    public init(
        textPreview: String? = nil,
        documentTitle: String? = nil,
        exifData: [String: String]? = nil,
        pageCount: Int? = nil,
        author: String? = nil,
        creationDate: Date? = nil,
        keywords: [String]? = nil,
        ocrText: String? = nil,
        ocrConfidence: Float? = nil,
        detectedKeywords: [String]? = nil
    ) {
        self.textPreview = textPreview
        self.documentTitle = documentTitle
        self.exifData = exifData
        self.pageCount = pageCount
        self.author = author
        self.creationDate = creationDate
        self.keywords = keywords
        self.ocrText = ocrText
        self.ocrConfidence = ocrConfidence
        self.detectedKeywords = detectedKeywords
    }

    public var isEmpty: Bool {
        textPreview == nil && documentTitle == nil && exifData == nil && ocrText == nil
    }

    /// All available text content (document text + OCR)
    public var allTextContent: String? {
        var parts: [String] = []
        if let preview = textPreview { parts.append(preview) }
        if let ocr = ocrText { parts.append(ocr) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Summary for AI prompt
    public var summary: String {
        var parts: [String] = []

        if let title = documentTitle {
            parts.append("Title: \"\(title)\"")
        }
        if let preview = textPreview {
            let trimmed = preview.prefix(300).replacingOccurrences(of: "\n", with: " ")
            parts.append("Content: \"\(trimmed)...\"")
        }
        if let ocr = ocrText {
            let trimmed = ocr.prefix(200).replacingOccurrences(of: "\n", with: " ")
            parts.append("OCR: \"\(trimmed)...\"")
        }
        if let detected = detectedKeywords, !detected.isEmpty {
            parts.append("Detected: \(detected.joined(separator: ", "))")
        }
        if let exif = exifData {
            if let camera = exif["camera"] {
                parts.append("Camera: \(camera)")
            }
            if let date = exif["dateTime"] {
                parts.append("Taken: \(date)")
            }
        }
        if let pages = pageCount {
            parts.append("\(pages) pages")
        }

        return parts.isEmpty ? "" : "[\(parts.joined(separator: ", "))]"
    }
}

/// Actor that analyzes file content
public actor ContentAnalyzer {
    private let maxPreviewLength = 800
    private let maxBytesToRead = 4096 // 4KB
    private let visionAnalyzer = VisionAnalyzer()

    // Configuration
    public var enableOCR: Bool = true
    public var enableDeepDocumentScan: Bool = true

    public init() {}

    /// Analyze a file and extract relevant metadata
    public func analyze(fileURL: URL, enableOCR: Bool = true) async -> ContentMetadata? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let ext = fileURL.pathExtension.lowercased()

        switch ext {
        case "pdf":
            return await extractPDFContent(from: fileURL)
        case "jpg", "jpeg", "heic", "png", "tiff", "tif", "bmp", "gif":
            return await extractImageContent(from: fileURL, performOCR: enableOCR)
        case "docx":
            return await extractDOCXContent(from: fileURL)
        case "txt", "md", "rtf":
            return extractTextContent(from: fileURL)
        default:
            return nil
        }
    }

    /// Batch analyze multiple files
    public func analyzeFiles(
        _ urls: [URL],
        enableOCR: Bool = true,
        progressHandler: ((Int, Int) -> Void)? = nil
    ) async -> [URL: ContentMetadata] {
        var results: [URL: ContentMetadata] = [:]

        for (index, url) in urls.enumerated() {
            if let metadata = await analyze(fileURL: url, enableOCR: enableOCR) {
                results[url] = metadata
            }
            progressHandler?(index + 1, urls.count)

            // Yield periodically for UI updates
            if index % 10 == 0 {
                await Task.yield()
            }
        }

        return results
    }

    // MARK: - PDF Extraction

    private func extractPDFContent(from url: URL) async -> ContentMetadata? {
        guard let document = PDFDocument(url: url) else {
            return nil
        }

        var metadata = ContentMetadata()

        // Get document attributes
        if let attributes = document.documentAttributes {
            metadata.documentTitle = attributes[PDFDocumentAttribute.titleAttribute] as? String
            metadata.author = attributes[PDFDocumentAttribute.authorAttribute] as? String
            if let keywordsString = attributes[PDFDocumentAttribute.keywordsAttribute] as? String {
                metadata.keywords = keywordsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }

        metadata.pageCount = document.pageCount

        // Extract text from first page(s)
        var extractedText = ""
        let pagesToScan = min(document.pageCount, 2)

        for i in 0..<pagesToScan {
            if let page = document.page(at: i),
               let text = page.string {
                extractedText += text + " "
                if extractedText.count > maxPreviewLength {
                    break
                }
            }
        }

        if !extractedText.isEmpty {
            metadata.textPreview = String(extractedText.prefix(maxPreviewLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If no text extracted (scanned PDF), try OCR on first page
        if extractedText.isEmpty && enableOCR, let firstPage = document.page(at: 0) {
            if let ocrResult = await performOCROnPDFPage(firstPage) {
                metadata.ocrText = ocrResult.text
                metadata.ocrConfidence = ocrResult.confidence
                metadata.detectedKeywords = ocrResult.detectedKeywords
            }
        }

        return metadata.isEmpty ? nil : metadata
    }

    private func performOCROnPDFPage(_ page: PDFPage) async -> OCRResult? {
        // Render PDF page to image for OCR
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0 // Higher resolution for better OCR
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)

        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.scaleBy(x: scale, y: scale)

        page.draw(with: .mediaBox, to: context)

        guard let cgImage = context.makeImage() else {
            return nil
        }

        // Use CGImage directly for compatibility with VisionAnalyzer (Sendable)
        return await visionAnalyzer.analyzeImage(cgImage)
    }

    // MARK: - Image Extraction with OCR

    private func extractImageContent(from url: URL, performOCR: Bool) async -> ContentMetadata? {
        var metadata = extractEXIFData(from: url) ?? ContentMetadata()

        // Perform OCR if enabled
        if performOCR {
            if let ocrResult = await visionAnalyzer.analyzeImage(at: url) {
                metadata.ocrText = ocrResult.text
                metadata.ocrConfidence = ocrResult.confidence
                metadata.detectedKeywords = ocrResult.detectedKeywords
            }
        }

        return metadata.isEmpty ? nil : metadata
    }

    // MARK: - EXIF Extraction

    private func extractEXIFData(from url: URL) -> ContentMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        var exifDict: [String: String] = [:]

        // EXIF data
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            if let dateTime = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                exifDict["dateTime"] = dateTime
            }
            if let fNumber = exif[kCGImagePropertyExifFNumber as String] {
                exifDict["fNumber"] = "f/\(fNumber)"
            }
            if let iso = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [Int], let firstISO = iso.first {
                exifDict["iso"] = "ISO \(firstISO)"
            }
        }

        // TIFF data (camera info)
        if let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
            var cameraInfo: [String] = []
            if let make = tiff[kCGImagePropertyTIFFMake as String] as? String {
                cameraInfo.append(make)
            }
            if let model = tiff[kCGImagePropertyTIFFModel as String] as? String {
                cameraInfo.append(model)
            }
            if !cameraInfo.isEmpty {
                exifDict["camera"] = cameraInfo.joined(separator: " ")
            }
        }

        // GPS data
        if let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any] {
            if let lat = gps[kCGImagePropertyGPSLatitude as String] as? Double,
               let lon = gps[kCGImagePropertyGPSLongitude as String] as? Double {
                exifDict["gps"] = String(format: "%.4f, %.4f", lat, lon)
            }
        }

        // Image dimensions
        if let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
           let height = properties[kCGImagePropertyPixelHeight as String] as? Int {
            exifDict["dimensions"] = "\(width)x\(height)"
        }

        guard !exifDict.isEmpty else {
            return nil
        }

        return ContentMetadata(exifData: exifDict)
    }

    // MARK: - DOCX Extraction

    private func extractDOCXContent(from url: URL) async -> ContentMetadata? {
        // DOCX files are ZIP archives containing XML
        let coordinator = NSFileCoordinator()
        var extractedText: String?
        var error: NSError?

        coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { accessedURL in
            do {
                // Create temporary directory for extraction
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer {
                    try? FileManager.default.removeItem(at: tempDir)
                }

                // Unzip using Process
                let unzipProcess = Process()
                unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzipProcess.arguments = ["-o", "-q", accessedURL.path, "word/document.xml", "-d", tempDir.path]
                unzipProcess.standardOutput = FileHandle.nullDevice
                unzipProcess.standardError = FileHandle.nullDevice

                try unzipProcess.run()
                unzipProcess.waitUntilExit()

                // Read the document.xml
                let documentPath = tempDir.appendingPathComponent("word/document.xml")
                if let xmlData = try? Data(contentsOf: documentPath),
                   let xmlString = String(data: xmlData, encoding: .utf8) {
                    // Simple extraction of text content from XML (strips tags)
                    extractedText = extractTextFromXML(xmlString)
                }
            } catch {
                DebugLogger.log("DOCX extraction failed: \(error)")
            }
        }

        guard let text = extractedText, !text.isEmpty else {
            return nil
        }

        return ContentMetadata(textPreview: String(text.prefix(maxPreviewLength)))
    }

    private func extractTextFromXML(_ xml: String) -> String {
        // Simple regex to extract text between <w:t> tags
        let pattern = "<w:t[^>]*>([^<]+)</w:t>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return ""
        }

        let matches = regex.matches(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml))
        var texts: [String] = []

        for match in matches {
            if let range = Range(match.range(at: 1), in: xml) {
                texts.append(String(xml[range]))
            }
        }

        return texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Plain Text Extraction

    private func extractTextContent(from url: URL) -> ContentMetadata? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }

        // Only read first few KB
        let bytesToRead = min(data.count, maxBytesToRead)
        let subset = data.prefix(bytesToRead)

        guard let text = String(data: subset, encoding: .utf8) else {
            return nil
        }

        let preview = String(text.prefix(maxPreviewLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ContentMetadata(textPreview: preview)
    }
}

// MARK: - Import for AppKit NSColor/NSImage
import AppKit
