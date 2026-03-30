//
//  Constants.swift
//  Sorty
//
//  App-wide constants
//

import Foundation

enum Constants {
    static let appGroupIdentifier = "group.com.sorty.app"
    static let maxPreviewVersions = 5
    static let largeOperationThreshold = 1000
}

extension Notification.Name {
    public static let organizationDidStart = Notification.Name("OrganizationDidStart")
    public static let organizationDidFinish = Notification.Name("OrganizationDidFinish")
    public static let organizationDidRevert = Notification.Name("OrganizationDidRevert")
    public static let forceQuitSorty = Notification.Name("ForceQuitSorty")
    
    /// Triggered when the user requests to delete all usage data
    public static let clearAllUsageData = Notification.Name("clearAllUsageData")
}




import SwiftUI
import AppKit

// MARK: - Haptic Feedback Manager

/// Manages haptic feedback for user interactions on macOS
@MainActor
public class HapticFeedbackManager {
    @MainActor
    public static let shared = HapticFeedbackManager()

    private init() {}

    /// Performs haptic feedback for button taps and general interactions
    public func tap() {
        performEmphasizedPulse()
    }

    /// Performs haptic feedback for successful actions
    public func success() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Performs haptic feedback for alignment or snapping
    public func alignment() {
        performLightAlignmentHaptic()
    }

    /// Performs haptic feedback for errors or warnings
    public func error() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Performs haptic feedback for selection changes
    public func selection() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    /// Performs a subtle light haptic for hover transitions and gentle state changes.
    public func light() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    /// Emits a short two-step pulse that is more perceptible than a single generic tap.
    private func performEmphasizedPulse() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func performLightAlignmentHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }
}

// MARK: - Haptic Sequence Manager

/// Plays timed haptic sequences that follow visual animations (e.g., shimmer left-to-right).
@MainActor
public final class HapticSequenceManager {
    public static let shared = HapticSequenceManager()
    private var activeTask: Task<Void, Never>?
    private var lastWaveStartAt: Date = .distantPast
    
    private init() {}
    
    /// Plays a left-to-right haptic wave that eases forward to mirror shimmer motion.
    public func playShimmerWave(
        tapCount: Int = 5,
        duration: TimeInterval = 0.65,
        minimumInterval: TimeInterval = 0.2
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastWaveStartAt) >= minimumInterval else { return }
        lastWaveStartAt = now

