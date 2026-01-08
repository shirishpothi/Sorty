//
//  MenuBarDropZone.swift
//  Sorty
//
//  macOS Menu Bar "Drop Zone" for quick file organization
//  Provides a persistent drop target in the menu bar with a Liquid Glass popover
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

// MARK: - Menu Bar Controller

@MainActor
public class MenuBarController: ObservableObject {
    @Published public var isDropTargeted: Bool = false
    @Published public var droppedFileURL: URL?
    @Published public var suggestion: QuickOrganizeSuggestion?
    @Published public var isProcessing: Bool = false
    @Published public var errorMessage: String?
    @Published public var showPopover: Bool = false

    private var organizer: FolderOrganizer?
    private var settingsViewModel: SettingsViewModel?

    public init() {}

    public func configure(organizer: FolderOrganizer, settings: SettingsViewModel) {
        self.organizer = organizer
        self.settingsViewModel = settings
    }

    public func handleDrop(providers: [NSItemProvider]) async -> Bool {
        guard let provider = providers.first else { return false }

        isProcessing = true
        errorMessage = nil

        do {
            // Get the file URL from the provider
            let url = try await loadURL(from: provider)
            droppedFileURL = url

            // Get AI suggestion
            suggestion = try await getQuickSuggestion(for: url)
            showPopover = true

            isProcessing = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
            return false
        }
    }

