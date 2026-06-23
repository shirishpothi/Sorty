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

// MARK: - Rolling number text (macOS-compatible count-up)

/// A `Text` that rolls through intermediate values when `value` changes,
/// reproducing Apple's numeric count-up animation on macOS.
///
/// `contentTransition(.numericText())` does not render its odometer effect on
/// AppKit-backed SwiftUI, so this view instead drives a real value tween via
/// an `Animatable` `ViewModifier`: SwiftUI interpolates `animatableData` from
/// the previous value to the new one across animation frames and re-renders
/// the `Text` for each intermediate number.
struct RollingNumberText: View {
    let value: Double
    let format: (Double) -> String
    let duration: Double
    @State private var displayed: Double

    init(
        value: Double,
        format: @escaping (Double) -> String = { "\(Int($0))" },
        duration: Double = 0.25
    ) {
        self.value = value
        self.format = format
        self.duration = duration
        _displayed = State(initialValue: value)
    }

    var body: some View {
        // Hidden base text reserves the layout width of the final value; the
        // modifier overlays the tweened text so only the rolling digits show.
        Text(format(value))
            .hidden()
            .modifier(RollingNumberModifier(animatableData: displayed, format: format))
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: duration)) {
                    displayed = newValue
                }
            }
    }
}

private struct RollingNumberModifier: ViewModifier, Animatable {
    var animatableData: Double
    let format: (Double) -> String

    func body(content: Content) -> some View {
        content.overlay(
            Text(format(animatableData))
                .monospacedDigit()
        )
    }
}