        activeTask?.cancel()
        activeTask = Task { @MainActor in
            let clampedTapCount = max(tapCount, 2)
            var previousEasedPhase = 0.0

            for i in 0..<clampedTapCount {
                guard !Task.isCancelled else { return }

                if i > 0 {
                    let phase = Double(i) / Double(clampedTapCount - 1)
                    let easedPhase = pow(phase, 1.35)
                    let delay = max(0, duration * (easedPhase - previousEasedPhase))
                    previousEasedPhase = easedPhase

                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }

                guard !Task.isCancelled else { return }

                let feedback: NSHapticFeedbackManager.FeedbackPattern =
                    i == clampedTapCount - 1 ? .levelChange : .alignment
                NSHapticFeedbackManager.defaultPerformer.perform(feedback, performanceTime: .now)
            }
        }
    }
    
    /// Plays a single emphasis haptic for a notable UI event (new insight, popup appearing).
    public func playEventPulse() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
    
    public func cancel() {
        activeTask?.cancel()
        activeTask = nil
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
    /// Smooth spring animation for page transitions - subtle
    public static var pageTransition: Animation {
        .easeOut(duration: 0.2)
    }

    /// Bouncy spring animation for modals and sheets - subtle
    public static var modalBounce: Animation {
        .easeOut(duration: 0.2)
    }

    /// Subtle bounce for interactive elements
    public static var subtleBounce: Animation {
        .easeOut(duration: 0.15)
    }

    /// Quick snap animation for selections
    public static var quickSnap: Animation {
        .easeOut(duration: 0.12)
    }

    /// Loading pulse animation
    public static var loadingPulse: Animation {
        .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
    }

    /// Smooth ease for general transitions
    public static var smoothEase: Animation {
        .easeInOut(duration: 0.2)
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
        case light
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
                        case .light:
                            HapticFeedbackManager.shared.light()
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

/// Modal bounce presentation modifier - subtle version
struct ModalBounceModifier: ViewModifier {
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(appeared ? 1.0 : 0.96)
            .opacity(appeared ? 1.0 : 0.5)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2)) {
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

/// Shimmer loading effect modifier with smooth continuous animation
struct ShimmerModifier: ViewModifier {
    let isLoading: Bool
    private let bandWidthRatio: CGFloat = 0.42
    private let shimmerAngle = Angle(degrees: 18)
    private let shimmerSpeed: Double = 1.15

    func body(content: Content) -> some View {
        if isLoading {
            content
                .overlay {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let height = max(geometry.size.height, 1)
                        let bandWidth = width * bandWidthRatio
                        let travelDistance = width + (bandWidth * 2)

                        SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isLoading)) { context in
                            let elapsed = context.date.timeIntervalSinceReferenceDate * shimmerSpeed
                            let progress = elapsed - floor(elapsed)
                            let offsetX = (progress * travelDistance) - bandWidth

                            LinearGradient(
                                colors: [
                                    .clear,
                                    .white.opacity(0.6),
                                    .white.opacity(0.28),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: bandWidth, height: height * 2.2)
                            .rotationEffect(shimmerAngle)
                            .offset(x: offsetX)
                        }
                    }
                }
                .blendMode(.screen)
                .mask(content)
                .drawingGroup(opaque: false)
        } else {
            content
        }
    }
}

/// Text-specific shimmer that preserves base legibility and adds a subtle moving highlight.
struct TextShimmerModifier: ViewModifier {
    let isLoading: Bool
    let phaseOffset: Double
    let intensity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private let bandWidthRatio: CGFloat = 0.46
    private let shimmerAngle = Angle(degrees: 10)
    private let shimmerSpeed: Double = 0.72

    private var clampedIntensity: Double {
        min(max(intensity, 0.5), 2.0)
    }

    func body(content: Content) -> some View {
        if isLoading {
            content
                .overlay {
                    GeometryReader { geometry in
                        let width = max(geometry.size.width, 1)
                        let height = max(geometry.size.height, 1)
                        let bandWidth = width * bandWidthRatio
                        let travelDistance = width + (bandWidth * 2.8)

                        if reduceMotion {
                            LinearGradient(
                                colors: [
                                    .clear,
                                    Color.accentColor.opacity((colorScheme == .dark ? 0.2 : 0.14) * clampedIntensity),
                                    .clear
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: bandWidth * 1.2, height: height * 1.8)
                            .rotationEffect(shimmerAngle)
                            .offset(x: (width - bandWidth) * 0.18)
                        } else {
                            SwiftUI.TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isLoading)) { context in
                                let elapsed = (context.date.timeIntervalSinceReferenceDate + phaseOffset) * shimmerSpeed
                                let progress = elapsed - floor(elapsed)
                                let easedProgress = progress * progress * (3 - (2 * progress))
                                let offsetX = (easedProgress * travelDistance) - (bandWidth * 1.2)
                                let pulse = (sin(elapsed * 1.3) + 1) * 0.5

                                let accentBase = (colorScheme == .dark ? 0.14 : 0.10) * clampedIntensity
                                let accentRange = (colorScheme == .dark ? 0.14 : 0.12) * clampedIntensity
                                let whiteBase = (colorScheme == .dark ? 0.24 : 0.17) * clampedIntensity
                                let whiteRange = (colorScheme == .dark ? 0.22 : 0.16) * clampedIntensity

                                let accentGlow = min(accentBase + (pulse * accentRange), 0.68)
                                let whiteGlow = min(whiteBase + (pulse * whiteRange), 0.9)

                                ZStack(alignment: .leading) {
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            Color.accentColor.opacity(accentGlow * 0.45),
                                            .white.opacity(whiteGlow * 0.78),
                                            .white.opacity(whiteGlow),
                                            .white.opacity(whiteGlow * 0.72),
                                            Color.accentColor.opacity(accentGlow * 0.6),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: bandWidth, height: height * 2.2)
                                    .rotationEffect(shimmerAngle)
                                    .offset(x: offsetX)
                                    .blendMode(.plusLighter)

                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(min(whiteGlow * 1.15, 1)),
                                            .white.opacity(min(whiteGlow * 0.82, 1)),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: bandWidth * 0.58, height: height * 2.2)
                                    .rotationEffect(shimmerAngle)
                                    .offset(x: offsetX - (bandWidth * 0.12))
                                    .blur(radius: 1.1)
                                    .blendMode(.plusLighter)
                                }
                            }
                        }
                    }
                }
                .mask(content)
                .drawingGroup(opaque: false)
        } else {
            content
        }
    }
}

