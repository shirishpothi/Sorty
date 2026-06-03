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
            HUDNotificationTorchEffect(isAnimated: appeared && !reduceMotion)
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

private struct HUDNotificationTorchEffect: View {
    let isAnimated: Bool

    private let accent = Color(red: 1.0, green: 0.22, blue: 0.62)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                torchGlow(in: geometry.size)

                if isAnimated {
                    SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                        ParticleField(time: timeline.date.timeIntervalSinceReferenceDate, accent: accent)
                    }
                } else {
                    ParticleField(time: 0, accent: accent)
                }
            }
        }
    }

    private func torchGlow(in size: CGSize) -> some View {
        ZStack(alignment: .leading) {
            LinearGradient(
                colors: [
                    accent.opacity(0.52),
                    accent.opacity(0.24),
                    accent.opacity(0.075),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: min(250, size.width * 0.60), height: size.height)
            .blur(radius: 18)

            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            accent.opacity(0.72),
                            accent.opacity(0.28),
                            accent.opacity(0.08),
                            .clear
                        ],
                        center: .leading,
                        startRadius: 0,
                        endRadius: 92
                    )
                )
                .frame(width: min(210, size.width * 0.50), height: size.height * 1.28)
                .blur(radius: 12)
                .offset(x: -46)

            Rectangle()
                .fill(accent.opacity(0.24))
                .frame(width: 3, height: size.height * 0.72)
                .blur(radius: 4)
                .offset(x: 1)
        }
    }
}

private struct ParticleField: View {
    let time: TimeInterval
    let accent: Color

    private let particles: [Particle] = [
        .init(seed: 0.07, y: 0.30, size: 1.1, speed: 14, delay: 0.00),
        .init(seed: 0.22, y: 0.40, size: 0.8, speed: 18, delay: 0.32),
        .init(seed: 0.39, y: 0.52, size: 1.0, speed: 12, delay: 0.64),
        .init(seed: 0.56, y: 0.63, size: 0.7, speed: 16, delay: 0.96),
        .init(seed: 0.74, y: 0.46, size: 0.9, speed: 20, delay: 1.28)
    ]

    var body: some View {
        Canvas { context, size in
            for particle in particles {
                let cycle = 3.0
                let progress = ((time + particle.delay).truncatingRemainder(dividingBy: cycle)) / cycle
                let easedProgress = 1 - pow(1 - progress, 3)
                let x = 18 + CGFloat(easedProgress) * particle.speed * 3.2
                let drift = CGFloat(sin((time * 1.2) + particle.seed * 8.0) * 2.0)
                let y = size.height * particle.y + drift
                let fade = sin(progress * .pi)
                let rect = CGRect(
                    x: x,
                    y: y,
                    width: particle.size,
                    height: particle.size
                )

                context.opacity = max(0, fade) * 0.55
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(accent.opacity(0.74))
                )
            }
        }
    }
}

private struct Particle {
    let seed: Double
    let y: CGFloat
    let size: CGFloat
    let speed: CGFloat
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
