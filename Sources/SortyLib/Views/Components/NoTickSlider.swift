//
//  NoTickSlider.swift
//  Sorty
//
//  Slider wrapper that suppresses the macOS native tick mark dots.
//

import SwiftUI

struct NoTickSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double?

    init(value: Binding<Double>, in range: ClosedRange<Double>, step: Double? = nil) {
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        Group {
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
        }
        .labelsHidden()
    }
}
