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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
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
        .animation(
            reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.78),
            value: notificationManager.currentHUDNotification?.id
        )
        .ignoresSafeArea()
        .zIndex(1000)
    }
}

/// Individual HUD notification card with liquid glass styling
struct HUDNotificationCard: View {
    let notification: HUDNotification
    let onDismiss: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .overlay {
            HUDNotificationAmbientEffect(isAnimated: appeared && !reduceMotion)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
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
            appeared = true

            withAnimation(reduceMotion ? nil : .linear(duration: autoDismissSeconds)) {
                progressRemaining = 0
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(notification.title): \(notification.message)")
        .accessibilityHint(notification.defaultAction == nil ? "Tap to dismiss" : "Tap to open")
    }
}

private struct HUDNotificationAmbientEffect: View {
    let isAnimated: Bool

    private let cyan = Color(red: 0.08, green: 0.88, blue: 0.92)
    private let pink = Color(red: 1.0, green: 0.22, blue: 0.62)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                leftIconHalo(in: geometry.size)
                horizontalMist(in: geometry.size)

                if isAnimated {
                    SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                        ParticleField(time: timeline.date.timeIntervalSinceReferenceDate, size: geometry.size, accent: cyan)
                    }
                } else {
                    ParticleField(time: 0, size: geometry.size, accent: cyan)
                }
            }
        }
    }

    private func leftIconHalo(in size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(cyan.opacity(0.18), lineWidth: 1)
                .frame(width: 66, height: 58)
                .blur(radius: 1)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            cyan.opacity(0.22),
                            cyan.opacity(0.07),
                            .clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 42
                    )
                )
                .frame(width: 84, height: 84)
                .blur(radius: 8)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .offset(x: 42, y: 0)
    }

    private func horizontalMist(in size: CGSize) -> some View {
        LinearGradient(
            colors: [
                .clear,
                cyan.opacity(0.08),
                pink.opacity(0.045),
                .clear
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(width: min(260, size.width * 0.62), height: min(58, size.height * 0.70))
        .blur(radius: 18)
        .offset(x: 58)
    }
}

private struct ParticleField: View {
    let time: TimeInterval
    let size: CGSize
    let accent: Color

    private let particles: [Particle] = [
        .init(seed: 0.13, x: 0.38, y: 0.37, size: 1.8, drift: 5, delay: 0.00),
        .init(seed: 0.42, x: 0.43, y: 0.50, size: 1.2, drift: 4, delay: 0.36),
        .init(seed: 0.71, x: 0.49, y: 0.42, size: 1.5, drift: 6, delay: 0.72)
    ]

    var body: some View {
        Canvas { context, _ in
            for particle in particles {
                let pulse = (sin((time + particle.delay) * 1.7 + particle.seed * 9.0) + 1) / 2
                let drift = CGFloat(sin((time + particle.delay) * 0.9 + particle.seed * 6.0)) * particle.drift
                let rect = CGRect(
                    x: size.width * particle.x + drift,
                    y: size.height * particle.y,
                    width: particle.size,
                    height: particle.size
                )

                context.opacity = 0.32 + pulse * 0.28
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(accent.opacity(0.58))
                )
            }
        }
    }
}

private struct Particle {
    let seed: Double
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let drift: CGFloat
    let delay: TimeInterval
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
