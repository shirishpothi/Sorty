//
//  HUDNotificationOverlay.swift
//  Sorty
//
//  A subtle bottom-left HUD notification overlay with liquid glass styling
//

import SwiftUI

/// HUD notification overlay that appears at the bottom-left of the window
public struct HUDNotificationOverlay: View {
    @ObservedObject private var notificationManager: NotificationManager
    
    public init() {
        self._notificationManager = ObservedObject(wrappedValue: NotificationManager.shared)
    }
    
    public var body: some View {
        VStack {
            Spacer()
            
            HStack {
                if let notification = notificationManager.currentHUDNotification {
                    HUDNotificationCard(notification: notification) {
                        notificationManager.dismissHUD()
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.92).combined(with: .opacity).combined(with: .offset(x: -20)),
                        removal: .scale(scale: 0.95).combined(with: .opacity).combined(with: .offset(x: -10))
                    ))
                }
                
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.bottom, 20)
        }
        .allowsHitTesting(notificationManager.currentHUDNotification != nil)
        .animation(.spring(response: 0.5, dampingFraction: 0.78), value: notificationManager.currentHUDNotification?.id)
        .ignoresSafeArea()
        .zIndex(1000)
    }
}

/// Individual HUD notification card with liquid glass styling
struct HUDNotificationCard: View {
    let notification: HUDNotification
    let onDismiss: () -> Void
    
    @State private var isHovered = false
    @State private var progressRemaining: CGFloat = 1.0
    @State private var appeared = false
    
    private let autoDismissSeconds: Double = 4.0
    
    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [notification.iconColor, notification.iconColor.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 8)
            
            HStack(spacing: 12) {
                Image(systemName: notification.icon)
                    .font(.title3)
                    .foregroundStyle(notification.iconColor)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(notification.iconColor.opacity(0.12))
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(notification.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    
                    Text(notification.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                if isHovered {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 14)
                    .fill(notification.iconColor.opacity(0.03))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.25),
                            notification.iconColor.opacity(0.15),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .bottom) {
            GeometryReader { geo in
                Capsule()
                    .fill(notification.iconColor.opacity(0.4))
                    .frame(width: geo.size.width * progressRemaining, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
            .padding(.horizontal, 6)
            .padding(.bottom, 3)
        }
        .shadow(color: notification.iconColor.opacity(0.12), radius: 12, x: 0, y: 6)
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            onDismiss()
        }
        .onAppear {
            withAnimation(.linear(duration: autoDismissSeconds)) {
                progressRemaining = 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.title): \(notification.message)")
        .accessibilityHint("Tap to dismiss")
    }
}

#Preview("HUD Overlay") {
    ZStack {
        Color.gray.opacity(0.3)
        HUDNotificationOverlay()
    }
    .frame(width: 800, height: 600)
    .onAppear {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            NotificationManager.shared.showInfo(title: "Test Notification", message: "This is a preview notification to verify the HUD is working correctly!")
        }
    }
}
