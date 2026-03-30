//
//  LiquidDropdown.swift
//  Sorty
//
//  A "Liquid Glass" style dropdown with smooth popover animation
//

import SwiftUI

struct LiquidDropdown<T: Identifiable & RawRepresentable & Hashable>: View where T.RawValue == String {
    let options: [T]
    @Binding var selection: T
    var title: String? = nil

    @State private var isExpanded = false
    @State private var isHovered = false

    var body: some View {
        triggerButton
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                optionsList
            }
            .fixedSize()
    }

    private var triggerButton: some View {
        Button {
            HapticFeedbackManager.shared.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                isExpanded.toggle()
            }
        } label: {
            triggerLabel
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.86)) {
                isHovered = hovering
            }
        }
    }

    private var triggerLabel: some View {
        HStack(spacing: 8) {
            if let title = title {
                Text(title)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Text(selection.rawValue)
                .fontWeight(.medium)

            Image(systemName: "chevron.down")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 6 : 4, y: 2)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(isHovered ? 0.18 : 0.1), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
    }

    private var optionsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(options) { option in
                optionRow(option)
            }
        }
        .padding(6)
        .frame(minWidth: 160)
    }

    private func optionRow(_ option: T) -> some View {
        let isSelected = selection == option
        return Button {
            HapticFeedbackManager.shared.tap()
            withAnimation(.spring(response: 0.2, dampingFraction: 0.86)) {
                selection = option
                isExpanded = false
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .secondary)

                Text(option.rawValue)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
