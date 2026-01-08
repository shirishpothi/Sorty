//
//  LearningsHoningView.swift
//  Sorty
//
//  Interactive Q&A session to refine the user's profile.
//

import SwiftUI

struct LearningsHoningView: View {
    @StateObject private var engine: LearningsHoningEngine
    @Environment(\.presentationMode) var presentationMode
    
    // Aesthetic state
    @State private var hoveredOption: String?
    
    private let onComplete: ([HoningAnswer]) -> Void
    
    init(config: AIConfig, onComplete: @escaping ([HoningAnswer]) -> Void) {
        _engine = StateObject(wrappedValue: LearningsHoningEngine(config: config))
        self.onComplete = onComplete
    }
    
    var body: some View {
        ZStack {
            // Ambient Background
            Color.black.opacity(0.8)
                .background(
                    RadialGradient(gradient: Gradient(colors: [Color.blue.opacity(0.15), Color.black]), center: .center, startRadius: 2, endRadius: 600)
                )
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Header
                HStack {
                    Text("Profile Honing")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.white, .blue.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    
                    Spacer()
                    
                    if let session = engine.currentSession {
                        Text("\(min(session.answers.count + 1, session.targetQuestionCount)) / \(session.targetQuestionCount)")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(.gray)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Material.ultraThinMaterial)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                if let error = engine.error {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
                
                if engine.isGenerating {
                    // Loading State
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.blue)
                        
                        Text("Analyzing your organization style...")
                            .font(.body)
                            .foregroundColor(.gray)
                            .transition(.opacity)
                    }
                    .frame(maxHeight: .infinity)
                    
                } else if let session = engine.currentSession, !session.isComplete {
                    // Question State
                    if let question = session.questions.last {
                        questionView(question: question)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
                    }
                    
                } else if engine.currentSession?.isComplete == true {
                    // Completion State
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        
                        Text("Profile Updated")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        
                        Text("We've refined your organization model based on your answers.")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button {
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(
                                    LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing)
                                )
                                .cornerRadius(25)
                                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                    }
                    .frame(maxHeight: .infinity)
                    
                } else {
                    // Start State
                    VStack(spacing: 20) {
                        Text("Let's fine-tune your ecosystem.")
                            .font(.title3)
                            .foregroundColor(.white)
                        
                        Text("Answer 5 quick scenarios to help the AI understand exactly how you think.")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        Button {
                            Task {
                                await engine.startSession()
                            }
                        } label: {
                            Text("Start Honing")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(width: 200, height: 50)
                                .background(Color.blue)
                                .cornerRadius(25)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .padding()
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            engine.onComplete = onComplete
        }
    }
    
    @ViewBuilder
    private func questionView(question: HoningQuestion) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(question.text)
                .font(.system(size: 20, weight: .medium, design: .default))
                .foregroundColor(.white)
                .padding(.horizontal)
            
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            submitAnswer(questionId: question.id, option: option)
                        } label: {
                            HStack {
                                Text(option)
                                    .font(.body)
                                    .foregroundColor(hoveredOption == option ? .white : .gray)
                                
                                Spacer()
                                
                                if hoveredOption == option {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(hoveredOption == option ? Color.white.opacity(0.1) : Color.black.opacity(0.4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(hoveredOption == option ? Color.blue.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHover { isHovering in
                            withAnimation(.easeInOut(duration: 0.2)) {
                                hoveredOption = isHovering ? option : nil
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private func submitAnswer(questionId: String, option: String) {
        let answer = HoningAnswer(questionId: questionId, selectedOption: option)
        Task {
            withAnimation {
                // Optimistic UI update/transition could happen here
            }
            await engine.submitAnswer(answer)
        }
    }
}
