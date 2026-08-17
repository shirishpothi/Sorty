//
//  ButtonStyles.swift
//  Sorty
//
//  Centralized button styles for the application
//

import AppKit
import SwiftUI

import Beam

public enum SortyButtonIntent: Equatable {
    case primary
    case secondary
    case success
    case warning
    case info
    case destructive

    var accent: Color {
        switch self {
        case .primary:
            return SortyDesignSystem.Colors.resolvedAccent
        case .secondary:
            return .secondary
        case .success:
            return SortyDesignSystem.Colors.success
        case .warning:
            return SortyDesignSystem.Colors.warning
        case .info:
            return SortyDesignSystem.Colors.info
        case .destructive:
            return SortyDesignSystem.Colors.error
        }
    }
}

/// Standard app button style for regular controls, with semantic tint variants.
public struct SortyStandardButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    var intent: SortyButtonIntent
    var isProminent: Bool
    var size: ControlSize

    public init(
        intent: SortyButtonIntent = .secondary,
        isProminent: Bool = false,
        size: ControlSize = .regular
    ) {
        self.intent = intent
        self.isProminent = isProminent
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let resolvedIntent = resolvedIntent(for: configuration)
        let accent = resolvedIntent.accent
        let radius = size == .small ? 7.0 : 8.0

        configuration.label
            .font(.system(size: fontSize, weight: isProminent ? .semibold : .medium))
            .lineLimit(1)
            .foregroundStyle(foregroundStyle(intent: resolvedIntent, accent: accent))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(backgroundStyle(accent: accent, isPressed: pressed))
            }
            .systemLiquidGlassBackground(cornerRadius: radius)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderStyle(intent: resolvedIntent, accent: accent), lineWidth: isProminent ? 1.15 : 1)
            }
            .scaleEffect(pressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.52)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .onChange(of: pressed) { _, newValue in
                if newValue {
                    if resolvedIntent == .destructive {
                        HapticFeedbackManager.shared.error()
                    } else {
                        HapticFeedbackManager.shared.tap()
                    }
                }
            }
    }

    private var fontSize: CGFloat {
        switch size {
        case .mini: return 11
        case .small: return 12
        case .large, .extraLarge: return 15
        default: return 14
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .mini: return 10
        case .small: return 12
        case .large, .extraLarge: return 20
        default: return 16
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .mini: return 4
        case .small: return 6
        case .large, .extraLarge: return 11
        default: return 9
        }
    }

    private func resolvedIntent(for configuration: Configuration) -> SortyButtonIntent {
        configuration.role == .destructive ? .destructive : intent
    }

    private func foregroundStyle(intent: SortyButtonIntent, accent: Color) -> some ShapeStyle {
        isProminent ? AnyShapeStyle(.white) : AnyShapeStyle(intent == .secondary ? Color.primary : accent)
    }

    private func backgroundStyle(accent: Color, isPressed: Bool) -> some ShapeStyle {
        if isProminent {
            return AnyShapeStyle(accent.opacity(isPressed ? 0.78 : 0.9))
        }

        return AnyShapeStyle(Color.clear)
    }

    private func borderStyle(intent: SortyButtonIntent, accent: Color) -> some ShapeStyle {
        if isProminent {
            return AnyShapeStyle(Color.white.opacity(0.24))
        }

        return AnyShapeStyle(accent.opacity(intent == .secondary ? 0.24 : 0.38))
    }
}

/// Primary pill-shaped button style used for main actions
public struct SortyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isSecondary: Bool = false
    var size: ControlSize = .regular
    
    public init(isSecondary: Bool = false, size: ControlSize = .regular) {
        self.isSecondary = isSecondary
        self.size = size
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .small ? 13 : 15, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(.white)
            .padding(.horizontal, size == .small ? 16 : 22)
            .padding(.vertical, size == .small ? 8 : 10)
            .background(
                ZStack {
                    if isSecondary {
                        Capsule()
                            .fill(Color.secondary.opacity(0.3))
                    } else {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.85), location: 0),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent, location: 0.3),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.95), location: 0.5),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent, location: 0.7),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.85), location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.black.opacity(0.15), location: 0),
                                        .init(color: Color.clear, location: 0.3),
                                        .init(color: Color.clear, location: 0.7),
                                        .init(color: Color.black.opacity(0.15), location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.white.opacity(0.1),
                                        Color.black.opacity(0.1),
                                        Color.black.opacity(0.2)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                }
            )
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
            .shadow(color: Color.black.opacity(isSecondary ? 0 : 0.15), radius: 8, x: 0, y: 4)
    }
}

