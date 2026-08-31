//
//  CopyButtonWithAnimation.swift
//  Sorty
//
//  Reusable copy button that shows a checkmark animation after copying
//

import AppKit
import SwiftUI

public struct CopyButtonWithAnimation: View {
    @SortyHotReload private var hotReload
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let content: String
    var label: String?
    var copyIcon: String = "doc.on.doc"
    var iconSize: CGFloat = 13
    
    @State private var showCheckmark = false
    @State private var resetTask: Task<Void, Never>?
    
    public init(content: String, label: String? = nil, copyIcon: String = "doc.on.doc", iconSize: CGFloat = 13) {
        self.content = content
        self.label = label
        self.copyIcon = copyIcon
        self.iconSize = iconSize
    }
    
    public var body: some View {
        Button {
            copyToClipboard()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showCheckmark ? "checkmark" : copyIcon)
                    .font(.system(size: iconSize))
                    .foregroundStyle(showCheckmark ? .green : .secondary)
                    .symbolReplaceTransition(animationValue: showCheckmark)
                
                if let label {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(showCheckmark ? .green : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label ?? "Copy")
        .accessibilityValue(showCheckmark ? "Copied" : "")
        .accessibilityIdentifier("CopyButtonWithAnimation")
        .onDisappear {
            resetTask?.cancel()
        }
    }
    
    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        
        HapticFeedbackManager.shared.tap()
        
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
            showCheckmark = true
        }
        
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.7)) {
                showCheckmark = false
            }
        }
    }
}

#Preview("Copy Button") {
    VStack(spacing: 16) {
        CopyButtonWithAnimation(content: "Hello World")
        CopyButtonWithAnimation(content: "Hello World", label: "Copy")
        CopyButtonWithAnimation(content: "/path/to/file", label: "Copy Path", copyIcon: "folder")
    }
    .padding()
}
