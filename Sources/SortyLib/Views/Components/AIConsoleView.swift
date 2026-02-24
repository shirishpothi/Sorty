//
//  AIConsoleView.swift
//  Sorty
//

import SwiftUI

struct AIConsoleView: View {
    let isStreaming: Bool
    let insights: (current: String, history: [AIInsight])
    let funnyMessage: String
    let funnyMessageOpacity: Double
    let liveOrganizationMoves: [LiveOrganizationMove]
    @Binding var liveInsightsEnabled: Bool

    @State private var isExpanded = true
    @State private var userScrolledUp = false

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if isExpanded {
                consoleBody
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Header

    private var headerBar: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                Text("AI Console")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                if isStreaming {
                    Circle()
                        .fill(.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: .green.opacity(0.6), radius: 4)
                        .modifier(PulsingDot())
                }

                Spacer()

                if !insights.history.isEmpty {
                    Text("\(insights.history.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                }

                if isStreaming {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            liveInsightsEnabled.toggle()
                        }
                    } label: {
                        Image(systemName: liveInsightsEnabled ? "bolt.badge.checkmark" : "bolt.slash")
                            .font(.caption)
                            .foregroundStyle(liveInsightsEnabled ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(liveInsightsEnabled ? "Disable live insights" : "Enable live insights")
                    .accessibilityIdentifier("AIConsole_LiveInsightsToggle")
                }

                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Color(NSColor.controlBackgroundColor).opacity(0.4)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("AIConsole_HeaderToggle")
    }

    // MARK: - Console Body

    private var consoleBody: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(allEntries) { entry in
                            consoleRow(for: entry)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("console_bottom_anchor")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        GeometryReader { geo in
                            Color.clear.onChange(of: geo.frame(in: .named("consoleScroll")).minY) { _, newValue in
                                let threshold: CGFloat = -10
                                userScrolledUp = newValue < threshold
                            }
                        }
                    )
                }
                .coordinateSpace(name: "consoleScroll")
                .frame(maxHeight: 220)
                .onChange(of: insights.history.count) { _, _ in
                    if !userScrolledUp {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("console_bottom_anchor", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: funnyMessage) { _, _ in
                    if !userScrolledUp {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("console_bottom_anchor", anchor: .bottom)
                        }
                    }
                }
            }

            if userScrolledUp {
                Button {
                    userScrolledUp = false
                } label: {
                    HStack(spacing: 4) {
                        Text("⬇")
                            .font(.system(size: 10))
                        Text("Auto-scroll")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.ultraThinMaterial)
                            .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .accessibilityIdentifier("AIConsole_AutoScrollButton")
            }
        }
    }

    // MARK: - Log Entry Model

    private struct ConsoleEntry: Identifiable {
        let id: String
        let timestamp: Date
        let category: AIInsight.Category?
        let text: String
        let filePath: String?
        let isStatus: Bool
    }

    private var allEntries: [ConsoleEntry] {
        var entries: [ConsoleEntry] = []

        for insight in insights.history {
            entries.append(ConsoleEntry(
                id: insight.id,
                timestamp: insight.timestamp,
                category: insight.category,
                text: insight.text,
                filePath: insight.filePath,
                isStatus: false
            ))
        }

        if !funnyMessage.isEmpty, funnyMessageOpacity > 0 {
            entries.append(ConsoleEntry(
                id: "status_funny_\(funnyMessage.hashValue)",
                timestamp: Date(),
                category: nil,
                text: funnyMessage,
                filePath: nil,
                isStatus: true
            ))
        }

        return entries
    }

    // MARK: - Console Row

    @ViewBuilder
    private func consoleRow(for entry: ConsoleEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(Self.timestampFormatter.string(from: entry.timestamp))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)

            if entry.isStatus {
                statusBadge
            } else if let category = entry.category {
                categoryBadge(category)
            }

            highlightedText(entry.text, filePath: entry.filePath)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(entry.isStatus ? .secondary : .primary)
                .opacity(entry.isStatus ? funnyMessageOpacity : 1.0)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(entry.isStatus ? Color.clear : rowBackground(for: entry.category))
        )
    }

    // MARK: - Category Badge

    private func categoryBadge(_ category: AIInsight.Category) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color(for: category))
                .frame(width: 6, height: 6)

            Text(category.rawValue)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(color(for: category))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(color(for: category).opacity(0.12))
        )
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.secondary)
                .frame(width: 6, height: 6)

            Text("[STATUS]")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        )
    }

    // MARK: - Text Highlighting

    @ViewBuilder
    private func highlightedText(_ text: String, filePath: String?) -> some View {
        Text(highlightPaths(in: text, explicitPath: filePath))
    }

    private func highlightPaths(in text: String, explicitPath: String? = nil) -> AttributedString {
        var attributed = AttributedString(text)

        if let path = explicitPath, !path.isEmpty, let range = text.range(of: path) {
            if let attrRange = Range(range, in: attributed) {
                attributed[attrRange].foregroundColor = .blue
                attributed[attrRange].backgroundColor = Color.blue.opacity(0.08)
            }
            return attributed
        }

        let pathPattern = #"(/[\w.\-]+)+"#
        guard let regex = try? NSRegularExpression(pattern: pathPattern) else {
            return attributed
        }
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)
        for match in matches.reversed() {
            guard let range = Range(match.range, in: text),
                  let attrRange = Range(range, in: attributed) else { continue }
            attributed[attrRange].foregroundColor = .blue
            attributed[attrRange].backgroundColor = Color.blue.opacity(0.08)
        }
        return attributed
    }

    // MARK: - Colors

    private func color(for category: AIInsight.Category) -> Color {
        switch category {
        case .file: return .blue
        case .folder: return .orange
        case .constraint: return .yellow
        case .decision: return .green
        case .pattern: return .purple
        case .general: return .secondary
        }
    }

    private func rowBackground(for category: AIInsight.Category?) -> Color {
        guard let category else { return .clear }
        return color(for: category).opacity(0.04)
    }
}

// MARK: - Pulsing Dot Modifier

private struct PulsingDot: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.4 : 1.0)
            .opacity(isPulsing ? 0.6 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Preview

#Preview {
    let sampleInsights: [AIInsight] = [
        AIInsight(text: "Scanning /Users/demo/Documents/report.pdf", category: .file, filePath: "/Users/demo/Documents/report.pdf"),
        AIInsight(text: "Creating folder: Work Documents", category: .folder),
        AIInsight(text: "Constraint: Keep .DS_Store files in place", category: .constraint),
        AIInsight(text: "Decision: Group by file type first, then by project", category: .decision),
        AIInsight(text: "Pattern detected: 12 screenshots follow naming convention", category: .pattern),
        AIInsight(text: "Analyzing folder structure...", category: .general),
    ]

    AIConsoleView(
        isStreaming: true,
        insights: (current: "Analyzing folder structure...", history: sampleInsights),
        funnyMessage: "Teaching files to organize themselves... 🤖",
        funnyMessageOpacity: 0.8,
        liveOrganizationMoves: [],
        liveInsightsEnabled: .constant(true)
    )
    .frame(width: 520)
    .padding()
}
