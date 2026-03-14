//
//  TrafficLightUpdateButton.swift
//  Sorty
//
//  Orange traffic-light style button in the title bar next to the traffic lights.
//  Release builds: appears only when a Sparkle update is available.
//  Debug builds: always visible as a "REBUILD" button that triggers `make now`.
//

import SwiftUI
import AppKit
import Combine

/// An orange traffic-light style control that appears in the title bar right
/// after the standard window buttons.
public struct TrafficLightUpdateButton: NSViewRepresentable {
    @ObservedObject var updateManager: SparkleUpdateManager

    public init(updateManager: SparkleUpdateManager) {
        self.updateManager = updateManager
    }

    public func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.async {
            guard let window = container.window else { return }
            context.coordinator.install(in: window, updateManager: updateManager)
        }
        return container
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateVisibility(for: updateManager.updateState)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject {
        private var buttonView: UpdateButtonNSView?
        private weak var installedWindow: NSWindow?

        func install(in window: NSWindow, updateManager: SparkleUpdateManager) {
            guard installedWindow !== window else { return }
            installedWindow = window

            guard let titlebarContainer = window.standardWindowButton(.closeButton)?.superview else { return }

            let button = UpdateButtonNSView(updateManager: updateManager)
            button.translatesAutoresizingMaskIntoConstraints = false
            titlebarContainer.addSubview(button)

            // Position right after the zoom (green) traffic-light button
            if let zoomButton = window.standardWindowButton(.zoomButton),
               let closeButton = window.standardWindowButton(.closeButton) {
                NSLayoutConstraint.activate([
                    button.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
                    button.leadingAnchor.constraint(equalTo: zoomButton.trailingAnchor, constant: 8),
                ])
            }

            self.buttonView = button
            updateVisibility(for: updateManager.updateState)
        }

        func updateVisibility(for state: SparkleUpdateManager.UpdateState) {
            guard let buttonView else { return }
            #if DEBUG
            buttonView.isHidden = false
            #else
            switch state {
            case .available:
                buttonView.isHidden = false
            default:
                buttonView.isHidden = true
            }
            #endif
        }
    }
}

// MARK: - AppKit Button View

final class UpdateButtonNSView: NSView {
    private weak var updateManager: SparkleUpdateManager?

    private let fillLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let arrowLayer = CAShapeLayer()
    private let spinnerLayer = CAShapeLayer()
    private let textLayer = CATextLayer()

    private let labelFont = NSFont.systemFont(ofSize: 8.4, weight: .bold)
    private let iconToTextSpacing: CGFloat = 5
    private let horizontalPadding: CGFloat = 7
    private let arrowOpticalOffsetY: CGFloat = -0.2
    private var widthConstraint: NSLayoutConstraint?
    private var isHovered = false
    private var isPressed = false
    private var isWindowFocused = false
    private var isRebuilding = false
    private var trackingArea: NSTrackingArea?
    private var windowFocusObservations: [NSObjectProtocol] = []
    private var rebuildStateCancellable: AnyCancellable?

    private let buttonDiameter: CGFloat = 14
    private let collapsedPillWidth: CGFloat = 14

    private let normalFillColor = NSColor.clear
    private let hoverFillColor  = NSColor(red: 0.91, green: 0.58, blue: 0.30, alpha: 1.0)
    private let pressedFillColor = NSColor(red: 0.79, green: 0.43, blue: 0.19, alpha: 1.0)

    private let normalBorderColor = NSColor(red: 0.76, green: 0.49, blue: 0.24, alpha: 1.0)
    private let hoverBorderColor  = NSColor(red: 0.70, green: 0.38, blue: 0.15, alpha: 1.0)
    private let pressedBorderColor = NSColor(red: 0.54, green: 0.27, blue: 0.09, alpha: 1.0)

    private let normalArrowColor = NSColor(red: 0.76, green: 0.49, blue: 0.24, alpha: 1.0)
    private let hoverArrowColor = NSColor.white

    private let normalHighlightColor = NSColor.clear
    private let hoverHighlightColor  = NSColor(calibratedWhite: 1.0, alpha: 0.38)
    private let pressedHighlightColor = NSColor(calibratedWhite: 1.0, alpha: 0.18)

