//
//  CompletionStepView.swift
//  Sorty
//
//  Completion step of the onboarding flow
//

import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

@MainActor
private enum CompletionPalette {
    static var accent: Color { SortyDesignSystem.Colors.resolvedAccent }
    static let softRose = Color(red: 1.0, green: 0.48, blue: 0.58)
    static let deepRose = Color(red: 0.42, green: 0.19, blue: 0.25)
    static let shadowRose = Color(red: 0.22, green: 0.10, blue: 0.14)
}

// MARK: - Completion Reveal Blob

/// A vibrant gradient blob that expands from center for the completion celebration
private struct CompletionRevealBlob: NSViewRepresentable {
    @SortyHotReload private var hotReload
    let scale: CGFloat
    let opacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    func makeNSView(context: Context) -> RetainedCompletionRevealBlobView {
        RetainedCompletionRevealBlobView()
    }

    func updateNSView(_ nsView: RetainedCompletionRevealBlobView, context: Context) {
        nsView.update(
            scale: scale,
            opacity: opacity,
            reduceMotion: reduceMotion,
            isActive: controlActiveState != .inactive
        )
    }
}

private struct CompletionRevealBaseGraphic: View {
    @SortyHotReload private var hotReload
    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        CompletionPalette.accent.opacity(0.30),
                        CompletionPalette.softRose.opacity(0.18),
                        CompletionPalette.deepRose.opacity(0.08),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 300
                )
            )
            .frame(width: 600, height: 500)
            .blur(radius: 60)
            .frame(width: 600, height: 520)
            .accessibilityHidden(true)
    }
}

private struct CompletionRevealHighlightGraphic: View {
    @SortyHotReload private var hotReload
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.15),
                        CompletionPalette.accent.opacity(0.16),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 120
                )
            )
            .frame(width: 240, height: 240)
            .blur(radius: 30)
            .frame(width: 600, height: 520)
            .accessibilityHidden(true)
    }
}

private struct CompletionFloatingGlowGraphic: View {
    @SortyHotReload private var hotReload
    var body: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        CompletionPalette.softRose.opacity(0.18),
                        CompletionPalette.accent.opacity(0.12),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 250
                )
            )
            .frame(width: 450, height: 400)
            .blur(radius: 50)
            .frame(width: 570, height: 520)
            .accessibilityHidden(true)
    }
}

/// Rasterizes the two large blurred primitives once, then lets the compositor
/// animate the same reveal scale and opacity without re-rendering their blur.
@MainActor
private final class RetainedCompletionRevealBlobView: NSView {
    private let baseHost = NSHostingView(rootView: CompletionRevealBaseGraphic())
    private let floatingGlow = NSHostingView(rootView: CompletionFloatingGlowGraphic())
    private let highlightHost = NSHostingView(rootView: CompletionRevealHighlightGraphic())
    private var hasConfiguredPresentation = false
    private var targetScale: CGFloat = 0.82
    private var targetOpacity: Float = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)

        baseHost.wantsLayer = true
        baseHost.layer?.shouldRasterize = true
        highlightHost.wantsLayer = true
        highlightHost.layer?.shouldRasterize = true
        floatingGlow.wantsLayer = true
        floatingGlow.layer?.shouldRasterize = true
        addSubview(baseHost)
        addSubview(floatingGlow)
        addSubview(highlightHost)

        applyModelValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        let scale = window?.backingScaleFactor ?? 2
        floatingGlow.layer?.rasterizationScale = scale
        baseHost.layer?.rasterizationScale = scale
        highlightHost.layer?.rasterizationScale = scale
    }

    override func layout() {
        super.layout()
        baseHost.frame = bounds
        floatingGlow.frame = CGRect(
            x: bounds.midX - 285,
            y: bounds.midY - 260,
            width: 570,
            height: 520
        )
        highlightHost.frame = bounds
    }

    func update(
        scale: CGFloat,
        opacity: Double,
        reduceMotion: Bool,
        isActive: Bool
    ) {
        let resolvedScale = reduceMotion ? 1 : scale
        let resolvedOpacity = Float(opacity)
        guard !hasConfiguredPresentation
                || targetScale != resolvedScale
                || targetOpacity != resolvedOpacity else { return }

        let previousOpacity = targetOpacity
        targetScale = resolvedScale
        targetOpacity = resolvedOpacity

        if !hasConfiguredPresentation {
            hasConfiguredPresentation = true
            if resolvedOpacity == 0 {
                applyModelValues()
                return
            }
        }

        if reduceMotion {
            layer?.removeAnimation(forKey: "completionRevealScale")
            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.fromValue = layer?.presentation()?.opacity ?? layer?.opacity ?? 0
            opacityAnimation.toValue = resolvedOpacity
            opacityAnimation.duration = 0.25
            opacityAnimation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(opacityAnimation, forKey: "completionRevealOpacity")
            applyModelValues()
            return
        }

        let isReceding = resolvedOpacity < previousOpacity
        let duration: CFTimeInterval = resolvedOpacity == 0 ? 0.52 : (isReceding ? 0.65 : 0.7)
        let timing = CAMediaTimingFunction(
            name: isReceding ? .easeInEaseOut : .easeOut
        )

        if let layer {
            let fromScale = ((layer.presentation()?.value(forKeyPath: "transform.scale")
                ?? layer.value(forKeyPath: "transform.scale")) as? Double)
                ?? Double(resolvedScale)
            let scaleAnimation = CABasicAnimation(keyPath: "transform.scale")
            scaleAnimation.fromValue = fromScale
            scaleAnimation.toValue = Double(resolvedScale)
            scaleAnimation.duration = duration
            scaleAnimation.timingFunction = timing
            layer.add(scaleAnimation, forKey: "completionRevealScale")

            let opacityAnimation = CABasicAnimation(keyPath: "opacity")
            opacityAnimation.fromValue = layer.presentation()?.opacity ?? layer.opacity
            opacityAnimation.toValue = resolvedOpacity
            opacityAnimation.duration = duration
            opacityAnimation.timingFunction = timing
            layer.add(opacityAnimation, forKey: "completionRevealOpacity")
        }

        applyModelValues()
    }

    private func applyModelValues() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.setValue(targetScale, forKeyPath: "transform.scale")
        layer?.opacity = targetOpacity
        CATransaction.commit()
    }
}

