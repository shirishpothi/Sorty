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
        HStack {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.white)
            
            if let label = actionLabel, let action = action {
                Spacer()
                Button(action: action) {
                    Text(label)
                        .bold()
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
        .shadow(radius: 4)
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
