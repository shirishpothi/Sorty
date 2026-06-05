//
//  SortyDesignSystem.swift
//  Sorty
//
//  Centralized design system for consistent theming across the app
//

import SwiftUI

// MARK: - Design System Namespace
@MainActor
public enum SortyDesignSystem {
    
    // MARK: - Animation Constants
    public enum Animation {
        // Durations
        public static let quick: Double = 0.15
        public static let standard: Double = 0.3
        public static let slow: Double = 0.5
        public static let pageTransition: Double = 0.35
        
        // Spring configurations
        public static let springStandard = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
        public static let springBouncy = SwiftUI.Animation.spring(response: 0.6, dampingFraction: 0.7)
        public static let springSnappy = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.9)
        
        // Stagger delays for sequential animations
        public static let staggerDelay: Double = 0.05
        public static let staggerDelayMedium: Double = 0.1
        public static let staggerDelaySlow: Double = 0.15
        
        // Easing curves
        public static let easeStandard = SwiftUI.Animation.easeInOut(duration: standard)
        public static let easeQuick = SwiftUI.Animation.easeOut(duration: quick)
    }
    
    // MARK: - Colors
    public enum Colors {
        /// Sorty brand accent.
        /// Adapts between light and dark appearances.
        public static let accent: Color = {
            let light = Color(red: 0.180, green: 0.616, blue: 0.361)
            let dark  = Color(red: 0.224, green: 0.714, blue: 0.427)
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return isDark ? NSColor(dark) : NSColor(light)
            })
        }()

        // Brand colors
        public static var primary: Color { resolvedAccent }
        public static let purple = Color.purple
        public static let purpleLight = Color.purple.opacity(0.1)
        public static let blue = Color.blue
        public static let blueLight = Color.blue.opacity(0.1)
        public static let green = Color.green
        public static let greenLight = Color.green.opacity(0.1)
        public static let orange = Color.orange
        public static let orangeLight = Color.orange.opacity(0.1)
        public static let red = Color.red
        public static let redLight = Color.red.opacity(0.1)
        
        // Semantic colors
        public static let success = Color.green
        public static let warning = Color.orange
        public static let error = Color.red
        public static let info = Color.blue
        
        // Background colors (macOS adaptive)
        public static let backgroundPrimary = Color(NSColor.windowBackgroundColor)
        public static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
        public static let backgroundTertiary = Color(NSColor.textBackgroundColor)
        
        // Text colors
        public static let textPrimary = Color.primary
        public static let textSecondary = Color.secondary
        public static let textTertiary = Color(NSColor.tertiaryLabelColor)
        
        // Overlay colors
        public static let glassBackground = Color.white.opacity(0.1)
        public static let glassBorder = Color.white.opacity(0.2)
        public static let overlayLight = Color.black.opacity(0.05)
        public static let overlayMedium = Color.black.opacity(0.1)

        /// Returns the system accent color when the user has chosen a specific
        /// accent in System Settings, or Sorty's custom brand accent when the
        /// system is set to "Multicolor" (the default).
        ///
        /// macOS stores the user's choice in `AppleAccentColor` in the global
        /// domain. The values are:
        ///   • absent  — historical "Multicolor" representation
        ///   • -1      — Graphite (older macOS used this for Multicolor too)
        ///   • -2      — "Multicolor" on macOS Sonoma+ (the default)
        ///   •  0..6   — a specific accent (Red, Orange, Yellow, Green, Blue,
        ///              Purple, Pink)
        ///
        /// We treat any of the "Multicolor" representations as the trigger to
        /// fall back to Sorty's brand accent. Any explicit color chosen by the
        /// user is respected via the live system accent.
        public static var resolvedAccent: Color {
            let raw = UserDefaults.standard.object(forKey: "AppleAccentColor")
            if let value = raw as? Int, value >= 0 {
                // User picked a specific accent (Red/Orange/Yellow/Green/Blue/
                // Purple/Pink) — respect it via SwiftUI's live accent color.
                // Avoid NSColor.controlAccentColor here; on macOS it can make
                // SwiftUI ignore the app's asset-catalog accent in Multicolor.
                return .accentColor
            }
            // Multicolor (absent / -1 / -2) — enforce Sorty's brand accent.
            return accent
        }
    }
    
    // MARK: - Typography
    public enum Typography {
        // Font sizes
        public static let sizeCaption2: CGFloat = 10
        public static let sizeCaption: CGFloat = 12
        public static let sizeSubheadline: CGFloat = 13
        public static let sizeBody: CGFloat = 14
        public static let sizeHeadline: CGFloat = 15
        public static let sizeTitle3: CGFloat = 18
        public static let sizeTitle2: CGFloat = 22
        public static let sizeTitle: CGFloat = 28
        public static let sizeLargeTitle: CGFloat = 36
        
        // Font weights
        public static let weightRegular = Font.Weight.regular
        public static let weightMedium = Font.Weight.medium
        public static let weightSemibold = Font.Weight.semibold
        public static let weightBold = Font.Weight.bold
        
        // Standard font styles
        public static func caption2(weight: Font.Weight = .regular) -> Font {
            .system(size: sizeCaption2, weight: weight)
        }
        
        public static func caption(weight: Font.Weight = .regular) -> Font {
            .system(size: sizeCaption, weight: weight)
        }
        
        public static func subheadline(weight: Font.Weight = .regular) -> Font {
            .system(size: sizeSubheadline, weight: weight)
        }
        
        public static func body(weight: Font.Weight = .regular) -> Font {
            .system(size: sizeBody, weight: weight)
        }
        
        public static func headline(weight: Font.Weight = .semibold) -> Font {
            .system(size: sizeHeadline, weight: weight)
        }
        
        public static func title3(weight: Font.Weight = .semibold) -> Font {
            .system(size: sizeTitle3, weight: weight)
        }
        
        public static func title2(weight: Font.Weight = .bold) -> Font {
            .system(size: sizeTitle2, weight: weight)
        }
        
        public static func title(weight: Font.Weight = .bold) -> Font {
            .system(size: sizeTitle, weight: weight, design: .rounded)
        }
        
        public static func largeTitle(weight: Font.Weight = .bold) -> Font {
            .system(size: sizeLargeTitle, weight: weight, design: .rounded)
        }
        
        // Monospaced for data
        public static func mono(size: CGFloat = sizeBody) -> Font {
            .system(size: size, design: .monospaced)
        }
    }
    
    // MARK: - Spacing
    public enum Spacing {
        // Micro spacing
        public static let xxxs: CGFloat = 2
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 6
        
        // Standard spacing
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
        public static let xxxxl: CGFloat = 40
        
        // Section spacing
        public static let sectionSmall: CGFloat = 20
        public static let sectionMedium: CGFloat = 28
        public static let sectionLarge: CGFloat = 36
    }
    
    // MARK: - Sizing
    public enum Sizing {
        // Icon sizes
        public static let iconSmall: CGFloat = 12
        public static let iconMedium: CGFloat = 16
        public static let iconLarge: CGFloat = 20
        public static let iconXLarge: CGFloat = 24
        public static let iconXXLarge: CGFloat = 32
        public static let iconHuge: CGFloat = 48
        
        // Button sizes
        public static let buttonHeightSmall: CGFloat = 24
        public static let buttonHeightMedium: CGFloat = 32
        public static let buttonHeightLarge: CGFloat = 40
        
        // Card sizes
        public static let cardCornerRadius: CGFloat = 12
        public static let cardPadding: CGFloat = 16
        public static let cardMinWidth: CGFloat = 200
        
        // Window sizes
        public static let windowMinWidth: CGFloat = 1000
        public static let windowMinHeight: CGFloat = 700
        public static let windowOnboardingWidth: CGFloat = 1000
        public static let windowOnboardingHeight: CGFloat = 720
    }
    
    // MARK: - Shadows
    public enum Shadows {
        public static let small = ShadowStyle(color: .black, radius: 2, x: 0, y: 1)
        public static let medium = ShadowStyle(color: .black, radius: 5, x: 0, y: 2)
        public static let large = ShadowStyle(color: .black, radius: 12, x: 0, y: 4)
        
        public struct ShadowStyle: Sendable {
            let color: Color
            let radius: CGFloat
            let x: CGFloat
            let y: CGFloat
            let opacity: Double
            
            init(color: Color, radius: CGFloat, x: CGFloat, y: CGFloat, opacity: Double = 0.15) {
                self.color = color
                self.radius = radius
                self.x = x
                self.y = y
                self.opacity = opacity
            }
        }
        
        public struct ShadowModifier: ViewModifier {
            let style: ShadowStyle
            
            public func body(content: Content) -> some View {
                content
                    .shadow(
                        color: style.color.opacity(style.opacity),
                        radius: style.radius,
                        x: style.x,
                        y: style.y
                    )
            }
        }
    }
    
    // MARK: - Card Styles
    public enum CardStyles {
        // Material styles
        public static let standard = CardStyle(
            backgroundColor: Color(NSColor.controlBackgroundColor),
            cornerRadius: Sizing.cardCornerRadius,
            strokeColor: Colors.glassBorder,
            strokeWidth: 1,
            padding: Sizing.cardPadding,
            useUltraThinMaterial: true
        )
        
        public static let filled = CardStyle(
            backgroundColor: Color(NSColor.controlBackgroundColor),
            cornerRadius: Sizing.cardCornerRadius,
            strokeColor: Color(NSColor.separatorColor),
            strokeWidth: 1,
            padding: Sizing.cardPadding,
            useUltraThinMaterial: false
        )
        
        public static let elevated = CardStyle(
            backgroundColor: Color(NSColor.controlBackgroundColor),
            cornerRadius: Sizing.cardCornerRadius,
            strokeColor: Color.clear,
            strokeWidth: 0,
            padding: Sizing.cardPadding,
            useUltraThinMaterial: false,
            hasShadow: true
        )
        
        public static let subtle = CardStyle(
            backgroundColor: Colors.overlayLight,
            cornerRadius: 8,
            strokeColor: Color.clear,
            strokeWidth: 0,
            padding: Spacing.md,
            useUltraThinMaterial: false
        )
        
        public struct CardStyle: Sendable {
            let backgroundColor: Color
            let cornerRadius: CGFloat
            let strokeColor: Color
            let strokeWidth: CGFloat
            let padding: CGFloat
            let useUltraThinMaterial: Bool
            let hasShadow: Bool
            
            init(
                backgroundColor: Color,
                cornerRadius: CGFloat,
                strokeColor: Color,
                strokeWidth: CGFloat,
                padding: CGFloat,
                useUltraThinMaterial: Bool = false,
                hasShadow: Bool = false
            ) {
                self.backgroundColor = backgroundColor
                self.cornerRadius = cornerRadius
                self.strokeColor = strokeColor
                self.strokeWidth = strokeWidth
                self.padding = padding
                self.useUltraThinMaterial = useUltraThinMaterial
                self.hasShadow = hasShadow
            }
        }
    }
    
    // MARK: - Border Radius
    public enum Radius {
        public static let none: CGFloat = 0
        public static let small: CGFloat = 4
        public static let medium: CGFloat = 8
        public static let large: CGFloat = 12
        public static let xLarge: CGFloat = 16
        public static let circle: CGFloat = 9999
    }
    
    // MARK: - Opacity
    public enum Opacity {
        public static let disabled: Double = 0.5
        public static let subtle: Double = 0.3
        public static let light: Double = 0.6
        public static let medium: Double = 0.8
        public static let full: Double = 1.0
    }
}