private struct CompletionCelebrationBackdrop: View {
    @SortyHotReload private var hotReload
    let revealScale: CGFloat
    let revealOpacity: Double
    let showParticles: Bool
    let exitTriggered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ZStack {
            if !exitTriggered {
                CompletionRevealBlob(scale: revealScale, opacity: revealOpacity)
                    .frame(width: 600, height: 520)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            RetainedCompletionParticles(
                isVisible: showParticles && !exitTriggered,
                reduceMotion: reduceMotion,
                isActive: controlActiveState != .inactive
            )
            .frame(width: 520, height: 420)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

}

private struct RetainedCompletionParticles: NSViewRepresentable {
    @SortyHotReload private var hotReload
    let isVisible: Bool
    let reduceMotion: Bool
    let isActive: Bool

    func makeNSView(context: Context) -> RetainedCompletionParticlesView {
        RetainedCompletionParticlesView()
    }

    func updateNSView(_ nsView: RetainedCompletionParticlesView, context: Context) {
        nsView.update(
            isVisible: isVisible,
            reduceMotion: reduceMotion,
            isActive: isActive
        )
    }
}

@MainActor
private final class RetainedCompletionParticlesView: NSView {
    private let particleLayers = (0..<7).map { _ in CAShapeLayer() }
    private var isAnimating = false
    private var isPaused = false
    private var lastIsVisible: Bool?
    private var lastReduceMotion: Bool?
    private var lastIsActive: Bool?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        setAccessibilityElement(false)
        particleLayers.forEach {
            $0.fillColor = NSColor.white.withAlphaComponent(0.30).cgColor
            $0.opacity = 0
            layer?.addSublayer($0)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        for (index, particleLayer) in particleLayers.enumerated() {
            let size = 3 + CGFloat((index * 17 + 5) % 30) / 10
            particleLayer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            particleLayer.path = CGPath(ellipseIn: particleLayer.bounds, transform: nil)
            particleLayer.position = CGPoint(
                x: bounds.midX - 200 + CGFloat((index * 137 + 43) % 400),
                y: bounds.midY - 80
            )
        }
    }

    func update(isVisible: Bool, reduceMotion: Bool, isActive: Bool) {
        guard lastIsVisible != isVisible
                || lastReduceMotion != reduceMotion
                || lastIsActive != isActive else { return }
        lastIsVisible = isVisible
        lastReduceMotion = reduceMotion
        lastIsActive = isActive

        if reduceMotion || !isVisible {
            stopAnimating()
        } else if !isAnimating {
            startAnimating()
        }

        if isActive {
            resumeIfNeeded()
        } else {
            pauseIfNeeded()
        }
    }

    private func startAnimating() {
        isAnimating = true
        for (index, particleLayer) in particleLayers.enumerated() {
            let now = particleLayer.convertTime(CACurrentMediaTime(), from: nil)
            let duration = 3 + seededParticleValue(index: index, range: 0...3)
            let travel = CAKeyframeAnimation(keyPath: "transform.translation")
            travel.values = [
                NSValue(point: .zero),
                NSValue(point: CGPoint(x: 12, y: 75)),
                NSValue(point: CGPoint(x: 16, y: 150)),
                NSValue(point: CGPoint(x: 8, y: 225)),
                NSValue(point: CGPoint(x: 0, y: 300))
            ]
            travel.keyTimes = [0, 0.25, 0.5, 0.75, 1]
            travel.beginTime = now + Double(index) * 0.4
            travel.duration = duration
            travel.repeatCount = .infinity
            travel.fillMode = .backwards
            travel.calculationMode = .cubic
            particleLayer.add(travel, forKey: "completionParticleTravel")

            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 0.6, 0.6, 0]
            opacity.keyTimes = [0, 0.12, 0.72, 1]
            opacity.beginTime = now + Double(index) * 0.4
            opacity.duration = duration
            opacity.repeatCount = .infinity
            opacity.fillMode = .backwards
            opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            particleLayer.add(opacity, forKey: "completionParticleOpacity")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            particleLayer.opacity = 0.6
            CATransaction.commit()
        }
    }

    private func stopAnimating() {
        guard isAnimating else { return }
        isAnimating = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        particleLayers.forEach {
            $0.removeAnimation(forKey: "completionParticleTravel")
            $0.removeAnimation(forKey: "completionParticleOpacity")
            $0.opacity = 0
        }
        CATransaction.commit()
    }

    private func pauseIfNeeded() {
        guard isAnimating, !isPaused, let layer else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
        isPaused = true
    }

    private func resumeIfNeeded() {
        guard isPaused, let layer else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        isPaused = false
    }

    private func seededParticleValue(index: Int, range: ClosedRange<Double>) -> Double {
        let value = Double((index * 53 + 17) % 101) / 100
        return range.lowerBound + (range.upperBound - range.lowerBound) * value
    }
}

private struct CompletionHero: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    let showGlowRing: Bool
    let exitTriggered: Bool
    let contentDismissed: Bool
    let isButtonHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CompletionRippleField(
                hasAppeared: hasAppeared,
                showGlowRing: showGlowRing,
                exitTriggered: exitTriggered
            )
            CompletionCheckmarkIcon(
                hasAppeared: hasAppeared,
                isButtonHovered: isButtonHovered
            )
        }
        .opacity(hasAppeared ? 1 : 0)
        .scaleEffect(reduceMotion || hasAppeared ? 1 : 0.9)
        .animation(
            reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.9),
            value: hasAppeared
        )
        .scaleEffect(contentDismissed ? 0.8 : 1.0)
        .opacity(contentDismissed ? 0 : 1)
    }
}