    #if DEBUG
    private let idleLabelText = "REBUILD"
    private let rebuildingLabelText = "BUILDING"
    #else
    private let idleLabelText = "UPDATE"
    private let rebuildingLabelText = "UPDATING"
    #endif

    private var labelText: String {
        isRebuilding ? rebuildingLabelText : idleLabelText
    }

    private lazy var expandedPillWidth: CGFloat = {
        let idleTextWidth = (idleLabelText as NSString).size(withAttributes: [.font: labelFont]).width
        let rebuildingTextWidth = (rebuildingLabelText as NSString).size(withAttributes: [.font: labelFont]).width
        let measuredTextWidth = max(idleTextWidth, rebuildingTextWidth)
        let iconWidth: CGFloat = 7
        return ceil(horizontalPadding + iconWidth + iconToTextSpacing + measuredTextWidth + horizontalPadding)
    }()

    init(updateManager: SparkleUpdateManager) {
        self.updateManager = updateManager
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        setupLayers()
        setupRebuildObservation()

        let widthConstraint = widthAnchor.constraint(equalToConstant: collapsedPillWidth)
        self.widthConstraint = widthConstraint

        NSLayoutConstraint.activate([
            widthConstraint,
            heightAnchor.constraint(equalToConstant: buttonDiameter),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        removeWindowFocusObservation()
    }

    // MARK: Setup

    private func setupLayers() {
        fillLayer.backgroundColor = normalFillColor.cgColor
        layer?.addSublayer(fillLayer)

        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        borderLayer.strokeColor = normalBorderColor.cgColor
        layer?.addSublayer(borderLayer)

        highlightLayer.fillColor = nil
        highlightLayer.lineWidth = 1
        highlightLayer.strokeColor = normalHighlightColor.cgColor
        layer?.addSublayer(highlightLayer)

        // Down-arrow icon
        let arrowPath = CGMutablePath()
        arrowPath.move(to: CGPoint(x: 0, y: 2.3))
        arrowPath.addLine(to: CGPoint(x: 0, y: -2.3))
        arrowPath.move(to: CGPoint(x: -1.9, y: -0.3))
        arrowPath.addLine(to: CGPoint(x: 0, y: -2.3))
        arrowPath.addLine(to: CGPoint(x: 1.9, y: -0.3))

        arrowLayer.path = arrowPath
        arrowLayer.strokeColor = normalArrowColor.cgColor
        arrowLayer.fillColor = nil
        arrowLayer.lineWidth = 1.5
        arrowLayer.lineCap = .round
        arrowLayer.lineJoin = .round
        layer?.addSublayer(arrowLayer)

        spinnerLayer.fillColor = nil
        spinnerLayer.lineWidth = 1.45
        spinnerLayer.lineCap = .round
        spinnerLayer.strokeColor = NSColor.white.cgColor
        spinnerLayer.isHidden = true
        layer?.addSublayer(spinnerLayer)

        // Label text — always visible
        textLayer.string = labelText
        textLayer.font = labelFont
        textLayer.fontSize = labelFont.pointSize
        textLayer.foregroundColor = NSColor.white.cgColor
        textLayer.alignmentMode = .left
        textLayer.isWrapped = false
        textLayer.opacity = 1
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(textLayer)

        applyVisualState(animated: false)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowFocusIfNeeded()
    }

    private func observeWindowFocusIfNeeded() {
        removeWindowFocusObservation()

        guard let window else {
            isWindowFocused = false
            applyVisualState(animated: false)
            return
        }

        let nc = NotificationCenter.default

        windowFocusObservations.append(
            nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.refreshWindowFocus(animated: true)
            }
        )

        windowFocusObservations.append(
            nc.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.refreshWindowFocus(animated: true)
            }
        )

        windowFocusObservations.append(
            nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshWindowFocus(animated: true)
            }
        )