// MARK: - Reusable Design System Components

public struct ExamplePill: View {
    let text: String
    let action: () -> Void
    @State private var isHovered = false
    
    public init(text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .baselineOffset(0)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(minHeight: 22)
                .background(isHovered ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.15) : Color.primary.opacity(0.05))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(isHovered ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - View Extensions for Design System
public extension View {
    /// Apply a card style from the design system
    @ViewBuilder
    func sortyCardStyle(_ style: SortyDesignSystem.CardStyles.CardStyle = SortyDesignSystem.CardStyles.standard) -> some View {
        if style.useUltraThinMaterial {
            self
                .padding(style.padding)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .stroke(style.strokeColor, lineWidth: style.strokeWidth)
                )
        } else {
            self
                .padding(style.padding)
                .background(style.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: style.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: style.cornerRadius)
                        .stroke(style.strokeColor, lineWidth: style.strokeWidth)
                )
        }
    }
    
    /// Apply a shadow from the design system
    func sortyShadow(_ shadow: SortyDesignSystem.Shadows.ShadowStyle = SortyDesignSystem.Shadows.medium) -> some View {
        self.modifier(SortyDesignSystem.Shadows.ShadowModifier(style: shadow))
    }
}

// MARK: - Animation Extensions
public extension Animation {
    static var sortySpringStandard: Animation { SortyDesignSystem.Animation.springStandard }
    static var sortySpringBouncy: Animation { SortyDesignSystem.Animation.springBouncy }
    static var sortySpringSnappy: Animation { SortyDesignSystem.Animation.springSnappy }
    static var sortyPageTransition: Animation { .spring(response: 0.3, dampingFraction: 0.88) }
}

// MARK: - Transition Extensions
public extension AnyTransition {
    static var sortyScaleAndFade: AnyTransition {
        .opacity
    }
    
    static var sortySlideFromRight: AnyTransition {
        .opacity
    }
    
    static var sortySlideFromLeft: AnyTransition {
        .opacity
    }
    
    static var sortySlideFromBottom: AnyTransition {
        .opacity
    }
    
    static var sortyModal: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.97).combined(with: .opacity),
            removal: .scale(scale: 0.97).combined(with: .opacity)
        )
    }
}