private struct CompletionRippleField: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    let showGlowRing: Bool
    let exitTriggered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        RetainedCompletionHeroEffects(
            isVisible: !exitTriggered && showGlowRing && hasAppeared,
            reduceMotion: reduceMotion,
            isActive: controlActiveState != .inactive
        )
        .frame(width: 240, height: 240)
        .transition(.opacity)
    }
}

private struct CompletionGlowRingGraphic: View {
    @SortyHotReload private var hotReload
    var body: some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        CompletionPalette.softRose.opacity(0.86),
                        CompletionPalette.accent.opacity(0.78),
                        CompletionPalette.deepRose.opacity(0.46),
                        CompletionPalette.softRose.opacity(0.86)
                    ],
                    center: .center
                ),
                lineWidth: 3
            )
            .frame(width: 140, height: 140)
            .blur(radius: 8)
            .frame(width: 180, height: 180)
            .accessibilityHidden(true)
    }
}

private struct RetainedCompletionHeroEffects: NSViewRepresentable {
    @SortyHotReload private var hotReload
    let isVisible: Bool
    let reduceMotion: Bool
    let isActive: Bool

    func makeNSView(context: Context) -> RetainedCompletionHeroEffectsView {
        RetainedCompletionHeroEffectsView()
    }

    func updateNSView(_ nsView: RetainedCompletionHeroEffectsView, context: Context) {
        nsView.update(
            isVisible: isVisible,
            reduceMotion: reduceMotion,
            isActive: isActive
        )
    }
}

