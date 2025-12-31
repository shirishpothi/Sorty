//
//  AnimationUtilities.swift
//  FileOrganizer
//
//  Animation utilities for micro-animations, haptic feedback, and motion effects
//

import SwiftUI
import AppKit

// MARK: - Haptic Feedback Manager

/// Manages haptic feedback for user interactions on macOS
public class HapticFeedbackManager {
    public static let shared = HapticFeedbackManager()

    private init() {}

    /// Performs haptic feedback for button taps and general interactions
    public func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    /// Performs haptic feedback for successful actions
    public func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
    }

    /// Performs haptic feedback for alignment or snapping
    public func alignment() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    /// Performs haptic feedback for errors or warnings
    public func error() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// Performs haptic feedback for selection changes
    public func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
}

// MARK: - Page Transition Styles

/// Custom page transition animation types
public enum PageTransitionStyle {
    case slide
    case fade
    case scale
    case slideUp
    case slideDown

    var insertion: AnyTransition {
        switch self {
        case .slide:
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .fade:
            return .opacity
        case .scale:
            return .asymmetric(
                insertion: .scale(scale: 0.9).combined(with: .opacity),
                removal: .scale(scale: 1.1).combined(with: .opacity)
            )
        case .slideUp:
            return .asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        case .slideDown:
            return .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            )
        }
    }
}

// MARK: - Custom Animations

extension Animation {
    /// Smooth spring animation for page transitions
    public static var pageTransition: Animation {
        .spring(response: 0.35, dampingFraction: 0.85, blendDuration: 0.1)
    }

    /// Bouncy spring animation for modals and sheets
    public static var modalBounce: Animation {
        .spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0.1)
    }

    /// Subtle bounce for interactive elements
    public static var subtleBounce: Animation {
        .spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0)
    }

    /// Quick snap animation for selections
    public static var quickSnap: Animation {
        .spring(response: 0.25, dampingFraction: 0.8, blendDuration: 0)
    }

    /// Loading pulse animation
    public static var loadingPulse: Animation {
        .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }

    /// Smooth ease for general transitions
    public static var smoothEase: Animation {
        .easeInOut(duration: 0.25)
    }
}

// MARK: - View Modifiers

/// Adds haptic feedback on tap
public struct HapticTapModifier: ViewModifier {
    let feedbackType: HapticFeedbackType

    public enum HapticFeedbackType {
        case tap
        case success
        case error
        case selection
    }

    public func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        switch feedbackType {
                        case .tap:
                            HapticFeedbackManager.shared.tap()
                        case .success:
                            HapticFeedbackManager.shared.success()
                        case .error:
                            HapticFeedbackManager.shared.error()
                        case .selection:
                            HapticFeedbackManager.shared.selection()
                        }
                    }
            )
    }
}

/// Adds bounce animation on tap
struct BounceTapModifier: ViewModifier {
    @State private var isPressed = false
    let scale: CGFloat

    init(scale: CGFloat = 0.95) {
        self.scale = scale
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(.subtleBounce, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            HapticFeedbackManager.shared.tap()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

/// Page transition modifier with animation
struct PageTransitionModifier: ViewModifier {
    let style: PageTransitionStyle

    func body(content: Content) -> some View {
        content
            .transition(style.insertion)
            .animation(.pageTransition, value: UUID())
    }
}

/// Modal bounce presentation modifier
struct ModalBounceModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1.0 : 0.8)
            .opacity(appeared ? 1.0 : 0.0)
            .onAppear {
                withAnimation(.modalBounce) {
                    appeared = true
                }
            }
    }
}

/// Loading state animation modifier
struct LoadingAnimationModifier: ViewModifier {
    let isLoading: Bool
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isLoading ? rotation : 0))
            .scaleEffect(isLoading ? scale : 1.0)
            .onChange(of: isLoading) { oldValue, newValue in
                if newValue {
                    withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                    withAnimation(.loadingPulse) {
                        scale = 1.1
                    }
                } else {
                    rotation = 0
                    scale = 1.0
                }
            }
    }
}

/// Pulsing loading indicator modifier
struct PulsingLoadingModifier: ViewModifier {
    let isLoading: Bool
    @State private var opacity: Double = 1.0

    func body(content: Content) -> some View {
        content
            .opacity(isLoading ? opacity : 1.0)
            .onChange(of: isLoading) { oldValue, newValue in
                if newValue {
                    withAnimation(.loadingPulse) {
                        opacity = 0.5
                    }
                } else {
                    opacity = 1.0
                }
            }
    }
}

/// Shimmer loading effect modifier
struct ShimmerModifier: ViewModifier {
    let isLoading: Bool
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if isLoading {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.3),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.5)
                        .offset(x: -geometry.size.width * 0.25 + phase * geometry.size.width * 1.5)
                        .animation(
                            .linear(duration: 1.5).repeatForever(autoreverses: false),
                            value: phase
                        )
                    }
                    .mask(content)
                    .onAppear {
                        phase = 1
                    }
                }
            }
    }
}

