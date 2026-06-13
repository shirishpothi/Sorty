//
//  DirectoryScanner.swift
//  Sorty
//
//  Recursively scans directories and builds file tree
//

import CryptoKit
import Foundation
import os.log

actor DirectoryScanner {
    private var isScanning = false
    private var scannedCount = 0
    private var cloudPlaceholdersSkipped = 0
    private var isPaused = false
    private var memoryPressureState: MemoryPressureState = .normal
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pauseTimeoutTask: Task<Void, Never>?
    private var isMonitoringSetup = false
    private let contentAnalyzer = ContentAnalyzer()
    private let logger = Logger(subsystem: "com.sorty.app", category: "DirectoryScanner")

    // Configuration
    private var normalBatchSize = 50
    private var pressureBatchSize = 10
    private let pauseTimeout: Duration = .seconds(30)

    /// Whether the last scan was degraded due to memory pressure
    private(set) var lastScanWasDegraded = false
    /// Description of degradation that occurred
    private(set) var degradationReason: String?

    /// Callback for deep scan progress updates
    private var deepScanProgressCallback: (@Sendable (_ current: Int, _ total: Int) -> Void)?
    private var deepScanAnalyzedCount = 0

    deinit {
        pressureSource?.cancel()
        pauseTimeoutTask?.cancel()
    }

    /// Memory pressure states for graceful degradation
    public enum MemoryPressureState: String, Sendable {
        case normal = "normal"
        case warning = "warning"
        case critical = "critical"
    }

    /// Initialize and set up memory pressure monitoring
    init() {
        // Setup happens lazily on first scan to avoid actor isolation issues
    }

    func setCustomOCRKeywords(_ keywords: [String]) async {
        await contentAnalyzer.setCustomOCRKeywords(keywords)
    }

    func setOCRLanguages(_ languages: [String]) async {
        await contentAnalyzer.setOCRLanguages(languages)
    }

    /// Scan directory with optional deep content analysis and hash computation
    func scanDirectory(
        at url: URL,
        includeHidden: Bool = false,
        deepScan: Bool = false,
        computeHashes: Bool = false,
        skipCloudPlaceholders: Bool = true
    ) async throws -> [FileItem] {
        guard !isScanning else {
            throw ScannerError.alreadyScanning
        }

        isScanning = true
        scannedCount = 0
        cloudPlaceholdersSkipped = 0
        isPaused = false
        lastScanWasDegraded = false
        degradationReason = nil
        deepScanAnalyzedCount = 0

        // Lazy initialization of memory pressure monitoring
        if !isMonitoringSetup {
            setupMemoryPressureMonitoring()
            isMonitoringSetup = true
        }

        defer {
            isScanning = false
            pauseTimeoutTask?.cancel()
        }

        var files: [FileItem] = []
        let fileManager = FileManager.default

        guard url.isFileURL else {
            throw ScannerError.invalidURL
        }

        guard fileManager.fileExists(atPath: url.path) else {
            throw ScannerError.pathNotFound
        }

        // Check initial memory pressure
        await checkMemoryPressure()

        try await scanDirectoryRecursive(
            at: url,
            fileManager: fileManager,
            includeHidden: includeHidden,
            deepScan: deepScan,
            computeHashes: computeHashes,
            skipCloudPlaceholders: skipCloudPlaceholders,
            files: &files
        )

        logger.info(
            "Scan completed: \(self.scannedCount) files, cloud placeholders skipped: \(self.cloudPlaceholdersSkipped), memory pressure: \(self.memoryPressureState.rawValue)"
        )

        return files
    }

    /// Scan a single file and return a FileItem
    func scanFile(
        at url: URL,
        deepScan: Bool = false,
        computeHashes: Bool = false
    ) async throws -> FileItem {
        let fileManager = FileManager.default

        guard url.isFileURL else {
            throw ScannerError.invalidURL
        }

        guard fileManager.fileExists(atPath: url.path) else {
            throw ScannerError.pathNotFound
        }

        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey, .fileSizeKey, .creationDateKey, .isHiddenKey,
            .contentModificationDateKey, .contentAccessDateKey, .tagNamesKey,
        ]
        let resourceValues = try? url.resourceValues(forKeys: Set(resourceKeys))

        let isDirectory = resourceValues?.isDirectory ?? false
        let size = resourceValues?.fileSize ?? 0
        let creationDate = resourceValues?.creationDate
        let modificationDate = resourceValues?.contentModificationDate
        let lastAccessDate = resourceValues?.contentAccessDate
        let finderTags = resourceValues?.tagNames

        let pathExtension = url.pathExtension
        let fileName = url.deletingPathExtension().lastPathComponent

        // Read Finder comment via extended attribute
        let finderComment = Self.readFinderComment(at: url)

        // Deep scan: extract content metadata
        var contentMetadata: ContentMetadata?
        if deepScan {
            contentMetadata = await contentAnalyzer.analyze(fileURL: url)
        }

        let extractedOCRText = contentMetadata?.ocrText
        let extractedDimensions = Self.extractImageDimensions(from: contentMetadata)

        // Hash computation for duplicate detection
        var sha256Hash: String?
        if computeHashes {
            sha256Hash = HashUtility.computeSHA256(for: url)
        }

        return FileItem(
            path: url.path,
            name: fileName,
            extension: pathExtension,
            size: Int64(size),
            isDirectory: isDirectory,
            creationDate: creationDate,
            modificationDate: modificationDate,
            lastAccessDate: lastAccessDate,
            contentMetadata: contentMetadata,
            sha256Hash: sha256Hash,
            ocrText: extractedOCRText,
            imageWidth: extractedDimensions?.width,
            imageHeight: extractedDimensions?.height,
            finderComment: finderComment,
            finderTags: finderTags
        )
    }

    private func scanDirectoryRecursive(
        at url: URL,
        fileManager: FileManager,
        includeHidden: Bool,
        deepScan: Bool,
        computeHashes: Bool,
        skipCloudPlaceholders: Bool,
        files: inout [FileItem]
    ) async throws {
        let cloudResourceKeys: [URLResourceKey] = [
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadingStatusKey,
        ]
        let resourceKeys: [URLResourceKey] =
            [
                .isDirectoryKey, .fileSizeKey, .creationDateKey, .isHiddenKey,
                .contentModificationDateKey, .contentAccessDateKey, .tagNamesKey,
            ] + cloudResourceKeys

        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }

        try Task.checkCancellation()

        guard
            let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: resourceKeys,
                options: options
            )
        else {
            throw ScannerError.enumerationFailed
        }

        // Graceful degradation: skip non-essential work under memory pressure
        let effectiveDeepScan = deepScan && !shouldSkipNonEssentialWork()
        let effectiveComputeHashes = computeHashes && !shouldSkipNonEssentialWork()

        if deepScan && !effectiveDeepScan {
            lastScanWasDegraded = true
            degradationReason = "Deep content analysis was skipped due to high memory usage"
            logger.info("Deep scan disabled due to memory pressure")
        }
        if computeHashes && !effectiveComputeHashes {
            lastScanWasDegraded = true
            if degradationReason == nil {
                degradationReason = "File hash computation was skipped due to high memory usage"
            }
            logger.info("Hash computation disabled due to memory pressure")
        }

        let batchSize = getCurrentBatchSize()
        var lastBatchTime = Date()

        while let fileURL = enumerator.nextObject() as? URL {
            // Check and wait if paused due to memory pressure
            try await waitIfPaused()
            try Task.checkCancellation()

            // Get file attributes. The enumerator already skips hidden files when requested,
            // so avoid an extra per-file resource lookup for large directories.
            let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            let isDirectory = resourceValues?.isDirectory ?? false
            let size = resourceValues?.fileSize ?? 0
            let creationDate = resourceValues?.creationDate
            let modificationDate = resourceValues?.contentModificationDate
            let lastAccessDate = resourceValues?.contentAccessDate
            let finderTags = resourceValues?.tagNames

            // Skip if it's a directory (we only want files)
            if isDirectory {
                continue
            }

            let pathExtension = fileURL.pathExtension
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            let hasCloudSignals = hasPotentialCloudSignals(
                at: fileURL,
                resourceValues: resourceValues,
                pathExtension: pathExtension
            )

            // Cloud placeholder detection can require xattr checks, so only run it
            // when the path or prefetched resource values indicate cloud storage.
            if skipCloudPlaceholders && hasCloudSignals && isCloudPlaceholder(at: fileURL) {
                let provider = cloudProviderName(for: fileURL) ?? "Unknown"
                logger.debug(
                    "Skipping cloud placeholder (\(provider)): \(fileURL.lastPathComponent)")
                cloudPlaceholdersSkipped += 1
                continue
            }

            // Determine cloud status for the file
            let cloudStatus = hasCloudSignals ? detectCloudStatus(at: fileURL) : nil

            // Read Finder comment via extended attribute
            let finderComment = Self.readFinderComment(at: fileURL)

            // Deep scan: extract content metadata (skipped under memory pressure)
            var contentMetadata: ContentMetadata?
            if effectiveDeepScan {
                contentMetadata = await contentAnalyzer.analyze(fileURL: fileURL)
                deepScanAnalyzedCount += 1
                deepScanProgressCallback?(deepScanAnalyzedCount, 0)
            }

            let extractedOCRText = contentMetadata?.ocrText
            let extractedDimensions = Self.extractImageDimensions(from: contentMetadata)

            // Hash computation for duplicate detection (skipped under memory pressure)
            var sha256Hash: String?
            if effectiveComputeHashes {
                sha256Hash = HashUtility.computeSHA256(for: fileURL)
            }

            let fileItem = FileItem(
                path: fileURL.path,
                name: fileName,
                extension: pathExtension,
                size: Int64(size),
                isDirectory: false,
                creationDate: creationDate,
                modificationDate: modificationDate,
                lastAccessDate: lastAccessDate,
                contentMetadata: contentMetadata,
                sha256Hash: sha256Hash,
                ocrText: extractedOCRText,
                imageWidth: extractedDimensions?.width,
                imageHeight: extractedDimensions?.height,
                cloudStatus: cloudStatus,
                finderComment: finderComment,
                finderTags: finderTags
            )

            files.append(fileItem)
            scannedCount += 1

            // Periodic memory pressure check and yield
            if scannedCount % getCurrentBatchSize() == 0 {
                await Task.yield()
                await checkMemoryPressure()

                // Log progress periodically under memory pressure
                if memoryPressureState != .normal && scannedCount % (batchSize * 10) == 0 {
                    logger.info(
                        "Scan progress: \(self.scannedCount) files, pressure: \(self.memoryPressureState.rawValue)"
                    )
                }
            }
        }

        // Final memory state logging
        if memoryPressureState != .normal {
            logger.info("Scan completed under memory pressure: \(self.scannedCount) files total")
        }
    }

    func getProgress() -> Int {
        scannedCount
    }

    func getMemoryPressureState() -> MemoryPressureState {
        memoryPressureState
    }

    func getCloudPlaceholderCount() -> Int {
        cloudPlaceholdersSkipped
    }

    func setDeepScanProgressCallback(
        _ callback: (@Sendable (_ current: Int, _ total: Int) -> Void)?
    ) {
        deepScanProgressCallback = callback
    }

    // MARK: - Finder Metadata

    private static func extractImageDimensions(from metadata: ContentMetadata?) -> (
        width: Int, height: Int
    )? {
        guard let dimensionsString = metadata?.exifData?["dimensions"] else {
            return nil
        }

        let parts = dimensionsString.split(separator: "x", maxSplits: 1).map(String.init)
        guard parts.count == 2,
            let width = Int(parts[0]),
            let height = Int(parts[1])
        else {
            return nil
        }

        return (width, height)
    }

    private static func readFinderComment(at url: URL) -> String? {
        let path = url.path
        let key = "com.apple.metadata:kMDItemFinderComment"

        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buf in
            getxattr(path, key, buf.baseAddress, size, 0, 0)
        }
        guard result > 0 else { return nil }

        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? String
    }

    // MARK: - Cloud Storage Detection

    private func hasPotentialCloudSignals(
        at url: URL,
        resourceValues: URLResourceValues?,
        pathExtension: String
    ) -> Bool {
        if resourceValues?.ubiquitousItemDownloadingStatus != nil
            || resourceValues?.ubiquitousItemIsDownloading == true
        {
            return true
        }

        let lowercasedExtension = pathExtension.lowercased()
        if lowercasedExtension == "icloud" || lowercasedExtension == "cloud"
            || googleDriveNativeExtensions.contains(lowercasedExtension)
        {
            return true
        }

        let pathComponents = url.standardizedFileURL.pathComponents.map { $0.lowercased() }
        return pathComponents.contains("cloudstorage") || pathComponents.contains("dropbox")
    }

    private func isCloudPlaceholder(at url: URL) -> Bool {
        // iCloud: check ubiquitous item download status
        if let resourceValues = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
        ]) {
            if let status = resourceValues.ubiquitousItemDownloadingStatus,
                status == .notDownloaded
            {
                return true
            }
        }

        // iCloud: .icloud wrapper file (e.g., ".Document.icloud")
        let fileName = url.lastPathComponent
        if fileName.hasPrefix(".") && url.pathExtension == "icloud" {
            return true
        }

        // Google Drive exposes cloud-native Docs, Sheets, and Slides as small
        // local files. They can be moved in Finder and should be organized.

        // Dropbox: check for extended attribute or zero-size placeholder
        let path = url.path
        let xattrLength = getxattr(path, "com.dropbox.attrs", nil, 0, 0, 0)
        if xattrLength > 0 {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
            if size == 0 {
                return true
            }
        }

        // OneDrive: check for .cloud file or zero-byte placeholder with attributes
        if url.pathExtension == "cloud" {
            return true
        }

        return false
    }

    private func cloudProviderName(for url: URL) -> String? {
        // iCloud detection
        if let resourceValues = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey
        ]) {
            if resourceValues.ubiquitousItemDownloadingStatus != nil {
                return "iCloud"
            }
        }
        let fileName = url.lastPathComponent
        if fileName.hasPrefix(".") && url.pathExtension == "icloud" {
            return "iCloud"
        }

        let pathComponents = Set(url.standardizedFileURL.pathComponents.map { $0.lowercased() })
        if pathComponents.contains("cloudstorage") {
            if let provider = fileProviderName(for: url) {
                return provider
            }
            return "Cloud Storage"
        }

        if googleDriveNativeExtensions.contains(url.pathExtension.lowercased()) {
            return "Google Drive"
        }

        // Dropbox extended attribute
        let xattrLength = getxattr(url.path, "com.dropbox.attrs", nil, 0, 0, 0)
        if xattrLength > 0 {
            return "Dropbox"
        }

        // OneDrive
        if url.pathExtension == "cloud" {
            return "OneDrive"
        }

        return nil
    }

    private func detectCloudStatus(at url: URL) -> CloudFileStatus? {
        if let resourceValues = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
        ]) {
            if let isDownloading = resourceValues.ubiquitousItemIsDownloading, isDownloading {
                return .downloading
            }
            if let status = resourceValues.ubiquitousItemDownloadingStatus {
                switch status {
                case .notDownloaded:
                    return .cloudOnly
                case .downloaded, .current:
                    return .synced
                default:
                    break
                }
            }
        }

        let fileName = url.lastPathComponent
        if fileName.hasPrefix(".") && url.pathExtension == "icloud" {
            return .cloudOnly
        }

        if googleDriveNativeExtensions.contains(url.pathExtension.lowercased()) {
            return .synced
        }

        let xattrLength = getxattr(url.path, "com.dropbox.attrs", nil, 0, 0, 0)
        if xattrLength > 0 {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
            if size == 0 {
                return .cloudOnly
            }
            return .synced
        }

        if url.pathExtension == "cloud" {
            return .cloudOnly
        }

        if cloudProviderName(for: url) != nil {
            return .synced
        }

        return nil
    }

    private var googleDriveNativeExtensions: Set<String> {
        ["gdoc", "gsheet", "gslides", "gdraw", "gform", "gmap", "gsite", "jam"]
    }

    private func fileProviderName(for url: URL) -> String? {
        let components = url.standardizedFileURL.pathComponents
        guard
            let cloudStorageIndex = components.firstIndex(where: {
                $0.caseInsensitiveCompare("CloudStorage") == .orderedSame
            }),
            components.indices.contains(cloudStorageIndex + 1)
        else {
            return nil
        }

        let providerFolder = components[cloudStorageIndex + 1].lowercased()
        if providerFolder.contains("googledrive") || providerFolder.contains("google drive") {
            return "Google Drive"
        }
        if providerFolder.contains("onedrive") || providerFolder.contains("one drive") {
            return "OneDrive"
        }
        if providerFolder.contains("dropbox") {
            return "Dropbox"
        }
        if providerFolder.contains("box") {
            return "Box"
        }
        if providerFolder.contains("icloud") {
            return "iCloud"
        }

        return nil
    }

    // MARK: - Memory Pressure Handling

    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical], queue: DispatchQueue.global())

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task { await self.handleMemoryPressureEvent() }
        }

        pressureSource = source
        source.resume()
        logger.debug("Memory pressure monitoring initialized")
    }

    private func handleMemoryPressureEvent() async {
        let eventMask = pressureSource?.data ?? []

        if eventMask.contains(.critical) {
            await setMemoryPressureState(.critical)
        } else if eventMask.contains(.warning) {
            await setMemoryPressureState(.warning)
        }
    }

    private func setMemoryPressureState(_ state: MemoryPressureState) async {
        let previousState = memoryPressureState
        memoryPressureState = state

        if state != previousState {
            logger.warning(
                "Memory pressure changed: \(previousState.rawValue) -> \(state.rawValue)")

            switch state {
            case .warning:
                isPaused = true
                startPauseTimeout()
                logger.info("Scan paused due to memory warning")
            case .critical:
                isPaused = true
                // Clear caches immediately
                await contentAnalyzer.clearCache()
                logger.warning("Scan paused, caches cleared due to critical memory pressure")
            case .normal:
                isPaused = false
                pauseTimeoutTask?.cancel()
                logger.info("Scan resumed, memory pressure normal")
            }
        }
    }

    private func checkMemoryPressure() async {
        // Check physical memory availability
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = getCurrentMemoryUsage()
        let memoryPressure = Double(usedMemory) / Double(physicalMemory)

        if memoryPressure > 0.85 {
            await setMemoryPressureState(.critical)
        } else if memoryPressure > 0.70 {
            await setMemoryPressureState(.warning)
        } else {
            await setMemoryPressureState(.normal)
        }
    }

    private func getCurrentMemoryUsage() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count)
            }
        }

        guard kerr == KERN_SUCCESS else {
            return 0
        }

        return info.resident_size
    }

    private func startPauseTimeout() {
        pauseTimeoutTask?.cancel()
        pauseTimeoutTask = Task {
            try? await Task.sleep(for: pauseTimeout)

            guard !Task.isCancelled else { return }

            // Force resume after timeout
            if isPaused && isScanning {
                logger.warning("Pause timeout reached, forcing resume")
                isPaused = false
                memoryPressureState = .normal
            }
        }
    }

    private func shouldSkipNonEssentialWork() -> Bool {
        memoryPressureState == .warning || memoryPressureState == .critical
    }

    private func getCurrentBatchSize() -> Int {
        switch memoryPressureState {
        case .normal:
            return normalBatchSize
        case .warning, .critical:
            return pressureBatchSize
        }
    }

    private func waitIfPaused() async throws {
        while isPaused && isScanning {
            try Task.checkCancellation()
            await Task.yield()
            await checkMemoryPressure()
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

enum ScannerError: LocalizedError {
    case alreadyScanning
    case invalidURL
    case pathNotFound
    case enumerationFailed
    case memoryPressureTimeout

    var errorDescription: String? {
        switch self {
        case .alreadyScanning:
            return "A scan is already in progress"
        case .invalidURL:
            return "Invalid URL provided"
        case .pathNotFound:
            return "The specified path does not exist"
        case .enumerationFailed:
            return "Failed to enumerate directory contents"
        case .memoryPressureTimeout:
            return "Scan timed out waiting for memory pressure to decrease"
        }
    }
}