@MainActor
private final class RetainedCompletionHeroEffectsView: NSView {
    private let glowHost = NSHostingView(rootView: CompletionGlowRingGraphic())
    private let rippleLayers = (0..<3).map { _ in CAShapeLayer() }
    private var isVisible = false
    private var isAnimating = false
    private var isPaused = false
    private var lastReduceMotion: Bool?
    private var lastIsActive: Bool?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)

        glowHost.wantsLayer = true
        glowHost.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addSubview(glowHost)

        for (index, rippleLayer) in rippleLayers.enumerated() {
            rippleLayer.fillColor = NSColor.clear.cgColor
            rippleLayer.strokeColor = NSColor(
                CompletionPalette.softRose.opacity(0.18 - Double(index) * 0.04)
            ).cgColor
            rippleLayer.lineWidth = 2
            layer?.insertSublayer(rippleLayer, below: glowHost.layer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        glowHost.frame = CGRect(
            x: bounds.midX - 90,
            y: bounds.midY - 90,
            width: 180,
            height: 180
        )
        glowHost.layer?.position = CGPoint(x: bounds.midX, y: bounds.midY)

        for (index, rippleLayer) in rippleLayers.enumerated() {
            let diameter = CGFloat(140 + index * 30)
            let frame = CGRect(
                x: bounds.midX - diameter / 2,
                y: bounds.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            rippleLayer.frame = frame
            rippleLayer.path = CGPath(ellipseIn: rippleLayer.bounds, transform: nil)
        }
    }

    func update(isVisible: Bool, reduceMotion: Bool, isActive: Bool) {
        let visibilityChanged = self.isVisible != isVisible
        let motionChanged = lastReduceMotion != reduceMotion
        let activityChanged = lastIsActive != isActive
        self.isVisible = isVisible
        lastReduceMotion = reduceMotion
        lastIsActive = isActive
        guard visibilityChanged || motionChanged || activityChanged else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glowHost.layer?.opacity = isVisible ? 0.6 : 0
        rippleLayers.forEach { $0.opacity = isVisible && reduceMotion ? 0.10 : 0 }
        CATransaction.commit()

        guard isVisible else {
            stopAnimating()
            return
        }
        guard !reduceMotion else {
            stopAnimating()
            return
        }

        startAnimatingIfNeeded()
        if isActive {
            resumeIfNeeded()
        } else {
            pauseIfNeeded()
        }
    }

    private func startAnimatingIfNeeded() {
        guard !isAnimating else { return }
        isAnimating = true

        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1
        pulse.toValue = 1.15
        pulse.duration = 2
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glowHost.layer?.add(pulse, forKey: "completionGlowPulse")

        for (index, rippleLayer) in rippleLayers.enumerated() {
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.8
            scale.toValue = 1.2

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 1
            opacity.toValue = 0

            let group = CAAnimationGroup()
            group.animations = [scale, opacity]
            group.duration = 1.5
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.3
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            rippleLayer.add(group, forKey: "completionRipple")
        }
    }

    private func stopAnimating() {
        guard isAnimating || isPaused else { return }
        resumeIfNeeded()
        isAnimating = false
        glowHost.layer?.removeAnimation(forKey: "completionGlowPulse")
        rippleLayers.forEach { $0.removeAllAnimations() }
    }

    private func pauseIfNeeded() {
        guard isAnimating, !isPaused, let layer else { return }
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0
        layer.timeOffset = pausedTime
        isPaused = true
    }

    private func resumeIfNeeded() {
        guard isPaused, let layer else { return }
        let pausedTime = layer.timeOffset
        layer.speed = 1
        layer.timeOffset = 0
        layer.beginTime = 0
        layer.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        isPaused = false
    }
}

private struct CompletionCheckmarkIcon: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    let isButtonHovered: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(CompletionPalette.shadowRose.opacity(0.30))
                .frame(width: 118, height: 118)

            Circle()
                .fill(CompletionPalette.softRose)
                .frame(width: 72, height: 72)
                .opacity(isButtonHovered ? 0 : 1)

            ZStack {
                Image(systemName: "checkmark")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(CompletionPalette.deepRose.opacity(0.92))
                    .opacity(isButtonHovered ? 0 : 1)
                    .scaleEffect(isButtonHovered ? 0.72 : 1)
                    .symbolEffect(.bounce, value: reduceMotion ? false : hasAppeared)

                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 88, height: 88)
                    .opacity(isButtonHovered ? 1 : 0)
                    .scaleEffect(isButtonHovered ? 1 : 0.72)
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82),
                value: isButtonHovered
            )
        }
    }
}

