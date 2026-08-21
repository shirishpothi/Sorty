import AppKit
import CoreImage
import Foundation
import QuartzCore

final class OverlayWindowController: NSWindowController {
    private static let guideSize = NSSize(width: 530, height: 109)
    private static let flightInset: CGFloat = 40
    private static let initialWindowSize = NSSize(width: 610, height: 189)

    private let windowSize = OverlayWindowController.guideSize
    private let flightContentInset = OverlayWindowController.flightInset
    private let launchAnimationDuration: TimeInterval = 0.78
    private let returnAnimationDuration: TimeInterval = 0.6
    private let flightApexLift: CGFloat = 160
    private let maximumFlightBlurRadius: CGFloat = 12
    private let initialAlpha: CGFloat = 0.9
    private let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private let flightContentView: OverlayFlightContentView
    private let flightBlurFilter = CIFilter(name: "CIGaussianBlur")!
    private var launchAnimationTimer: Timer?
    private var launchStartTime: CFTimeInterval = 0
    private var launchFromFrame = NSRect.zero
    private var launchToFrame = NSRect.zero
    private var sourceFrame = NSRect.zero
    private var activeAnimationDuration: TimeInterval = 0.72
    private var isAnimatingLaunch = false
    private var isAnimatingReturn = false
    private var returnCompletion: (() -> Void)?

