//
//  DirectoryScanner.swift
//  Sorty
//
//  Recursively scans directories and builds file tree
//

import Foundation
import CryptoKit
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
    
    deinit {
        pressureSource?.cancel()
        pauseTimeoutTask?.cancel()
    }
    
    /// Memory pressure states for graceful degradation
    enum MemoryPressureState: String {
        case normal = "normal"
        case warning = "warning"
        case critical = "critical"
    }
    
    /// Initialize and set up memory pressure monitoring
    init() {
        // Setup happens lazily on first scan to avoid actor isolation issues
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
        
        logger.info("Scan completed: \(self.scannedCount) files, cloud placeholders skipped: \(self.cloudPlaceholdersSkipped), memory pressure: \(self.memoryPressureState.rawValue)")
        
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
        
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .creationDateKey, .isHiddenKey]
        let resourceValues = try? url.resourceValues(forKeys: Set(resourceKeys))
        
        let isDirectory = resourceValues?.isDirectory ?? false
        let size = resourceValues?.fileSize ?? 0
        let creationDate = resourceValues?.creationDate
        
        let pathExtension = url.pathExtension
        let fileName = url.deletingPathExtension().lastPathComponent
        
        // Deep scan: extract content metadata
        var contentMetadata: ContentMetadata?
        if deepScan {
            contentMetadata = await contentAnalyzer.analyze(fileURL: url)
        }
        
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
            contentMetadata: contentMetadata,
            sha256Hash: sha256Hash
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
            .ubiquitousItemDownloadingStatusKey
        ]
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .creationDateKey, .isHiddenKey] + cloudResourceKeys
        
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden {
            options.insert(.skipsHiddenFiles)
        }
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            options: options
        ) else {
            throw ScannerError.enumerationFailed
        }
        
        // Graceful degradation: skip non-essential work under memory pressure
        let effectiveDeepScan = deepScan && !shouldSkipNonEssentialWork()
        let effectiveComputeHashes = computeHashes && !shouldSkipNonEssentialWork()
        
        if deepScan && !effectiveDeepScan {
            logger.info("Deep scan disabled due to memory pressure")
        }
        if computeHashes && !effectiveComputeHashes {
            logger.info("Hash computation disabled due to memory pressure")
        }
        
        let batchSize = getCurrentBatchSize()
        var lastBatchTime = Date()
        
        while let fileURL = enumerator.nextObject() as? URL {
            // Check and wait if paused due to memory pressure
            await waitIfPaused()
            
            // Skip hidden files if not including them
            if !includeHidden {
                let resourceValues = try? fileURL.resourceValues(forKeys: [.isHiddenKey])
                if resourceValues?.isHidden == true {
                    continue
                }
            }
            
            // Get file attributes
            let resourceValues = try? fileURL.resourceValues(forKeys: Set(resourceKeys))
            let isDirectory = resourceValues?.isDirectory ?? false
            let size = resourceValues?.fileSize ?? 0
            let creationDate = resourceValues?.creationDate
            
            // Skip if it's a directory (we only want files)
            if isDirectory {
                continue
            }
            
            // Cloud placeholder detection
            if skipCloudPlaceholders && isCloudPlaceholder(at: fileURL) {
                let provider = cloudProviderName(for: fileURL) ?? "Unknown"
                logger.debug("Skipping cloud placeholder (\(provider)): \(fileURL.lastPathComponent)")
                cloudPlaceholdersSkipped += 1
                continue
            }
            
            let pathExtension = fileURL.pathExtension
            let fileName = fileURL.deletingPathExtension().lastPathComponent
            
            // Determine cloud status for the file
            let cloudStatus = detectCloudStatus(at: fileURL)
            
            // Deep scan: extract content metadata (skipped under memory pressure)
            var contentMetadata: ContentMetadata?
            if effectiveDeepScan {
                contentMetadata = await contentAnalyzer.analyze(fileURL: fileURL)
            }
            
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
                contentMetadata: contentMetadata,
                sha256Hash: sha256Hash,
                cloudStatus: cloudStatus
            )
            
            files.append(fileItem)
            scannedCount += 1
            
            // Periodic memory pressure check and yield
            if scannedCount % batchSize == 0 {
                await Task.yield()
                await checkMemoryPressure()
                
                // Log progress periodically under memory pressure
                if memoryPressureState != .normal && scannedCount % (batchSize * 10) == 0 {
                    logger.info("Scan progress: \(self.scannedCount) files, pressure: \(self.memoryPressureState.rawValue)")
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
    
    // MARK: - Cloud Storage Detection
    
    private func isCloudPlaceholder(at url: URL) -> Bool {
        // iCloud: check ubiquitous item download status
        if let resourceValues = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ]) {
            if let status = resourceValues.ubiquitousItemDownloadingStatus,
               status == .notDownloaded {
                return true
            }
        }
        
        // iCloud: .icloud wrapper file (e.g., ".Document.icloud")
        let fileName = url.lastPathComponent
        if fileName.hasPrefix(".") && url.pathExtension == "icloud" {
            return true
        }
        
        // Google Drive: stream file placeholders
        let googleStreamExtensions: Set<String> = ["gdoc", "gsheet", "gslides"]
        if googleStreamExtensions.contains(url.pathExtension.lowercased()) {
            return true
        }
        
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
        if let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]) {
            if resourceValues.ubiquitousItemDownloadingStatus != nil {
                return "iCloud"
            }
        }
        let fileName = url.lastPathComponent
        if fileName.hasPrefix(".") && url.pathExtension == "icloud" {
            return "iCloud"
        }
        
        // Google Drive stream files
        let googleStreamExtensions: Set<String> = ["gdoc", "gsheet", "gslides"]
        if googleStreamExtensions.contains(url.pathExtension.lowercased()) {
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
            .ubiquitousItemIsDownloadingKey
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
        
        let googleStreamExtensions: Set<String> = ["gdoc", "gsheet", "gslides"]
        if googleStreamExtensions.contains(url.pathExtension.lowercased()) {
            return .cloudOnly
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
        
        return nil
    }
    
    // MARK: - Memory Pressure Handling
    
    private func setupMemoryPressureMonitoring() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: DispatchQueue.global())
        
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
            logger.warning("Memory pressure changed: \(previousState.rawValue) -> \(state.rawValue)")
            
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
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
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
    
    private func waitIfPaused() async {
        while isPaused && isScanning {
            await Task.yield()
            // Check if pressure has decreased
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



