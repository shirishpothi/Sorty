//
//  TagDotsView.swift
//  Sorty
//

import SwiftUI

struct TagDotsView: View {
    let tags: [String]

    private var colorTags: [(String, Color)] {
        tags.compactMap { tag -> (String, Color)? in
            guard let color = finderTagColor(tag) else { return nil }
            return (tag, color)
        }
    }

    private var hoverText: String {
        let descriptiveTags = tags.filter { finderTagColor($0) == nil }
        return (descriptiveTags.isEmpty ? tags : descriptiveTags).joined(separator: ", ")
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(colorTags.prefix(3), id: \.0) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }

            if colorTags.isEmpty, !tags.isEmpty {
                Circle()
                    .fill(.secondary)
                    .frame(width: 8, height: 8)
            }
        }
        .frame(minWidth: 8, minHeight: 16)
        .contentShape(Rectangle())
        .help(hoverText)
        .accessibilityLabel("Tags: \(hoverText)")
    }

    private func finderTagColor(_ tag: String) -> Color? {
        switch tag.lowercased() {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        case "gray", "grey": return .gray
        default: return nil
        }
    }
}
