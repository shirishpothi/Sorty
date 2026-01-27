//
//  LearningsFSMonitor.swift
//  Sorty
//
//  FSEvents-based file system monitor for detecting manual file moves
//  after AI organization. Used to learn from user corrections.
//

import Foundation
import Combine

/// Snapshot of a directory's contents for detecting moves
// (Renamed to avoid conflict with WorkspaceHealth.DirectorySnapshot)
public struct FSSnapshot: Sendable {
    let files: Set<String>  // Full paths
    let timestamp: Date
    
    init(at url: URL) {
        var fileSet = Set<String>()
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                if let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile {
                    fileSet.insert(fileURL.path)
                }
            }
        }
        self.files = fileSet
        self.timestamp = Date()
    }
}

/// Represents a detected file move
public struct DetectedFileMove: Sendable {
    public let fromPath: String
    public let toPath: String
    public let timestamp: Date
}

/// FSEvents-based monitor for detecting file moves in recently organized directories
@MainActor
public class LearningsFSMonitor: ObservableObject {
    
    // MARK: - Properties
    
    /// Directories being monitored with their snapshots
    private var monitoredDirectories: [URL: FSSnapshot] = [:]
    
    /// Cleanup timers for auto-removing monitoring after correlation window
    private var cleanupTasks: [URL: Task<Void, Never>] = [:]
    
    /// The FSEventStream reference
    private var eventStream: FSEventStreamRef?
    
    /// Paths currently being watched
    private var watchedPaths: [String] = []
    
    /// Callback for detected file moves
    public var onFileMoveDetected: ((DetectedFileMove) -> Void)?
    
    /// Correlation window in seconds (default 30 minutes)
    public var correlationWindowSeconds: TimeInterval = 30 * 60
    
    /// Minimum time between snapshot updates to avoid thrashing
    private let snapshotDebounceInterval: TimeInterval = 2.0
    private var pendingSnapshotUpdates: [URL: Task<Void, Never>] = [:]
    
    /// Queue for FSEvents callbacks
    private let eventQueue = DispatchQueue(label: "com.sorty.learnings.fsmonitor", qos: .utility)
    
    // MARK: - Initialization
    
    public init() {}
    
    deinit {
        // Can't safely call stopAllMonitoring() here because it's MainActor isolated
        // and we can't spin up a MainActor task in deinit.
        // The event stream is a C pointer (FSEventStreamRef) which needs manual cleanup.
        // However, standard practice with @MainActor classes is to ensure cleanup 
        // is called before the object is released.
        // To be safe against leaks if manual cleanup isn't done, we'd need to extract
        // the stream management to a non-isolated helper class.
        // For now, removing the unsafe call.
    }
    
    // MARK: - Public API
    
    /// Start monitoring a directory for file moves
    public func startMonitoring(directory: URL) {
        guard !monitoredDirectories.keys.contains(directory) else {
            LogManager.shared.log("Already monitoring: \(directory.lastPathComponent)", category: "LearningsFSMonitor")
            return
        }
        
        // Take initial snapshot
        let snapshot = FSSnapshot(at: directory)
        monitoredDirectories[directory] = snapshot
        
        LogManager.shared.log("Started monitoring: \(directory.lastPathComponent) (\(snapshot.files.count) files)", category: "LearningsFSMonitor")
        
        // Schedule automatic cleanup after correlation window
        scheduleCleanup(for: directory)
        
        // Restart FSEvents stream with new path
        restartEventStream()
    }
    
    /// Stop monitoring a specific directory
    public func stopMonitoring(directory: URL) {
        guard monitoredDirectories.keys.contains(directory) else { return }
        
        monitoredDirectories.removeValue(forKey: directory)
        cleanupTasks[directory]?.cancel()
        cleanupTasks.removeValue(forKey: directory)
        pendingSnapshotUpdates[directory]?.cancel()
        pendingSnapshotUpdates.removeValue(forKey: directory)
        
        LogManager.shared.log("Stopped monitoring: \(directory.lastPathComponent)", category: "LearningsFSMonitor")
        
        // Restart FSEvents stream without this path
        if monitoredDirectories.isEmpty {
            stopEventStream()
        } else {
            restartEventStream()
        }
    }
    
    /// Stop all monitoring
    public func stopAllMonitoring() {
        stopEventStream()
        for task in cleanupTasks.values {
            task.cancel()
        }
        for task in pendingSnapshotUpdates.values {
            task.cancel()
        }
        monitoredDirectories.removeAll()
        cleanupTasks.removeAll()
        pendingSnapshotUpdates.removeAll()
    }
    