    init(
        hostApp: PermisoHostApp,
        panel: PermisoPanel,
        onBack: @escaping () -> Void,
        onDrop: @escaping () -> Void,
        onMissingApp: @escaping () -> Void
    ) {
        let window = PassiveOverlayPanel(
            contentRect: NSRect(origin: .zero, size: Self.initialWindowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        flightContentView = OverlayFlightContentView(
            hostApp: hostApp,
            panel: panel,
            contentInset: flightContentInset,
            onBack: onBack,
            onDrop: onDrop,
            onMissingApp: onMissingApp
        )
        super.init(window: window)
        configureWindow(window)
        window.contentView = flightContentView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func close() {
        stopLaunchAnimation()
        window?.orderOut(nil)
        super.close()
    }

    func present(
        from sourceFrameInScreen: CGRect?, sourceSnapshot: NSImage?, settingsFrame: CGRect,
        visibleFrame: CGRect
    ) {
        stopLaunchAnimation()
        guard let window else { return }
        let targetOrigin = anchoredOrigin(for: settingsFrame, visibleFrame: visibleFrame)
        let targetFrame = NSRect(origin: targetOrigin, size: windowSize)

        flightContentView.setSourceSnapshot(sourceSnapshot)

        if reduceMotion {
            sourceFrame = sourceFrameInScreen ?? .zero
            isAnimatingLaunch = false
            isAnimatingReturn = false
            window.alphaValue = 1
            flightContentView.setFlightProgress(1)
            setFlightBlur(radius: 0)
            window.setFrame(windowFrame(containing: targetFrame), display: false)
            window.orderFrontRegardless()
            return
        }

        guard let sourceFrameInScreen, !sourceFrameInScreen.isEmpty else {
            sourceFrame = .zero
            isAnimatingLaunch = false
            isAnimatingReturn = false
            window.alphaValue = 1
            flightContentView.setFlightProgress(1)
            setFlightBlur(radius: 0)
            window.setFrame(windowFrame(containing: targetFrame), display: false)
            window.orderFrontRegardless()
            return
        }

        sourceFrame = sourceFrameInScreen
        isAnimatingLaunch = true
        isAnimatingReturn = false
        activeAnimationDuration = launchAnimationDuration
        launchFromFrame = sourceFrameInScreen
        launchToFrame = targetFrame
        launchStartTime = CACurrentMediaTime()

        window.alphaValue = initialAlpha
        setFlightBlur(radius: 0)
        window.setFrame(windowFrame(containing: sourceFrameInScreen), display: false)
        flightContentView.setFlightProgress(0)
        window.orderFrontRegardless()
        stepLaunchAnimation()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.stepLaunchAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        launchAnimationTimer = timer
    }

    func updatePosition(with settingsFrame: CGRect, visibleFrame: CGRect) {
        guard let window else { return }
        let contentFrame = NSRect(
            origin: anchoredOrigin(for: settingsFrame, visibleFrame: visibleFrame),
            size: windowSize
        )
        launchToFrame = contentFrame
        guard !isAnimatingLaunch else { return }
        window.setFrame(windowFrame(containing: contentFrame), display: false)
        window.orderFrontRegardless()
    }

    func hide() {
        isAnimatingLaunch = false
        isAnimatingReturn = false
        stopLaunchAnimation()
        setFlightBlur(radius: 0)
        window?.orderOut(nil)
    }

    func returnToSource(completion: @escaping () -> Void) {
        stopLaunchAnimation()
        if reduceMotion {
            window?.orderOut(nil)
            completion()
            return
        }
        guard let window, !sourceFrame.isEmpty else {
            completion()
            return
        }

        isAnimatingLaunch = false
        isAnimatingReturn = true
        returnCompletion = completion
        activeAnimationDuration = returnAnimationDuration
        launchFromFrame = contentFrame(for: window.frame)
        launchToFrame = sourceFrame
        launchStartTime = CACurrentMediaTime()
        window.alphaValue = 1
        flightContentView.setFlightProgress(1)
        setFlightBlur(radius: 0)
        window.orderFrontRegardless()
        stepLaunchAnimation()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.stepLaunchAnimation()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        launchAnimationTimer = timer
    }

    private func configureWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .statusBar
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [
            .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary,
        ]
        window.animationBehavior = .none
    }

    private func stepLaunchAnimation() {
        guard let window else {
            stopLaunchAnimation()
            return
        }

        let elapsed = max(0, CACurrentMediaTime() - launchStartTime)
        if elapsed >= activeAnimationDuration {
            let wasReturning = isAnimatingReturn
            let completion = returnCompletion
            isAnimatingLaunch = false
            isAnimatingReturn = false
            returnCompletion = nil
            stopLaunchAnimation()
            window.alphaValue = wasReturning ? initialAlpha : 1
            flightContentView.setFlightProgress(wasReturning ? 0 : 1)
            setFlightBlur(radius: 0)
            window.setFrame(windowFrame(containing: launchToFrame), display: true)
            if wasReturning {
                window.orderOut(nil)
                completion?()
            }
            return
        }

        let timeProgress = CGFloat(min(max(elapsed / activeAnimationDuration, 0), 1))
        let motionProgress = easeInOutCubic(timeProgress)
        if isAnimatingReturn {
            window.alphaValue = 1 - ((1 - initialAlpha) * motionProgress)
            flightContentView.setFlightProgress(1 - motionProgress)
        } else {
            window.alphaValue = initialAlpha + ((1 - initialAlpha) * motionProgress)
            flightContentView.setFlightProgress(motionProgress)
        }
        setFlightBlur(radius: bellBlur(at: timeProgress) * maximumFlightBlurRadius)
        window.setFrame(
            windowFrame(
                containing: curvedFrame(
                    from: launchFromFrame,
                    to: launchToFrame,
                    progress: motionProgress
                )
            ),
            display: true
        )
    }

    private func stopLaunchAnimation() {
        launchAnimationTimer?.invalidate()
        launchAnimationTimer = nil
    }

    private func clampedUnit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    private func bellBlur(at progress: CGFloat) -> CGFloat {
        let clampedProgress = clampedUnit(progress)
        return 4 * clampedProgress * (1 - clampedProgress)
    }

    private func easeInOutCubic(_ progress: CGFloat) -> CGFloat {
        let clampedProgress = clampedUnit(progress)
        if clampedProgress < 0.5 {
            return 4 * clampedProgress * clampedProgress * clampedProgress
        }

        return 1 - pow(-2 * clampedProgress + 2, 3) / 2
    }

    private func setFlightBlur(radius: CGFloat) {
        guard radius > 0 else {
            flightContentView.layer?.filters = nil
            return
        }

        flightBlurFilter.setValue(radius, forKey: kCIInputRadiusKey)
        flightContentView.layer?.filters = [flightBlurFilter]
    }

    private func windowFrame(containing contentFrame: NSRect) -> NSRect {
        contentFrame.insetBy(dx: -flightContentInset, dy: -flightContentInset)
    }

    private func contentFrame(for windowFrame: NSRect) -> NSRect {
        windowFrame.insetBy(dx: flightContentInset, dy: flightContentInset)
    }

    private func curvedFrame(from: NSRect, to: NSRect, progress: CGFloat) -> NSRect {
        let sizeProgress = clampedUnit(progress)
        let pathProgress = clampedUnit(progress)
        let size = NSSize(
            width: from.size.width + ((to.size.width - from.size.width) * sizeProgress),
            height: from.size.height + ((to.size.height - from.size.height) * sizeProgress)
        )

        let startCenter = CGPoint(x: from.midX, y: from.midY)
        let endCenter = CGPoint(x: to.midX, y: to.midY)
        let midPoint = CGPoint(
            x: (startCenter.x + endCenter.x) * 0.5,
            y: max(startCenter.y, endCenter.y)
        )

        let controlPoint = CGPoint(x: midPoint.x, y: midPoint.y + flightApexLift)
        let inverse = 1 - pathProgress
        let center = CGPoint(
            x: (inverse * inverse * startCenter.x) + (2 * inverse * pathProgress * controlPoint.x)
                + (pathProgress * pathProgress * endCenter.x),
            y: (inverse * inverse * startCenter.y) + (2 * inverse * pathProgress * controlPoint.y)
                + (pathProgress * pathProgress * endCenter.y)
        )

        return NSRect(
            x: center.x - (size.width * 0.5),
            y: center.y - (size.height * 0.5),
            width: size.width,
            height: size.height
        )
    }

    private func anchoredOrigin(for settingsFrame: CGRect, visibleFrame: CGRect) -> NSPoint {
        let sidebarWidth: CGFloat = 170
        let contentMinX = settingsFrame.minX + sidebarWidth
        let contentWidth = max(settingsFrame.width - sidebarWidth, windowSize.width)
        let preferredX = contentMinX + ((contentWidth - windowSize.width) / 2) - 8
        let preferredY = settingsFrame.minY + 14
        let minX = visibleFrame.minX + 8
        let maxX = visibleFrame.maxX - windowSize.width - 8
        let minY = visibleFrame.minY + 8
        let maxY = visibleFrame.maxY - windowSize.height - 8

        return NSPoint(
            x: min(max(preferredX, minX), maxX),
            y: min(max(preferredY, minY), maxY)
        )
    }
}

private final class PassiveOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlayFlightContentView: NSView {
    private let liveContentView: OverlayContentView
    private let sourceImageView = NSImageView()
    private let contentContainer = NSView()
    private let contentInset: CGFloat

    init(
        hostApp: PermisoHostApp,
        panel: PermisoPanel,
        contentInset: CGFloat,
        onBack: @escaping () -> Void,
        onDrop: @escaping () -> Void,
        onMissingApp: @escaping () -> Void
    ) {
        self.contentInset = contentInset
        liveContentView = OverlayContentView(
            hostApp: hostApp,
            panel: panel,
            onBack: onBack,
            onDrop: onDrop,
            onMissingApp: onMissingApp
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 530, height: 109))
        translatesAutoresizingMaskIntoConstraints = false
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setSourceSnapshot(_ image: NSImage?) {
        sourceImageView.image = image
        sourceImageView.isHidden = image == nil
        if image == nil {
            liveContentView.alphaValue = 1
            sourceImageView.alphaValue = 0
        } else {
            liveContentView.alphaValue = 0
            sourceImageView.alphaValue = 1
        }
    }

    func setFlightProgress(_ progress: CGFloat) {
        let clampedProgress = min(max(progress, 0), 1)
        guard sourceImageView.image != nil else {
            liveContentView.alphaValue = 1
            sourceImageView.alphaValue = 0
            return
        }

        let crossfade = Self.apexCrossfade(for: clampedProgress)
        sourceImageView.alphaValue = 1 - crossfade
        liveContentView.alphaValue = crossfade
    }

    private func setup() {
        wantsLayer = true

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        sourceImageView.translatesAutoresizingMaskIntoConstraints = false
        sourceImageView.imageAlignment = .alignCenter
        sourceImageView.imageScaling = .scaleProportionallyDown
        sourceImageView.animates = false
        addSubview(contentContainer)
        contentContainer.addSubview(liveContentView)
        contentContainer.addSubview(sourceImageView)

        NSLayoutConstraint.activate([
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInset),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInset),
            contentContainer.topAnchor.constraint(equalTo: topAnchor, constant: contentInset),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInset),

            liveContentView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            liveContentView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            liveContentView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            liveContentView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),

            sourceImageView.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            sourceImageView.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            sourceImageView.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            sourceImageView.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    private static func apexCrossfade(for progress: CGFloat) -> CGFloat {
        if progress <= 0.35 {
            return 0
        }
        if progress >= 0.65 {
            return 1
        }

        let localProgress = (progress - 0.35) / 0.3
        return localProgress * localProgress * (3 - (2 * localProgress))
    }
}

private final class OverlayContentView: NSView {
    private let onBack: () -> Void

