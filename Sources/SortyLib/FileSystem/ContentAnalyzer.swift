//
//  ContentAnalyzer.swift
//  Sorty
//
//  Extracts content from files for deep scanning (PDF text, EXIF data, DOCX text, OCR)
//

import Foundation
import PDFKit
import ImageIO
import UniformTypeIdentifiers
import Compression
@preconcurrency import AVFoundation
import CoreServices
import CoreMedia

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
    public var duration: TimeInterval?       // Duration in seconds for audio/video
    public var mediaInfo: [String: String]?  // Codec, bitrate, title, artist, album, genre

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
        detectedKeywords: [String]? = nil,
        duration: TimeInterval? = nil,
        mediaInfo: [String: String]? = nil
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
        self.duration = duration
        self.mediaInfo = mediaInfo
    }

    public var isEmpty: Bool {
        textPreview == nil && documentTitle == nil && exifData == nil && ocrText == nil && mediaInfo == nil
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
            let trimmed = preview.prefix(500).replacingOccurrences(of: "\n", with: " ")
            parts.append("Content: \"\(trimmed)...\"")
        }
        if let ocr = ocrText {
            let trimmed = ocr.prefix(400).replacingOccurrences(of: "\n", with: " ")
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
        if let duration = duration {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            parts.append("Duration: \(minutes)m \(seconds)s")
        }
        if let info = mediaInfo {
            if let artist = info["artist"] {
                parts.append("Artist: \(artist)")
            }
            if let title = info["title"] {
                parts.append("Track: \(title)")
            }
        }

        return parts.isEmpty ? "" : "[\(parts.joined(separator: ", "))]"
    }
}

