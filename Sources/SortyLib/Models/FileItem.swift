//
//  FileItem.swift
//  Sorty
//
//  File and Directory Model
//

import Foundation

public struct FileItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var path: String
    public var name: String
    public var `extension`: String
    public var size: Int64
    public var isDirectory: Bool
    public var creationDate: Date?
    public var modificationDate: Date?
    public var lastAccessDate: Date?

    // Deep scanning metadata
    public var contentMetadata: ContentMetadata?

    // For duplicate detection (SHA-256)
    public var sha256Hash: String?

    // AI-Driven Smart Renaming - suggested filename from AI
    public var suggestedFilename: String?

    // Semantic Content Analysis - OCR extracted text from images
    public var ocrText: String?

    // Semantic duplicate detection - embedding/fingerprint for near-duplicate detection
    public var contentFingerprint: String?

    // Image dimensions for duplicate comparison
    public var imageWidth: Int?
    public var imageHeight: Int?

    public init(
        id: UUID = UUID(),
        path: String,
        name: String,
        extension: String = "",
        size: Int64 = 0,
        isDirectory: Bool = false,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        lastAccessDate: Date? = nil,
        contentMetadata: ContentMetadata? = nil,
        sha256Hash: String? = nil,
        suggestedFilename: String? = nil,
        ocrText: String? = nil,
        contentFingerprint: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.extension = `extension`
        self.size = size
        self.isDirectory = isDirectory
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.lastAccessDate = lastAccessDate
        self.contentMetadata = contentMetadata
        self.sha256Hash = sha256Hash
        self.suggestedFilename = suggestedFilename
        self.ocrText = ocrText
        self.contentFingerprint = contentFingerprint
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
    }

    public var url: URL? {
        URL(fileURLWithPath: path)
    }

    public var displayName: String {
        if `extension`.isEmpty {
            return name
        }
        return "\(name).\(`extension`)"
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Returns the suggested filename if available, otherwise the original display name
    public var finalDisplayName: String {
        if let suggested = suggestedFilename, !suggested.isEmpty {
            return suggested
        }
        return displayName
    }

    /// Check if this file has semantic content (OCR or extracted text)
    public var hasSemanticContent: Bool {
        if let ocr = ocrText, !ocr.isEmpty { return true }
        if let metadata = contentMetadata, metadata.textPreview != nil { return true }
        return false
    }

    /// Get all available text content for AI analysis
    public var semanticTextContent: String? {
        var parts: [String] = []

        if let ocr = ocrText, !ocr.isEmpty {
            parts.append("OCR: \(ocr)")
        }

        if let metadata = contentMetadata {
            if let title = metadata.documentTitle {
                parts.append("Title: \(title)")
            }
            if let preview = metadata.textPreview {
                parts.append("Content: \(preview)")
            }
            if let keywords = metadata.keywords {
                parts.append("Keywords: \(keywords.joined(separator: ", "))")
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: " | ")
    }

    /// Resolution string for images (e.g., "1920x1080")
    public var resolutionString: String? {
        guard let width = imageWidth, let height = imageHeight else { return nil }
        return "\(width)x\(height)"
    }

    /// Total pixels for resolution comparison
    public var totalPixels: Int? {
        guard let width = imageWidth, let height = imageHeight else { return nil }
        return width * height
    }
}

