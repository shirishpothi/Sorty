//
//  SettingPreviews.swift
//  Sorty
//
//  Live preview components for non-obvious settings.
//

import SwiftUI

struct SettingPreviewPanel<Content: View>: View {
    let title: String?
    let icon: String?
    let accent: Color
    @ViewBuilder let content: Content

    init(
        title: String? = nil,
        icon: String? = nil,
        accent: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack(spacing: 4) {
                    if let icon {
                        Image(systemName: icon)
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }
                    Text(LocalizedStringKey(title))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                }
            }
            content
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )
        }
    }
}