    init(
        hostApp: PermisoHostApp,
        panel: PermisoPanel,
        onBack: @escaping () -> Void,
        onDrop: @escaping () -> Void,
        onMissingApp: @escaping () -> Void
    ) {
        self.onBack = onBack
        super.init(frame: NSRect(x: 0, y: 0, width: 530, height: 109))
        translatesAutoresizingMaskIntoConstraints = false
        setup(
            hostApp: hostApp,
            panel: panel,
            onDrop: onDrop,
            onMissingApp: onMissingApp
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup(
        hostApp: PermisoHostApp,
        panel: PermisoPanel,
        onDrop: @escaping () -> Void,
        onMissingApp: @escaping () -> Void
    ) {
        let materialView: NSView
        let usesSystemGlass: Bool

        if #available(macOS 26.0, *) {
            let glassView = NSGlassEffectView()
            glassView.translatesAutoresizingMaskIntoConstraints = false
            glassView.cornerRadius = 22
            glassView.style = .regular
            glassView.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.12)

            let contentView = NSView()
            contentView.wantsLayer = true
            glassView.contentView = contentView
            addSubview(glassView)
            materialView = contentView
            usesSystemGlass = true

            NSLayoutConstraint.activate([
                glassView.leadingAnchor.constraint(equalTo: leadingAnchor),
                glassView.trailingAnchor.constraint(equalTo: trailingAnchor),
                glassView.topAnchor.constraint(equalTo: topAnchor),
                glassView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            let effectView = NSVisualEffectView()
            effectView.translatesAutoresizingMaskIntoConstraints = false
            effectView.material = .popover
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = 18
            effectView.layer?.masksToBounds = true
            effectView.layer?.borderWidth = 0.5
            effectView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.18).cgColor
            addSubview(effectView)
            materialView = effectView
            usesSystemGlass = false

            NSLayoutConstraint.activate([
                effectView.leadingAnchor.constraint(equalTo: leadingAnchor),
                effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
                effectView.topAnchor.constraint(equalTo: topAnchor),
                effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        let tintView = NSView()
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor =
            NSColor.windowBackgroundColor
            .withAlphaComponent(usesSystemGlass ? 0.10 : 0.78)
            .cgColor
        materialView.addSubview(tintView)

        let backChrome = NSView()
        backChrome.translatesAutoresizingMaskIntoConstraints = false
        backChrome.wantsLayer = true
        backChrome.layer?.backgroundColor =
            NSColor.controlBackgroundColor.withAlphaComponent(0.95).cgColor
        backChrome.layer?.cornerRadius = 16
        materialView.addSubview(backChrome)

        let backButton = NSButton()
        backButton.translatesAutoresizingMaskIntoConstraints = false
        backButton.isBordered = false
        backButton.image = NSImage(
            systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.contentTintColor = NSColor.labelColor.withAlphaComponent(0.72)
        backButton.target = self
        backButton.action = #selector(backPressed)
        if let cell = backButton.cell as? NSButtonCell {
            cell.imagePosition = .imageOnly
        }
        backChrome.addSubview(backButton)

        let arrowView = NSImageView()
        arrowView.translatesAutoresizingMaskIntoConstraints = false
        arrowView.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        arrowView.symbolConfiguration = .init(pointSize: 28, weight: .bold)
        arrowView.contentTintColor = NSColor(calibratedRed: 0.15, green: 0.54, blue: 0.98, alpha: 1)
        materialView.addSubview(arrowView)

        let titleLabel = NSTextField(
            labelWithAttributedString: title(hostApp: hostApp, panel: panel))
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.maximumNumberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail
        materialView.addSubview(titleLabel)

        let actionView: NSView
        if panel.supportsAppDrop {
            actionView = AppDragSourceView(hostApp: hostApp) { operation in
                guard operation != [] else { return }
                onDrop()
            }
        } else {
            actionView = PermissionGuideView(
                symbolName: panel.guideSymbol,
                instruction: panel.guideInstruction(appName: hostApp.displayName),
                showsMissingAppHelp: panel == .automation,
                showsNotificationToggle: panel == .notifications,
                onMissingApp: onMissingApp
            )
        }
        materialView.addSubview(actionView)

        let dragCue: PermissionDragCueView?
        if panel.supportsAppDrop {
            let cue = PermissionDragCueView()
            materialView.addSubview(cue)
            dragCue = cue
        } else {
            dragCue = nil
        }

        NSLayoutConstraint.activate([
            tintView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: materialView.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),

            backChrome.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 18),
            backChrome.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 52),
            backChrome.widthAnchor.constraint(equalToConstant: 32),
            backChrome.heightAnchor.constraint(equalToConstant: 32),

            backButton.centerXAnchor.constraint(equalTo: backChrome.centerXAnchor),
            backButton.centerYAnchor.constraint(equalTo: backChrome.centerYAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 14),
            backButton.heightAnchor.constraint(equalToConstant: 14),

            arrowView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 47),
            arrowView.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 10),
            arrowView.widthAnchor.constraint(equalToConstant: 28),
            arrowView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.leadingAnchor.constraint(equalTo: arrowView.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: arrowView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(
                equalTo: materialView.trailingAnchor, constant: -22),

            actionView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor, constant: 64),
            actionView.topAnchor.constraint(equalTo: materialView.topAnchor, constant: 47),
            actionView.heightAnchor.constraint(equalToConstant: 43),
        ])

        if let dragCue {
            NSLayoutConstraint.activate([
                dragCue.leadingAnchor.constraint(equalTo: actionView.trailingAnchor, constant: 12),
                dragCue.trailingAnchor.constraint(equalTo: materialView.trailingAnchor, constant: -21),
                dragCue.centerYAnchor.constraint(equalTo: actionView.centerYAnchor),
                dragCue.widthAnchor.constraint(equalToConstant: 52),
                dragCue.heightAnchor.constraint(equalToConstant: 52),
            ])
        } else {
            actionView.trailingAnchor.constraint(
                equalTo: materialView.trailingAnchor, constant: -21
            ).isActive = true
        }
    }

