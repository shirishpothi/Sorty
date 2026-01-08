//
//  DebugLogger.swift
//  Sorty
//
//  Debug logging utility
//

import Foundation

struct DebugLogger {
    /// Simple log convenience method
    static func log(_ message: String) {
        LogManager.shared.log(message, level: .debug, category: "DebugLogger")
    }
    
    static func log(sessionId: String = "debug-session", runId: String = "run1", hypothesisId: String, location: String, message: String, data: [String: Any] = [:]) {
        let context: [String: Any] = [
            "sessionId": sessionId,
            "runId": runId,
            "hypothesisId": hypothesisId,
            "location": location,
            "originalData": data
        ]
        
        LogManager.shared.log(message, level: .debug, category: "DebugLogger", data: context)
    }
}

