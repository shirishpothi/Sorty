//
//  ToastOverlay.swift
//  Sorty
//
//  A reusable toast notification view.
//

import SwiftUI

struct ToastOverlay: View {
    let message: String
    let actionLabel: String?
    let action: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var opacity: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            
            if let label = actionLabel, let action = action {
                Spacer()
                Button(action: action) {
                    Text(label)
                        .bold()
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .systemLiquidGlassBackground(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 10, x: 0, y: 5)
        .padding(.bottom, 20)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeIn(duration: 0.3)) {
                opacity = 1
            }
            
            // Auto dismiss after 4 seconds if no action is taken
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 4_000_000_000) // 4s
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                onDismiss()
            }
        }
    }
}
