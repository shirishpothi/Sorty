//
//  OrganizationResultView.swift
//  Sorty
//
//  Display for organization results and stats
//

import SwiftUI

struct OrganizationResultView: View {
    let stats: GenerationStats
    var duplicatesFound: Int = 0
    
    var body: some View {
        VStack(spacing: 0) {
            GenerationStatsView(stats: stats, duplicatesFound: duplicatesFound)
        }
        .padding()
    }
}

struct GenerationStatsView: View {
    let stats: GenerationStats
    var duplicatesFound: Int = 0
    
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16),
            GridItem(.flexible(), spacing: 16)
        ]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.purple)
                
                Text("Stats for Nerds")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Spacer()
                
                if let model = stats.model.description.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ".").first {
                    Text(model)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(6)
                        .foregroundStyle(.purple)
                }
            }
            .padding(.horizontal, 4)
            
            LazyVGrid(columns: gridColumns, spacing: 16) {
                NerdStatPillExpanded(
                    icon: "bolt.fill",
                    color: .orange,
                    title: "Throughput",
                    value: String(format: "%.1f", stats.tps),
                    unit: "t/s"
                )
                
                NerdStatPillExpanded(
                    icon: "timer",
                    color: .green,
                    title: "Latency",
                    value: String(format: "%.2f", stats.ttft),
                    unit: "s"
                )
                
                let timeSaved = stats.estimatedTimeSaved
                NerdStatPillExpanded(
                    icon: "hourglass.badge.plus",
                    color: .blue,
                    title: "Time Saved",
                    value: timeSaved >= 60 ? String(format: "%.1f", timeSaved / 60.0) : String(format: "%.0f", timeSaved),
                    unit: timeSaved >= 60 ? "min" : "sec"
                )
                
                NerdStatPillExpanded(
                    icon: "dollarsign.circle.fill",
                    color: .green,
                    title: "Total Cost",
                    value: "$\(stats.computedCost)",
                    unit: "USD"
                )
                
                NerdStatPillExpanded(
                    icon: "number",
                    color: .teal,
                    title: "Output",
                    value: "\(stats.totalTokens)",
                    unit: "tok"
                )
                
                if let promptTokens = stats.promptTokens {
                    NerdStatPillExpanded(
                        icon: "text.alignleft",
                        color: .indigo,
                        title: "Input",
                        value: "\(promptTokens)",
                        unit: "tok"
                    )
                }
                
                if let scanned = stats.filesScanned {
                    NerdStatPillExpanded(
                        icon: "doc.text.magnifyingglass",
                        color: .cyan,
                        title: "Scanned",
                        value: "\(scanned)",
                        unit: "files"
                    )
                }
                
                if let size = stats.totalFileSize {
                    NerdStatPillExpanded(
                        icon: "sdcard.fill",
                        color: .gray,
                        title: "Total Size",
                        value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                        unit: nil
                    )
                }
                
                let dups = duplicatesFound > 0 ? duplicatesFound : (stats.duplicatesFound ?? 0)
                if dups > 0 {
                    NerdStatPillExpanded(
                        icon: "square.on.square",
                        color: .red,
                        title: "Duplicates",
                        value: "\(dups)",
                        unit: "files"
                    )
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}

public struct NerdStatPill: View {
    public let icon: String
    public let value: String
    public let unit: String?
    public let color: Color
    
    public init(icon: String, value: String, unit: String?, color: Color) {
        self.icon = icon
        self.value = value
        self.unit = unit
        self.color = color
    }
    
    public var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
            
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
            
            if let unit = unit {
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(color.opacity(0.1))
        )
    }
}

public struct NerdStatPillExpanded: View {
    public let icon: String
    public let color: Color
    public let title: String
    public let value: String
    public let unit: String?
    
    public init(icon: String, color: Color, title: String, value: String, unit: String?) {
        self.icon = icon
        self.color = color
        self.title = title
        self.value = value
        self.unit = unit
    }
    
    public var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 24, height: 24)
                
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let unit = unit {
                        Text(unit)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Text(title)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
        .help(title)
    }
}

struct NerdStatCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let unit: String?
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconColor)
                
                Text(title)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    
                    if let unit = unit {
                        Text(unit)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
                
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit ?? "")")
    }
}