/// Primary pill-shaped button style used for onboarding and main actions
public struct OnboardingPillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    var isSecondary: Bool = false
    var size: ControlSize = .regular
    var isGlassInteractive: Bool = true
    
    public init(
        isSecondary: Bool = false,
        size: ControlSize = .regular,
        isGlassInteractive: Bool = true
    ) {
        self.isSecondary = isSecondary
        self.size = size
        self.isGlassInteractive = isGlassInteractive
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        let fontSize: CGFloat = {
            switch size {
            case .small: return 13
            case .large, .extraLarge: return 18
            default: return 15
            }
        }()
        let horizontalPadding: CGFloat = {
            switch size {
            case .small: return 16
            case .large, .extraLarge: return 32
            default: return 22
            }
        }()
        let verticalPadding: CGFloat = {
            switch size {
            case .small: return 8
            case .large, .extraLarge: return 16
            default: return 10
            }
        }()
        return configuration.label
            .font(.system(size: fontSize, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(isSecondary ? .primary : .white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                ZStack {
                    if isSecondary {
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.92 : 0.98))

                        Capsule()
                            .strokeBorder(
                                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                                lineWidth: 1
                            )
                    } else {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.85), location: 0),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent, location: 0.3),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.95), location: 0.5),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent, location: 0.7),
                                        .init(color: SortyDesignSystem.Colors.resolvedAccent.opacity(0.85), location: 1)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.black.opacity(0.15), location: 0),
                                        .init(color: Color.clear, location: 0.3),
                                        .init(color: Color.clear, location: 0.7),
                                        .init(color: Color.black.opacity(0.15), location: 1)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )

                        Capsule()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.25),
                                        Color.white.opacity(0.1),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                }
            )
            .systemLiquidGlassBackground(
                cornerRadius: 999,
                interactive: isGlassInteractive
            )
            .shadow(
                color: isSecondary
                    ? Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05)
                    : SortyDesignSystem.Colors.resolvedAccent.opacity(0.3),
                radius: 8,
                x: 0,
                y: 4
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    HapticFeedbackManager.shared.tap()
                }
            }
    }
}

/// Pill button style with a caller-provided fill color for semantic actions.
public struct TintedPillButtonStyle: ButtonStyle {
    var fillColor: Color
    var foregroundColor: Color = .white
    var size: ControlSize = .regular

    public init(fillColor: Color, foregroundColor: Color = .white, size: ControlSize = .regular) {
        self.fillColor = fillColor
        self.foregroundColor = foregroundColor
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .small ? 13 : 15, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, size == .small ? 16 : 22)
            .padding(.vertical, size == .small ? 8 : 10)
            .background(
                ZStack {
                    Capsule()
                        .fill(fillColor.opacity(configuration.isPressed ? 0.88 : 1.0))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    Capsule()
                        .strokeBorder(
                            fillColor.opacity(0.35),
                            lineWidth: 1
                        )
                }
            )
            .systemLiquidGlassBackground(cornerRadius: 999)
            .shadow(color: fillColor.opacity(0.24), radius: 8, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, newValue in
                if newValue {
                    HapticFeedbackManager.shared.tap()
                }
            }
    }
}

/// Standard secondary button style with border and haptic feedback
public struct SortySecondaryButtonStyle: ButtonStyle {
    var size: ControlSize = .regular
    var color: Color = .secondary
    
    public init(size: ControlSize = .regular, color: Color = .secondary) {
        self.size = size
        self.color = color
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .small ? 12 : 14, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, size == .small ? 12 : 16)
            .padding(.vertical, size == .small ? 6 : 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
            )
            .systemLiquidGlassBackground(cornerRadius: 8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(color == .secondary ? .primary : color)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.subtleBounce, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    HapticFeedbackManager.shared.tap()
                }
            }
    }
}

/// Destructive button style for dangerous actions
public struct SortyDestructiveButtonStyle: ButtonStyle {
    var size: ControlSize = .regular
    
    public init(size: ControlSize = .regular) {
        self.size = size
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .small ? 12 : 14, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(.white)
            .padding(.horizontal, size == .small ? 12 : 16)
            .padding(.vertical, size == .small ? 6 : 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.red.opacity(0.85))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.subtleBounce, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    HapticFeedbackManager.shared.error()
                }
            }
    }
}