    private func loadURL(from provider: NSItemProvider) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: MenuBarError.invalidDrop)
                }
            }
        }
    }

    private func getQuickSuggestion(for fileURL: URL) async throws -> QuickOrganizeSuggestion {
        guard let organizer = organizer else {
            throw MenuBarError.organizerNotConfigured
        }

        // Create a FileItem for the dropped file
        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .isDirectoryKey])

        let fileItem = FileItem(
            path: fileURL.path,
            name: fileURL.deletingPathExtension().lastPathComponent,
            extension: fileURL.pathExtension,
            size: Int64(resourceValues.fileSize ?? 0),
            isDirectory: resourceValues.isDirectory ?? false,
            creationDate: resourceValues.creationDate
        )

        // Get the parent directory
        let parentDirectory = fileURL.deletingLastPathComponent()

        // Get existing folders for context
        let contents = try FileManager.default.contentsOfDirectory(at: parentDirectory, includingPropertiesForKeys: [.isDirectoryKey])
        let existingFolders = contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .map { $0.lastPathComponent }
            .filter { !$0.hasPrefix(".") }

        // If we have an AI client configured, get a real suggestion
        if organizer.aiClient != nil {
            // For quick mode, we'll use a simplified approach
            // Analyze just this one file with context
            // For future AI integration, we can use the following prompt:
            /*
            Quick organize this single file. Existing folders: \(existingFolders.joined(separator: ", ")).
            Choose the best existing folder OR suggest a new folder name.
            Also suggest a better filename if the current name is not descriptive.
            Return JSON: {"folder": "FolderName", "suggestedFilename": "optional_new_name.ext", "reason": "brief explanation"}
            */


            // For now, return a smart default based on file type
            return suggestBasedOnFileType(fileItem, existingFolders: existingFolders, parentDirectory: parentDirectory)
        } else {
            // Fallback to basic suggestion
            return suggestBasedOnFileType(fileItem, existingFolders: existingFolders, parentDirectory: parentDirectory)
        }
    }

    private func suggestBasedOnFileType(_ file: FileItem, existingFolders: [String], parentDirectory: URL) -> QuickOrganizeSuggestion {
        let ext = file.extension.lowercased()

        // Determine category
        let (category, suggestedFolder) = categorizeFile(ext, existingFolders: existingFolders)

        // Generate suggested filename based on date
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = dateFormatter.string(from: file.creationDate ?? Date())

        let suggestedFilename: String?
        if file.name.hasPrefix("IMG_") || file.name.hasPrefix("DSC") || file.name.hasPrefix("Screenshot") {
            suggestedFilename = "\(datePrefix)_\(category)_\(file.name).\(file.extension)"
        } else {
            suggestedFilename = nil
        }

        return QuickOrganizeSuggestion(
            originalFile: file,
            suggestedFolder: suggestedFolder,
            suggestedPath: parentDirectory.appendingPathComponent(suggestedFolder).path,
            suggestedFilename: suggestedFilename,
            reason: "Organized by file type: \(category)",
            confidence: 0.85
        )
    }

    private func categorizeFile(_ ext: String, existingFolders: [String]) -> (category: String, folder: String) {
        let imageExts = ["jpg", "jpeg", "png", "gif", "heic", "heif", "bmp", "tiff", "webp", "raw", "cr2", "nef"]
        let videoExts = ["mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v"]
        let audioExts = ["mp3", "wav", "aac", "flac", "ogg", "m4a", "wma"]
        let documentExts = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "rtf", "pages", "numbers", "keynote"]
        let archiveExts = ["zip", "rar", "7z", "tar", "gz", "dmg", "iso"]
        let codeExts = ["swift", "py", "js", "ts", "html", "css", "java", "c", "cpp", "go", "rs", "rb", "php"]

        let category: String
        let defaultFolder: String

        if imageExts.contains(ext) {
            category = "Images"
            defaultFolder = findMatchingFolder(["Images", "Photos", "Pictures", "Media"], in: existingFolders) ?? "Images"
        } else if videoExts.contains(ext) {
            category = "Videos"
            defaultFolder = findMatchingFolder(["Videos", "Movies", "Media"], in: existingFolders) ?? "Videos"
        } else if audioExts.contains(ext) {
            category = "Audio"
            defaultFolder = findMatchingFolder(["Audio", "Music", "Sounds", "Media"], in: existingFolders) ?? "Audio"
        } else if documentExts.contains(ext) {
            category = "Documents"
            defaultFolder = findMatchingFolder(["Documents", "Docs", "Papers", "Files"], in: existingFolders) ?? "Documents"
        } else if archiveExts.contains(ext) {
            category = "Archives"
            defaultFolder = findMatchingFolder(["Archives", "Compressed", "Downloads"], in: existingFolders) ?? "Archives"
        } else if codeExts.contains(ext) {
            category = "Code"
            defaultFolder = findMatchingFolder(["Code", "Projects", "Development", "Source"], in: existingFolders) ?? "Code"
        } else {
            category = "Other"
            defaultFolder = findMatchingFolder(["Other", "Misc", "Miscellaneous"], in: existingFolders) ?? "Other"
        }

        return (category, defaultFolder)
    }

    private func findMatchingFolder(_ preferred: [String], in existing: [String]) -> String? {
        for folder in preferred {
            if existing.contains(where: { $0.localizedCaseInsensitiveCompare(folder) == .orderedSame }) {
                return existing.first { $0.localizedCaseInsensitiveCompare(folder) == .orderedSame }
            }
        }
        return nil
    }

    public func applyOrganization() async {
        guard let suggestion = suggestion, let fileURL = droppedFileURL else { return }

        isProcessing = true

        do {
            let fileManager = FileManager.default
            let destinationFolder = URL(fileURLWithPath: suggestion.suggestedPath)

            // Create folder if needed
            if !fileManager.fileExists(atPath: destinationFolder.path) {
                try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            }

            // Determine final filename
            let finalFilename = suggestion.suggestedFilename ?? fileURL.lastPathComponent
            let destinationURL = destinationFolder.appendingPathComponent(finalFilename)

            // Handle conflicts
            var finalDestination = destinationURL
            var counter = 1
            while fileManager.fileExists(atPath: finalDestination.path) {
                let name = destinationURL.deletingPathExtension().lastPathComponent
                let ext = destinationURL.pathExtension
                finalDestination = destinationFolder.appendingPathComponent("\(name)_\(counter).\(ext)")
                counter += 1
            }

            // Move the file
            try fileManager.moveItem(at: fileURL, to: finalDestination)

            // Success
            isProcessing = false
            showPopover = false
            droppedFileURL = nil
            self.suggestion = nil

            // Show success notification
            await showSuccessNotification(filename: finalFilename, folder: suggestion.suggestedFolder)

        } catch {
            errorMessage = error.localizedDescription
            isProcessing = false
        }
    }

    private func showSuccessNotification(filename: String, folder: String) async {
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "File Organized"
        content.body = "\(filename) moved to \(folder)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }

    public func dismiss() {
        showPopover = false
        droppedFileURL = nil
        suggestion = nil
        errorMessage = nil
    }
}

// MARK: - Supporting Types

public struct QuickOrganizeSuggestion: Sendable {
    public let originalFile: FileItem
    public let suggestedFolder: String
    public let suggestedPath: String
    public let suggestedFilename: String?
    public let reason: String
    public let confidence: Double

    public var confidencePercentage: String {
        String(format: "%.0f%%", confidence * 100)
    }
}

enum MenuBarError: LocalizedError {
    case invalidDrop
    case organizerNotConfigured
    case aiUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidDrop:
            return "Invalid file dropped"
        case .organizerNotConfigured:
            return "Organizer not configured"
        case .aiUnavailable:
            return "AI service unavailable"
        }
    }
}

// MARK: - Menu Bar View

public struct MenuBarDropZoneView: View {
    @ObservedObject var controller: MenuBarController
    @State private var isTargeted = false

    public init(controller: MenuBarController) {
        self.controller = controller
    }

