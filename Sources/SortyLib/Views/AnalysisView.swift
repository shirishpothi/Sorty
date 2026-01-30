//
//  AnalysisView.swift
//  Sorty
//
//  Real-time organization display with streaming progress
//

import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @State private var hasAppeared = false
    @State private var currentFunnyMessage: String = ""
    @State private var currentFileDisplay: String = ""
    @State private var funnyMessageOpacity: Double = 0
    @State private var fileDisplayOpacity: Double = 0
    @State private var funnyMessageTimer: Timer?
    @State private var fileDisplayTimer: Timer?
    @State private var elapsedSeconds: Int = 0
    
    private enum MessageTier {
        case none
        case backgroundTip
        case takingLonger
    }
    
    private var currentMessageTier: MessageTier {
        if elapsedSeconds >= 60 || organizer.showTimeoutMessage {
            return .takingLonger
        } else if elapsedSeconds >= 30 {
            return .backgroundTip
        }
        return .none
    }
    
    private let calmerMessages = [
        "Still working...",
        "Almost there...",
        "Processing your files...",
        "Organizing in progress...",
        "Just a moment longer..."
    ]
    
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
        WorkflowContainer(currentStep: .analyze) {
            VStack(spacing: 28) {
                progressSection
                    .opacity(hasAppeared ? 1 : 0)
                    .scaleEffect(hasAppeared ? 1 : 0.9)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                stageIndicator
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)

                tieredNoticeView

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
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                .accessibilityIdentifier("AnalysisCancelButton")
            }
        }
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
            elapsedSeconds = Int(newTime)
        }
    }
    
    @ViewBuilder
    private var tieredNoticeView: some View {
        switch currentMessageTier {
        case .none:
            EmptyView()
        case .backgroundTip:
            multitaskingHint
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity
                ))
        case .takingLonger:
            timeoutMessage
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity),
                    removal: .opacity
                ))
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning: Organization is taking longer than usual")
        }
    }
    
    private func startFunnyMessageCycle() {
        // Initial message
        currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
        withAnimation(.easeIn(duration: 0.5)) {
            funnyMessageOpacity = 1
        }
        
        // Cycle messages every 4 seconds
        funnyMessageTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            Task { @MainActor in
                // Fade out
                withAnimation(.easeOut(duration: 0.4)) {
                    funnyMessageOpacity = 0
                }
                
                // Wait for fade out, then change message and fade in
                try? await Task.sleep(nanoseconds: 450_000_000)
                
                // After 30 seconds, use calmer messages instead
                if elapsedSeconds > 30 {
                    currentFunnyMessage = calmerMessages.randomElement() ?? calmerMessages[0]
                } else {
                    currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
                }
                
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
        InlineNotice(
            icon: "clock",
            title: "This is taking longer than usual",
            message: "Large folders may take 1-3 minutes. You can switch windows—we'll notify you when ready.",
            severity: .warning,
            actions: [
                InlineNoticeAction(title: "Try Faster Model", systemImage: "bolt") {
                    appState.selectedSettingsSection = .provider
                    appState.currentView = .settings
                },
                InlineNoticeAction(title: "Cancel", systemImage: "xmark") {
                    organizer.reset()
                }
            ]
        )
    }
    
    private var multitaskingHint: some View {
        InlineNotice(
            icon: "bell.badge",
            title: "Working in the background",
            message: "Sorty will send a notification when your preview is ready",
            severity: .tip
        )
        .accessibilityLabel("Background processing")
        .accessibilityHint("You will be notified when the preview is ready")
    }
    
    @State private var isHoveringHistory = false
    @State private var showDebugStream = false
    
    // MARK: - AI Insights View
    
    private var aiInsightsView: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 8) {
                if organizer.isStreaming {
                    LoadingDotsView(dotCount: 3, dotSize: 4, color: .purple.opacity(0.6))
                } else {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.purple.opacity(0.8))
                }
                
                Text(organizer.isStreaming ? "AI is reasoning..." : "Analysis complete")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if appState.debugMode {
                    Button {
                        withAnimation(.spring()) {
                            showDebugStream.toggle()
                        }
                    } label: {
                        Image(systemName: showDebugStream ? "terminal.fill" : "terminal")
                            .font(.caption)
                            .foregroundStyle(showDebugStream ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle raw AI stream")
                }
            }
            .padding(.horizontal, 4)
            
            // Current insight (Integrated Pill style)
            if !organizer.currentInsight.isEmpty {
                currentInsightPill
            }
            
            // Recent insights history (wrapped pills)
            if organizer.insightHistory.count > 1 {
                insightHistoryWrap
            }
            
            // Raw stream (Debug only)
            if showDebugStream && appState.debugMode {
                streamingPreview
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 550)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.primary.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        )
    }
    
    private var currentInsightPill: some View {
        HStack(spacing: 12) {
            // Pulsing indicator
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 20, height: 20)
                    .scaleEffect(organizer.isStreaming ? 1.4 : 1.0)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 10))
                    .foregroundStyle(.purple)
            }
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: organizer.isStreaming)
            
            Text(organizer.currentInsight)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.purple.opacity(0.1))
                .overlay(
                    Capsule()
                        .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                )
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: organizer.currentInsight)
    }
    
    private var insightHistoryWrap: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(Array(organizer.insightHistory.dropLast().reversed().prefix(4))) { insight in
                    InsightPill(insight: insight)
                        .opacity(isHoveringHistory ? 1.0 : 0.4)
                        .blur(radius: isHoveringHistory ? 0 : 0.5)
                        .animation(.spring(response: 0.3), value: isHoveringHistory)
                }
            }
        }
        .padding(.horizontal, 4)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3)) {
                isHoveringHistory = hovering
            }
        }
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

