//
//  PersonaGeneratorView.swift
//  FileOrganizer
//
//  UI for generating personas from natural language
//

import SwiftUI

struct PersonaGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject var store: CustomPersonaStore
    @Binding var selectedPersonaId: String?
    
    @StateObject private var generator = PersonaGenerator()
    @State private var prompt: String = ""
    @State private var generatedPersona: CustomPersona?
    @State private var isDetailView: Bool = false
    
    @StateObject private var honingEngine = PersonaHoningEngine()
    @State private var questions: [HoningQuestion] = []
    @State private var answers: [String: String] = [:] // QuestionID -> SelectedOption
    @State private var isHoning: Bool = false
    @State private var isLoadingQuestions: Bool = false
    @State private var currentQuestionIndex: Int = 0

    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                if isHoning && !questions.isEmpty {
                    honingView
                } else {
                    initialInputView
                }
            }
            
            if generator.isGenerating {
                generationOverlay
            }
        }
        .frame(width: 500, height: 550)
        .alert("Persona Generated", isPresented: $isDetailView) {
            Button("Save & Use") {
                if let persona = generatedPersona {
                    store.addPersona(persona)
                    selectedPersonaId = persona.id
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your new expert-level persona has been created.")
        }
    }

    private var generationOverlay: some View {
        VStack(spacing: 24) {
            ProgressView()
                .controlSize(.large)
            
            VStack(spacing: 8) {
                Text("Architecting Strategy...")
                    .font(.headline)
                    .foregroundStyle(.primary)
                
                Text("Designing deep folder structures and organization rules.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var initialInputView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                
                Text("Generate Persona")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Describe your ideal organization style.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 30)
            
            // Input Area
            VStack(alignment: .leading, spacing: 8) {
                Text("I want to organize...")
                    .font(.headline)
                
                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(height: 120)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                
                Text("Example: \"Organize my sci-fi ebook collection by author, then series.\"")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 30)
            
            if let error = generator.error {
                Text(error.localizedDescription).foregroundColor(.red).font(.caption).padding(.horizontal)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                
                Button {
                    startHoning()
                } label: {
                    if isLoadingQuestions {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Next")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(prompt.isEmpty || isLoadingQuestions)
            }
            .padding(.bottom, 30)
        }
    }
    
    private var honingView: some View {
        VStack(spacing: 24) {
            Text("Refining Your Persona")
                .font(.title3)
                .fontWeight(.bold)
                .padding(.top, 20)
            
            ProgressView(value: Double(currentQuestionIndex + 1), total: Double(questions.count))
                .padding(.horizontal)
            
            let question = questions[currentQuestionIndex]
            
            VStack(alignment: .leading, spacing: 16) {
                Text(question.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                
                ForEach(question.options, id: \.self) { option in
                    Button {
                        selectAnswer(option, for: question)
                    } label: {
                        HStack {
                            Text(option)
                            Spacer()
                            if answers[question.id] == option {
                                Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                            }
                        }
                        .padding()
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(answers[question.id] == option ? Color.blue : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            HStack {
                if currentQuestionIndex > 0 {
                    Button("Back") { currentQuestionIndex -= 1 }
                }
                
                Spacer()
                
                Button(currentQuestionIndex == questions.count - 1 ? "Generate Persona" : "Next") {
                    if currentQuestionIndex < questions.count - 1 {
                        currentQuestionIndex += 1
                    } else {
                        generateFinalPersona()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(answers[question.id] == nil || generator.isGenerating)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }
    
    private func selectAnswer(_ option: String, for question: HoningQuestion) {
        answers[question.id] = option
        // Auto-advance after small delay if it's not the last one? No, let user click Next for control.
    }
    
    private func startHoning() {
        isLoadingQuestions = true
        Task {
            do {
                questions = try await honingEngine.generateQuestions(from: prompt, config: settingsViewModel.config)
                if questions.isEmpty {
                    // Fallback to direct generation if no questions needed/generated
                    generateFinalPersona()
                } else {
                    isHoning = true
                }
            } catch {
                // Ignore error and fall back to direct generation
                generateFinalPersona()
            }
            isLoadingQuestions = false
        }
    }
    
    private func generateFinalPersona() {
        Task {
            // Map back question text for better context
             // Actually, passing the question text in the prompt would be better.
             // We can do a quick mapping here
             var richAnswers: [HoningAnswer] = []
             for (qId, option) in answers {
                 if let q = questions.first(where: { $0.id == qId }) {
                     // We'll append the question text to the option for the generator context
                     let richOption = "Q: \(q.text) -> A: \(option)"
                     richAnswers.append(HoningAnswer(questionId: qId, selectedOption: richOption))
                 }
             }

            do {
                let result = try await generator.generatePersona(from: prompt, answers: richAnswers, config: settingsViewModel.config)
                
                let newPersona = CustomPersona(
                    name: result.name,
                    description: prompt,
                    promptModifier: result.prompt
                )
                
                await MainActor.run {
                    self.generatedPersona = newPersona
                    self.isDetailView = true
                }
            } catch {
                // error handled by generator binding
            }
        }
    }
}