private struct CompletionCopy: View {
    @SortyHotReload private var hotReload
    let hasAppeared: Bool
    let contentDismissed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Text("Ready to Organize")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 20)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.2),
                    value: hasAppeared
                )

            Text("Drop in a folder, preview the plan, and undo anything you change.")
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 420)
                .opacity(hasAppeared ? 1 : 0)
                .offset(y: hasAppeared ? 0 : 15)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.4),
                    value: hasAppeared
                )
        }
        .opacity(contentDismissed ? 0 : 1)
        .offset(y: contentDismissed ? 30 : 0)
    }
}

private struct CompletionTipsGrid: View {
    @SortyHotReload private var hotReload
    let tipsAppeared: Bool
    let contentDismissed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 48) {
            VStack(alignment: .leading, spacing: 14) {
                quickTip(icon: "folder.badge.plus", text: "Organize from Finder", delay: 0)
                quickTip(icon: "arrow.uturn.backward", text: "Undo from History", delay: 0.08)
            }
            VStack(alignment: .leading, spacing: 14) {
                quickTip(icon: "keyboard", text: "⌘O opens a folder", delay: 0.04)
                quickTip(icon: "gearshape", text: "Swap models in Settings", delay: 0.12)
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(contentDismissed ? 0 : 1)
        .offset(y: contentDismissed ? 40 : 0)
    }

    private func quickTip(icon: String, text: String, delay: Double) -> some View {
        QuickTipRow(icon: icon, text: text)
            .opacity(tipsAppeared ? 1 : 0)
            .offset(y: tipsAppeared ? 0 : 12)
            .animation(
                reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.85).delay(delay),
                value: tipsAppeared
            )
    }
}

private struct CompletionPrimaryAction: View {
    @SortyHotReload private var hotReload
    let tipsAppeared: Bool
    let contentDismissed: Bool
    let isChecking: Bool
    let action: () -> Void
    let onHoverChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("Start Using Sorty")
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
            }
        }
        .buttonStyle(.sortyPrimary(size: .large))
        .onboardingBeamBorder(variant: .featured, active: !isChecking)
        .keyboardShortcut(.defaultAction)
        .disabled(isChecking)
        .onHover { hovering in
            onHoverChanged(hovering)
        }
        .opacity(tipsAppeared && !contentDismissed ? 1 : 0)
        .offset(y: tipsAppeared ? (contentDismissed ? 50 : 0) : 16)
        .animation(
            reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.85).delay(0.2),
            value: tipsAppeared
        )
        .padding(.top, 6)
        .accessibilityIdentifier("OnboardingCompleteButton")
    }
}

