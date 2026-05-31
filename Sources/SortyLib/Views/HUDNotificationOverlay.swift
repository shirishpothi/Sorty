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
    private let actionColumns = [
        GridItem(.adaptive(minimum: 136, maximum: 210), spacing: 8, alignment: .leading)
    ]

    private var inlineAction: HUDNotificationAction? {
        notification.actions.count == 1 ? notification.actions.first : nil
    }
    
    var body: some View {
        HStack(spacing: 10) {
            Capsule(style: .continuous)
                .fill(notification.iconColor)
                .frame(width: 3)
                .padding(.vertical, 10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: notification.icon)
                        .font(.title3)
                        .foregroundStyle(notification.iconColor)
                        .frame(width: 28, height: 28)
                        .systemLiquidGlassBackground(cornerRadius: 14)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(notification.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(notification.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let inlineAction {
                        Button(role: inlineAction.role) {
                            inlineAction.action()
                        } label: {
                            HUDNotificationActionLabel(action: inlineAction, fillsWidth: false)
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: false)
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

                if notification.actions.count > 1 {
                    LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                        ForEach(notification.actions) { action in
                            Button(role: action.role) {
                                action.action()
                            } label: {
                                HUDNotificationActionLabel(action: action, fillsWidth: true)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.trailing, 12)
            .padding(.vertical, 10)
        }
        .padding(.leading, 12)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .systemLiquidGlassBackground(cornerRadius: 14)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    Color.white.opacity(0.18),
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
            if let defaultAction = notification.defaultAction {
                HapticFeedbackManager.shared.tap()
                defaultAction()
            } else {
                onDismiss()
            }
        }
        .onAppear {
            withAnimation(.linear(duration: autoDismissSeconds)) {
                progressRemaining = 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.title): \(notification.message)")
        .accessibilityHint(notification.defaultAction == nil ? "Tap to dismiss" : "Tap to open")
    }
}

private struct HUDNotificationActionLabel: View {
    let action: HUDNotificationAction
    let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    private var isDestructive: Bool {
        action.role == .destructive
    }

    private var accent: Color {
        isDestructive ? SortyDesignSystem.Colors.error : SortyDesignSystem.Colors.resolvedAccent
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage = action.systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }

            Text(action.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(isDestructive ? Color.red : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: 30, alignment: .center)
        .systemLiquidGlassBackground(cornerRadius: 8)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(accent.opacity(isDestructive ? 0.28 : 0.22), lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