    private func title(hostApp: PermisoHostApp, panel: PermisoPanel) -> NSAttributedString {
        NSAttributedString(
            string: panel.supportsAppDrop
                ? "Drag \(hostApp.displayName) to the list above to allow \(panel.title)"
                : "Finish allowing \(panel.title) in System Settings",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(0.82),
            ]
        )
    }

    @objc
    private func backPressed() {
        onBack()
    }
}

private final class PermissionDragCueView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let symbol = NSImageView()
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
        symbol.symbolConfiguration = .init(pointSize: 18, weight: .medium)
        symbol.contentTintColor = NSColor.secondaryLabelColor
        addSubview(symbol)

        let label = NSTextField(labelWithString: "Drag")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = NSColor.secondaryLabelColor
        addSubview(label)

        NSLayoutConstraint.activate([
            symbol.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -7),
            symbol.widthAnchor.constraint(equalToConstant: 22),
            symbol.heightAnchor.constraint(equalToConstant: 22),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.topAnchor.constraint(equalTo: symbol.bottomAnchor, constant: -1),
        ])

        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        layer?.backgroundColor = NSColor.white.withAlphaComponent(isDark ? 0.08 : 0.42).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(isDark ? 0.12 : 0.30).cgColor
    }
}

private final class PermissionGuideView: NSView {
    private let onMissingApp: () -> Void

