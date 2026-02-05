//
//  AnalysisView.swift
//  Sorty
//
//  Real-time organization display with streaming progress
//

import SwiftUI

// MARK: - Unified Refresh Manager

/// Consolidates multiple timers into a single refresh manager to reduce memory overhead
/// and potential retain cycles. Uses the shared RefreshManager for centralized control.
@MainActor
final class AnalysisRefreshManager: ObservableObject {
    @Published var currentFunnyMessage: String = ""
    @Published var currentFileDisplay: String = ""
    @Published var funnyMessageOpacity: Double = 0
    @Published var fileDisplayOpacity: Double = 0
    
    private var refreshManager: RefreshManager?
    private var fileNames: [String] = []
    private weak var organizer: FolderOrganizer?
    private var timerGroup: CoordinatedRefreshGroup?
    
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
    
    private let calmerMessages = [
        "Still working...",
        "Almost there...",
        "Processing your files...",
        "Organizing in progress...",
        "Just a moment longer..."
    ]
    
    func start(organizer: FolderOrganizer) {
        self.organizer = organizer
        collectFileNames()
        
        // Set initial values
        currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
        if !fileNames.isEmpty {
            currentFileDisplay = fileNames.randomElement() ?? ""
        }
        
        withAnimation(.easeIn(duration: 0.5)) {
            funnyMessageOpacity = 1
        }
        withAnimation(.easeIn(duration: 0.3)) {
            fileDisplayOpacity = 1
        }
        
        // Use the centralized RefreshManager with coordinated group
        refreshManager = RefreshManager()
        timerGroup = refreshManager?.createCoordinatedGroup()
        
        startRefreshLoop()
    }
    
    func stop() {
        // Cancel all timers in the coordinated group
        timerGroup?.cancelAll()
        timerGroup = nil
        refreshManager?.cancelAll()
        refreshManager = nil
        organizer = nil
        fileNames = []
    }
    
    func pause() {
        timerGroup?.pause()
    }
    
    func resume() {
        timerGroup?.resume()
    }
    
    private func collectFileNames() {
        guard let plan = organizer?.currentPlan else {
            fileNames = []
            return
        }
        
        func collect(from suggestions: [FolderSuggestion]) -> [String] {
            var names: [String] = []
            for suggestion in suggestions {
                names.append(contentsOf: suggestion.files.map { $0.displayName })
                names.append(contentsOf: collect(from: suggestion.subfolders))
            }
            return names
        }
        
        fileNames = collect(from: plan.suggestions) + plan.unorganizedFiles.map { $0.displayName }
    }
    
    private func startRefreshLoop() {
        // Use async tasks with weak self to prevent retain cycles
        // File display cycle: every 1.5s
        timerGroup?.addTimer(interval: 1.5) { [weak self] in
            Task { [weak self] in
                await self?.cycleFileDisplay()
            }
        }
        
        // Funny message cycle: every 4s
        timerGroup?.addTimer(interval: 4.0) { [weak self] in
            Task { [weak self] in
                await self?.cycleFunnyMessage()
            }
        }
    }
    
    private func cycleFunnyMessage() async {
        withAnimation(.easeOut(duration: 0.4)) {
            funnyMessageOpacity = 0
        }
        
        try? await Task.sleep(nanoseconds: 450_000_000)
        guard organizer != nil else { return } // Check if still valid
        
        let elapsedSeconds = Int(organizer?.elapsedTime ?? 0)
        if elapsedSeconds > 30 {
            currentFunnyMessage = calmerMessages.randomElement() ?? calmerMessages[0]
        } else {
            currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
        }
        
        withAnimation(.easeIn(duration: 0.4)) {
            funnyMessageOpacity = 1
        }
    }
    
