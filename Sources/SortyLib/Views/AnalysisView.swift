//
//  AnalysisView.swift
//  Sorty
//
//  Real-time organization display with streaming progress
//

import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @State private var hasAppeared = false
    @State private var currentFunnyMessage: String = ""
    @State private var currentFileDisplay: String = ""
    @State private var funnyMessageOpacity: Double = 0
    @State private var fileDisplayOpacity: Double = 0
    @State private var showMultitaskingHint: Bool = false
    @State private var funnyMessageTimer: Timer?
    @State private var fileDisplayTimer: Timer?
    
    // Funny messages that cycle during organization
    private let funnyMessages = [
        "Teaching folders to play nice together...",
        "Convincing files they belong somewhere...",
        "Negotiating peace between PDFs and PNGs...",
        "Whispering sweet nothings to your documents...",
        "Giving your files a well-deserved spa day...",
        "Herding digital cats into folders...",
        "Making your chaos look intentional...",
        "Turning your file salad into a proper meal...",
        "Convincing duplicates to pick a side...",
        "Teaching old files new tricks...",
        "Sorting at the speed of thought...",
        "Giving your desktop a makeover...",
        "Playing matchmaker with your files...",
        "Building tiny digital homes for your data...",
        "Turning file spaghetti into lasagna...",
        "Your files are learning to get along...",
        "Orchestrating a symphony of folders...",
        "Performing file feng shui...",
        "Making Marie Kondo proud...",
        "Alphabetizing... just kidding, we're smarter than that..."
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 28) {
                progressSection
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                stageIndicator
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)

                if organizer.showTimeoutMessage {
                    timeoutMessage
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
                
                if showMultitaskingHint {
                    multitaskingHint
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                if organizer.isStreaming {
                    aiInsightsView
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .opacity
                        ))
                }

                Button {
                    HapticFeedbackManager.shared.tap()
                    organizer.reset()
                } label: {
                    Text("Cancel")
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                .accessibilityIdentifier("AnalysisCancelButton")
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
            startFunnyMessageCycle()
            startFileDisplayCycle()
        }
        .onDisappear {
            stopTimers()
        }
        .onChange(of: organizer.elapsedTime) { _, newTime in
            // Show multitasking hint after 60-300 seconds (1-5 minutes)
            if newTime >= 60 && !showMultitaskingHint {
                withAnimation(.easeInOut(duration: 0.5)) {
                    showMultitaskingHint = true
                }
            }
        }
    }
    
    private func startFunnyMessageCycle() {
        // Initial message
        currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
        withAnimation(.easeIn(duration: 0.5)) {
            funnyMessageOpacity = 1
        }
        
        // Cycle messages every 3 seconds
        funnyMessageTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            Task { @MainActor in
                // Fade out
                withAnimation(.easeOut(duration: 0.4)) {
                    funnyMessageOpacity = 0
                }
                
                // Wait for fade out, then change message and fade in
                try? await Task.sleep(nanoseconds: 450_000_000)
                
                currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
                
                withAnimation(.easeIn(duration: 0.4)) {
                    funnyMessageOpacity = 1
                }
            }
        }
    }
    
    private func startFileDisplayCycle() {
        // Only show file names if we have scanned files
        guard let plan = organizer.currentPlan else {
            updateFileDisplayFromStream()
            return
        }
        
        // Collect all file names from the plan
        func collectFileNames(from suggestions: [FolderSuggestion]) -> [String] {
            var names: [String] = []
            for suggestion in suggestions {
                names.append(contentsOf: suggestion.files.map { $0.displayName })
                names.append(contentsOf: collectFileNames(from: suggestion.subfolders))
            }
            return names
        }
        
        let fileNames = collectFileNames(from: plan.suggestions) + plan.unorganizedFiles.map { $0.displayName }
        guard !fileNames.isEmpty else {
            updateFileDisplayFromStream()
            return
        }
        
        // Initial file
        currentFileDisplay = fileNames.randomElement() ?? ""
        withAnimation(.easeIn(duration: 0.3)) {
            fileDisplayOpacity = 1
        }
        
        // Cycle file names every 1.5 seconds
        fileDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.25)) {
                    fileDisplayOpacity = 0
                }
                
                try? await Task.sleep(nanoseconds: 300_000_000)
                
                currentFileDisplay = fileNames.randomElement() ?? ""
                
                withAnimation(.easeIn(duration: 0.25)) {
                    fileDisplayOpacity = 1
                }
            }
        }
    }
    
    private func updateFileDisplayFromStream() {
        // If no plan yet, try to extract file references from streaming content
        fileDisplayTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                let content = organizer.displayStreamingContent
                
                // Try to extract a filename from the streaming content
                if let fileName = extractFileNameFromContent(content) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        fileDisplayOpacity = 0
                    }
                    
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    
                    currentFileDisplay = fileName
                    
                    withAnimation(.easeIn(duration: 0.25)) {
                        fileDisplayOpacity = 1
                    }
                }
            }
        }
    }
    
    private func extractFileNameFromContent(_ content: String) -> String? {
        // Look for patterns that might indicate file names
        let patterns = [
            "\"name\":\\s*\"([^\"]+)\"",
            "\"file\":\\s*\"([^\"]+)\"",
            "([\\w\\-\\.]+\\.(pdf|doc|docx|jpg|png|txt|md|swift|js|py|zip|mp3|mp4))"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(content.startIndex..., in: content)
                let matches = regex.matches(in: content, options: [], range: range)
                if let match = matches.last, let range = Range(match.range(at: 1), in: content) {
                    return String(content[range])
                }
            }
        }
        return nil
    }
    
    private func stopTimers() {
        funnyMessageTimer?.invalidate()
        funnyMessageTimer = nil
        fileDisplayTimer?.invalidate()
        fileDisplayTimer = nil
    }
    
    private var progressSection: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                    .frame(width: 120, height: 120)
                
                Circle()
                    .trim(from: 0, to: organizer.progress)
                    .stroke(
                        Color.accentColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.4, dampingFraction: 0.9), value: organizer.progress)
                
                VStack(spacing: 2) {
                    Text("\(Int(organizer.progress * 100))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    
                    if organizer.elapsedTime > 0 {
                        Text(formatTime(organizer.elapsedTime))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .accessibilityIdentifier("AnalysisPercentageText")
            }
        }
    }
    
    private var stageIndicator: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                stageIcon
                    .font(.system(size: 24))
                
                Text(organizer.organizationStage)
                    .font(.headline)
            }
            
            if isEstablishingConnection {
                HStack(spacing: 6) {
                    Text("Connecting to AI provider")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LoadingDotsView(dotCount: 3, dotSize: 5, color: .secondary)
                }
            } else if organizer.isStreaming {
                VStack(spacing: 8) {
                    // Funny message with fade animation
                    Text(currentFunnyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .opacity(funnyMessageOpacity)
                        .frame(height: 20)
                    
                    // File being analyzed with fade animation
                    if !currentFileDisplay.isEmpty {
                        HStack(spacing: 4) {
                            Text("Analyzing")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(currentFileDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .opacity(fileDisplayOpacity)
                        .frame(maxWidth: 300)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current organization stage: \(organizer.organizationStage)")
        .accessibilityIdentifier("AnalysisStageInfo")
    }
    
    private var isEstablishingConnection: Bool {
        if case .organizing = organizer.state {
            return organizer.organizationStage.contains("Establishing") && !organizer.isStreaming
        }
        return false
    }
    
    @ViewBuilder
    private var stageIcon: some View {
        if case .scanning = organizer.state {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse.byLayer, options: .repeating)
        } else if case .organizing = organizer.state {
            if isEstablishingConnection {
                Image(systemName: "network")
                    .foregroundStyle(.orange)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                Image(systemName: "brain.head.profile")
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse.byLayer, options: .repeating)
            }
        }
    }
    
    private var timeoutMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock")
                    .foregroundStyle(.orange)

                Text("Taking longer than expected")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text("AI organization can take a while depending on the number of files, model speed, and network conditions. For large directories, this may take a few minutes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 400)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Warning: Organization is taking longer than expected")
    }
    
    private var multitaskingHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.title3)
                .foregroundStyle(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Feel free to switch apps!")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text("Sorty will keep organizing in the background. We'll notify you when it's done.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
        .frame(maxWidth: 400)
    }
    
    // MARK: - AI Insights View
    
    private var aiInsightsView: some View {
        VStack(spacing: 12) {
            // Current insight (prominent display)
            if !organizer.currentInsight.isEmpty {
                currentInsightBubble
            }
            
            // Recent insights history
            if organizer.insightHistory.count > 1 {
                insightHistoryView
            }
        }
        .frame(maxWidth: 500)
    }
    
    private var currentInsightBubble: some View {
        HStack(spacing: 10) {
            // Pulsing indicator
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
                .scaleEffect(organizer.isStreaming ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: organizer.isStreaming)
            
            Text(organizer.currentInsight)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                )
        )
        .animation(nil, value: organizer.currentInsight)
    }
    
    private var insightHistoryView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(organizer.insightHistory.dropLast()) { insight in
                    InsightPill(insight: insight)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 4)
        }
        .frame(height: 32)
    }
    
    private var streamingPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.word.spacing")
                    .foregroundStyle(.purple)
                Text("AI Response")
                    .fontWeight(.medium)
            }
            .font(.caption)
            
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
                    .onChange(of: organizer.displayStreamingContent) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: 550, maxHeight: 180)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
        )
        .accessibilityLabel("AI response preview")
    }

    private var truncatedStreamContent: String {
        let content = organizer.displayStreamingContent
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
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .onChange(of: progress) { _, newValue in
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

// MARK: - Insight Pill

struct InsightPill: View {
    let insight: AIInsight
    
    private var iconColor: Color {
        switch insight.category {
        case .file: return .blue
        case .folder: return .orange
        case .constraint: return .yellow
        case .decision: return .green
        case .pattern: return .purple
        case .general: return .secondary
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: insight.category.icon)
                .font(.caption2)
                .foregroundStyle(iconColor)
            
            Text(insight.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.1))
        .clipShape(Capsule())
    }
}

#Preview {
    AnalysisView()
        .environmentObject(FolderOrganizer())
        .frame(width: 600, height: 400)
}
