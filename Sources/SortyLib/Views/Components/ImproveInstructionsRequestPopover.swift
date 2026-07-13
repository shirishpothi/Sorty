//
//  ImproveInstructionsRequestPopover.swift
//  Sorty
//

import SwiftUI

struct ImproveInstructionsRequestPopover: View {
    let message: String
    let onDismiss: () -> Void

    @FocusState private var isDismissButtonFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "questionmark.bubble.fill")
                    .foregroundStyle(.teal)
                    .accessibilityHidden(true)

                Text("Sorty needs more detail")
                    .font(.headline)
            }

            Text(message)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text("Edit the instructions above, then click Improve again.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()

                Button("Edit Instructions", action: onDismiss)
                    .buttonStyle(.sortyProminent)
                    .keyboardShortcut(.defaultAction)
                    .focused($isDismissButtonFocused)
            }
        }
        .padding(16)
        .frame(width: 320)
        .foregroundStyle(.primary)
        .systemLiquidGlassPopover(cornerRadius: 12)
        .onAppear {
            isDismissButtonFocused = true
        }
    }
}