    /// Get list of currently monitored directories
    public var monitoredURLs: [URL] {
        Array(monitoredDirectories.keys)
    }
    
    // MARK: - FSEvents Management
    
    private func restartEventStream() {
        stopEventStream()
        
        guard !monitoredDirectories.isEmpty else { return }
        
        watchedPaths = monitoredDirectories.keys.map { $0.path }
        
        // Use weak self in the callback context
        let pathsToWatch = watchedPaths as CFArray
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info = info else { return }
            let monitor = Unmanaged<LearningsFSMonitor>.fromOpaque(info).takeUnretainedValue()
            
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
            
            // Post to main actor
            Task { @MainActor in
                monitor.handleFSEvents(paths: paths, flags: Array(UnsafeBufferPointer(start: eventFlags, count: numEvents)))
            }
        }
        
        eventStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,  // Latency in seconds
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        
        if let stream = eventStream {
            FSEventStreamSetDispatchQueue(stream, eventQueue)
            FSEventStreamStart(stream)
        }
    }
    
    private func stopEventStream() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
        watchedPaths = []
    }
    
    // MARK: - Event Handling
    
    private func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        // Debounce: schedule snapshot update for affected directories
        for path in paths {
            for (dirURL, _) in monitoredDirectories {
                if path.hasPrefix(dirURL.path) {
                    scheduleSnapshotUpdate(for: dirURL)
                    break
                }
            }
        }
    }
    
    private func scheduleSnapshotUpdate(for directory: URL) {
        // Cancel any pending update for this directory
        pendingSnapshotUpdates[directory]?.cancel()
        
        // Schedule new update after debounce interval
        pendingSnapshotUpdates[directory] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(snapshotDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            await self.updateSnapshotAndDetectMoves(for: directory)
        }
    }
    
    private func updateSnapshotAndDetectMoves(for directory: URL) async {
        guard let oldSnapshot = monitoredDirectories[directory] else { return }
        
        // Take new snapshot on background thread
        let newSnapshot = await Task.detached(priority: .utility) {
            FSSnapshot(at: directory)
        }.value
        
        // Detect moves by comparing snapshots
        let moves = detectFileMoves(from: oldSnapshot, to: newSnapshot, in: directory)
        
        // Update stored snapshot
        monitoredDirectories[directory] = newSnapshot
        
        // Notify about detected moves
        for move in moves {
            LogManager.shared.log("Detected move: \(URL(fileURLWithPath: move.fromPath).lastPathComponent) → \(URL(fileURLWithPath: move.toPath).deletingLastPathComponent().lastPathComponent)/", category: "LearningsFSMonitor")
            onFileMoveDetected?(move)
        }
    }
    
    // MARK: - Move Detection
    
    /// Detect file moves by comparing snapshots
    /// Uses filename matching as a heuristic (could be enhanced with file hashes)
    private func detectFileMoves(from oldSnapshot: FSSnapshot, to newSnapshot: FSSnapshot, in directory: URL) -> [DetectedFileMove] {
        var moves: [DetectedFileMove] = []
        
        let removedFiles = oldSnapshot.files.subtracting(newSnapshot.files)
        let addedFiles = newSnapshot.files.subtracting(oldSnapshot.files)
        
        // For each removed file, see if a file with the same name appeared elsewhere
        for removedPath in removedFiles {
            let removedURL = URL(fileURLWithPath: removedPath)
            let fileName = removedURL.lastPathComponent
            
            // Look for the same filename in added files
            for addedPath in addedFiles {
                let addedURL = URL(fileURLWithPath: addedPath)
                if addedURL.lastPathComponent == fileName {
                    // Found a probable move
                    moves.append(DetectedFileMove(
                        fromPath: removedPath,
                        toPath: addedPath,
                        timestamp: Date()
                    ))
                    break
                }
            }
        }
        
        return moves
    }
    
    // MARK: - Cleanup
    
    private func scheduleCleanup(for directory: URL) {
        cleanupTasks[directory]?.cancel()
        
        cleanupTasks[directory] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(correlationWindowSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            LogManager.shared.log("Correlation window expired for: \(directory.lastPathComponent)", category: "LearningsFSMonitor")
            self.stopMonitoring(directory: directory)
        }
    }
}
