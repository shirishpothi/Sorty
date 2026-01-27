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
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 12))
                        .foregroundStyle(.purple)
                    
                    Text("Stats for Nerds")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        NerdStatPill(icon: "bolt.fill", value: String(format: "%.1f", stats.tps), unit: "tok/s", color: .orange)
                        NerdStatPill(icon: "clock.fill", value: String(format: "%.2f", stats.duration), unit: "s", color: .blue)
                        NerdStatPill(icon: "timer", value: String(format: "%.2f", stats.ttft), unit: "s", color: .green)
                        NerdStatPill(icon: "cpu", value: stats.model, unit: nil, color: .purple)
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stats for nerds. \(isExpanded ? "Collapse" : "Expand") for details")
            
            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)
                
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12), 
                    GridItem(.flexible(), spacing: 12), 
                    GridItem(.flexible(), spacing: 12), 
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    NerdStatPillExpanded(
                        icon: "bolt.fill",
                        color: .orange,
                        title: "Throughput",
                        value: String(format: "%.1f", stats.tps),
                        unit: "tok/s"
                    )
                    
                    NerdStatPillExpanded(
                        icon: "timer",
                        color: .green,
                        title: "Latency",
                        value: String(format: "%.2f", stats.ttft),
                        unit: "s TTFT"
                    )
                    
                    NerdStatPillExpanded(
                        icon: "clock.fill",
                        color: .blue,
                        title: "Total Duration",
                        value: String(format: "%.2f", stats.duration),
                        unit: "s"
                    )
                    
                    NerdStatPillExpanded(
                        icon: "number",
                        color: .teal,
                        title: "Output Size",
                        value: "\(stats.totalTokens)",
                        unit: "tokens"
                    )
                    
                    if let promptTokens = stats.promptTokens {
                        NerdStatPillExpanded(
                            icon: "text.alignleft",
                            color: .indigo,
                            title: "Input Size",
                            value: "\(promptTokens)",
                            unit: "tokens"
                        )
                    }
                    
                    if let scanned = stats.filesScanned {
                        NerdStatPillExpanded(
                            icon: "doc.text.magnifyingglass",
                            color: .cyan,
                            title: "Files Scanned",
                            value: "\(scanned)",
                            unit: "files"
                        )
                    }
                    
                    if let scanDuration = stats.scanDuration {
                        NerdStatPillExpanded(
                            icon: "magnifyingglass",
                            color: .yellow,
                            title: "Scan Duration",
                            value: String(format: "%.2f", scanDuration),
                            unit: "s"
                        )
                    }
                    
                    if let size = stats.totalFileSize {
                        NerdStatPillExpanded(
                            icon: "sdcard.fill",
                            color: .gray,
                            title: "Total Data Size",
                            value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file),
                            unit: nil
                        )
                    }
                    
                    let dups = duplicatesFound > 0 ? duplicatesFound : (stats.duplicatesFound ?? 0)
                    if dups > 0 {
                        NerdStatPillExpanded(
                            icon: "square.on.square",
                            color: .red,
                            title: "Duplicates Found",
                            value: "\(dups)",
                            unit: "files"
                        )
                    }
                    
                    if let cost = stats.estimatedCost {
                        NerdStatPillExpanded(
                            icon: "dollarsign.circle.fill",
                            color: .green,
                            title: "Estimated Cost",
                            value: "\(cost)",
                            unit: "USD"
                        )
                    }
                    
                    if let provider = stats.provider {
                        NerdStatPillExpanded(
                            icon: "cloud.fill",
                            color: .blue,
                            title: "AI Provider",
                            value: provider,
                            unit: nil
                        )
                    }
                    
                    NerdStatPillExpanded(
                        icon: "cpu",
                        color: .purple,
                        title: "AI Model",
                        value: stats.model,
                        unit: nil
                    )
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)),
                    removal: .opacity
                ))
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
        .accessibilityElement(children: .contain)
    }
}

struct NerdStatPill: View {
    let icon: String
    let value: String
    let unit: String?
    let color: Color
    
    var body: some View {
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

struct NerdStatPillExpanded: View {
    let icon: String
    let color: Color
    let title: String
    let value: String
    let unit: String?
    
    var body: some View {
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
