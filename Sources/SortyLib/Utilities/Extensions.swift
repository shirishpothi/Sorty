//
//  Extensions.swift
//  Sorty
//
//  Utility extensions
//

import Foundation
import SwiftUI



extension KeyEquivalent {
    static let cancelAction = KeyEquivalent("\u{1b}") // Escape
    static let defaultAction = KeyEquivalent("\r") // Return
}

extension String {
    /// Returns true if the string is a subpath of the given base path
    func isSubpath(of base: String) -> Bool {
        let pathURL = URL(fileURLWithPath: self).standardized
        let baseURL = URL(fileURLWithPath: base).standardized
        
        // Exact match
        if pathURL.path == baseURL.path { return true }
        
        // Check if path starts with base and next char is separator
        let basePath = baseURL.path
        let targetPath = pathURL.path
        
        if targetPath.hasPrefix(basePath) {
            let nextIndex = targetPath.index(targetPath.startIndex, offsetBy: basePath.count)
            if nextIndex == targetPath.endIndex { return true } // Exact match again
            return targetPath[nextIndex] == "/"
        }
        
        return false
    }
}

extension Date {
    /// Returns a human-readable timestamp suitable for filenames (e.g., "2024-05-24 14-30-05")
    var filenameTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter.string(from: self)
    }
}
