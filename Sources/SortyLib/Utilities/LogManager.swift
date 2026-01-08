//
//  LogManager.swift
//  Sorty
//
//  Production-grade logging system with rotation, sanitization, and export.
//

import Foundation

public final class LogManager: @unchecked Sendable {
    public static let shared = LogManager()
    
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.sorty.logQueue")
    private let maxLogFiles = 5
    private let maxLogSize: UInt64 = 5 * 1024 * 1024 // 5MB
    
    // Sensitive keys to redact
    private let sensitiveKeys = [
        "apiKey", "access_token", "sk-", "ghp_", "gho_"
    ]
    
    private var logsDirectory: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.sorty.FileOrganizer"
        let logsDir = appSupport.appendingPathComponent(bundleID).appendingPathComponent("Logs")
        
        if !fileManager.fileExists(atPath: logsDir.path) {
            try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        }
        
        return logsDir
    }
    
    private var currentLogFile: URL? {
        return logsDirectory?.appendingPathComponent("sorty.log")
    }
    
    private init() {
        rotateLogsIfNeeded()
    }
    
    // MARK: - Public API
    
    public func log(_ message: String, level: LogLevel = .info, category: String = "General", data: [String: Any]? = nil) {
        queue.async {
            self.writeLog(message, level: level, category: category, data: data)
        }
    }
    
    public func exportLogs() -> URL? {
        guard let logsDirectory = logsDirectory else { return nil }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let exportURL = fileManager.temporaryDirectory.appendingPathComponent("Sorty_Logs_\(timestamp).zip")
        
        do {
            // Remove existing if any (unlikely with timestamp)
            if fileManager.fileExists(atPath: exportURL.path) {
                try fileManager.removeItem(at: exportURL)
            }
            
            // Simple zip by using file coordinator or shell (simpler for this context)
            // Using zip command for reliability on macOS
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-r", "-j", exportURL.path, logsDirectory.path]
            
            try process.run()
            process.waitUntilExit()
            
            return process.terminationStatus == 0 ? exportURL : nil
        } catch {
            print("Failed to export logs: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func writeLog(_ message: String, level: LogLevel, category: String, data: [String: Any]?) {
        guard let logFile = currentLogFile else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let sanitizedMessage = sanitize(message)
        var contextString = ""
        
        if let data = data {
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                contextString = " | Context: " + sanitize(jsonString)
            }
        }
        
        let logLine = "[\(timestamp)] [\(level.rawValue.uppercased())] [\(category)] \(sanitizedMessage)\(contextString)\n"
        
        if let data = logLine.data(using: .utf8) {
            if !fileManager.fileExists(atPath: logFile.path) {
                try? data.write(to: logFile)
            } else {
                if let fileHandle = try? FileHandle(forWritingTo: logFile) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    try? fileHandle.close()
                }
            }
        }
        
        checkRotation()
    }
    
    private func sanitize(_ text: String) -> String {
        var result = text
        
        // Redact standard API keys
        result = result.replacingOccurrences(of: "sk-[a-zA-Z0-9]{20,}", with: "[REDACTED_OPENAI_KEY]", options: .regularExpression)
        result = result.replacingOccurrences(of: "ghp_[a-zA-Z0-9]{20,}", with: "[REDACTED_GITHUB_TOKEN]", options: .regularExpression)
        result = result.replacingOccurrences(of: "gho_[a-zA-Z0-9]{20,}", with: "[REDACTED_GITHUB_TOKEN]", options: .regularExpression)
        
        // Redact User Paths
        // Matches /Users/username/ or /Users/username
        // We look for /Users/ followed by non-slash characters
        if let regex = try? NSRegularExpression(pattern: "/Users/([^/]+)", options: []) {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Iterate in reverse to avoid range offsets shifting
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let usernameRange = match.range(at: 1)
                    let username = nsString.substring(with: usernameRange)
                    
                    // Don't redact "Shared" or "Guest" if desired, but for strict privacy, redact all users
                    if username != "Shared" {
                        result = result.replacingOccurrences(of: "/Users/\(username)", with: "/Users/[REDACTED_USER]")
                    }
                }
            }
        }
        
        return result
    }
    
    private func checkRotation() {
        guard let logFile = currentLogFile else { return }
        
        if let attrs = try? fileManager.attributesOfItem(atPath: logFile.path),
           let size = attrs[.size] as? UInt64,
           size > maxLogSize {
            rotateLogsIfNeeded(force: true)
        }
    }
    
    private func rotateLogsIfNeeded(force: Bool = false) {
        guard let logsDirectory = logsDirectory, let currentLog = currentLogFile else { return }
        
        // If current log exists and is too big, or if we just want to verify cleanup
        if force || (try? fileManager.attributesOfItem(atPath: currentLog.path)) != nil {
            if force {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let timestamp = formatter.string(from: Date())
                let archivedLog = logsDirectory.appendingPathComponent("sorty-\(timestamp).log")
                
                try? fileManager.moveItem(at: currentLog, to: archivedLog)
            }
            
            // Cleanup old logs
            do {
                let fileURLs = try fileManager.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
                let logFiles = fileURLs.filter { $0.pathExtension == "log" }
                
                if logFiles.count > maxLogFiles {
                    let sortedFiles = logFiles.sorted {
                        let date0 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                        let date1 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                        return date0 < date1
                    }
                    
                    // Delete oldest
                    for i in 0..<(sortedFiles.count - maxLogFiles) {
                        try? fileManager.removeItem(at: sortedFiles[i])
                    }
                }
            } catch {
                print("Error rotating logs: \(error)")
            }
        }
    }
}

public enum LogLevel: String {
    case debug
    case info
    case warning
    case error
    case fault
}
