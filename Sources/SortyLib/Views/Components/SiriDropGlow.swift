//
//  SiriDropGlow.swift
//  Sorty
//
//  Shared drop-zone modifier.
//

import SwiftUI

enum SiriGlowPresentation {
    case border
    case window
}

// MARK: - Drop Zone Modifier

/// A view modifier that wraps any view with drag-and-drop support.
struct SiriDropZoneModifier: ViewModifier {
    let acceptedTypes: [String]
    let cornerRadius: CGFloat
    let isEnabled: Bool
    let glowPresentation: SiriGlowPresentation
    let glowLineWidth: CGFloat
    let glowRadius: CGFloat
    let onDrop: ([NSItemProvider]) -> Bool
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
                    onDrop(providers)
                }
        } else {
            content
        }
    }
}

extension View {
    /// Adds shared drop zone behavior.
    /// - Parameters:
    ///   - acceptedTypes: UTI type identifiers to accept.
    ///   - cornerRadius: Reserved for API compatibility.
    ///   - isEnabled: Whether drag/drop should be active.
    ///   - glowPresentation: Reserved for API compatibility.
    ///   - glowLineWidth: Reserved for API compatibility.
    ///   - glowRadius: Reserved for API compatibility.
    ///   - isTargeted: Binding that tracks whether a drag is hovering.
    ///   - onDrop: Closure called when items are dropped.
    func siriDropZone(
        acceptedTypes: [String] = ["public.file-url"],
        cornerRadius: CGFloat = 16,
        isEnabled: Bool = true,
        glowPresentation: SiriGlowPresentation = .border,
        glowLineWidth: CGFloat = 2.5,
        glowRadius: CGFloat = 12,
        isTargeted: Binding<Bool>,
        onDrop: @escaping ([NSItemProvider]) -> Bool
    ) -> some View {
        modifier(SiriDropZoneModifier(
            acceptedTypes: acceptedTypes,
            cornerRadius: cornerRadius,
            isEnabled: isEnabled,
            glowPresentation: glowPresentation,
            glowLineWidth: glowLineWidth,
            glowRadius: glowRadius,
            onDrop: onDrop,
            isTargeted: isTargeted
        ))
    }
}
