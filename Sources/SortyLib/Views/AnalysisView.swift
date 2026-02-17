//
//  AnalysisView.swift
//  Sorty
//
//  Real-time organization display with streaming progress
//

import SwiftUI
import Combine
import UniformTypeIdentifiers

// MARK: - Analysis Icon Provider

@MainActor
enum AnalysisIconProvider {
    private static var cache: [String: NSImage] = [:]

    static func icon(for contentType: UTType) -> NSImage {
        let key = "type:\(contentType.identifier)"
        if let image = cache[key] {
            return image
        }
        let image = NSWorkspace.shared.icon(for: contentType)
        image.size = NSSize(width: 32, height: 32)
        cache[key] = image
        return image
    }

    static func icon(forFileExtension fileExtension: String) -> NSImage {
        let normalizedExtension = fileExtension
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedExtension.isEmpty else {
            return icon(for: .data)
        }

        let key = "ext:\(normalizedExtension)"
        if let image = cache[key] {
            return image
        }
        let image = NSWorkspace.shared.icon(forFileType: normalizedExtension)
        image.size = NSSize(width: 32, height: 32)
        cache[key] = image
        return image
    }
}

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
    private(set) var fileNames: [String] = []
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
        timerGroup?.cancelAll()
        timerGroup = nil
        refreshManager?.cancelAll()
        refreshManager = nil
        organizer = nil
        fileNames = []
        currentFunnyMessage = ""
        currentFileDisplay = ""
        funnyMessageOpacity = 0
        fileDisplayOpacity = 0
    }
    
    func pause() {
        timerGroup?.pause()
    }
    
    func resume() {
        timerGroup?.resume()
    }
    
    private func collectFileNames() {
        var names: [String] = []
        
        if let plan = organizer?.currentPlan {
            func collect(from suggestions: [FolderSuggestion]) -> [String] {
                var result: [String] = []
                for suggestion in suggestions {
                    result.append(contentsOf: suggestion.files.map { $0.displayName })
                    result.append(contentsOf: collect(from: suggestion.subfolders))
                }
                return result
            }
            names = collect(from: plan.suggestions) + plan.unorganizedFiles.map { $0.displayName }
        }
        
        if names.isEmpty, let scanned = organizer?.scannedFiles, !scanned.isEmpty {
            names = scanned.map { $0.displayName }
        }
        
        fileNames = names
    }
    
    private func startRefreshLoop() {
        // Use async tasks with weak self to prevent retain cycles
        // File display cycle: every 3s (reduced from 1.5s to cut redraw frequency)
        timerGroup?.addTimer(interval: 3.0) { [weak self] in
            Task { [weak self] in
                await self?.cycleFileDisplay()
            }
        }
        
        // Funny message cycle: every 5s (reduced from 4s)
        timerGroup?.addTimer(interval: 5.0) { [weak self] in
            Task { [weak self] in
                await self?.cycleFunnyMessage()
            }
        }
    }
    
    private func cycleFunnyMessage() async {
        guard organizer != nil else { return }
        
        withAnimation(.easeInOut(duration: 0.55)) {
            funnyMessageOpacity = 0
        }
        
        try? await Task.sleep(nanoseconds: 520_000_000)
        guard organizer != nil else { return }
        
        let elapsedSeconds = Int(organizer?.elapsedTime ?? 0)
        if elapsedSeconds > 30 {
            currentFunnyMessage = calmerMessages.randomElement() ?? calmerMessages[0]
        } else {
            currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
        }
        
        withAnimation(.easeInOut(duration: 0.65)) {
            funnyMessageOpacity = 1
        }
    }
    
    private func cycleFileDisplay() async {
        guard organizer != nil else { return }
        
        var nextFileName: String?
        
        if !fileNames.isEmpty {
            nextFileName = fileNames.randomElement()
        } else if let content = organizer?.displayStreamingContent {
            nextFileName = extractFileNameFromContent(content)
        }
        
        guard let fileName = nextFileName, !fileName.isEmpty else { return }
        
        withAnimation(.easeInOut(duration: 0.35)) {
            fileDisplayOpacity = 0
        }
        
        try? await Task.sleep(nanoseconds: 360_000_000)
        guard organizer != nil else { return }
        
        currentFileDisplay = fileName
        
        withAnimation(.easeInOut(duration: 0.4)) {
            fileDisplayOpacity = 1
        }
    }
    
    private static let fileNameRegexes: [NSRegularExpression] = {
        let patterns = [
            "\"name\":\\s*\"([^\"]+)\"",
            "\"file\":\\s*\"([^\"]+)\"",
            "([\\w\\-\\.]+\\.(pdf|doc|docx|jpg|png|txt|md|swift|js|py|zip|mp3|mp4))"
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: .caseInsensitive) }
    }()
    
    private func extractFileNameFromContent(_ content: String) -> String? {
        for regex in Self.fileNameRegexes {
            let range = NSRange(content.startIndex..., in: content)
            let matches = regex.matches(in: content, options: [], range: range)
            if let match = matches.last, let range = Range(match.range(at: 1), in: content) {
                return String(content[range])
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
    @State private var isCancelHovered = false
    @State private var showCancelConfirmation = false
    @State private var showFasterModelPicker = false
    
    private enum MessageTier {
        case none
        case backgroundTip
        case takingLonger
    }
    
    private var currentMessageTier: MessageTier {
        let elapsedSeconds = Int(organizer.elapsedTime)
        if elapsedSeconds >= 90 || organizer.showTimeoutMessage {
            return .takingLonger
        } else if elapsedSeconds >= 30 {
            return .backgroundTip
        }
        return .none
    }

    var body: some View {
        WorkflowContainer(currentStep: .analyze) {
            Spacer(minLength: 20)
            
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
            .frame(maxHeight: .infinity)
            
            Spacer(minLength: 20)
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
        StreamingProgressRing(
            progress: organizer.progress,
            elapsedSeconds: Int(organizer.elapsedTime),
            isEstablishingConnection: isEstablishingConnection
        )
    }

    private var stageIndicator: some View {
        AIReasoningStatus(
            state: organizer.state,
            organizationStage: organizer.organizationStage,
            isStreaming: organizer.isStreaming,
            isEstablishingConnection: isEstablishingConnection,
            funnyMessage: refreshManager.currentFunnyMessage,
            funnyMessageOpacity: refreshManager.funnyMessageOpacity,
            fileDisplay: refreshManager.currentFileDisplay,
            fileDisplayOpacity: refreshManager.fileDisplayOpacity
        )
    }
    
    private var isEstablishingConnection: Bool {
        if case .organizing = organizer.state {
            let stage = organizer.organizationStage
            let isConnecting = stage.contains("Establishing") || stage.contains("Connecting")
            return isConnecting && !organizer.isStreaming
        }
        return false
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
                    showFasterModelPicker = true
                }
            ]
        )
        .sheet(isPresented: $showFasterModelPicker) {
            ModelSelectionPopover(
                isPresented: $showFasterModelPicker,
                currentProvider: settingsViewModel.config.provider,
                currentModel: settingsViewModel.config.model,
                onSelect: { provider, model in
                    showFasterModelPicker = false
                    Task {
                        try? await organizer.regenerateWithModel(
                            provider: provider,
                            model: model
                        )
                    }
                }
            )
        }
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
    
    // MARK: - AI Insights View
    
    private var cachedInsights: (current: String, history: [AIInsight]) {
        organizer.getCachedInsights()
    }
    
    private var aiInsightsView: some View {
        InsightHistorySection(
            isStreaming: organizer.isStreaming,
            insights: cachedInsights,
            debugModeEnabled: appState.debugMode,
            streamPreview: organizer.truncatedDisplayStreamingContent
        )
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

private struct StreamingProgressRing: View {
    let progress: Double
    let elapsedSeconds: Int
    let isEstablishingConnection: Bool

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                SortyGradientCircularProgress(
                    progress: progress,
                    size: 120,
                    lineWidth: 8
                )
                .shimmer(isLoading: isEstablishingConnection)
                
                VStack(spacing: 2) {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.3), value: Int(progress * 100))

                    if elapsedSeconds > 0 {
                        Text(Self.formatTime(elapsedSeconds))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .accessibilityIdentifier("AnalysisPercentageText")
            }
        }
    }

    private static func formatTime(_ elapsedSeconds: Int) -> String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

private struct AIReasoningStatus: View {
    let state: OrganizationState
    let organizationStage: String
    let isStreaming: Bool
    let isEstablishingConnection: Bool
    let funnyMessage: String
    let funnyMessageOpacity: Double
    let fileDisplay: String
    let fileDisplayOpacity: Double

    private var isAnalyzingStage: Bool {
        let stage = organizationStage.lowercased()
        return stage.contains("analyz") || stage.contains("analys")
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                stageIcon
                    .font(.system(size: 24))
                
                Text(organizationStage)
                    .font(.headline)
                    .shimmer(isLoading: isAnalyzingStage)
            }
            .modifier(SliverMotionEffect(isActive: isAnalyzingStage))
            
            if isEstablishingConnection {
                HStack(spacing: 6) {
                    Text("Connecting to AI provider")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    LoadingDotsView(dotCount: 3, dotSize: 5, color: .secondary)
                }
                .transition(.opacity.animation(.spring(response: 0.4, dampingFraction: 0.85)))
            } else if isStreaming {
                VStack(spacing: 5) {
                    Text(funnyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .opacity(funnyMessageOpacity)
                        .offset(y: funnyMessageOpacity > 0.5 ? 0 : 2)
                        .blur(radius: funnyMessageOpacity > 0.5 ? 0 : 0.35)
                        .animation(.easeInOut(duration: 0.6), value: funnyMessageOpacity)
                        .frame(height: 20)
                    
                    if !fileDisplay.isEmpty {
                        HStack(spacing: 4) {
                            Text("Analysing")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Text(fileDisplay)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .shimmer(isLoading: true)
                        .opacity(fileDisplayOpacity)
                        .modifier(SliverMotionEffect(isActive: true))
                        .frame(maxWidth: 300)
                    }
                }
                .transition(.opacity.animation(.spring(response: 0.4, dampingFraction: 0.85)))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Current organization stage: \(organizationStage)")
        .accessibilityIdentifier("AnalysisStageInfo")
    }

    @ViewBuilder
    private var stageIcon: some View {
        if case .scanning = state {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse.byLayer, options: .repeating)
        } else if case .organizing = state {
            if isEstablishingConnection {
                Image(systemName: "network")
                    .foregroundStyle(.orange)
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            } else {
                ZStack {
                    PingRingView()
                    OrganizingMascotView()
                        .drawingGroup()
                }
            }
        }
    }
}

private struct SliverMotionEffect: ViewModifier {
    let isActive: Bool
    @State private var animate = false

    func body(content: Content) -> some View {
        content
            .offset(x: isActive && animate ? 0.8 : -0.8)
            .opacity(isActive ? (animate ? 1.0 : 0.94) : 1.0)
            .animation(
                isActive
                    ? .easeInOut(duration: 1.6).repeatForever(autoreverses: true)
                    : .default,
                value: animate
            )
            .onAppear {
                guard isActive else { return }
                animate = true
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    animate = true
                } else {
                    animate = false
                }
            }
    }
}

@MainActor
final class AnalysisInsightViewState: ObservableObject {
    @Published var isHoveringHistory = false
    @Published var showDebugStream = false
    @Published var isExpanded = true
}

private struct InsightHistorySection: View {
    let isStreaming: Bool
    let insights: (current: String, history: [AIInsight])
    let debugModeEnabled: Bool
    let streamPreview: String
    
    @StateObject private var viewState = AnalysisInsightViewState()

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewState.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if isStreaming {
                        if let nsImage = SortyResources.image(named: "SortyMascot") {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.callout)
                                .foregroundStyle(Color.accentColor)
                                .symbolEffect(.pulse.byLayer, options: .repeating)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.green)
                    }
                    
                    Text(isStreaming ? "AI is reasoning..." : "Analysis complete")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    
                    if isStreaming {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                    
                    Spacer()
                    
                    let insightCount = insights.history.count
                    if insightCount > 0 {
                        Text("\(insightCount)")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    
                    if debugModeEnabled {
                        Button {
                            withAnimation(.spring()) {
                                viewState.showDebugStream.toggle()
                            }
                        } label: {
                            Image(systemName: viewState.showDebugStream ? "terminal.fill" : "terminal")
                                .font(.caption)
                                .foregroundStyle(viewState.showDebugStream ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Toggle raw AI stream")
                    }
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(viewState.isExpanded ? 0 : -90))
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: viewState.isExpanded)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: viewState.isExpanded ? 0 : 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.08),
                                    Color.accentColor.opacity(0.03)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .contentShape(RoundedRectangle(cornerRadius: viewState.isExpanded ? 0 : 16))
            
            if viewState.isExpanded {
                LazyVStack(spacing: 16) {
                    let currentInsightItem = insights.history.last(where: { $0.text == insights.current })
                    if !insights.current.isEmpty {
                        currentInsightPill(insight: insights.current, detail: currentInsightItem)
                    } else if isStreaming {
                        receivingResponseView
                    }
                    
                    if insights.history.count > 1 {
                        insightHistoryWrap(history: insights.history)
                    }
                    
                    if viewState.showDebugStream && debugModeEnabled {
                        streamingPreview
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: 550)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .frame(maxHeight: 220)
    }

    private var receivingResponseView: some View {
        HStack(spacing: 12) {
            SortyGradientLoadingBar(width: 84, height: 8)
                .padding(.vertical, 6)
            
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
            insightIcon(for: detail, fallbackText: insight)
                .frame(width: 24, height: 24)
            
            Text(insight)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            if isStreaming {
                Circle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 6, height: 6)
                    .scaleEffect(isStreaming ? 1.3 : 1.0)
                    .animation(.default.speed(0.8), value: isStreaming)
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
    }

    @ViewBuilder
    private func insightIcon(for insight: AIInsight?, fallbackText: String) -> some View {
        if let filePath = insight?.filePath {
            let url = URL(fileURLWithPath: filePath)
            if url.hasDirectoryPath {
                FolderThumbnailView(url: url, size: CGSize(width: 20, height: 20))
            } else {
                FileThumbnailView(url: url, size: CGSize(width: 20, height: 20))
            }
        } else {
            let iconStyle = fallbackIconStyle(for: fallbackText)
            if let tint = iconStyle.tint {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(nsImage: AnalysisIconProvider.icon(for: iconStyle.type))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                }
            } else {
                Image(nsImage: AnalysisIconProvider.icon(for: iconStyle.type))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
        }
    }

    private func insightHistoryWrap(history: [AIInsight]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                ForEach(Array(history.dropLast().reversed().prefix(3))) { insight in
                    InsightPill(insight: insight)
                        .opacity(viewState.isHoveringHistory ? 1.0 : 0.4)
                        .blur(radius: viewState.isHoveringHistory ? 0 : 0.5)
                        .animation(.spring(response: 0.3), value: viewState.isHoveringHistory)
                }
            }
        }
        .padding(.horizontal, 4)
        .onHover { hovering in
            withAnimation(.spring(response: 0.3)) {
                viewState.isHoveringHistory = hovering
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
                        Text(streamPreview)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onChange(of: streamPreview) { _, _ in
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

    private func fallbackIconStyle(for text: String) -> (type: UTType, tint: Color?) {
        let lowercased = text.lowercased()
        if lowercased.contains("folder") || lowercased.contains("directory") || lowercased.contains("organizing") {
            return (.folder, nil)
        }
        if lowercased.contains("image") || lowercased.contains("photo") || lowercased.contains("picture") || lowercased.contains("screenshot") {
            return (.image, .pink)
        }
        if lowercased.contains("document") || lowercased.contains("pdf") || lowercased.contains("file") {
            return (.pdf, .blue)
        }
        if lowercased.contains("video") || lowercased.contains("movie") {
            return (.movie, .orange)
        }
        if lowercased.contains("audio") || lowercased.contains("music") || lowercased.contains("sound") {
            return (.audio, .red)
        }
        if lowercased.contains("code") || lowercased.contains("script") || lowercased.contains("programming") {
            return (.sourceCode, .cyan)
        }
        if lowercased.contains("archive") || lowercased.contains("zip") || lowercased.contains("compress") {
            return (.archive, .brown)
        }
        return (.data, nil)
    }
}

// MARK: - Animated Progress Ring

struct AnimatedProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let color: Color

    init(progress: Double, lineWidth: CGFloat = 8, color: Color = .blue) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.color = color
    }

    var body: some View {
        SortyGradientCircularProgress(
            progress: progress,
            accent: color,
            size: 120,
            lineWidth: lineWidth
        )
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
    
    private var resolvedIcon: NSImage {
        if insight.category == .folder {
            return AnalysisIconProvider.icon(for: .folder)
        }

        if let filePath = insight.filePath {
            let ext = URL(fileURLWithPath: filePath).pathExtension
            if !ext.isEmpty {
                return AnalysisIconProvider.icon(forFileExtension: ext)
            }
        }
        
        let text = insight.text
        if let dotIndex = text.lastIndex(of: ".") {
            let ext = String(text[text.index(after: dotIndex)...])
                .trimmingCharacters(in: .whitespaces)
                .components(separatedBy: .whitespaces).first ?? ""
            if !ext.isEmpty {
                return AnalysisIconProvider.icon(forFileExtension: ext)
            }
        }
        
        return AnalysisIconProvider.icon(for: .data)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: resolvedIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
            
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

private struct PingRingView: View {
    @State private var ping = false
    
    var body: some View {
        Circle()
            .stroke(Color.accentColor.opacity(ping ? 0 : 0.3), lineWidth: 2)
            .frame(width: 32, height: 32)
            .scaleEffect(ping ? 2.0 : 1.0)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                    ping = true
                }
            }
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
