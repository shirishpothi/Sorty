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
    @Published var funnyMessageOpacity: Double = 0
    
    private var refreshManager: RefreshManager?
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
        
        // Set initial values
        currentFunnyMessage = funnyMessages.randomElement() ?? funnyMessages[0]
        
        withAnimation(.easeIn(duration: 0.5)) {
            funnyMessageOpacity = 1
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
        currentFunnyMessage = ""
        funnyMessageOpacity = 0
    }
    
    func pause() {
        timerGroup?.pause()
    }
    
    func resume() {
        timerGroup?.resume()
    }
    
    private func startRefreshLoop() {
        // Use async tasks with weak self to prevent retain cycles
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
}

struct AnalysisView: View {
    @EnvironmentObject var organizer: FolderOrganizer
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var learningsManager: LearningsManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @AppStorage("analysis.liveInsightsEnabled") private var liveInsightsEnabled = true
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
            
            VStack(spacing: 24) {
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
            organizer.setLiveInsightsEnabled(liveInsightsEnabled)
            refreshManager.start(organizer: organizer)
        }
        .onDisappear {
            refreshManager.stop()
        }
        .onChange(of: liveInsightsEnabled) { _, enabled in
            organizer.setLiveInsightsEnabled(enabled)
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
            funnyMessageOpacity: refreshManager.funnyMessageOpacity
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
            title: "Complex folder detected —",
            message: "Large folders with many files may take 1-3 minutes to analyze. Feel free to switch windows—we'll notify you when ready.",
            severity: .info,
            actions: [
                InlineNoticeAction(title: "Try Faster Model", systemImage: "bolt.circle") {
                    showFasterModelPicker = true
                }
            ],
            isCentered: true
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
            severity: .tip,
            isCentered: true
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
            streamPreview: organizer.truncatedDisplayStreamingContent,
            liveInsightsEnabled: $liveInsightsEnabled
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
                    lineWidth: 8,
                    showsShimmer: false
                )
                
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

    private var isAnalyzingStage: Bool {
        let stage = organizationStage.lowercased()
        return stage.contains("analyz") || stage.contains("analys")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            stageIcon
                .font(.system(size: 24))

            VStack(alignment: .leading, spacing: 2) {
                Text(organizationStage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textShimmer(isLoading: isAnalyzingStage, phaseOffset: 0.08, intensity: 1.55)

                if isEstablishingConnection {
                    HStack(spacing: 6) {
                        Text("Connecting to AI provider")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textShimmer(isLoading: true, phaseOffset: 0.34, intensity: 1.65)

                        LoadingDotsView(dotCount: 3, dotSize: 5, color: .secondary)
                    }
                    .transition(.opacity.animation(.spring(response: 0.4, dampingFraction: 0.85)))
                } else if isStreaming {
                    Text(funnyMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textShimmer(isLoading: true, phaseOffset: 0.62, intensity: 1.65)
                        .opacity(funnyMessageOpacity)
                        .offset(y: funnyMessageOpacity > 0.5 ? 0 : 1)
                        .blur(radius: funnyMessageOpacity > 0.5 ? 0 : 0.3)
                        .animation(.easeInOut(duration: 0.6), value: funnyMessageOpacity)
                        .transition(.opacity.animation(.spring(response: 0.4, dampingFraction: 0.85)))
                }
            }
        }
        .padding(.leading, -10) // Move the whole group slightly left to compensate for mascot's orbit padding
        .frame(maxWidth: .infinity, alignment: .center)
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
                }
            }
        }
    }
}

@MainActor
final class AnalysisInsightViewState: ObservableObject {
    @Published var showDebugStream = false
    @Published var isExpanded = true
}

private struct InsightHistorySection: View {
    let isStreaming: Bool
    let insights: (current: String, history: [AIInsight])
    let debugModeEnabled: Bool
    let streamPreview: String
    @Binding var liveInsightsEnabled: Bool
    
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
                    
                    Text(headerTitle)
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

