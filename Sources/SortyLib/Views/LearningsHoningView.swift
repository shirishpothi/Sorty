//
//  LearningsHoningView.swift
//  Sorty
//
//  Interactive Q&A session to refine the user's profile.
//

import SwiftUI

struct LearningsHoningView: View {
    @StateObject private var engine: LearningsHoningEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var hoveredOption: String?
    
    private let onComplete: ([HoningAnswer]) -> Void
    
    init(config: AIConfig, onComplete: @escaping ([HoningAnswer]) -> Void) {
        _engine = StateObject(wrappedValue: LearningsHoningEngine(config: config))
        self.onComplete = onComplete
    }
    
    var body: some View {
        VStack {
            if engine.isGenerating {
                loadingView
            } else if let session = engine.currentSession, !session.isComplete {
                if let question = session.questions.last {
                    questionView(question: question, session: session)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                }
            } else if engine.currentSession?.isComplete == true {
                completionView
            } else {
                startView
            }
        }
        .frame(minWidth: 550, minHeight: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            engine.onComplete = onComplete
        }
    }
    
    // MARK: - Loading
    
    private var loadingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            
            VStack(spacing: 8) {
                Text("Analyzing your organization style...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("Generating questions based on your behavior patterns.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    // MARK: - Start
    
    private var startView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                
                Text("Profile Honing")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Answer 5 quick scenarios to help the AI understand exactly how you think about file organization.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .frame(maxWidth: 400)
            }
            // Removed redundant top padding to prevent layout shift
            
            if let error = engine.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.onboardingPillSecondary)
                
                Button {
                    Task {
                        await engine.startSession()
                    }
                } label: {
                    Text("Start Honing")
                }
                .buttonStyle(.onboardingPill)
            }
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 40)
        .liquidGlassCard(cornerRadius: 16)
        .padding(20)
    }
    
    // MARK: - Question
    
    @ViewBuilder
    private func questionView(question: HoningQuestion, session: HoningSession) -> some View {
        VStack(spacing: 24) {
            Text("Profile Honing")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 30)
            
            ProgressView(value: Double(min(session.answers.count + 1, session.targetQuestionCount)), total: Double(session.targetQuestionCount))
                .padding(.horizontal, 40)
            
            if let error = engine.error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            
            VStack(alignment: .leading, spacing: 20) {
                Text(question.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 8)
                
                ForEach(question.options, id: \.self) { option in
                    Button {
                        submitAnswer(questionId: question.id, option: option)
                    } label: {
                        HStack {
                            Text(option)
                                .font(.body)
                            Spacer()
                            if hoveredOption == option {
                                Image(systemName: "arrow.right.circle.fill")
                                    .transition(.opacity.combined(with: .scale))
                                    .foregroundColor(.accentColor)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .liquidGlassCard(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                    .onHover { isHovering in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            hoveredOption = isHovering ? option : nil
                        }
                    }
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            HStack {
                Text("Scenario \(min(session.answers.count + 1, session.targetQuestionCount)) of \(session.targetQuestionCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 30)
        }
        .liquidGlassCard(cornerRadius: 16)
        .padding(20)
    }
    
    // MARK: - Completion
    
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            
            VStack(spacing: 8) {
                Text("Profile Updated")
                    .font(.title2.bold())
                
                Text("We've refined your organization model based on your answers.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
            
            Button("Done") {
                dismiss()
            }
            .buttonStyle(.onboardingPill)
            .padding(.bottom, 30)
        }
        .liquidGlassCard(cornerRadius: 16)
        .padding(20)
    }
    
    private func submitAnswer(questionId: String, option: String) {
        let answer = HoningAnswer(questionId: questionId, selectedOption: option)
        Task {
            withAnimation {
            }
            await engine.submitAnswer(answer)
        }
    }
}