    private func cycleFileDisplay() async {
        // Try to get file name from plan or streaming content
        var nextFileName: String?
        
        if !fileNames.isEmpty {
            nextFileName = fileNames.randomElement()
        } else if let content = organizer?.displayStreamingContent {
            nextFileName = extractFileNameFromContent(content)
        }
        
        guard let fileName = nextFileName, !fileName.isEmpty else { return }
        
        withAnimation(.easeOut(duration: 0.25)) {
            fileDisplayOpacity = 0
        }
        
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard organizer != nil else { return } // Check if still valid
        
        currentFileDisplay = fileName
        
        withAnimation(.easeIn(duration: 0.25)) {
            fileDisplayOpacity = 1
        }
    }
    
    private func extractFileNameFromContent(_ content: String) -> String? {
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
}

struct AnalysisView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var learningsManager: LearningsManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @StateObject private var refreshManager = AnalysisRefreshManager()
    @State private var hasAppeared = false
    @State private var elapsedSeconds: Int = 0
    @State private var isCancelHovered = false
    @State private var showCancelConfirmation = false
    
    private enum MessageTier {
        case none
        case backgroundTip
        case takingLonger
    }
    
    private var currentMessageTier: MessageTier {
        if elapsedSeconds >= 90 || organizer.showTimeoutMessage {
            return .takingLonger
        } else if elapsedSeconds >= 30 {
            return .backgroundTip
        }
        return .none
    }

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
                    showCancelConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                        Text("Cancel Generation")
                    }
                    .padding(.horizontal, 4)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .foregroundStyle(.red)
                .scaleEffect(isCancelHovered ? 1.03 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isCancelHovered)
                .onHover { hovering in
                    isCancelHovered = hovering
                }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(hasAppeared ? 1 : 0)
                .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                .accessibilityIdentifier("AnalysisCancelButton")
                .confirmationDialog(
                    "Cancel Organization?",
                    isPresented: $showCancelConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Cancel Generation", role: .destructive) {
                        recordCancelledAnalysis()
                        withAnimation(.easeOut(duration: 0.3)) {
                            organizer.reset()
                        }
                    }
                    Button("Continue", role: .cancel) { }
                } message: {
                    Text("This will stop the AI analysis and return to folder selection. Your progress will not be saved.")
                }
            }
        }
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
            refreshManager.start(organizer: organizer)
        }
        .onDisappear {
            refreshManager.stop()
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
                    Text(refreshManager.currentFunnyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .opacity(refreshManager.funnyMessageOpacity)
                        .frame(height: 20)
                    
                    // File being analyzed with fade animation
                    if !refreshManager.currentFileDisplay.isEmpty {
                        HStack(spacing: 4) {
                            Text("Analyzing")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(refreshManager.currentFileDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .opacity(refreshManager.fileDisplayOpacity)
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
                OrganizingMascotView()
            }
        }
    }
    
    private var timeoutMessage: some View {
        InlineNotice(
            icon: "folder.badge.gearshape",
            title: "Complex folder detected",
            message: "Large folders with many files may take 1-3 minutes to analyze. Feel free to switch windows—we'll notify you when ready.",
            severity: .info,
            actions: [
                InlineNoticeAction(title: "Cancel", systemImage: "xmark.circle") {
                    recordCancelledAnalysis()
                    withAnimation(.easeOut(duration: 0.3)) {
                        organizer.reset()
                    }
                },
                InlineNoticeAction(title: "Try Faster Model", systemImage: "bolt.circle") {
                    appState.selectedSettingsSection = .provider
                    appState.currentView = .settings
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
    
    /// Computed property to access cached insights for better performance
    private var cachedInsights: (current: String, history: [AIInsight]) {
        // Use the FolderOrganizer's cache to avoid re-parsing during render
        organizer.getCachedInsights()
    }
    
    private var aiInsightsView: some View {
        VStack(spacing: 16) {
            // Header with improved animation
            HStack(spacing: 8) {
                if organizer.isStreaming {
                    // Animated brain icon with glow effect
                    ZStack {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor.opacity(0.3))
                            .blur(radius: 4)
                            .scaleEffect(1.2)
                        
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse.byLayer, options: .repeating)
                    }
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                
                Text(organizer.isStreaming ? "AI is reasoning..." : "Analysis complete")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .contentTransition(.interpolate)
                
                if organizer.isStreaming {
                    // Animated bouncing dots
                    BouncingDotsView()
                }
                
                Spacer()
                
                if appState.debugMode {
                    Button {
                        withAnimation(.spring()) {
                            showDebugStream.toggle()
                        }
                    } label: {
                        Image(systemName: showDebugStream ? "terminal.fill" : "terminal")
                            .font(.caption)
                            .foregroundStyle(showDebugStream ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle raw AI stream")
                }
            }
            .padding(.horizontal, 4)
            
            // Current insight or receiving indicator
            let insights = cachedInsights
            let currentInsightItem = insights.history.last(where: { $0.text == insights.current })
            if !insights.current.isEmpty {
                currentInsightPill(insight: insights.current, detail: currentInsightItem)
            } else if organizer.isStreaming {
                // Show "Receiving AI response..." when streaming but no insights yet
                receivingResponseView
            }
            
            // Recent insights history (wrapped pills) - uses cached insights
            if insights.history.count > 1 {
                insightHistoryWrap(history: insights.history)
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
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
                )
        )
    }
    
    private var receivingResponseView: some View {
        HStack(spacing: 12) {
            // Typing indicator animation using BouncingDotsView
            BouncingDotsView()
                .foregroundStyle(Color.accentColor.opacity(0.8))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(0.1))
                )
            
            Text("Receiving AI response...")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.05))
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                )
        )
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private func currentInsightPill(insight: String, detail: AIInsight?) -> some View {
        HStack(spacing: 12) {
            // Icon based on insight content - Finder-style icons
            insightIcon(for: detail, fallbackText: insight)
                .frame(width: 24, height: 24)
            
            Text(insight)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            if organizer.isStreaming {
                // Small pulsing indicator
                Circle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .scaleEffect(organizer.isStreaming ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: organizer.isStreaming)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            Capsule()
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: insight)
    }
    
    @ViewBuilder
    private func insightIcon(for insight: AIInsight?, fallbackText: String) -> some View {
        if let filePath = insight?.filePath {
            let url = URL(fileURLWithPath: filePath)
            if url.hasDirectoryPath {
                return AnyView(FolderThumbnailView(url: url, size: CGSize(width: 20, height: 20)))
            }
            return AnyView(FileThumbnailView(url: url, size: CGSize(width: 20, height: 20)))
        }
        
        let lowercased = fallbackText.lowercased()
        
        if lowercased.contains("folder") || lowercased.contains("directory") || lowercased.contains("organizing") {
            return AnyView(
                Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            )
        } else if lowercased.contains("image") || lowercased.contains("photo") || lowercased.contains("picture") || lowercased.contains("screenshot") {
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Color.pink.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(nsImage: NSWorkspace.shared.icon(for: .image))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            )
        } else if lowercased.contains("document") || lowercased.contains("pdf") || lowercased.contains("file") {
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(nsImage: NSWorkspace.shared.icon(for: .pdf))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            )
        } else if lowercased.contains("video") || lowercased.contains("movie") {
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(nsImage: NSWorkspace.shared.icon(for: .movie))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            )
        } else if lowercased.contains("audio") || lowercased.contains("music") || lowercased.contains("sound") {
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(nsImage: NSWorkspace.shared.icon(for: .audio))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            )
        } else if lowercased.contains("code") || lowercased.contains("script") || lowercased.contains("programming") {
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Color.cyan.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(nsImage: NSWorkspace.shared.icon(for: .sourceCode))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            )
        } else if lowercased.contains("archive") || lowercased.contains("zip") || lowercased.contains("compress") {
            return AnyView(
                ZStack {
                    Circle()
                        .fill(Color.brown.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(nsImage: NSWorkspace.shared.icon(for: .archive))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            )
        }
        
        return AnyView(
            Image(nsImage: NSWorkspace.shared.icon(for: .data))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        )
    }
    
    private func insightHistoryWrap(history: [AIInsight]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(Array(history.dropLast().reversed().prefix(4))) { insight in
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

    private func recordCancelledAnalysis() {
        guard let directory = appState.selectedDirectory ?? organizer.currentDirectory else { return }

        let plan = organizer.currentPlan
        let fileCount = max(plan?.totalFiles ?? 0, organizer.scannedFileCount)
        let proposedFolderCount = plan?.totalFolders ?? 0
        let folderNames = plan?.suggestions.map { $0.folderName }

        learningsManager.recordCancelledOrganization(
            folderPath: directory.path,
            fileCount: fileCount,
            proposedFolderCount: proposedFolderCount,
            instructions: organizer.customInstructions.isEmpty ? nil : organizer.customInstructions,
            stage: organizer.organizationStage.isEmpty ? "analysis" : organizer.organizationStage,
            proposedFolderNames: (folderNames?.isEmpty == false) ? folderNames : nil,
            proposedStructureSummary: nil,
            fileExtensionCounts: nil,
            regenerationCount: plan?.version ?? 0,
            regenerationInstructions: nil,
            aiModel: settingsViewModel.config.model
        )
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
    
    private var fileIcon: NSImage {
        if let filePath = insight.filePath {
            if FileManager.default.fileExists(atPath: filePath) {
                return NSWorkspace.shared.icon(forFile: filePath)
            }
            let ext = URL(fileURLWithPath: filePath).pathExtension
            if !ext.isEmpty {
                return NSWorkspace.shared.icon(forFileType: ext)
            }
        }
        
        let text = insight.text
        if let dotIndex = text.lastIndex(of: ".") {
            let ext = String(text[text.index(after: dotIndex)...])
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).first ?? ""
            if !ext.isEmpty {
                return NSWorkspace.shared.icon(forFileType: ext)
            }
        }
        
        return NSWorkspace.shared.icon(for: .data)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            if insight.category == .folder {
                Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else if insight.category == .file || insight.filePath != nil {
                Image(nsImage: fileIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(for: .data))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
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

#Preview("Analysis View - Scanning") {
    AnalysisView()
        .environmentObject({
            let organizer = FolderOrganizer()
            organizer.state = .scanning
            organizer.progress = 0.45
            organizer.organizationStage = "Scanning files..."
            organizer.elapsedTime = 3.5
            return organizer
        }())
        .environmentObject(AppState.preview)
        .frame(width: 700, height: 500)
}

#Preview("Analysis View - Organizing") {
    AnalysisView()
        .environmentObject({
            let organizer = FolderOrganizer()
            organizer.state = .organizing
            organizer.progress = 0.75
            organizer.organizationStage = "Analyzing with AI..."
            organizer.elapsedTime = 8.2
            organizer.isStreaming = true
            organizer.currentInsight = "Creating project folders based on file types"
            return organizer
        }())
        .environmentObject(AppState.preview)
        .frame(width: 700, height: 550)
}

#Preview("Analysis View - Applying") {
    AnalysisView()
        .environmentObject({
            let organizer = FolderOrganizer()
            organizer.state = .applying
            organizer.progress = 0.85
            organizer.organizationStage = "Moving files..."
            organizer.elapsedTime = 12.5
            return organizer
        }())
        .environmentObject(AppState.preview)
        .frame(width: 700, height: 500)
}

#Preview("Analysis View - Long Running") {
    AnalysisView()
        .environmentObject({
            let organizer = FolderOrganizer()
            organizer.state = .organizing
            organizer.progress = 0.65
            organizer.organizationStage = "Processing large folder..."
            organizer.elapsedTime = 65.0
            organizer.showTimeoutMessage = true
            organizer.isStreaming = true
            return organizer
        }())
        .environmentObject(AppState.preview)
        .frame(width: 700, height: 550)
}
