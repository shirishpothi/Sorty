//
//  LiquidDropdown.swift
//  Sorty
//
//  A "Liquid Glass" style dropdown component
//

import SwiftUI

struct LiquidDropdown<T: Identifiable & RawRepresentable & Hashable>: View where T.RawValue == String {
    let options: [T]
    @Binding var selection: T
    var title: String? = nil
    
    var body: some View {
        Menu {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        if selection == option {
                            Image(systemName: "checkmark")
                        }
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton) // Remove default button border
        .fixedSize()
    }
}