/// Button style that provides haptic feedback and subtle bounce on press
public struct HapticBounceButtonStyle: ButtonStyle {
    let feedbackType: HapticTapModifier.HapticFeedbackType

    public init(feedbackType: HapticTapModifier.HapticFeedbackType = .tap) {
        self.feedbackType = feedbackType
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.subtleBounce, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { oldValue, newValue in
                if newValue {
                    switch feedbackType {
                    case .tap:
                        HapticFeedbackManager.shared.tap()
                    case .success:
                        HapticFeedbackManager.shared.success()
                    case .error:
                        HapticFeedbackManager.shared.error()
                    case .selection:
                        HapticFeedbackManager.shared.selection()
                    case .light:
                        HapticFeedbackManager.shared.light()
                    }
                }
            }
    }
}

/// SwiftUI port of metal-fx's chromatic liquid-metal button treatment.
public struct MetalFxPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isPaused: Bool
    var usesSubtleIdleBeam: Bool
    @State private var isHovering = false

    public init(isPaused: Bool = false, usesSubtleIdleBeam: Bool = false) {
        self.isPaused = isPaused
        self.usesSubtleIdleBeam = usesSubtleIdleBeam
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background {
                MetalFxPillSurface(
                    isPressed: pressed,
                    isHovering: isHovering,
                    isEnabled: isEnabled,
                    isPaused: isPaused,
                    usesSubtleIdleBeam: usesSubtleIdleBeam,
                    colorScheme: colorScheme,
                    reduceMotion: reduceMotion
                )
            }
            .contentShape(Capsule())
            .shadow(
                color: Color(red: 0.65, green: 0.91, blue: 1).opacity(isEnabled ? (isHovering ? 0.24 : 0.14) : 0.03),
                radius: pressed ? 4 : (isHovering ? 12 : 8),
                y: pressed ? 1 : (isHovering ? 5 : 3)
            )
            .scaleEffect(pressed ? 0.975 : 1)
            .opacity(isEnabled ? 1 : 0.56)
            .animation(.easeOut(duration: 0.14), value: pressed)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    HapticFeedbackManager.shared.selection()
                }
            }
            .onChange(of: pressed) { _, newValue in
                if newValue {
                    HapticFeedbackManager.shared.tap()
                }
            }
    }
}

private struct MetalFxPillSurface: View {
    let isPressed: Bool
    let isHovering: Bool
    let isEnabled: Bool
    let isPaused: Bool
    let usesSubtleIdleBeam: Bool
    let colorScheme: ColorScheme
    let reduceMotion: Bool

    private var isIntensified: Bool {
        isHovering || isPressed
    }

    private var idleBeamOpacity: Double {
        usesSubtleIdleBeam && !isIntensified ? 0.42 : 1.0
    }

    private var shouldAnimateSurface: Bool {
        !isPaused && isEnabled && !reduceMotion
    }

    var body: some View {
        if shouldAnimateSurface {
            SwiftUI.TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                surface(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            surface(time: 0)
        }
    }

    private func surface(time: TimeInterval) -> some View {
        // Keep phase values small. Feeding an ever-growing uptime value into
        // AngularGradient eventually loses precision and can render a dark seam.
        let phase = time.truncatingRemainder(dividingBy: 12) / 12

        return ZStack {
            Capsule()
                .fill(baseFill)

            Capsule()
                .strokeBorder(
                    AngularGradient(
                        colors: ringColors,
                        center: .center,
                        angle: .degrees(phase * 360)
                    ),
                    lineWidth: isIntensified ? 3.2 : 1.6
                )
                .blur(radius: 0.35)
                .opacity(idleBeamOpacity)

            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.30 : 0.38),
                            Color.white.opacity(0.08),
                            Color.black.opacity(colorScheme == .dark ? 0.28 : 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )

            movingCatchlight(phase: phase)
                .opacity(usesSubtleIdleBeam && !isIntensified ? 0.38 : 1.0)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isPressed ? 0.08 : (isHovering ? 0.16 : (usesSubtleIdleBeam ? 0.08 : 0.11))),
                            Color.clear,
                            Color.black.opacity(isPressed ? 0.22 : 0.13)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(3)
        }
        .clipShape(Capsule())
        .compositingGroup()
    }

    private var baseFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(red: 0.98, green: 0.31, blue: 0.45),
                Color(red: 0.94, green: 0.20, blue: 0.36),
                Color(red: 0.72, green: 0.15, blue: 0.36)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var ringColors: [Color] {
        if colorScheme == .dark {
            return [
                .black.opacity(0.72),
                Color(red: 0.67, green: 0.91, blue: 1.00),
                Color(red: 0.77, green: 1.00, blue: 0.62),
                Color(red: 0.97, green: 0.53, blue: 0.55),
                .black.opacity(0.82),
                Color(red: 1.00, green: 0.99, blue: 0.76),
                .black.opacity(0.72)
            ]
        }

        return [
            Color(red: 1.00, green: 0.95, blue: 0.95),
            Color(red: 1.00, green: 0.98, blue: 0.82),
            Color(red: 0.69, green: 0.91, blue: 0.74),
            Color(red: 0.62, green: 0.63, blue: 0.65),
            Color(red: 0.88, green: 0.93, blue: 1.00),
            .white,
            Color(red: 1.00, green: 0.95, blue: 0.95)
        ]
    }

    private func movingCatchlight(phase: Double) -> some View {
        let travel = (sin(phase * 2 * .pi) + 1) / 2

        return Capsule()
            .strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: max(0, travel - 0.22)),
                        .init(color: Color.white.opacity(isHovering ? 0.72 : 0.52), location: travel),
                        .init(color: Color(red: 0.67, green: 0.91, blue: 1).opacity(0.28), location: min(1, travel + 0.18)),
                        .init(color: .clear, location: min(1, travel + 0.30))
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: isHovering ? 6 : 5
            )
            .blur(radius: 5)
            .opacity(isPressed ? 0.35 : 0.72)
    }
}

