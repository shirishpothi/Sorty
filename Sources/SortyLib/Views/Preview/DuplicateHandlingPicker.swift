//
//  DuplicateHandlingPicker.swift
//  Sorty
//
//  Duplicate handling selector for preview workflows.
//

import SwiftUI

struct DuplicateHandlingPicker: View {
    @Binding var selection: DuplicateHandlingMode
    var compact: Bool = false
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            triggerLabel
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popoverContent
                .systemLiquidGlassPopover(cornerRadius: 12)
        }
        .fixedSize(horizontal: compact, vertical: false)
        .accessibilityLabel("Duplicate handling")
        .accessibilityValue(selection.rawValue)
        .accessibilityHint("Choose how duplicate detection is handled during preview")
    }

    private var triggerLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !compact {
                Text("Duplicates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(selection.rawValue)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(DuplicateHandlingMode.allCases) { mode in
                optionButton(for: mode)
            }
        }
        .padding(10)
        .frame(minWidth: 280, maxWidth: 320)
    }

    private func optionButton(for mode: DuplicateHandlingMode) -> some View {
        Button {
            selection = mode
            HapticFeedbackManager.shared.selection()
            showPopover = false
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: selection == mode ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection == mode ? Color.accentColor : Color.secondary)
                    .font(.caption)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