    init(
        symbolName: String,
        instruction: String,
        showsMissingAppHelp: Bool,
        showsNotificationToggle: Bool,
        onMissingApp: @escaping () -> Void
    ) {
        self.onMissingApp = onMissingApp
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.22).cgColor

        let symbol = NSImageView()
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        symbol.symbolConfiguration = .init(pointSize: 15, weight: .semibold)
        symbol.contentTintColor = .controlAccentColor
        addSubview(symbol)

        let label = NSTextField(labelWithString: instruction)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        let missingAppButton = NSButton(
            title: "Sorty isn't listed?",
            target: self,
            action: #selector(missingAppPressed)
        )
        missingAppButton.translatesAutoresizingMaskIntoConstraints = false
        missingAppButton.bezelStyle = .inline
        missingAppButton.font = .systemFont(ofSize: 12, weight: .medium)
        missingAppButton.isHidden = !showsMissingAppHelp
        missingAppButton.setAccessibilityLabel("Get help if Sorty is not listed")
        missingAppButton.setAccessibilityHelp(
            "Returns to Sorty with steps to restore the Automation permission entry."
        )
        addSubview(missingAppButton)

        let notificationToggle = NotificationToggleCueView()
        notificationToggle.isHidden = !showsNotificationToggle
        addSubview(notificationToggle)