        windowFocusObservations.append(
            nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshWindowFocus(animated: true)
            }
        )

        refreshWindowFocus(animated: false)
    }

    private func removeWindowFocusObservation() {
        for observation in windowFocusObservations {
            NotificationCenter.default.removeObserver(observation)
        }
        windowFocusObservations.removeAll()
    }

    private func refreshWindowFocus(animated: Bool) {
        let focused = (window?.isKeyWindow ?? false) && NSApp.isActive
        guard focused != isWindowFocused else { return }
        isWindowFocused = focused
        applyVisualState(animated: animated)
    }

    private func setupRebuildObservation() {
        #if DEBUG
        setRebuildState(DevRebuilder.shared.isRebuilding, animated: false)
        rebuildStateCancellable = DevRebuilder.shared.$isRebuilding
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] rebuilding in
                self?.setRebuildState(rebuilding, animated: true)
            }
        #endif
    }

    private func setRebuildState(_ rebuilding: Bool, animated: Bool) {
        guard isRebuilding != rebuilding else { return }
        isRebuilding = rebuilding

        textLayer.string = labelText
        if rebuilding {
            startBusyAnimation()
            setExpanded(true, animated: animated)
        } else {
            stopBusyAnimation()
            setExpanded(isHovered, animated: animated)
        }

        applyVisualState(animated: animated)
        needsLayout = true
    }

    private func startBusyAnimation() {
        arrowLayer.isHidden = true
        spinnerLayer.isHidden = false

        if spinnerLayer.animation(forKey: "spin") == nil {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = CGFloat.pi * 2
            spin.duration = 0.85
            spin.repeatCount = .infinity
            spin.timingFunction = CAMediaTimingFunction(name: .linear)
            spinnerLayer.add(spin, forKey: "spin")
        }

        if fillLayer.animation(forKey: "pulse") == nil {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.87
            pulse.toValue = 1.0
            pulse.duration = 0.42
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            fillLayer.add(pulse, forKey: "pulse")
        }
    }

    private func stopBusyAnimation() {
        fillLayer.removeAnimation(forKey: "pulse")
        spinnerLayer.removeAnimation(forKey: "spin")
        spinnerLayer.isHidden = true
        arrowLayer.isHidden = false
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        fillLayer.contentsScale = scale
        borderLayer.contentsScale = scale
        highlightLayer.contentsScale = scale
        arrowLayer.contentsScale = scale
        spinnerLayer.contentsScale = scale
        textLayer.contentsScale = scale

        fillLayer.frame = bounds
        fillLayer.cornerRadius = bounds.height / 2

        borderLayer.frame = bounds
        let borderRect = borderLayer.bounds.insetBy(dx: 0.5, dy: 0.5)
        borderLayer.path = CGPath(
            roundedRect: borderRect,
            cornerWidth: borderRect.height / 2,
            cornerHeight: borderRect.height / 2,
            transform: nil
        )

        highlightLayer.frame = bounds
        let highlightRect = highlightLayer.bounds.insetBy(dx: 1.25, dy: 1.25)
        highlightLayer.path = CGPath(
            roundedRect: highlightRect,
            cornerWidth: highlightRect.height / 2,
            cornerHeight: highlightRect.height / 2,
            transform: nil
        )

        let arrowBounds = arrowLayer.path?.boundingBoxOfPath ?? CGRect(x: 0, y: -2.3, width: 3.8, height: 4.6)
        let spinnerPath = CGMutablePath()
        spinnerPath.addArc(center: .zero, radius: 2.8, startAngle: 0.15, endAngle: .pi * 1.65, clockwise: false)
        spinnerLayer.path = spinnerPath
        let spinnerBounds = spinnerPath.boundingBox

        let iconWidth = ceil(max(arrowBounds.width + arrowLayer.lineWidth, spinnerBounds.width + spinnerLayer.lineWidth))
        let iconAreaWidth = min(buttonDiameter, bounds.width)
        let iconCenterX = pixelAligned(bounds.minX + iconAreaWidth / 2, scale: scale)
        let iconCenterY = pixelAligned(bounds.midY + arrowOpticalOffsetY, scale: scale)

        // Use a symmetric local bounds origin so `position` maps to path origin (0, 0).
        arrowLayer.bounds = CGRect(x: -0.5, y: -0.5, width: 1, height: 1)
        arrowLayer.position = CGPoint(x: iconCenterX, y: iconCenterY)
        spinnerLayer.bounds = CGRect(x: -0.5, y: -0.5, width: 1, height: 1)
        spinnerLayer.position = CGPoint(x: iconCenterX, y: iconCenterY)

        let measuredText = (labelText as NSString).size(withAttributes: [.font: labelFont])
        let textWidth = ceil(measuredText.width)
        let textHeight = ceil(labelFont.ascender - labelFont.descender)
        let textX = pixelAligned(iconCenterX + iconWidth / 2 + iconToTextSpacing, scale: scale)
        let textY = pixelAligned((bounds.height - textHeight) / 2, scale: scale)
        textLayer.frame = CGRect(x: textX, y: textY, width: textWidth, height: textHeight)

        CATransaction.commit()
    }

    private func pixelAligned(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return value }
        return round(value * scale) / scale
    }

    private func setExpanded(_ expanded: Bool, animated: Bool) {
        let targetWidth = expanded ? expandedPillWidth : collapsedPillWidth
        guard widthConstraint?.constant != targetWidth else { return }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = expanded ? 0.25 : 0.18
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1.0, 0.32, 1.0) // ease-out curve
                widthConstraint?.animator().constant = targetWidth
                superview?.layoutSubtreeIfNeeded()
            }
        } else {
            widthConstraint?.constant = targetWidth
            superview?.layoutSubtreeIfNeeded()
        }

        needsLayout = true
    }

    private func applyVisualState(animated: Bool) {
        let fillColor: NSColor
        let borderColor: NSColor
        let highlightColor: NSColor
        let arrowColor: NSColor
        let spinnerColor: NSColor
        let textColor: NSColor

        if isRebuilding {
            fillColor = hoverFillColor
            borderColor = hoverBorderColor
            highlightColor = hoverHighlightColor
            arrowColor = hoverArrowColor
            spinnerColor = hoverArrowColor
            textColor = .white
        } else if isPressed {
            fillColor = pressedFillColor
            borderColor = pressedBorderColor
            highlightColor = pressedHighlightColor
            arrowColor = hoverArrowColor
            spinnerColor = hoverArrowColor
            textColor = .white
        } else if isHovered {
            fillColor = hoverFillColor
            borderColor = hoverBorderColor
            highlightColor = hoverHighlightColor
            arrowColor = hoverArrowColor
            spinnerColor = hoverArrowColor
            textColor = .white
        } else if isWindowFocused {
            fillColor = hoverFillColor
            borderColor = hoverBorderColor
            highlightColor = normalHighlightColor
            arrowColor = hoverArrowColor
            spinnerColor = hoverArrowColor
            textColor = .white
        } else {
            fillColor = normalFillColor
            borderColor = normalBorderColor
            highlightColor = normalHighlightColor
            arrowColor = normalArrowColor
            spinnerColor = normalArrowColor
            textColor = normalArrowColor
        }

        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? 0.12 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        fillLayer.backgroundColor = fillColor.cgColor
        borderLayer.strokeColor = borderColor.cgColor
        highlightLayer.strokeColor = highlightColor.cgColor
        arrowLayer.strokeColor = arrowColor.cgColor
        spinnerLayer.strokeColor = spinnerColor.cgColor
        textLayer.foregroundColor = textColor.cgColor
        CATransaction.commit()
    }

    private func triggerPrimaryAction() {
        guard !isRebuilding else {
            HapticFeedbackManager.shared.selection()
            return
        }

        HapticFeedbackManager.shared.alignment()
        Task { @MainActor in
            #if DEBUG
            DevRebuilder.shared.rebuild()
            #else
            updateManager?.checkForUpdates()
            #endif
        }
    }

    // MARK: Click Handling

    override func mouseDown(with event: NSEvent) {
        guard !isRebuilding else {
            HapticFeedbackManager.shared.selection()
            return
        }

        isPressed = true
        applyVisualState(animated: false)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.isPressed = false
            self.applyVisualState(animated: true)
        }

        triggerPrimaryAction()
    }

    // MARK: Tracking & Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        setExpanded(true, animated: true)
        applyVisualState(animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        if isPressed || isRebuilding { return }
        isHovered = false
        setExpanded(false, animated: true)
        applyVisualState(animated: true)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Cursor

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

// MARK: - View Extension

extension View {
    /// Adds an orange update button to the traffic light bar when an update is available.
    public func trafficLightUpdateButton(updateManager: SparkleUpdateManager) -> some View {
        background(
            TrafficLightUpdateButton(updateManager: updateManager)
                .frame(width: 0, height: 0)
        )
    }
}
