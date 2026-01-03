//
//  DebugLogger.swift
//  FileOrganizer
//
//  Debug logging utility
//

import Foundation

struct DebugLogger {
    private static let logPath = "/Users/shirishpothi/Downloads/File Organiser/.cursor/debug.log"
    
    /// Simple log convenience method
    static func log(_ message: String) {
        log(sessionId: "default", runId: "run1", hypothesisId: "general", location: "app", message: message, data: [:])
    }
    
    static func log(sessionId: String = "debug-session", runId: String = "run1", hypothesisId: String, location: String, message: String, data: [String: Any] = [:]) {
        let logEntry: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "message": message,
            "data": data,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: logEntry),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        let logLine = jsonString + "\n"
        if let logData = logLine.data(using: .utf8) {
            let logURL = URL(fileURLWithPath: logPath)
            // Ensure directory exists
            try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(logData)
                try? fileHandle.close()
            } else {
                // Create file if it doesn't exist
                try? logData.write(to: logURL, options: .atomic)
            }
        }
    }
}

