//
//  PostOrganizationHoningView.swift
//  Sorty
//
//  Post-organization feedback and learning component
//

import SwiftUI

struct PostOrganizationHoningView: View {
    let fileCount: Int
    let folderCount: Int
    let config: AIConfig
    let learningsMaturity: LearningsManager.LearningsSummary.Maturity
    let onComplete: ([HoningAnswer]) -> Void
    let onSkip: () -> Void
    
    @StateObject private var engine: LearningsHoningEngine
    @State private var currentQuestionIndex = 0
    @State private var answers: [HoningAnswer] = []
    @State private var hasAppeared = false
    @State private var selectedOption: String?
    
    init(
        fileCount: Int,
        folderCount: Int,
        config: AIConfig,
        learningsMaturity: LearningsManager.LearningsSummary.Maturity = .new,
        onComplete: @escaping ([HoningAnswer]) -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.fileCount = fileCount
        self.folderCount = folderCount
        self.config = config
        self.learningsMaturity = learningsMaturity
        self.onComplete = onComplete
        self.onSkip = onSkip
        _engine = StateObject(wrappedValue: LearningsHoningEngine(config: config))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                headerSection
                    .opacity(hasAppeared ? 1 : 0)
                    .offset(y: hasAppeared ? 0 : 10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    feedbackHeader
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
                    
                    questionSection
                        .opacity(hasAppeared ? 1 : 0)
                        .offset(y: hasAppeared ? 0 : 10)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.3), value: hasAppeared)
                }
                .padding(24)
            }
            
            Spacer()
            
            Divider()
            
            Button {
                HapticFeedbackManager.shared.tap()
                onSkip()
            } label: {
                Text("Skip for now")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 24)
            .opacity(hasAppeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.4), value: hasAppeared)
            .accessibilityIdentifier("SkipFeedbackButton")
            .accessibilityLabel("Skip feedback")
        }
        .frame(width: 480, height: 520)
        .onAppear {
            withAnimation {
                hasAppeared = true
            }
            Task {
                await engine.startSession(questionCount: adaptiveQuestionCount)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Post-organization feedback")
    }

    private var adaptiveQuestionCount: Int {
        switch learningsMaturity {
        case .new, .growing:
            return 1
        case .established:
            return 2
        }
    }

    private var feedbackTitle: String {
        switch learningsMaturity {
        case .new:
            return "Help Sorty Learn"
        case .growing:
            return "Improve Your Preferences"
        case .established:
            return "Fine-Tune Your Rules"
        }
    }

    private var feedbackSubtitle: String {
        switch learningsMaturity {
        case .new:
            return "Answer one quick question so Sorty can learn your style"
        case .growing:
            return "Share one preference to sharpen upcoming suggestions"
        case .established:
            return "Answer two short prompts to keep your learned rules accurate"
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 70, height: 70)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.green)
            }
            
            Text("Organization Complete!")
                .font(.title3)
                .fontWeight(.bold)
            
            HStack(spacing: 12) {
                Label("\(fileCount) files", systemImage: "doc.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text("→")
                    .foregroundStyle(.tertiary)
                
                Label("\(folderCount) folders", systemImage: "folder.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private var feedbackHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                
                Text(feedbackTitle)
                    .font(.headline)
            }
            
            Text(feedbackSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var questionSection: some View {
        Group {
            if engine.isGenerating {
                VStack(spacing: 12) {
                    SortyGradientLoadingBar(width: 140, height: 9)
                    Text("Preparing question...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else if let session = engine.currentSession, !session.questions.isEmpty {
                let question = session.questions.last!
                dynamicQuestionView(question: question, questionId: question.id)
            } else {
                staticQuestionView
            }
        }
    }
    
    private func dynamicQuestionView(question: HoningQuestion, questionId: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(question.text)
                .font(.body)
                .fontWeight(.medium)
            
            ForEach(Array(question.options.enumerated()), id: \.element) { index, option in
                FeedbackOptionButton(
                    option: option,
                    isSelected: selectedOption == option,
                    delay: Double(index) * 0.05
                ) {
                    HapticFeedbackManager.shared.selection()
                    selectedOption = option
                    let answer = HoningAnswer(
                        questionId: questionId,
                        selectedOption: option
                    )
                    answers.append(answer)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                        onComplete(answers)
                    }
                }
            }
        }
    }
    
    private var staticQuestionView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Was this organization helpful?")
                .font(.body)
                .fontWeight(.medium)
            
            ForEach(Array(["Yes, it was great!", "It was okay", "Not really useful"].enumerated()), id: \.element) { index, option in
                FeedbackOptionButton(
                    option: option,
                    isSelected: selectedOption == option,
                    delay: Double(index) * 0.05
                ) {
                    HapticFeedbackManager.shared.selection()
                    selectedOption = option
                    let answer = HoningAnswer(
                        questionId: "post_org_feedback",
                        selectedOption: option
                    )
                    answers.append(answer)
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
                        onComplete(answers)
                    }
                }
            }
        }
    }
}

struct FeedbackOptionButton: View {
    let option: String
    let isSelected: Bool
    let delay: Double
    let action: () -> Void
    
    @State private var hasAppeared = false
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(option)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .foregroundStyle(isSelected ? .green : .secondary)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.green.opacity(0.1) : (isHovering ? Color.secondary.opacity(0.08) : Color.secondary.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .opacity(hasAppeared ? 1 : 0)
        .offset(x: hasAppeared ? 0 : -10)
        .animation(.spring(response: 0.4, dampingFraction: 0.8).delay(delay), value: hasAppeared)
        .onHover { hovering in
            isHovering = hovering
        }
        .onAppear {
            hasAppeared = true
        }
        .accessibilityLabel(option)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Post-Organization Honing") {
    PostOrganizationHoningView(
        fileCount: 45,
        folderCount: 8,
        config: PreviewMocks.makeAIConfig(),
        onComplete: { _ in
            print("Feedback completed")
        },
        onSkip: {
            print("Skipped feedback")
        }
    )
    .frame(width: 480, height: 520)
}