/// Animated appearance modifier for list items
struct AnimatedAppearanceModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .offset(y: appeared ? 0 : 20)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay)) {
                    appeared = true
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Adds haptic feedback on tap
    public func hapticFeedback(_ type: HapticTapModifier.HapticFeedbackType = .tap) -> some View {
        modifier(HapticTapModifier(feedbackType: type))
    }

    /// Adds bounce animation and haptic feedback on tap
    public func bounceTap(scale: CGFloat = 0.95) -> some View {
        modifier(BounceTapModifier(scale: scale))
    }

    /// Applies page transition animation
    public func pageTransition(_ style: PageTransitionStyle = .slide) -> some View {
        modifier(PageTransitionModifier(style: style))
    }

    /// Applies modal bounce animation on appear
    public func modalBounce() -> some View {
        modifier(ModalBounceModifier())
    }

    /// Applies loading rotation animation
    public func loadingAnimation(isLoading: Bool) -> some View {
        modifier(LoadingAnimationModifier(isLoading: isLoading))
    }

    /// Applies pulsing loading animation
    public func pulsingLoading(isLoading: Bool) -> some View {
        modifier(PulsingLoadingModifier(isLoading: isLoading))
    }

    /// Applies shimmer loading effect
    public func shimmer(isLoading: Bool) -> some View {
        modifier(ShimmerModifier(isLoading: isLoading))
    }

    /// Applies animated appearance with stagger delay
    public func animatedAppearance(delay: Double = 0) -> some View {
        modifier(AnimatedAppearanceModifier(delay: delay))
    }

    /// Performs action with haptic feedback
    public func withHaptic(action: @escaping () -> Void) -> some View {
        self.onTapGesture {
            HapticFeedbackManager.shared.tap()
            action()
        }
    }
}

// MARK: - Loading Indicator Views

/// Animated loading dots view
public struct LoadingDotsView: View {
    @State private var animatingDot = 0
    let dotCount: Int
    let dotSize: CGFloat
    let color: Color

    public init(dotCount: Int = 3, dotSize: CGFloat = 8, color: Color = .accentColor) {
        self.dotCount = dotCount
        self.dotSize = dotSize
        self.color = color
    }

    public var body: some View {
        HStack(spacing: dotSize * 0.75) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(animatingDot == index ? 1.3 : 0.8)
                    .opacity(animatingDot == index ? 1.0 : 0.5)
            }
        }
        .onAppear {
            startAnimation()
        }
    }

    private func startAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { timer in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                animatingDot = (animatingDot + 1) % dotCount
            }
        }
    }
}

/// Spinning loading indicator with bounce
public struct BouncingSpinner: View {
    @State private var isAnimating = false
    let size: CGFloat
    let color: Color

    public init(size: CGFloat = 24, color: Color = .accentColor) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(color, style: StrokeStyle(lineWidth: size * 0.15, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .scaleEffect(isAnimating ? 1.0 : 0.9)
            .onAppear {
                withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

/// Pulsing ring loading indicator
public struct PulsingRingLoader: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    let size: CGFloat
    let color: Color

    public init(size: CGFloat = 40, color: Color = .accentColor) {
        self.size = size
        self.color = color
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.3), lineWidth: 2)
                .frame(width: size, height: size)

            Circle()
                .stroke(color, lineWidth: 2)
                .frame(width: size, height: size)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.0).repeatForever(autoreverses: false)) {
                        scale = 1.5
                        opacity = 0
                    }
                }
        }
    }
}

// MARK: - Button Styles

/// Button style with haptic feedback and bounce animation
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
                    }
                }
            }
    }
}

extension ButtonStyle where Self == HapticBounceButtonStyle {
    /// Button style that provides haptic feedback and subtle bounce on press
    public static var hapticBounce: HapticBounceButtonStyle {
        HapticBounceButtonStyle()
    }

    /// Button style with success haptic feedback
    public static var hapticSuccess: HapticBounceButtonStyle {
        HapticBounceButtonStyle(feedbackType: .success)
    }
}

// MARK: - Transition Helpers

/// Namespace for commonly used transitions
public enum TransitionStyles {
    public static let slideFromRight = AnyTransition.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    )

    public static let slideFromLeft = AnyTransition.asymmetric(
        insertion: .move(edge: .leading).combined(with: .opacity),
        removal: .move(edge: .trailing).combined(with: .opacity)
    )

    public static let slideFromBottom = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .top).combined(with: .opacity)
    )

    public static let scaleAndFade = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.9).combined(with: .opacity),
        removal: .scale(scale: 0.9).combined(with: .opacity)
    )

    public static let modalPresentation = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.85).combined(with: .opacity),
        removal: .scale(scale: 0.95).combined(with: .opacity)
    )
}