private struct CompletionAnalyticsPreference: View {
    @SortyHotReload private var hotReload
    @Binding var isEnabled: Bool
    @State private var isShowingDetails = false

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: $isEnabled) {
                Text("Share anonymous analytics")
                    .font(.system(size: 13.5, weight: .medium, design: .rounded))
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityIdentifier("OnboardingAnalyticsToggle")

            Button {
                HapticFeedbackManager.shared.tap()
                isShowingDetails.toggle()
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                if hovering {
                    HapticFeedbackManager.shared.selection()
                }
            }
            .help("What anonymous analytics includes")
            .accessibilityLabel("About anonymous analytics")
            .accessibilityIdentifier("OnboardingAnalyticsInfoButton")
            .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
                analyticsDetails
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            CompletionPalette.shadowRose.opacity(0.18),
            in: Capsule()
        )
    }

    private var analyticsDetails: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Anonymous analytics")
                .font(.headline)

            Text("When this is on, Sorty sends limited product and reliability events so we can see which parts of the app are useful and where failures occur.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            detailSection(
                title: "What is included",
                systemImage: "checkmark.circle.fill",
                color: .green,
                text: "Screens and features used; broad actions, outcomes, counts, and timings; app and macOS versions and device category; sanitized errors and crashes with messages and sensitive values redacted."
            )

            detailSection(
                title: "What is never included",
                systemImage: "xmark.circle.fill",
                color: .red,
                text: "Your identity, folder or file names, paths, file contents, prompts, custom instructions, AI responses, API keys, or other credentials. Sorty does not record your screen or keystrokes."
            )

            Text("You can change this at any time in Settings → Advanced. Turning it off stops analytics and clears locally stored analytics data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 390, alignment: .leading)
        .systemLiquidGlassPopover(cornerRadius: 12)
    }

    private func detailSection(
        title: String,
        systemImage: String,
        color: Color,
        text: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Completion Step View

@MainActor
private final class CompletionAudioController {
    static let shared = CompletionAudioController()
    private var player: AVAudioPlayer?
    private var revealAccent: NSSound?
    private var fadeTask: Task<Void, Never>?

    func prepare() async {
        if revealAccent == nil {
            revealAccent = NSSound(named: "Glass")
            revealAccent?.volume = 0.15
        }
        guard player == nil else { return }
        guard let soundURL = resolvedSoundURL() else { return }
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: soundURL, options: .mappedIfSafe)
        }.value
        guard !Task.isCancelled, player == nil, let data else { return }

        preparePlayer(data: data)
    }

    private func prepareSynchronouslyIfNeeded() {
        guard player == nil else { return }
        let soundURL = resolvedSoundURL()
        guard let soundURL else { return }

        do {
            let player = try AVAudioPlayer(contentsOf: soundURL)
            player.numberOfLoops = 0
            player.volume = 0.3
            player.prepareToPlay()
            self.player = player
        } catch {
            print("[CompletionStepView] Failed to prepare Final Onboarding sound: \(error)")
        }
    }

    private func preparePlayer(data: Data) {
        do {
            let player = try AVAudioPlayer(data: data)
            player.numberOfLoops = 0
            player.volume = 0.3
            player.prepareToPlay()
            self.player = player
        } catch {
            print("[CompletionStepView] Failed to prepare Final Onboarding sound: \(error)")
        }
    }

    private func resolvedSoundURL() -> URL? {
        SortyResources.finalOnboardingSoundURL()
            ?? Bundle.main.url(forResource: "Final Onboarding", withExtension: "m4a")
    }

    func play() {
        fadeTask?.cancel()
        fadeTask = nil
        prepareSynchronouslyIfNeeded()
        player?.currentTime = 0
        player?.volume = 0.3
        player?.play()
    }

    func playRevealAccent() {
        if revealAccent == nil {
            revealAccent = NSSound(named: "Glass")
            revealAccent?.volume = 0.15
        }
        revealAccent?.play()
    }

    func fadeOutAndStop(duration: TimeInterval) {
        fadeTask?.cancel()
        guard let player else { return }
        player.setVolume(0, fadeDuration: duration)
        fadeTask = Task { @MainActor [weak self, weak player] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            player?.stop()
            self?.player = nil
            self?.fadeTask = nil
        }
    }
}

@MainActor
enum OnboardingCompletionAudio {
    static func prewarm() async {
        await CompletionAudioController.shared.prepare()
    }
}

@MainActor
private final class CompletionRuntimeController {
    var animationTask: Task<Void, Never>?
}

public struct CompletionStepView: View {
    @SortyHotReload private var hotReload
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var runtimeController = CompletionRuntimeController()

    let providerSetupStatus: ProviderSetupStatus
    let onFinish: () -> Void

    // Entry animation states
    @State private var revealScale: CGFloat = 0.82
    @State private var revealOpacity: Double = 0
    @State private var hasAppeared = false
    @State private var showGlowRing = false
    @State private var showParticles = false
    @State private var tipsAppeared = false
    @State private var isCompletionButtonHovered = false
    @State private var completionHoverTask: Task<Void, Never>?
    @State private var lockedHoverForExit: Bool?

    private let audioController = CompletionAudioController.shared
    @State private var readinessState: ReadinessState = .idle
    @State private var isAnalyticsEnabled = true

    // Exit animation states
    @State private var exitTriggered = false
    @State private var finishTask: Task<Void, Never>?
    @State private var contentDismissed = false

