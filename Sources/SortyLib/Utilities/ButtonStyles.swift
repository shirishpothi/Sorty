//
//  ButtonStyles.swift
//  Sorty
//
//  Centralized button styles for the application
//

import SwiftUI

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
                                        .init(color: Color.accentColor.opacity(0.85), location: 0),
                                        .init(color: Color.accentColor, location: 0.3),
                                        .init(color: Color.accentColor.opacity(0.95), location: 0.5),
                                        .init(color: Color.accentColor, location: 0.7),
                                        .init(color: Color.accentColor.opacity(0.85), location: 1)
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
    
    public init(isSecondary: Bool = false, size: ControlSize = .regular) {
        self.isSecondary = isSecondary
        self.size = size
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .small ? 13 : 15, weight: .semibold))
            .lineLimit(1)
            .foregroundColor(isSecondary ? .primary : .white)
            .padding(.horizontal, size == .small ? 16 : 22)
            .padding(.vertical, size == .small ? 8 : 10)
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
                                        .init(color: Color.accentColor.opacity(0.85), location: 0),
                                        .init(color: Color.accentColor, location: 0.3),
                                        .init(color: Color.accentColor.opacity(0.95), location: 0.5),
                                        .init(color: Color.accentColor, location: 0.7),
                                        .init(color: Color.accentColor.opacity(0.85), location: 1)
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
            .shadow(
                color: isSecondary
                    ? Color.black.opacity(colorScheme == .dark ? 0.14 : 0.05)
                    : Color.accentColor.opacity(0.3),
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

extension ButtonStyle where Self == OnboardingPillButtonStyle {
    public static var onboardingPill: OnboardingPillButtonStyle { OnboardingPillButtonStyle() }
    public static var onboardingPillSecondary: OnboardingPillButtonStyle { OnboardingPillButtonStyle(isSecondary: true) }
    
    public static func onboardingPill(size: ControlSize) -> OnboardingPillButtonStyle {
        OnboardingPillButtonStyle(size: size)
    }
    
    public static func onboardingPill(isSecondary: Bool, size: ControlSize = .regular) -> OnboardingPillButtonStyle {
        OnboardingPillButtonStyle(isSecondary: isSecondary, size: size)
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

extension ButtonStyle where Self == HapticBounceButtonStyle {
    /// Button style that provides haptic feedback and subtle bounce on press
    public static var hapticBounce: HapticBounceButtonStyle {
        HapticBounceButtonStyle()
    }
    
    public static func hapticBounce(_ type: HapticTapModifier.HapticFeedbackType) -> HapticBounceButtonStyle {
        HapticBounceButtonStyle(feedbackType: type)
    }
}