extension ButtonStyle where Self == OnboardingPillButtonStyle {
    public static var onboardingPill: OnboardingPillButtonStyle { OnboardingPillButtonStyle() }
    public static var onboardingPillSecondary: OnboardingPillButtonStyle { OnboardingPillButtonStyle(isSecondary: true) }
    
    public static func onboardingPill(size: ControlSize) -> OnboardingPillButtonStyle {
        OnboardingPillButtonStyle(size: size)
    }

    public static func onboardingPill(
        size: ControlSize,
        isGlassInteractive: Bool
    ) -> OnboardingPillButtonStyle {
        OnboardingPillButtonStyle(
            size: size,
            isGlassInteractive: isGlassInteractive
        )
    }
    
    public static func onboardingPill(isSecondary: Bool, size: ControlSize = .regular) -> OnboardingPillButtonStyle {
        OnboardingPillButtonStyle(isSecondary: isSecondary, size: size)
    }
}

public enum OnboardingBeamBorderVariant: Equatable {
    case standard
    case featured
    case info
    case success
    case warning
    case destructive

    fileprivate var palette: BeamPalette {
        switch self {
        case .standard:
            return .colorful
        case .featured, .warning, .destructive:
            return .sunset
        case .info, .success:
            return .ocean
        }
    }

    fileprivate var strength: Double {
        switch self {
        case .standard:
            return 0.86
        case .featured, .destructive:
            return 1
        case .info:
            return 0.9
        case .success:
            return 0.92
        case .warning:
            return 0.96
        }
    }
}

public extension View {
    /// Applies Beam's button-sized capsule treatment to prominent pill controls.
    func onboardingBeamBorder(
        variant: OnboardingBeamBorderVariant = .standard,
        active: Bool = true,
        isIntensified: Bool = false,
        includesInteriorGlow: Bool = false
    ) -> some View {
        overlay {
            OnboardingBeamBorder(
                variant: variant,
                active: active,
                isIntensified: isIntensified,
                includesInteriorGlow: includesInteriorGlow
            )
        }
    }
}

