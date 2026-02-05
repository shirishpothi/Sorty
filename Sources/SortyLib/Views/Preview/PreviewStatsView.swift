//
//  PreviewStatsView.swift
//  Sorty
//
//  Stats display component with "Stats for Nerds" collapsible section
//

import SwiftUI

struct PreviewStatsView: View {
    let stats: GenerationStats?
    let showStatsForNerds: Bool
    let estimatedTimeRemaining: TimeInterval?
    let currentFile: Int
    let totalFiles: Int
    let stage: String
    
    @State private var isExpanded = false
    @State private var showTooltip = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let stats = stats, showStatsForNerds {
                // Collapsible stats row
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
                        
                        Spacer()
                        
                        // Summary pills
                        HStack(spacing: 16) {
                            NerdStatPill(icon: "bolt.fill", value: String(format: "%.1f", stats.tps), unit: "tok/s", color: .orange)
                            NerdStatPill(icon: "clock.fill", value: String(format: "%.2f", stats.duration), unit: "s", color: .blue)
                            
                            // Time remaining estimate
                            if let estimatedTime = estimatedTimeRemaining, estimatedTime > 0 {
                                NerdStatPill(
                                    icon: "hourglass",
                                    value: formatTime(estimatedTime),
                                    unit: "left",
                                    color: .purple
                                )
                            }
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
                
                // Expanded detailed stats
                if isExpanded {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    detailedStatsView(stats: stats)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            } else if !showStatsForNerds && estimatedTimeRemaining != nil {
                // Simple progress with time estimate when stats are hidden
                HStack {
                    Spacer()
                    if let estimatedTime = estimatedTimeRemaining {
                        Label(formatTime(estimatedTime) + " remaining", systemImage: "hourglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func detailedStatsView(stats: GenerationStats) -> some View {
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
                title: "Total Tokens",
                value: "\(stats.totalTokens)",
                unit: nil
            )
            
            if let promptTokens = stats.promptTokens {
                NerdStatPillExpanded(
                    icon: "text.bubble",
                    color: .purple,
                    title: "Prompt Tokens",
                    value: "\(promptTokens)",
                    unit: nil
                )
            }
            
            if let filesScanned = stats.filesScanned {
                NerdStatPillExpanded(
                    icon: "doc.text.magnifyingglass",
                    color: .indigo,
                    title: "Files Scanned",
                    value: "\(filesScanned)",
                    unit: nil
                )
            }
            
            if let scanDuration = stats.scanDuration {
                NerdStatPillExpanded(
                    icon: "stopwatch",
                    color: .cyan,
                    title: "Scan Duration",
                    value: String(format: "%.2f", scanDuration),
                    unit: "s"
                )
            }
            
            if let estimatedCost = stats.estimatedCost {
                NerdStatPillExpanded(
                    icon: "dollarsign.circle",
                    color: .green,
                    title: "Est. Cost",
                    value: String(format: "$%.4f", NSDecimalNumber(decimal: estimatedCost).doubleValue),
                    unit: nil
                )
            }
            
            if let provider = stats.provider {
                NerdStatPillExpanded(
                    icon: "network",
                    color: .secondary,
                    title: "Provider",
                    value: provider,
                    unit: nil
                )
            }
            
            NerdStatPillExpanded(
                icon: "cpu",
                color: .primary,
                title: "Model",
                value: stats.model,
                unit: nil
            )
        }
    }
    
    private func formatTime(_ interval: TimeInterval) -> String {
        if interval < 60 {
            return String(format: "%.0fs", interval)
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            let seconds = Int(interval.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(interval / 3600)
            let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Previews

#Preview("Preview Stats - Collapsed") {
    PreviewStatsView(
        stats: GenerationStats(
            duration: 1.5,
            tps: 45.2,
            ttft: 0.3,
            totalTokens: 1250,
            model: "gpt-4o",
            filesScanned: 42,
            promptTokens: 850,
            provider: "OpenAI"
        ),
        showStatsForNerds: true,
        estimatedTimeRemaining: nil,
        currentFile: 0,
        totalFiles: 42,
        stage: "Analyzing"
    )
    .frame(width: 800)
}

#Preview("Preview Stats - Expanded") {
    PreviewStatsView(
        stats: GenerationStats(
            duration: 1.5,
            tps: 45.2,
            ttft: 0.3,
            totalTokens: 1250,
            model: "gpt-4o",
            filesScanned: 42,
            promptTokens: 850,
            provider: "OpenAI"
        ),
        showStatsForNerds: true,
        estimatedTimeRemaining: 120,  // 2 minutes
        currentFile: 20,
        totalFiles: 42,
        stage: "Moving files"
    )
    .frame(width: 800)
}

#Preview("Preview Stats - Hidden") {
    PreviewStatsView(
        stats: nil,
        showStatsForNerds: false,
        estimatedTimeRemaining: 45,
        currentFile: 10,
        totalFiles: 50,
        stage: "Organizing"
    )
    .frame(width: 800)
}
