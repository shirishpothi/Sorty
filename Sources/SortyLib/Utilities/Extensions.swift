//
//  Extensions.swift
//  Sorty
//
//  Utility extensions
//

import Foundation
import SwiftUI

private struct MinimumHitTargetModifier: ViewModifier {
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }
}

private enum NumericTextTransitionStyle {
    case automatic
    case value(Double)
}

private struct NumericTextTransitionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let style: NumericTextTransitionStyle
    let animationValue: Value
    let animation: Animation

    private var transition: ContentTransition {
        switch style {
        case .automatic:
            .numericText()
        case .value(let value):
            .numericText(value: value)
        }
    }

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : transition)
            .animation(
                reduceMotion ? .easeOut(duration: 0.12) : animation,
                value: animationValue
            )
    }
}

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

extension View {
    func minimumHitTarget(_ size: CGFloat = 40) -> some View {
        modifier(MinimumHitTargetModifier(size: size))
    }

    func numericTextTransition<Value: Equatable>(
        animationValue: Value,
        animation: Animation = .spring(response: 0.28, dampingFraction: 0.78)
    ) -> some View {
        modifier(
            NumericTextTransitionModifier(
                style: .automatic,
                animationValue: animationValue,
                animation: animation
            )
        )
    }

    func numericTextTransition(
        value: Double,
        animation: Animation = .spring(response: 0.28, dampingFraction: 0.78)
    ) -> some View {
        modifier(
            NumericTextTransitionModifier(
                style: .value(value),
                animationValue: value,
                animation: animation
            )
        )
    }
}