private struct OnboardingBeamBorder: View {
    let variant: OnboardingBeamBorderVariant
    let active: Bool
    let isIntensified: Bool
    let includesInteriorGlow: Bool

    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        Capsule()
            .fill(.clear)
            .beam(
                .small,
                palette: variant.palette,
                theme: .dark,
                active: active && controlActiveState != .inactive,
                shape: .capsule,
                strength: min(1, variant.strength * (isIntensified ? 1.12 : 1)),
                lensStrength: includesInteriorGlow ? (isIntensified ? 3 : 2) : 0
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension ButtonStyle where Self == TintedPillButtonStyle {
    public static func tintedPill(
        _ fillColor: Color,
        foreground foregroundColor: Color = .white,
        size: ControlSize = .regular
    ) -> TintedPillButtonStyle {
        TintedPillButtonStyle(fillColor: fillColor, foregroundColor: foregroundColor, size: size)
    }
}

extension ButtonStyle where Self == SortyStandardButtonStyle {
    public static var sortyBordered: SortyStandardButtonStyle {
        SortyStandardButtonStyle()
    }

    public static var sortyProminent: SortyStandardButtonStyle {
        SortyStandardButtonStyle(intent: .primary, isProminent: true)
    }

    public static func sortyBordered(
        intent: SortyButtonIntent = .secondary,
        size: ControlSize = .regular
    ) -> SortyStandardButtonStyle {
        SortyStandardButtonStyle(intent: intent, size: size)
    }

    public static func sortyProminent(
        intent: SortyButtonIntent = .primary,
        size: ControlSize = .regular
    ) -> SortyStandardButtonStyle {
        SortyStandardButtonStyle(intent: intent, isProminent: true, size: size)
    }
}

extension ButtonStyle where Self == SortyPrimaryButtonStyle {
    public static var sortyPrimary: SortyPrimaryButtonStyle { SortyPrimaryButtonStyle() }
    public static func sortyPrimary(isSecondary: Bool = false, size: ControlSize = .regular) -> SortyPrimaryButtonStyle {
        SortyPrimaryButtonStyle(isSecondary: isSecondary, size: size)
    }
}

extension ButtonStyle where Self == SortySecondaryButtonStyle {
    public static var sortySecondary: SortySecondaryButtonStyle { SortySecondaryButtonStyle() }
    public static func sortySecondary(size: ControlSize = .regular, color: Color = .secondary) -> SortySecondaryButtonStyle {
        SortySecondaryButtonStyle(size: size, color: color)
    }
}

extension ButtonStyle where Self == SortyDestructiveButtonStyle {
    public static var sortyDestructive: SortyDestructiveButtonStyle { SortyDestructiveButtonStyle() }
}

extension ButtonStyle where Self == MetalFxPrimaryButtonStyle {
    public static var metalFxPrimary: MetalFxPrimaryButtonStyle { MetalFxPrimaryButtonStyle() }

    public static func metalFxPrimary(
        isPaused: Bool = false,
        usesSubtleIdleBeam: Bool = false
    ) -> MetalFxPrimaryButtonStyle {
        MetalFxPrimaryButtonStyle(isPaused: isPaused, usesSubtleIdleBeam: usesSubtleIdleBeam)
    }
}

extension ButtonStyle where Self == HapticBounceButtonStyle {
    /// Button style that provides haptic feedback and subtle bounce on press
    public static var hapticBounce: HapticBounceButtonStyle {
        HapticBounceButtonStyle()
    }
    
    public static func hapticBounce(_ type: HapticTapModifier.HapticFeedbackType) -> HapticBounceButtonStyle {
        HapticBounceButtonStyle(feedbackType: type)
    }
}

// MARK: - Glossy Call-To-Action Button Style

/// A glossy, sculpted pill button style for prominent call-to-action buttons.
/// Features a raised outer bezel, radial glow center, and glass-like inner highlight.
public struct GlossyCallToActionButtonStyle: ButtonStyle {
    var baseColor: Color
    var size: ControlSize
    var isHovering: Bool

    public init(baseColor: Color, size: ControlSize = .regular, isHovering: Bool = false) {
        self.baseColor = baseColor
        self.size = size
        self.isHovering = isHovering
    }

    private var fontSize: CGFloat {
        switch size {
        case .mini: 12
        case .small: 13
        case .large: 16
        default: 16
        }
    }

    private var hPad: CGFloat {
        switch size {
        case .mini: 16
        case .small: 20
        case .large: 32
        default: 28
        }
    }

    private var vPad: CGFloat {
        switch size {
        case .mini: 8
        case .small: 10
        case .large: 12
        default: 13
        }
    }

    private var bezelInset: CGFloat {
        switch size {
        case .mini: 3
        case .small: 3.5
        case .large: 4.8
        default: 4.5
        }
    }

    public func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed

        configuration.label
            .font(.system(size: fontSize, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .padding(.horizontal, hPad)
            .padding(.vertical, vPad)
            .background {
                ZStack {
                    // 1. Outer bezel — uniform solid darker shade
                    Capsule()
                        .fill(baseColor.opacity(0.55))

                    // 2. Outer bezel 3D emboss — light top edge, dark bottom edge
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.28),
                                    Color.white.opacity(0.08),
                                    Color.clear,
                                    Color.black.opacity(0.15)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )

                    // 3. Outer bezel inner shadow — soft dark edge inside bezel
                    Capsule()
                        .stroke(Color.black.opacity(0.15), lineWidth: 2.5)
                        .blur(radius: 2)
                        .mask(Capsule().padding(1))

                    // 4. Inner capsule — main fill with warm radial gradient
                    Capsule()
                        .fill(baseColor)
                        .padding(bezelInset)

                    // 5. Warm radial glow — bright center fading to darker edges
                    Capsule()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(isHovering ? 0.40 : 0.32),
                                    Color.white.opacity(isHovering ? 0.18 : 0.12),
                                    Color.white.opacity(0.02),
                                    Color.clear
                                ],
                                center: UnitPoint(x: 0.5, y: 0.55),
                                startRadius: 0,
                                endRadius: size == .small ? 70 : (size == .large ? 110 : 100)
                            )
                        )
                        .padding(bezelInset)

                    // 6. Edge darkening — vignette effect on inner capsule edges
                    Capsule()
                        .stroke(
                            Color.black.opacity(pressed ? 0.30 : (size == .large ? 0.10 : 0.14)),
                            lineWidth: size == .small ? 8 : (size == .large ? 9 : 12)
                        )
                        .blur(radius: size == .small ? 6 : (size == .large ? 6 : 8))
                        .mask(Capsule().padding(bezelInset))

                    // 7. Top inner shadow — dark lip at top for inset look, deepens on press
                    Capsule()
                        .stroke(Color.black.opacity(pressed ? 0.30 : (isHovering ? 0.10 : 0.16)), lineWidth: pressed ? 5 : 3)
                        .blur(radius: pressed ? 5 : 3)
                        .mask(Capsule().padding(bezelInset))
                        .mask {
                            VStack(spacing: 0) {
                                Rectangle().frame(height: pressed ? 18 : 12)
                                Spacer()
                            }
                        }

                    // 8. Glass highlight — wide glossy band across top ~45%
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(pressed ? 0.25 : (isHovering ? 0.52 : 0.42)),
                                    Color.white.opacity(pressed ? 0.12 : (isHovering ? 0.28 : 0.20)),
                                    Color.white.opacity(pressed ? 0.02 : (isHovering ? 0.06 : 0.04)),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.65)
                            )
                        )
                        .padding(bezelInset + 0.5)

                    // 9. Bottom inner highlight — subtle light catchlight on lower edge
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.clear,
                                    Color.clear,
                                    Color.white.opacity(isHovering ? 0.20 : 0.10)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: isHovering ? 1.2 : 0.8
                        )
                        .padding(bezelInset)

                    // 10. Prominent inner ring — bright border separating bezel from inner capsule
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isHovering ? 0.55 : 0.45),
                                    Color.white.opacity(isHovering ? 0.30 : 0.22),
                                    Color.white.opacity(isHovering ? 0.22 : 0.15),
                                    Color.white.opacity(isHovering ? 0.28 : 0.18)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.2
                        )
                        .padding(bezelInset)
                }
                .animation(.easeOut(duration: 0.18), value: isHovering)
                .animation(.easeOut(duration: 0.1), value: pressed)
            }
            // Drop shadows — lift on hover, flatten on press
            .shadow(
                color: baseColor.opacity(pressed ? 0.10 : (isHovering ? 0.28 : (size == .large ? 0.18 : 0.25))),
                radius: pressed ? 3 : (isHovering ? 11 : (size == .large ? 6 : 8)),
                y: pressed ? 1 : (isHovering ? 6 : (size == .large ? 4 : 5))
            )
            .shadow(color: Color.black.opacity(pressed ? 0.06 : (isHovering ? 0.14 : 0.10)), radius: pressed ? 1 : (isHovering ? 5 : 3), y: pressed ? 1 : (isHovering ? 3 : 2))
            .scaleEffect(pressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: pressed)
            .animation(.spring(response: 0.22, dampingFraction: 0.84), value: isHovering)
            .onChange(of: pressed) { _, newValue in
                if newValue {
                    HapticFeedbackManager.shared.tap()
                }
            }
    }
}

extension ButtonStyle where Self == GlossyCallToActionButtonStyle {
    public static func glossyCallToAction(
        _ baseColor: Color,
        size: ControlSize = .regular,
        isHovering: Bool = false
    ) -> GlossyCallToActionButtonStyle {
        GlossyCallToActionButtonStyle(baseColor: baseColor, size: size, isHovering: isHovering)
    }
}