/// Animated appearance modifier for list items - subtle version
struct AnimatedAppearanceModifier: ViewModifier {
    let delay: Double
    @State private var appeared = false

    func body(content: Content) -> some View {
        content
            .offset(y: appeared ? 0 : 8)
            .opacity(appeared ? 1 : 0.4)
            .onAppear {
                withAnimation(.easeOut(duration: 0.2).delay(delay)) {
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

    /// Applies a subtle shimmer optimized for text legibility.
    public func textShimmer(isLoading: Bool, phaseOffset: Double = 0, intensity: Double = 1.0) -> some View {
        modifier(TextShimmerModifier(isLoading: isLoading, phaseOffset: phaseOffset, intensity: intensity))
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

// MARK: - Transition Helpers

/// Namespace for commonly used transitions - subtle versions
@MainActor
public enum TransitionStyles {
    @MainActor
    public static let slideFromRight = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(x: 20)),
        removal: .opacity.combined(with: .offset(x: -20))
    )

    public static let slideFromLeft = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(x: -20)),
        removal: .opacity.combined(with: .offset(x: 20))
    )

    public static let slideFromBottom = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 15)),
        removal: .opacity.combined(with: .offset(y: -15))
    )

    public static let scaleAndFade = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.97).combined(with: .opacity),
        removal: .scale(scale: 0.97).combined(with: .opacity)
    )


    public static let modalPresentation = AnyTransition.asymmetric(
        insertion: .scale(scale: 0.95).combined(with: .opacity),
        removal: .scale(scale: 0.98).combined(with: .opacity)
    )
}

// MARK: - Loading Indicator Views

/// Animated loading dots view
public struct LoadingDotsView: View {
    let dotCount: Int
    let dotSize: CGFloat
    let color: Color
    let speed: Double

    public init(dotCount: Int = 3, dotSize: CGFloat = 8, color: Color = .accentColor, speed: Double = 2.4) {
        self.dotCount = dotCount
        self.dotSize = dotSize
        self.color = color
        self.speed = speed
    }

    public var body: some View {
        SwiftUI.TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: dotSize * 0.75) {
                ForEach(0..<dotCount, id: \.self) { index in
                    let phase = time * speed + (Double(index) * 0.85)
                    let wave = (sin(phase) + 1) / 2
                    Circle()
                        .fill(color)
                        .frame(width: dotSize, height: dotSize)
                        .scaleEffect(0.7 + (0.6 * wave))
                        .opacity(0.35 + (0.65 * wave))
                }
            }
            .accessibilityHidden(true)
        }
        .drawingGroup(opaque: false)
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

/// Bouncing dots animation for AI reasoning indicator
public struct BouncingDotsView: View {
    @State private var animationPhase: Int = 0
    
    public init() {}
    
    public var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 0.15)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = time * 5 + Double(index) * 0.8
                    let offset = sin(phase) * 3
                    Circle()
                        .fill(Color.purple.opacity(0.6))
                        .frame(width: 4, height: 4)
                        .offset(y: offset)
                }
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
