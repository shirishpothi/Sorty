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

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil) {
        self._value = value
        self.range = range
        self.step = step
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(value: $value, step: step)
    }

    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.isContinuous = true
        slider.numberOfTickMarks = 0
        slider.allowsTickMarkValuesOnly = false
        slider.trackFillColor = nil
        context.coordinator.slider = slider
        return slider
    }

    func updateNSView(_ nsView: NSSlider, context: Context) {
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

// MARK: - Numeric roll animation

private struct NumericRollModifier: ViewModifier {
    let value: Double
    let duration: Double

    func body(content: Content) -> some View {
        // Plain .numericText() (no `value:`) performs an odometer-style digit
        // roll on each change rather than interpolating the numeric value.
        // Interpolating via numericText(value:) on a continuously slider-driven
        // value re-targets the tween on every tick and ends up showing nothing,
        // so the non-interpolating form is what actually animates here.
        content
            .contentTransition(.numericText())
            .animation(.easeOut(duration: duration), value: value)
    }
}

extension View {
    /// Apple-style odometer digit-roll for a numeric label. Pass the same
    /// numeric `value` shown in the label so SwiftUI re-evaluates and rolls
    /// the changed digits whenever it changes.
    func numericRoll(value: Double, duration: Double = 0.2) -> some View {
        modifier(NumericRollModifier(value: value, duration: duration))
    }
}