/// Actor that analyzes file content
public actor ContentAnalyzer {
    static let defaultTextPreviewLength = 1600

    private let maxPreviewLength = ContentAnalyzer.defaultTextPreviewLength
    private let maxTextBytesToRead = 262_144 // 256KB
    private let maxDocumentTextLength = 12_000
    private let visionAnalyzer = VisionAnalyzer()

    // Configuration
    public var enableOCR: Bool = true
    public var enableDeepDocumentScan: Bool = true
    public var customOCRKeywords: [String] = []
    public var ocrLanguages: [String] = ["en-US"]
    
    public func setCustomOCRKeywords(_ keywords: [String]) {
        self.customOCRKeywords = keywords
    }

    public func setOCRLanguages(_ languages: [String]) async {
        let cleaned = languages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        self.ocrLanguages = cleaned.isEmpty ? ["en-US"] : cleaned
        await visionAnalyzer.setRecognitionLanguages(self.ocrLanguages)
    }

    // MARK: - Content Metadata Cache

    /// Cache entry for content metadata
    private struct CacheEntry: Codable {
        let filePath: String
        let modificationDate: Date
        let fileSize: Int64
        let metadata: ContentMetadata
    }

    private var memoryCache: [String: CacheEntry] = [:]
    private let maximumCacheEntryCount = 500
    private var cacheLoaded = false
    private var diskCacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.sorty.app")
            .appendingPathComponent("content-metadata-cache.json")
    }

    public init() {}
    
    /// Clear any cached data to free memory
    public func clearCache() async {
        memoryCache.removeAll()
        if let cacheURL = diskCacheURL {
            try? FileManager.default.removeItem(at: cacheURL)
        }
        await visionAnalyzer.clearCache()
        ImageVisionAnalyzer.clearSharedCache()
    }

    private func ensureCacheLoaded() {
        if !cacheLoaded {
            cacheLoaded = true
            loadCacheFromDisk()
        }
    }

    private func lookupCache(for url: URL) -> ContentMetadata? {
        ensureCacheLoaded()
        let key = url.path
        guard let entry = memoryCache[key] else { return nil }

        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int64 else {
            memoryCache.removeValue(forKey: key)
            return nil
        }

        if entry.modificationDate == modDate && entry.fileSize == size {
            return entry.metadata
        }

        memoryCache.removeValue(forKey: key)
        return nil
    }

    private func cacheResult(_ metadata: ContentMetadata, for url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int64 else { return }

        let entry = CacheEntry(
            filePath: url.path,
            modificationDate: modDate,
            fileSize: size,
            metadata: metadata
        )
        memoryCache[url.path] = entry
        trimCacheIfNeeded()
    }

    private func trimCacheIfNeeded() {
        let overflow = memoryCache.count - maximumCacheEntryCount
        guard overflow > 0 else { return }

        let oldestKeys = memoryCache
            .sorted { $0.value.modificationDate < $1.value.modificationDate }
            .prefix(overflow)
            .map(\.key)
        for key in oldestKeys {
            memoryCache.removeValue(forKey: key)
        }
    }

    private func saveCacheToDisk() {
        guard let cacheURL = diskCacheURL else { return }
        do {
            let dir = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(Array(memoryCache.values))
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            DebugLogger.log("Failed to save content cache: \(error)")
        }
    }

    private func loadCacheFromDisk() {
        guard let cacheURL = diskCacheURL,
              let data = try? Data(contentsOf: cacheURL),
              let entries = try? JSONDecoder().decode([CacheEntry].self, from: data) else { return }

        for entry in entries
            .sorted(by: { $0.modificationDate > $1.modificationDate })
            .prefix(maximumCacheEntryCount) {
            memoryCache[entry.filePath] = entry
        }
    }

    /// Analyze a file and extract relevant metadata
    public func analyze(fileURL: URL, enableOCR: Bool = true) async -> ContentMetadata? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Check cache first
        if let cached = lookupCache(for: fileURL) {
            return cached
        }

        let ext = fileURL.pathExtension.lowercased()

        let result: ContentMetadata?
        switch ext {
        case "pdf":
            if enableDeepDocumentScan {
                result = await extractPDFContent(from: fileURL)
            } else {
                result = extractPDFMetadataOnly(from: fileURL)
            }
        case "jpg", "jpeg", "heic", "png", "tiff", "tif", "bmp", "gif":
            result = await extractImageContent(from: fileURL, performOCR: enableOCR)
        case "docx":
            result = enableDeepDocumentScan ? await extractDOCXContent(from: fileURL) : nil
        case "rtf":
            result = enableDeepDocumentScan ? extractRTFContent(from: fileURL) : nil
        case "mp3", "mp4", "m4a", "mov", "avi", "mkv", "wav", "aac", "flac", "m4v", "webm":
            result = await extractMediaContent(from: fileURL)
        case "pages", "numbers", "key":
            result = enableDeepDocumentScan ? extractIWorkContent(from: fileURL) : nil
        case "xlsx":
            result = enableDeepDocumentScan ? await extractXLSXContent(from: fileURL) : nil
        case "pptx":
            result = enableDeepDocumentScan ? await extractPPTXContent(from: fileURL) : nil
        default:
            result = enableDeepDocumentScan && isTextLikeFile(fileURL) ? extractTextContent(from: fileURL) : nil
        }

        // Cache the result
        if let result = result {
            cacheResult(result, for: fileURL)
        }

        return result
    }

    /// Batch analyze multiple files
    public func analyzeFiles(
        _ urls: [URL],
        enableOCR: Bool = true,
        progressHandler: (@Sendable (Int, Int) -> Void)? = nil
    ) async -> [URL: ContentMetadata] {
        var results: [URL: ContentMetadata] = [:]
        let total = urls.count

        // Process in batches to limit concurrency
        let batchSize = 4
        for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, urls.count)
            let batch = Array(urls[batchStart..<batchEnd])

            let batchResults = await withTaskGroup(of: (URL, ContentMetadata?).self) { group in
                for url in batch {
                    group.addTask {
                        let metadata = await self.analyze(fileURL: url, enableOCR: enableOCR)
                        return (url, metadata)
                    }
                }

                var batchDict: [URL: ContentMetadata] = [:]
                for await (url, metadata) in group {
                    if let metadata = metadata {
                        batchDict[url] = metadata
                    }
                }
                return batchDict
            }

            results.merge(batchResults) { _, new in new }
            progressHandler?(batchEnd, total)

            // Yield for UI updates between batches
            await Task.yield()
        }

        // Save cache after batch analysis
        saveCacheToDisk()

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

        // Extract text from all pages up to a reasonable ceiling so deep scan
        // has materially better context without producing unbounded payloads.
        var extractedText = ""
        let pagesToScan = document.pageCount

        for i in 0..<pagesToScan {
            if let page = document.page(at: i),
               let text = page.string {
                extractedText += text + " "
                if extractedText.count >= maxDocumentTextLength {
                    break
                }
            }
        }

        if !extractedText.isEmpty {
            metadata.textPreview = String(extractedText.prefix(maxDocumentTextLength))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // If no text extracted (scanned PDF), try OCR on first page
        if extractedText.isEmpty && enableOCR, let firstPage = document.page(at: 0) {
            if let ocrResult = await performOCROnPDFPage(firstPage) {
                metadata.ocrText = ocrResult.text
                metadata.ocrConfidence = ocrResult.confidence
                metadata.detectedKeywords = ocrResult.detectKeywords(using: customOCRKeywords)
            }
        }

        return metadata.isEmpty ? nil : metadata
    }

    /// Light PDF extraction: only metadata (title, author, page count), no text extraction
    private func extractPDFMetadataOnly(from url: URL) -> ContentMetadata? {
        guard let document = PDFDocument(url: url) else { return nil }

        var metadata = ContentMetadata()

        if let attributes = document.documentAttributes {
            metadata.documentTitle = attributes[PDFDocumentAttribute.titleAttribute] as? String
            metadata.author = attributes[PDFDocumentAttribute.authorAttribute] as? String
            if let keywordsString = attributes[PDFDocumentAttribute.keywordsAttribute] as? String {
                metadata.keywords = keywordsString.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }

        metadata.pageCount = document.pageCount

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
                metadata.detectedKeywords = ocrResult.detectKeywords(using: customOCRKeywords)
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
        guard let zipData = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }

        guard let xmlString = extractFileFromZip(data: zipData, fileName: "word/document.xml") else {
            return nil
        }

        let text = extractTextFromXML(xmlString)
        guard !text.isEmpty else { return nil }

        var metadata = ContentMetadata(textPreview: String(text.prefix(maxDocumentTextLength)))

        // Also try to extract core.xml for metadata
        if let coreXML = extractFileFromZip(data: zipData, fileName: "docProps/core.xml") {
            if let title = extractXMLValue(coreXML, tag: "dc:title") {
                metadata.documentTitle = title
            }
            if let author = extractXMLValue(coreXML, tag: "dc:creator") {
                metadata.author = author
            }
        }

        return metadata
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

        let bytesToRead = min(data.count, maxTextBytesToRead)
        let subset = data.prefix(bytesToRead)

        guard let text = decodeText(from: Data(subset)) else {
            return nil
        }

        let preview = String(text.prefix(maxPreviewLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !preview.isEmpty else { return nil }
        return ContentMetadata(textPreview: preview)
    }

    // MARK: - RTF Extraction

    private func extractRTFContent(from url: URL) -> ContentMetadata? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return nil
        }

        guard let attributedString = NSAttributedString(rtf: data, documentAttributes: nil) else {
            return extractTextContent(from: url)
        }

        let text = attributedString.string
        let preview = String(text.prefix(maxPreviewLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !preview.isEmpty else { return nil }
        return ContentMetadata(textPreview: preview)
    }

    // MARK: - Audio/Video Extraction

    private func extractMediaContent(from url: URL) async -> ContentMetadata? {
        let asset = AVURLAsset(url: url)
        var metadata = ContentMetadata()
        var mediaDict: [String: String] = [:]

        if let duration = try? await asset.load(.duration) {
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite && seconds > 0 {
                metadata.duration = seconds
            }
        }

        if let metadataItems = try? await asset.load(.commonMetadata) {
            for item in metadataItems {
                guard let key = item.commonKey?.rawValue,
                      let value = try? await item.load(.stringValue) else { continue }
                switch key {
                case AVMetadataKey.commonKeyTitle.rawValue:
                    metadata.documentTitle = value
                    mediaDict["title"] = value
                case AVMetadataKey.commonKeyArtist.rawValue:
                    metadata.author = value
                    mediaDict["artist"] = value
                case AVMetadataKey.commonKeyAlbumName.rawValue:
                    mediaDict["album"] = value
                case AVMetadataKey.commonKeyType.rawValue:
                    mediaDict["genre"] = value
                case AVMetadataKey.commonKeyCreationDate.rawValue:
                    mediaDict["creationDate"] = value
                default:
                    break
                }
            }
        }

        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio),
           let firstAudio = audioTracks.first {
            if let formatDescriptions = try? await firstAudio.load(.formatDescriptions),
               let desc = formatDescriptions.first {
                let audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(desc)
                if let sampleRate = audioDesc?.pointee.mSampleRate {
                    mediaDict["sampleRate"] = "\(Int(sampleRate)) Hz"
                }
            }
        }

        if let videoTracks = try? await asset.loadTracks(withMediaType: .video),
           let firstVideo = videoTracks.first {
            if let naturalSize = try? await firstVideo.load(.naturalSize) {
                mediaDict["resolution"] = "\(Int(naturalSize.width))x\(Int(naturalSize.height))"
            }
        }

        if !mediaDict.isEmpty {
            metadata.mediaInfo = mediaDict
        }

        return metadata.isEmpty ? nil : metadata
    }

    // MARK: - iWork Extraction (Pages, Numbers, Keynote)

    private func extractIWorkContent(from url: URL) -> ContentMetadata? {
        return extractSpotlightMetadata(from: url)
    }

    // MARK: - XLSX/PPTX Extraction

    private func extractXLSXContent(from url: URL) async -> ContentMetadata? {
        if let metadata = extractSpotlightMetadata(from: url) {
            return metadata
        }

        return await extractZipXMLContent(from: url, xmlPath: "xl/workbook.xml")
    }

    private func extractPPTXContent(from url: URL) async -> ContentMetadata? {
        if let metadata = extractSpotlightMetadata(from: url) {
            return metadata
        }

        return await extractZipXMLContent(from: url, xmlPath: "ppt/presentation.xml")
    }

    // MARK: - Shared Helpers

    private func extractSpotlightMetadata(from url: URL) -> ContentMetadata? {
        guard let mdItem = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return nil
        }

        var metadata = ContentMetadata()

        let attributes = [
            kMDItemTitle,
            kMDItemAuthors,
            kMDItemNumberOfPages,
            kMDItemTextContent,
            kMDItemKeywords
        ] as [CFString]

        if let attrDict = MDItemCopyAttributes(mdItem, attributes as CFArray) as? [String: Any] {
            if let title = attrDict[kMDItemTitle as String] as? String {
                metadata.documentTitle = title
            }
            if let authors = attrDict[kMDItemAuthors as String] as? [String], let firstAuthor = authors.first {
                metadata.author = firstAuthor
            }
            if let pages = attrDict[kMDItemNumberOfPages as String] as? Int {
                metadata.pageCount = pages
            }
            if let text = attrDict[kMDItemTextContent as String] as? String, !text.isEmpty {
                metadata.textPreview = String(text.prefix(maxDocumentTextLength))
            }
            if let keywords = attrDict[kMDItemKeywords as String] as? [String] {
                metadata.keywords = keywords
            }
        }

        return metadata.isEmpty ? nil : metadata
    }

    private func extractZipXMLContent(from url: URL, xmlPath: String) async -> ContentMetadata? {
        guard let zipData = try? Data(contentsOf: url, options: .mappedIfSafe),
              let xmlString = extractFileFromZip(data: zipData, fileName: xmlPath) else {
            return nil
        }

        let text = extractTextFromXML(xmlString)
        guard !text.isEmpty else { return nil }
        return ContentMetadata(textPreview: String(text.prefix(maxDocumentTextLength)))
    }

    // MARK: - Native ZIP Reading

    /// Extract a single file from a ZIP archive by name
    private func extractFileFromZip(data: Data, fileName: String) -> String? {
        // ZIP end of central directory signature
        let eocdSignature: [UInt8] = [0x50, 0x4B, 0x05, 0x06]

        guard data.count > 22 else { return nil }
        var eocdOffset = -1
        let searchStart = max(0, data.count - 65557)

        for i in stride(from: data.count - 22, through: searchStart, by: -1) {
            if data[i] == eocdSignature[0] && data[i+1] == eocdSignature[1] &&
               data[i+2] == eocdSignature[2] && data[i+3] == eocdSignature[3] {
                eocdOffset = i
                break
            }
        }

        guard eocdOffset >= 0 else { return nil }

        // Read central directory offset from EOCD
        let cdOffset = Int(data[eocdOffset + 16]) | (Int(data[eocdOffset + 17]) << 8) |
                       (Int(data[eocdOffset + 18]) << 16) | (Int(data[eocdOffset + 19]) << 24)

        // Iterate through central directory entries
        var pos = cdOffset
        let cdSignature: [UInt8] = [0x50, 0x4B, 0x01, 0x02]

        while pos + 46 < data.count {
            guard data[pos] == cdSignature[0] && data[pos+1] == cdSignature[1] &&
                  data[pos+2] == cdSignature[2] && data[pos+3] == cdSignature[3] else { break }

            let compressionMethod = UInt16(data[pos + 10]) | (UInt16(data[pos + 11]) << 8)
            let compressedSize = Int(data[pos + 20]) | (Int(data[pos + 21]) << 8) |
                                 (Int(data[pos + 22]) << 16) | (Int(data[pos + 23]) << 24)
            let uncompressedSize = Int(data[pos + 24]) | (Int(data[pos + 25]) << 8) |
                                   (Int(data[pos + 26]) << 16) | (Int(data[pos + 27]) << 24)
            let fileNameLength = Int(data[pos + 28]) | (Int(data[pos + 29]) << 8)
            let extraFieldLength = Int(data[pos + 30]) | (Int(data[pos + 31]) << 8)
            let commentLength = Int(data[pos + 32]) | (Int(data[pos + 33]) << 8)
            let localHeaderOffset = Int(data[pos + 42]) | (Int(data[pos + 43]) << 8) |
                                    (Int(data[pos + 44]) << 16) | (Int(data[pos + 45]) << 24)

            let nameStart = pos + 46
            let nameEnd = nameStart + fileNameLength
            guard nameEnd <= data.count else { break }

            let entryName = String(data: data[nameStart..<nameEnd], encoding: .utf8) ?? ""

            if entryName == fileName {
                // Found it — read from local file header
                let localPos = localHeaderOffset
                guard localPos + 30 < data.count else { return nil }

                let localNameLen = Int(data[localPos + 26]) | (Int(data[localPos + 27]) << 8)
                let localExtraLen = Int(data[localPos + 28]) | (Int(data[localPos + 29]) << 8)
                let dataStart = localPos + 30 + localNameLen + localExtraLen
                let dataEnd = dataStart + compressedSize

                guard dataEnd <= data.count else { return nil }

                let fileData = data[dataStart..<dataEnd]

                if compressionMethod == 0 {
                    // Stored (no compression)
                    return String(data: fileData, encoding: .utf8)
                } else if compressionMethod == 8 {
                    // Deflate — use Compression framework
                    let decompressed = decompressDeflate(Data(fileData), uncompressedSize: uncompressedSize)
                    return decompressed.flatMap { String(data: $0, encoding: .utf8) }
                }

                return nil
            }

            pos = nameEnd + extraFieldLength + commentLength
        }

        return nil
    }

    private func decompressDeflate(_ data: Data, uncompressedSize: Int) -> Data? {
        let bufferSize = max(uncompressedSize, 4096)
        var decompressed = Data(count: bufferSize)

        let result = decompressed.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                guard let destPtr = destBuffer.baseAddress,
                      let srcPtr = srcBuffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destPtr.assumingMemoryBound(to: UInt8.self),
                    bufferSize,
                    srcPtr.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard result > 0 else { return nil }
        return decompressed.prefix(result)
    }

    private func extractXMLValue(_ xml: String, tag: String) -> String? {
        let pattern = "<\(NSRegularExpression.escapedPattern(for: tag))[^>]*>([^<]+)</\(NSRegularExpression.escapedPattern(for: tag))>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: xml, options: [], range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else {
            return nil
        }
        return String(xml[range])
    }

    private func isTextLikeFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let textLikeExtensions: Set<String> = [
            "txt", "md", "markdown", "csv", "tsv", "json", "jsonl", "yaml", "yml",
            "xml", "html", "htm", "css", "scss", "js", "jsx", "ts", "tsx",
            "swift", "py", "rb", "go", "rs", "java", "kt", "c", "cc", "cpp",
            "h", "hpp", "m", "mm", "php", "pl", "sh", "zsh", "bash", "fish",
            "toml", "ini", "cfg", "conf", "sql", "log"
        ]
        if textLikeExtensions.contains(ext) {
            return true
        }

        guard let type = UTType(filenameExtension: ext) else {
            return false
        }

        return type.conforms(to: .plainText)
            || type.conforms(to: .sourceCode)
            || type.conforms(to: .script)
            || type.conforms(to: .xml)
            || type.conforms(to: .json)
            || type.conforms(to: .commaSeparatedText)
    }

    private func decodeText(from data: Data) -> String? {
        let candidateEncodings: [String.Encoding] = [
            .utf8,
            .utf16,
            .utf16LittleEndian,
            .utf16BigEndian,
            .windowsCP1252,
            .isoLatin1
        ]

        for encoding in candidateEncodings {
            guard let text = String(data: data, encoding: encoding) else {
                continue
            }
            let normalized = text
                .replacingOccurrences(of: "\u{0000}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !normalized.isEmpty {
                return normalized
            }
        }

        return nil
    }
}

// MARK: - Import for AppKit NSColor/NSImage
import AppKit