    public var body: some View {
        ZStack {
            // Drop target indicator
            RoundedRectangle(cornerRadius: 8)
                .fill(isTargeted ? Color.blue.opacity(0.3) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isTargeted ? Color.blue : Color.clear,
                            style: StrokeStyle(lineWidth: 2, dash: [5])
                        )
                )

            // Icon
            if controller.isProcessing {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                    .font(.system(size: 14))
                    .foregroundColor(isTargeted ? .blue : .primary)
            }
        }
        .frame(width: 22, height: 22)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                await controller.handleDrop(providers: providers)
            }
            return true
        }
        .popover(isPresented: $controller.showPopover, arrowEdge: .bottom) {
            LiquidGlassPopover(controller: controller)
        }
    }
}

// MARK: - Liquid Glass Popover

struct LiquidGlassPopover: View {
    @ObservedObject var controller: MenuBarController

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.title2)
                    .foregroundStyle(.purple.gradient)

                Text("Quick Organize")
                    .font(.headline)

                Spacer()

                Button {
                    controller.dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            if controller.isProcessing {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)

                    Text("Analyzing file...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding()

            } else if let error = controller.errorMessage {
                // Error state
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Dismiss") {
                        controller.dismiss()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
                .padding()

            } else if let suggestion = controller.suggestion, let fileURL = controller.droppedFileURL {
                // Suggestion state
                VStack(alignment: .leading, spacing: 16) {
                    // File info
                    HStack(spacing: 12) {
                        FileIconView(extension: suggestion.originalFile.extension)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileURL.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)

                            Text(suggestion.originalFile.formattedSize)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)

                    // Arrow
                    HStack {
                        Spacer()
                        Image(systemName: "arrow.down")
                            .font(.title2)
                            .foregroundStyle(.purple)
                        Spacer()
                    }

                    // Destination
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Destination", systemImage: "folder.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(.blue)

                            Text(suggestion.suggestedFolder)
                                .font(.headline)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.blue.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }

                    // Rename suggestion (if any)
                    if let newName = suggestion.suggestedFilename {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Rename to", systemImage: "pencil")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(newName)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }

                    // Reason
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)

                        Text(suggestion.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text(suggestion.confidencePercentage)
                            .font(.caption)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }

                    Divider()

                    // Actions
                    HStack(spacing: 12) {
                        Button("Cancel") {
                            controller.dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Spacer()

                        Button {
                            Task {
                                await controller.applyOrganization()
                            }
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding()
            }
        }
        .frame(width: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 10)
    }
}

// MARK: - File Icon View

struct FileIconView: View {
    let `extension`: String

    var iconName: String {
        let ext = `extension`.lowercased()
        switch ext {
        case "pdf": return "doc.fill"
        case "doc", "docx", "pages": return "doc.text.fill"
        case "xls", "xlsx", "numbers": return "tablecells.fill"
        case "ppt", "pptx", "keynote": return "rectangle.split.3x3.fill"
        case "jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff": return "photo.fill"
        case "mp4", "mov", "avi", "mkv": return "film.fill"
        case "mp3", "wav", "aac", "m4a": return "music.note"
        case "zip", "rar", "7z", "tar", "gz": return "archivebox.fill"
        case "swift", "py", "js", "ts", "java", "c", "cpp": return "chevron.left.forwardslash.chevron.right"
        case "html": return "globe"
        case "css": return "paintbrush.fill"
        case "json", "xml", "yaml": return "curlybraces"
        default: return "doc.fill"
        }
    }

    var iconColor: Color {
        let ext = `extension`.lowercased()
        switch ext {
        case "pdf": return .red
        case "doc", "docx", "pages": return .blue
        case "xls", "xlsx", "numbers": return .green
        case "ppt", "pptx", "keynote": return .orange
        case "jpg", "jpeg", "png", "gif", "heic", "bmp", "tiff": return .purple
        case "mp4", "mov", "avi", "mkv": return .pink
        case "mp3", "wav", "aac", "m4a": return .red
        case "zip", "rar", "7z", "tar", "gz": return .brown
        case "swift": return .orange
        case "py": return .blue
        case "js", "ts": return .yellow
        default: return .gray
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconColor.opacity(0.15))
                .frame(width: 40, height: 40)

            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
        }
    }
}

// MARK: - Menu Bar Scene (for App)

public struct MenuBarExtraScene: Scene {
    @StateObject private var controller = MenuBarController()
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var settingsViewModel: SettingsViewModel

    public init() {}

    public var body: some Scene {
        MenuBarExtra {
            MenuBarDropZoneView(controller: controller)
                .onAppear {
                    controller.configure(organizer: organizer, settings: settingsViewModel)
                }
        } label: {
            Label("Sorty", systemImage: "tray.and.arrow.down.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

// Required for notifications
import UserNotifications