    private enum ReadinessState: Equatable {
        case idle
        case checking
        case failed(String)
    }

    public init(
        providerSetupStatus: ProviderSetupStatus,
        onFinish: @escaping () -> Void
    ) {
        self.providerSetupStatus = providerSetupStatus
        self.onFinish = onFinish
        _isAnalyticsEnabled = State(
            initialValue: AnalyticsManager.shared.consent != .denied
        )
    }

    public var body: some View {
        ZStack {
            CompletionContrastBackdrop()
                .allowsHitTesting(false)

            CompletionCelebrationBackdrop(
                revealScale: revealScale,
                revealOpacity: revealOpacity,
                showParticles: showParticles,
                exitTriggered: exitTriggered
            )

            VStack(spacing: 16) {
                CompletionHero(
                    hasAppeared: hasAppeared,
                    showGlowRing: showGlowRing,
                    exitTriggered: exitTriggered,
                    contentDismissed: contentDismissed,
                    isButtonHovered: lockedHoverForExit ?? isCompletionButtonHovered
                )
                CompletionCopy(hasAppeared: hasAppeared, contentDismissed: contentDismissed)
                CompletionTipsGrid(tipsAppeared: tipsAppeared, contentDismissed: contentDismissed)
                CompletionAnalyticsPreference(isEnabled: $isAnalyticsEnabled)
                    .opacity(tipsAppeared && !contentDismissed ? 1 : 0)
                    .offset(y: tipsAppeared ? (contentDismissed ? 40 : 0) : 12)
                    .animation(
                        reduceMotion
                            ? nil
                            : .spring(response: 0.65, dampingFraction: 0.85).delay(0.16),
                        value: tipsAppeared
                    )
                CompletionPrimaryAction(
                    tipsAppeared: tipsAppeared,
                    contentDismissed: contentDismissed,
                    isChecking: readinessState == .checking,
                    action: verifyAndFinish,
                    onHoverChanged: { isHovered in
                        guard lockedHoverForExit == nil else { return }
                        completionHoverTask?.cancel()
                        // Small enter delay filters a sub-40ms swipe that would
                        // otherwise flash the app icon; leave delay keeps the
                        // exit from jittering when the cursor brushes the edge.
                        let delayMs: Int = isHovered ? 40 : 90
                        completionHoverTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(delayMs))
                            guard !Task.isCancelled else { return }
                            if reduceMotion {
                                isCompletionButtonHovered = isHovered
                            } else {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    isCompletionButtonHovered = isHovered
                                }
                            }
                        }
                    }
                )

                if case .failed(let message) = readinessState {
                    completionFailureCard(message: message)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .accessibilityIdentifier("OnboardingCompletionHealthError")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, 48)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .onAppear(perform: startRevealSequence)
        .onDisappear {
            completionHoverTask?.cancel()
            completionHoverTask = nil
            finishTask?.cancel()
            finishTask = nil
            runtimeController.animationTask?.cancel()
            runtimeController.animationTask = nil
            fadeOutAndStopAudio(duration: 0.25)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Completion Step")
    }

    // MARK: - Reveal Sequence