        if showsMissingAppHelp {
            setAccessibilityElement(false)
        } else {
            setAccessibilityElement(true)
            setAccessibilityRole(.staticText)
            setAccessibilityLabel(instruction)
        }

        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 22),
            symbol.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        if showsMissingAppHelp {
            NSLayoutConstraint.activate([
                missingAppButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                missingAppButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.trailingAnchor.constraint(
                    lessThanOrEqualTo: missingAppButton.leadingAnchor,
                    constant: -8
                ),
            ])
        }

        if showsNotificationToggle {
            NSLayoutConstraint.activate([
                notificationToggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                notificationToggle.centerYAnchor.constraint(equalTo: centerYAnchor),
                notificationToggle.widthAnchor.constraint(equalToConstant: 60),
                notificationToggle.heightAnchor.constraint(equalToConstant: 36),
                label.trailingAnchor.constraint(
                    lessThanOrEqualTo: notificationToggle.leadingAnchor,
                    constant: -12
                ),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc
    private func missingAppPressed() {
        onMissingApp()
    }
}

private final class NotificationToggleCueView: NSView {
    private let trackLayer = CALayer()
    private let knobLayer = CALayer()
    private let offTrackColor = NSColor.white.withAlphaComponent(0.18).cgColor
    private let onTrackColor = NSColor.systemBlue.cgColor
    private var isOn = false
    private var hasAnimatedInCurrentWindow = false
    private var layoutGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        configureLayers()
        scheduleAnimationAfterLayout()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            trackLayer.removeAllAnimations()
            knobLayer.removeAllAnimations()
            isOn = false
            hasAnimatedInCurrentWindow = false
            layoutGeneration += 1
            return
        }
        configureLayers()
        scheduleAnimationAfterLayout()
    }

    private func configureLayers() {
        guard bounds.width > 0, bounds.height > 0, let layer else { return }

        trackLayer.frame = bounds
        trackLayer.cornerRadius = bounds.height * 0.5
        trackLayer.masksToBounds = true
        trackLayer.backgroundColor = isOn ? onTrackColor : offTrackColor

        let inset: CGFloat = 4
        let knobDiameter = bounds.height - (inset * 2)
        knobLayer.bounds = NSRect(x: 0, y: 0, width: knobDiameter, height: knobDiameter)
        knobLayer.cornerRadius = knobDiameter * 0.5
        knobLayer.backgroundColor = NSColor.white.cgColor
        let knobPositionX = isOn
            ? bounds.width - inset - (knobDiameter * 0.5)
            : inset + (knobDiameter * 0.5)
        knobLayer.position = CGPoint(x: knobPositionX, y: bounds.midY)

        if trackLayer.superlayer == nil {
            layer.addSublayer(trackLayer)
        }
        if knobLayer.superlayer == nil {
            trackLayer.addSublayer(knobLayer)
        }
    }

    private func startAnimationIfReady() {
        guard window != nil, !hasAnimatedInCurrentWindow, bounds.width > 0, bounds.height > 0 else {
            return
        }

        hasAnimatedInCurrentWindow = true
        startAnimation()
    }

    private func scheduleAnimationAfterLayout() {
        guard window != nil, !hasAnimatedInCurrentWindow else { return }

        layoutGeneration += 1
        let generation = layoutGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.layoutGeneration == generation else { return }
            self.startAnimationIfReady()
        }
    }

    private func startAnimation() {
        trackLayer.removeAllAnimations()
        knobLayer.removeAllAnimations()

        let offPositionX = 4 + (knobLayer.bounds.width * 0.5)
        let onPositionX = bounds.width - 4 - (knobLayer.bounds.width * 0.5)

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            isOn = true
            trackLayer.backgroundColor = onTrackColor
            knobLayer.position.x = onPositionX
            return
        }

        isOn = true
        trackLayer.backgroundColor = onTrackColor
        knobLayer.position.x = onPositionX

        let trackAnimation = CABasicAnimation(keyPath: "backgroundColor")
        trackAnimation.fromValue = offTrackColor
        trackAnimation.toValue = onTrackColor
        trackAnimation.duration = 0.24
        trackAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let knobAnimation = CABasicAnimation(keyPath: "position.x")
        knobAnimation.fromValue = offPositionX
        knobAnimation.toValue = onPositionX
        knobAnimation.duration = 0.24
        knobAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        trackLayer.add(trackAnimation, forKey: "notificationToggleTrack")
        knobLayer.add(knobAnimation, forKey: "notificationToggleKnob")
    }
}
