//
//  NoTickSlider.swift
//  Sorty
//
//  Slider wrapper that suppresses the macOS native tick mark dots.
//

import SwiftUI
import AppKit

struct NoTickSlider: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?
    var onEditingChanged: ((Bool) -> Void)?

    init(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double? = nil,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.step = step
        self.onEditingChanged = onEditingChanged
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, step: step)
    }

    func makeNSView(context: Context) -> EditingTrackingSlider {
        let slider = EditingTrackingSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.changed(_:))
        )
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.trackFillColor = nil
        slider.editingChanged = { isEditing in
            onEditingChanged?(isEditing)
        }
        context.coordinator.slider = slider
        return slider
    }

    func updateNSView(_ nsView: EditingTrackingSlider, context: Context) {
        if nsView.minValue != range.lowerBound || nsView.maxValue != range.upperBound {
            nsView.minValue = range.lowerBound
            nsView.maxValue = range.upperBound
        }
        if abs(nsView.doubleValue - value) > 0.0001 {
            nsView.doubleValue = value
        }
        context.coordinator.step = step
    }

    final class Coordinator: NSObject {
        @Binding var value: Double
        var step: Double?
        weak var slider: NSSlider?

        init(value: Binding<Double>, step: Double?) {
            self._value = value
            self.step = step
        }

        @objc func changed(_ sender: NSSlider) {
            let raw = sender.doubleValue
            let snapped: Double
            if let step, step > 0 {
                snapped = (raw / step).rounded() * step
                if abs(snapped - raw) > 0.0001, snapped >= sender.minValue, snapped <= sender.maxValue {
                    sender.doubleValue = snapped
                }
            } else {
                snapped = raw
            }
            value = snapped
        }
    }
}

/// NSSlider subclass that reports edit-begin / edit-end. `mouseDown(with:)`
/// blocks until tracking completes (mouse up), so we bracket `super` with the
/// editing callbacks to drive animation gating in SwiftUI.
final class EditingTrackingSlider: NSSlider {
    var editingChanged: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        editingChanged?(true)
        super.mouseDown(with: event)
        editingChanged?(false)
    }
}

// MARK: - Numeric roll animation (slider-aware)

private struct NumericRollModifier: ViewModifier {
    let value: Double
    let isEditing: Bool
    let duration: Double

    func body(content: Content) -> some View {
        // While the slider is being dragged, update instantly so the number
        // tracks the thumb with zero lag. The digit-roll plays only on discrete
        // changes (release, keyboard nudge, reset-to-default, programmatic).
        if isEditing {
            content
        } else {
            content
                .contentTransition(.numericText(value: value))
                .animation(.spring(response: duration, dampingFraction: 0.78), value: value)
        }
    }
}

extension View {
    /// Apple-style numeric digit-roll animation, gated on slider editing state.
    ///
    /// Pass the same numeric `value` shown in the label and the slider's
    /// `isEditing` flag. While dragging, the label updates with no animation
    /// (direct manipulation feel); on discrete changes it rolls through the
    /// intermediate digits.
    func numericRoll(value: Double, isEditing: Bool, duration: Double = 0.28) -> some View {
        modifier(NumericRollModifier(value: value, isEditing: isEditing, duration: duration))
    }
}