    private func startRevealSequence() {
        runtimeController.animationTask?.cancel()
        audioController.play()

        // Reveal once and hold the backdrop steady until dismissal.
        revealScale = 1.12
        revealOpacity = 0.3
        hasAppeared = true
        showGlowRing = true
        audioController.playRevealAccent()

        if reduceMotion {
            tipsAppeared = true
            return
        }

        runtimeController.animationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            tipsAppeared = true
            showParticles = true
        }
    }

    private func fadeOutAndStopAudio(duration: TimeInterval) {
        audioController.fadeOutAndStop(duration: duration)
    }

    // MARK: - Exit Transition

    @ViewBuilder
    private func completionFailureCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider check failed")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Text("Retry now, or skip verification and land in provider setup repair before your first organization.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Retry") {
                    verifyAndFinish()
                }
                .buttonStyle(.sortyProminent)
                .controlSize(.small)
                .accessibilityIdentifier("OnboardingCompletionRetryButton")

                Button("Skip for Now") {
                    skipVerificationAndFinish()
                }
                .buttonStyle(.sortyBordered)
                .controlSize(.small)
                .accessibilityIdentifier("OnboardingCompletionSkipButton")
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.orange.opacity(0.035))
        )
        .systemLiquidGlassBackground(cornerRadius: 16, interactive: false)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.orange.opacity(0.15), lineWidth: 1)
        )
    }

    private func verifyAndFinish() {
        let configurationStatus = providerSetupStatus
        guard configurationStatus.isReady else {
            readinessState = .failed(configurationStatus.message)
            HapticFeedbackManager.shared.error()
            return
        }

        // Start the transition immediately — the previous flow blocked on a
        // network round-trip (`testConnection()`) before fading out, which
        // made "Start Using Sorty" feel sluggish/laggy. We now fire the
        // verification in the background; if it fails, the main app surfaces
        // the issue through the existing setup-repair channel.
        readinessState = .idle
        startTransition()

        let viewModel = settingsViewModel
        let state = appState
        Task { @MainActor in
            do {
                try await viewModel.testConnection()
                state.clearSetupRepairState()
            } catch {
                state.startSetupRepair(
                    message: "Sorty could not verify \(viewModel.config.provider.displayName). "
                        + error.localizedDescription,
                    navigateToSettings: false
                )
            }
        }
    }

    private func skipVerificationAndFinish() {
        appState.startSetupRepair(
            message: "Sorty could not verify \(settingsViewModel.config.provider.displayName) during onboarding. Finish provider setup in Settings before organizing files.",
            navigateToSettings: true
        )
        readinessState = .idle
        startTransition()
    }

    private func startTransition() {
        guard !exitTriggered else { return }
        runtimeController.animationTask?.cancel()
        runtimeController.animationTask = nil
        // Lock the hero icon to its current hover state so a click while
        // showing the Sorty app icon doesn't flick back to the checkmark
        // during the exit animation.
        lockedHoverForExit = isCompletionButtonHovered
        if lockedHoverForExit == false, completionHoverTask != nil {
            // Hover-enter was still in its 40ms debounce (raw hover true but
            // delayed state not yet flipped). Treat as hovered so Sorty stays.
            lockedHoverForExit = true
            completionHoverTask?.cancel()
            completionHoverTask = nil
        }
        AnalyticsManager.shared.setConsent(isAnalyticsEnabled ? .granted : .denied)
        let exitDuration = reduceMotion ? 0 : 0.52
        HapticFeedbackManager.shared.success()
        fadeOutAndStopAudio(duration: exitDuration)

        // Let the completed onboarding settle away before the main window
        // appears, rather than replacing the whole experience in one frame.
        withAnimation(reduceMotion ? nil : .easeInOut(duration: exitDuration)) {
            exitTriggered = true
            contentDismissed = true
            showParticles = false
            showGlowRing = false
            revealOpacity = 0
        }

        finishTask?.cancel()
        finishTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(exitDuration))
            guard !Task.isCancelled, exitTriggered else { return }
            onFinish()
        }
    }
}

private struct CompletionContrastBackdrop: View {
    @SortyHotReload private var hotReload
    var body: some View {
        ZStack {
            Color(NSColor.windowBackgroundColor).opacity(0.38)

            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.clear,
                    Color.black.opacity(0.10)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    CompletionPalette.softRose.opacity(0.18),
                    CompletionPalette.accent.opacity(0.08),
                    Color.clear
                ],
                center: UnitPoint(x: 0.50, y: 0.42),
                startRadius: 20,
                endRadius: 520
            )
        }
        .mask(alignment: .top) {
            VStack(spacing: 0) {
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.00),
                        .init(color: Color.black.opacity(0.48), location: 0.36),
                        .init(color: Color.black, location: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 192)

                Color.black
            }
        }
        .ignoresSafeArea()
    }
}

struct QuickTipRow: View {
    @SortyHotReload private var hotReload
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(CompletionPalette.accent.opacity(0.14))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                CompletionPalette.softRose.opacity(0.24),
                                lineWidth: 0.5
                            )
                    )

                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CompletionPalette.softRose)
            }

            Text(text)
                .font(.system(size: 13.5, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    let codexAuthManager = CodexCLIAuthManager()

    CompletionStepView(
        providerSetupStatus: ProviderSetupStatus(
            isReady: true,
            title: "Setup complete",
            message: "Provider is ready."
        ),
        onFinish: {}
    )
        .environmentObject(SettingsViewModel())
        .environmentObject(AppState())
        .environmentObject(codexAuthManager)
}
