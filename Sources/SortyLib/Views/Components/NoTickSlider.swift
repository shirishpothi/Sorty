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
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                value = snapped
            }
        }
    }
}
