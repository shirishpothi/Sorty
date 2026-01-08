//
//  AnalysisView.swift
//  Sorty
//
//  Real-time organization display with streaming progress
//

import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject var organizer: FolderOrganizer

    @State private var progressBarOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: 24) {
            // Progress indicator with motion
            VStack(spacing: 16) {
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(maxWidth: 500, maxHeight: 12)

                    // Animated progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            // Base progress
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geometry.size.width * organizer.progress))

                            // Shimmer overlay
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(0.4),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: 60)
                                .offset(x: progressBarOffset)
                                .mask(
                                    RoundedRectangle(cornerRadius: 6)
                                        .frame(width: max(0, geometry.size.width * organizer.progress))
                                )
                        }
                    }
                    .frame(maxWidth: 500, maxHeight: 12)
                }
                .frame(maxWidth: 500, maxHeight: 12)
                .onAppear {
                    withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                        progressBarOffset = 500
                    }
                }

                // Percentage
                Text("\(Int(organizer.progress * 100))%")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            // Stage indicator with icon
            HStack(spacing: 12) {
                Group {
                    if case .scanning = organizer.state {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                    } else if case .organizing = organizer.state {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 32))
                            .foregroundStyle(.purple)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(organizer.organizationStage)
                        .font(.headline)

                    if organizer.isStreaming {
                        HStack(spacing: 4) {
                            Text("Receiving response")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            LoadingDotsView(dotCount: 3, dotSize: 4, color: .secondary)
                        }
                    }

                    // Elapsed time
                    if organizer.elapsedTime > 0 {
                        Text("Elapsed: \(formatTime(organizer.elapsedTime))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }

            // Timeout message
            if organizer.showTimeoutMessage {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(.orange)

                            Text("Taking longer than expected")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }

                        Text("AI organization can take a while depending on the number of files, model speed, and network conditions. For large directories, this may take a few minutes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if organizer.elapsedTime > 60 {
                            Text("Tip: Consider organizing smaller directories first, or check your AI provider settings.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: 400)
                }
                .backgroundStyle(.yellow.opacity(0.1))
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Streaming content preview (if available)
            if organizer.isStreaming && !organizer.streamingContent.isEmpty {
                GroupBox {
                    ScrollView {
                        ScrollViewReader { proxy in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(truncatedStreamContent)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .id("bottom")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .onChange(of: organizer.streamingContent) { oldValue, newValue in
                                withAnimation(.easeOut(duration: 0.2)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: 600, maxHeight: 200)
                } label: {
                    HStack {
                        Image(systemName: "text.word.spacing")
                            .foregroundStyle(.purple)
                        Text("AI Response")
                    }
                    .font(.caption)
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
            }

            // Cancel button
            Button("Cancel") {
                HapticFeedbackManager.shared.tap()
                organizer.reset()
            }
            .keyboardShortcut(.escape, modifiers: [])
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var truncatedStreamContent: String {
        let content = organizer.streamingContent
        if content.count > 1000 {
            let start = content.index(content.endIndex, offsetBy: -1000)
            return "..." + String(content[start...])
        }
        return content
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Animated Progress Ring

struct AnimatedProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color

    @State private var animatedProgress: Double = 0

    init(progress: Double, lineWidth: CGFloat = 8, color: Color = .blue) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    AngularGradient(
                        colors: [color, color.opacity(0.5), color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .onChange(of: progress) { oldValue, newValue in
            withAnimation(.easeOut(duration: 0.3)) {
                animatedProgress = newValue
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) {
                animatedProgress = progress
            }
        }
    }
}

#Preview {
    AnalysisView()
        .environmentObject(FolderOrganizer())
        .frame(width: 600, height: 400)
}