                    if isStreaming {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                liveInsightsEnabled.toggle()
                                if !liveInsightsEnabled {
                                    viewState.showDebugStream = false
                                }
                            }
                        } label: {
                            Image(systemName: liveInsightsEnabled ? "bolt.badge.checkmark" : "bolt.slash")
                                .font(.caption)
                                .foregroundStyle(liveInsightsEnabled ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(liveInsightsEnabled ? "Disable streamed live insights" : "Enable streamed live insights")
                        .accessibilityIdentifier("LiveInsightsToggle")
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
                        .disabled(!liveInsightsEnabled)
                        .opacity(liveInsightsEnabled ? 1 : 0.45)
                        .help(liveInsightsEnabled ? "Toggle raw AI stream" : "Enable live insights to preview raw AI stream")
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
                LazyVStack(spacing: 14) {
                    liveInsightsPrimaryContent

                    if liveInsightsEnabled && viewState.showDebugStream && debugModeEnabled {
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
        .onChange(of: liveInsightsEnabled) { _, enabled in
            if !enabled {
                viewState.showDebugStream = false
            }
        }
    }

    private var headerTitle: String {
        guard isStreaming else { return "Analysis complete" }
        return "AI is reasoning..."
    }

    @ViewBuilder
    private var liveInsightsPrimaryContent: some View {
        let currentInsightItem = insights.history.last(where: { $0.text == insights.current })
        if liveInsightsEnabled, !insights.current.isEmpty {
            currentInsightPill(
                insight: insights.current,
                detail: currentInsightItem,
                fallbackCategory: currentInsightItem?.category
            )
        } else if liveInsightsEnabled, let fallbackInsight = streamFallbackInsight {
            currentInsightPill(
                insight: fallbackInsight,
                detail: nil,
                fallbackCategory: inferredInsightCategory(for: fallbackInsight)
            )
        } else if isStreaming {
            receivingResponseView
        }

        if liveInsightsEnabled && insights.history.count > 1 {
            insightHistoryScroller(
                entries: Array(insights.history.dropLast().reversed()),
                markFirstAsLatest: false
            )
        }
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

    private var streamFallbackInsight: String? {
        let content = streamPreview
            .replacingOccurrences(of: "...", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }

        if let assignment = extractJSONAssignmentSnippet(from: content) {
            return assignment
        }

        let plainLine = content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .reversed()
            .first { line in
                let lower = line.lowercased()
                return line.count >= 12 &&
                    !line.contains("{") &&
                    !line.contains("}") &&
                    !lower.hasPrefix("\"folders\"") &&
                    !lower.hasPrefix("\"files\"")
            }

        guard let plainLine else { return nil }
        return plainLine.count > 90 ? String(plainLine.prefix(90)) + "..." : plainLine
    }

    private func extractJSONAssignmentSnippet(from text: String) -> String? {
        let folderPattern = #""name"\s*:\s*"([^"\n]{2,80})""#
        let filePattern = #""([^"\n]{2,140}\.[a-zA-Z0-9]{1,12})""#

        guard let folderRegex = try? NSRegularExpression(pattern: folderPattern, options: [.caseInsensitive]),
              let fileRegex = try? NSRegularExpression(pattern: filePattern, options: []) else {
            return nil
        }

        let folderMatches = folderRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))
        let fileMatches = fileRegex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text))

        guard let folderMatch = folderMatches.last,
              let folderRange = Range(folderMatch.range(at: 1), in: text) else {
            return nil
        }

        let folderName = String(text[folderRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLikelyInsightFolderName(folderName) else { return nil }

        if let fileMatch = fileMatches.last,
           let fileRange = Range(fileMatch.range(at: 1), in: text) {
            let fileName = URL(fileURLWithPath: String(text[fileRange])).lastPathComponent
            if isLikelyFileName(fileName) {
                return "Assigning \(fileName) to \(folderName)"
            }
        }

        return "Preparing folder \(folderName)"
    }

    private func isLikelyInsightFolderName(_ candidate: String) -> Bool {
        let normalized = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))
            .lowercased()
        guard normalized.count >= 2, normalized.count <= 80 else { return false }
        guard !normalized.contains("{"), !normalized.contains("}"), !normalized.contains("/") else { return false }
        guard URL(fileURLWithPath: normalized).pathExtension.isEmpty else { return false }

        let blocked: Set<String> = [
            "a", "an", "and", "as", "at", "by", "for", "from", "gets", "in", "is", "it",
            "name", "of", "on", "or", "that", "the", "this", "to", "with", "folder",
            "folders", "file", "files", "filename", "json", "reasoning", "notes",
            "description", "content", "data", "true", "false", "null"
        ]
        return !blocked.contains(normalized)
    }

    private func isLikelyFileName(_ candidate: String) -> Bool {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 3, normalized.count <= 220 else { return false }
        let ext = URL(fileURLWithPath: normalized).pathExtension
        return !ext.isEmpty
    }

    private func inferredInsightCategory(for text: String) -> AIInsight.Category {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("file:") || mentionedFileExtension(in: text) != nil {
            return .file
        }
        if trimmed.hasPrefix("folder:") || mentionsFolderContext(in: text) {
            return .folder
        }
        if trimmed.hasPrefix("pattern:") { return .pattern }
        if trimmed.hasPrefix("decision:") { return .decision }
        if trimmed.hasPrefix("constraint:") { return .constraint }
        return .general
    }

    private func currentInsightPill(insight: String, detail: AIInsight?, fallbackCategory: AIInsight.Category?) -> some View {
        HStack(spacing: 12) {
            insightIcon(for: detail, fallbackText: insight, fallbackCategory: fallbackCategory)
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
    private func insightIcon(for insight: AIInsight?, fallbackText: String, fallbackCategory: AIInsight.Category?) -> some View {
        if let filePath = insight?.filePath {
            let url = URL(fileURLWithPath: filePath)
            if url.hasDirectoryPath {
                FolderThumbnailView(url: url, size: CGSize(width: 20, height: 20))
            } else {
                FileThumbnailView(url: url, size: CGSize(width: 20, height: 20))
            }
        } else if let category = insight?.category ?? fallbackCategory {
            if category == .folder {
                Image(nsImage: AnalysisIconProvider.icon(for: .folder))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            } else if category == .file {
                if let ext = mentionedFileExtension(in: fallbackText), !ext.isEmpty {
                    Image(nsImage: AnalysisIconProvider.icon(forFileExtension: ext))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                } else {
                    Image(nsImage: AnalysisIconProvider.icon(for: .data))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                }
            } else {
                categoryIndicator(for: category)
            }
        } else if let ext = mentionedFileExtension(in: fallbackText), !ext.isEmpty {
            Image(nsImage: AnalysisIconProvider.icon(forFileExtension: ext))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else if mentionsFolderContext(in: fallbackText) {
            Image(nsImage: AnalysisIconProvider.icon(for: .folder))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 20)
        } else {
            categoryIndicator(for: .general)
        }
    }

    @ViewBuilder
    private func categoryIndicator(for category: AIInsight.Category) -> some View {
        Circle()
            .fill(categoryColor(for: category).opacity(0.28))
            .overlay(
                Circle()
                    .stroke(categoryColor(for: category).opacity(0.55), lineWidth: 1)
            )
            .frame(width: 10, height: 10)
            .padding(6)
    }

    private func categoryColor(for category: AIInsight.Category) -> Color {
        switch category {
        case .file: return .blue
        case .folder: return .orange
        case .constraint: return .yellow
        case .decision: return .green
        case .pattern: return .purple
        case .general: return .secondary
        }
    }

    private func mentionedFileExtension(in text: String) -> String? {
        let pattern = #"(?:\"|')?([A-Za-z0-9_\-\(\) ]+\.([A-Za-z0-9]{1,12}))(?:\"|')?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.matches(in: text, options: [], range: NSRange(text.startIndex..., in: text)).last,
              let extRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        let ext = String(text[extRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ext.isEmpty ? nil : ext
    }

    private func mentionsFolderContext(in text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("folder") || lowered.contains("directory") {
            return true
        }
        return mentionedFileExtension(in: text) != nil && lowered.contains(" to ")
    }

    private func insightHistoryScroller(entries: [AIInsight], markFirstAsLatest: Bool) -> some View {
        ScrollView {
            FlowLayout(spacing: 6) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, insight in
                    HStack(spacing: 4) {
                        InsightPill(insight: insight)

                        if markFirstAsLatest, index == 0 {
                            Text("Latest")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.14))
                                )
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 170)
        .scrollIndicators(.visible)
        .accessibilityIdentifier("LiveInsightsHistoryScroll")
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
    var isCentered: Bool
    
    init(
        icon: String? = nil,
        title: String,
        message: String? = nil,
        severity: NoticeSeverity = .info,
        actions: [InlineNoticeAction] = [],
        isCentered: Bool = false
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.severity = severity
        self.actions = actions
        self.isCentered = isCentered
    }
    
    @available(*, deprecated, message: "Use severity-based initializer instead")
    init(icon: String, title: String, message: String? = nil, tintColor: Color) {
        self.icon = icon
        self.title = title
        self.message = message
        self.severity = tintColor == .orange ? .warning : (tintColor == .green ? .tip : .info)
        self.actions = []
        self.isCentered = false
    }
    
    private var effectiveIcon: String {
        icon ?? severity.defaultIcon
    }
    
    var body: some View {
        VStack(alignment: isCentered ? .center : .leading, spacing: 6) {
            HStack(spacing: 6) {
                if isCentered { Spacer(minLength: 0) }
                
                Image(systemName: effectiveIcon)
                    .font(.caption)
                    .foregroundStyle(severity.color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                
                if !isCentered {
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                }
            }
            
            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(isCentered ? .center : .leading)
                    .padding(.leading, isCentered ? 0 : 20)
            }
            
            if !actions.isEmpty {
                HStack(spacing: 8) {
                    if isCentered { Spacer(minLength: 0) }
                    
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
                    
                    if isCentered { Spacer(minLength: 0) }
                }
                .padding(.leading, isCentered ? 0 : 20)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
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
    
    private var resolvedFinderIcon: NSImage? {
        if let filePath = insight.filePath {
            let fileURL = URL(fileURLWithPath: filePath)
            if fileURL.hasDirectoryPath {
                return AnalysisIconProvider.icon(for: .folder)
            }
            let ext = fileURL.pathExtension
            if !ext.isEmpty {
                return AnalysisIconProvider.icon(forFileExtension: ext)
            }
            return AnalysisIconProvider.icon(for: .data)
        }

        if insight.category == .folder {
            return AnalysisIconProvider.icon(for: .folder)
        }

        if insight.category == .file {
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

        return nil
    }

    private var categoryColor: Color {
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
            if let finderIcon = resolvedFinderIcon {
                Image(nsImage: finderIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            } else {
                Circle()
                    .fill(categoryColor.opacity(0.3))
                    .overlay(
                        Circle().stroke(categoryColor.opacity(0.65), lineWidth: 1)
                    )
                    .frame(width: 8, height: 8)
                    .padding(.horizontal, 3)
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
