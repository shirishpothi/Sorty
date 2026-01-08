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

extension Date {
    /// Returns a human-readable timestamp suitable for filenames (e.g., "2024-05-24 14-30-05")
    var filenameTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return formatter.string(from: self)
    }
}
