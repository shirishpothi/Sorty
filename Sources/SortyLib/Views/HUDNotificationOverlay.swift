//
//  HUDNotificationOverlay.swift
//  Sorty
//
//  A subtle bottom-left HUD notification overlay
//

import SwiftUI

/// HUD notification overlay that appears at the bottom-left of the window
public struct HUDNotificationOverlay: View {
    @ObservedObject var notificationManager = NotificationManager.shared
    
    public init() {}
    
    public var body: some View {
        VStack {
            Spacer()
            
            HStack {
                if let notification = notificationManager.currentHUDNotification {
                    HUDNotificationCard(notification: notification) {
                        notificationManager.dismissHUD()
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
                
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.bottom, 20)
        }
        .animation(.easeOut(duration: 0.2), value: notificationManager.currentHUDNotification?.id)
    }
}

/// Individual HUD notification card
struct HUDNotificationCard: View {
    let notification: HUDNotification
    let onDismiss: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: notification.icon)
                .font(.title3)
                .foregroundStyle(notification.iconColor)
                .frame(width: 24, height: 24)
            
            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                
                Text(notification.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            
            // Dismiss button (appears on hover)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 320)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 4)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onDismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.title): \(notification.message)")
        .accessibilityHint("Tap to dismiss")
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.3)
        HUDNotificationOverlay()
    }
    .frame(width: 800, height: 600)
}