// MARK: - Inline Notice

struct InlineNoticeAction {
    let title: String
    let systemImage: String?
    let action: () -> Void
    
    init(title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

enum NoticeSeverity {
    case info
    case warning
    case tip
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .orange
        case .tip: return .green
        }
    }
    
    var defaultIcon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .tip: return "lightbulb.fill"
        }
    }
}

struct InlineNotice: View {
    let icon: String?
    let title: String
    let message: String?
    let severity: NoticeSeverity
    var actions: [InlineNoticeAction]
    
    init(
        icon: String? = nil,
        title: String,
        message: String? = nil,
        severity: NoticeSeverity = .info,
        actions: [InlineNoticeAction] = []
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.severity = severity
        self.actions = actions
    }
    
    @available(*, deprecated, message: "Use severity-based initializer instead")
    init(icon: String, title: String, message: String? = nil, tintColor: Color) {
        self.icon = icon
        self.title = title
        self.message = message
        self.severity = tintColor == .orange ? .warning : (tintColor == .green ? .tip : .info)
        self.actions = []
    }
    
    private var effectiveIcon: String {
        icon ?? severity.defaultIcon
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: effectiveIcon)
                    .font(.caption)
                    .foregroundStyle(severity.color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if let message = message {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer(minLength: 0)
            }
            
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(actions.indices, id: \.self) { index in
                        let action = actions[index]
                        Button {
                            action.action()
                        } label: {
                            HStack(spacing: 4) {
                                if let systemImage = action.systemImage {
                                    Image(systemName: systemImage)
                                        .font(.caption2)
                                }
                                Text(action.title)
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(severity.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(severity.color.opacity(0.12))
                        )
                    }
                }
                .padding(.leading, 20)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(severity.color.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(severity.color.opacity(0.15), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint(message ?? "")
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
        HStack(spacing: 6) {
            if let filePath = insight.filePath {
                FileThumbnailView(url: URL(fileURLWithPath: filePath), size: CGSize(width: 14, height: 14))
            } else if insight.category == .folder {
                // Use actual macOS folder icon for folder insights
                Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: insight.category.icon)
                    .font(.caption2)
                    .foregroundStyle(iconColor)
            }
            
            Text(insight.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

// MARK: - Flow Layout

public struct FlowLayout: Layout {
    public var spacing: CGFloat = 8
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutResult(for: subviews, in: proposal.width ?? 0)
        return CGSize(width: proposal.width ?? 0, height: result.height)
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutResult(for: subviews, in: bounds.width)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func layoutResult(for subviews: Subviews, in width: CGFloat) -> (positions: [CGPoint], height: CGFloat) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        
        return (positions, y + rowHeight)
    }
}

#Preview {
    AnalysisView()
        .environmentObject(FolderOrganizer())
        .frame(width: 600, height: 400)
}
