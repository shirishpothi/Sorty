//
//  PersonaGeneratorView.swift
//  Sorty
//
//  UI for generating personas from natural language
//

import Foundation
import SwiftUI

struct PersonaGeneratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject var store: CustomPersonaStore
    @Binding var selectedPersonaId: String?
    
    @StateObject private var generator = PersonaGenerator()
    @State private var prompt: String = ""
    @State private var promptSelection = NSRange(location: 0, length: 0)
    @State private var promptSuggestionIndex: Int = 0
    
    @StateObject private var honingEngine = PersonaHoningEngine()
    @State private var questions: [HoningQuestion] = []
    @State private var answers: [String: String] = [:] // QuestionID -> SelectedOption
    @State private var isHoning: Bool = false
    @State private var isLoadingQuestions: Bool = false
    @State private var currentQuestionIndex: Int = 0

    private let promptSuggestions = [
        "Organize my sci-fi ebook collection by author, then series.",
        "Group my photos by year and event, with RAW files separate from edits.",
        "Sort client work by project, then keep active and completed work separate.",
        "Organize school files by subject, unit, and assignment type.",
    ]

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
        .frame(width: 500, height: isHoning || generator.isGenerating ? 550 : 430)
        .animation(
            reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.82),
            value: isHoning || generator.isGenerating
        )
    }

    private var generationOverlay: some View {
        VStack(spacing: 22) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                .frame(width: 58, height: 58)
                .background(
                    SortyDesignSystem.Colors.resolvedAccent.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .symbolEffect(.breathe, isActive: !reduceMotion)

            VStack(spacing: 10) {
                Text("Building Your Persona")
                    .font(.title3.weight(.bold))

                SortyGradientLoadingBar(
                    accent: SortyDesignSystem.Colors.resolvedAccent,
                    width: 220,
                    height: 9
                )
            }

            VStack(spacing: 6) {
                if !generator.generationUpdate.isEmpty {
                    Label("Live model update", systemImage: "brain")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                }

                Text(currentGenerationStatus)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: 360)
                    .frame(minHeight: 42)
                    .id(currentGenerationStatus)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        )
                    )
            }
            .animation(.easeInOut(duration: 0.22), value: currentGenerationStatus)

            HStack(spacing: 14) {
                generationDetail(
                    icon: "slider.horizontal.3",
                    text: refinementSummary
                )
                generationDetail(
                    icon: "folder.badge.gearshape",
                    text: "Reusable strategy"
                )
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
                    .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                
                Text("Generate Persona")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Describe your ideal organization style.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 24)
            
            // Input Area
            VStack(alignment: .leading, spacing: 8) {
                Text("I want to organize...")
                    .font(.headline)
                
                ZStack(alignment: .topLeading) {
                    SubmittableTextEditor(
                        text: $prompt,
                        selectedRange: $promptSelection,
                        onAcceptSuggestion: acceptCurrentPromptSuggestion
                    ) {
                        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                              !isLoadingQuestions
                        else {
                            return
                        }
                        startHoning()
                    }

                    if prompt.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Text(currentPromptSuggestion)
                                .font(.body)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .numericTextTransition(animationValue: promptSuggestionIndex)

                            Spacer(minLength: 0)

                            Text("Tab")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    Color.secondary.opacity(0.10),
                                    in: RoundedRectangle(cornerRadius: 5)
                                )
                                .accessibilityHidden(true)
                        }
                        .padding(.leading, 15)
                        .padding(.trailing, 10)
                        .padding(.top, 7)
                        .allowsHitTesting(false)
                        .task {
                            promptSuggestionIndex = 0

                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(2.5))
                                guard !Task.isCancelled else { return }
                                promptSuggestionIndex =
                                    (promptSuggestionIndex + 1) % promptSuggestions.count
                            }
                        }
                    }
                }
                .frame(height: 120)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                }
                .accessibilityLabel("Persona description")
                .accessibilityHint(
                    prompt.isEmpty
                        ? "Press Tab to use the suggested description"
                        : "Press Command and Return to continue"
                )
            }
            .padding(.horizontal, 30)
            
            if let error = generator.error {
                Text(error.localizedDescription).foregroundColor(.red).font(.caption).padding(.horizontal)
            }
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.sortyBordered)
                
                Button {
                    startHoning()
                } label: {
                    if isLoadingQuestions {
                        SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    } else {
                        Text("Next")
                    }
                }
                .buttonStyle(.sortyProminent)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoadingQuestions)
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }
    
    private var honingView: some View {
        VStack(spacing: 20) {
            let question = questions[currentQuestionIndex]

            VStack(spacing: 10) {
                Text("Refining Your Persona")
                    .font(.title3.weight(.bold))

                HStack(spacing: 4) {
                    Text("Question")
                    Text("\(currentQuestionIndex + 1)")
                        .numericTextTransition(animationValue: currentQuestionIndex)
                    Text("of")
                    Text("\(questions.count)")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    SortyDesignSystem.Colors.resolvedAccent.opacity(0.12),
                    in: Capsule(style: .continuous)
                )
            }
            .padding(.top, 18)

            SortyGradientProgressBar(
                progress: Double(currentQuestionIndex + 1) / Double(max(questions.count, 1)),
                accent: SortyDesignSystem.Colors.resolvedAccent,
                height: 9
            )
            .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 16) {
                Text(question.text)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                
                ForEach(question.options, id: \.self) { option in
                    HoningOptionButton(
                        option: option,
                        isSelected: answers[question.id] == option
                    ) {
                        selectAnswer(option, for: question)
                    }
                }
            }
            .padding(.horizontal, 30)

            if let error = generator.error {
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
            
            HStack {
                if currentQuestionIndex > 0 {
                    Button("Back") {
                        HapticFeedbackManager.shared.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            currentQuestionIndex -= 1
                        }
                    }
                    .buttonStyle(.sortyBordered)
                }
                
                Spacer()
                
                Button(currentQuestionIndex == questions.count - 1 ? "Generate Persona" : "Next") {
                    if currentQuestionIndex < questions.count - 1 {
                        HapticFeedbackManager.shared.selection()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                            currentQuestionIndex += 1
                        }
                    } else {
                        generateFinalPersona()
                    }
                }
                .buttonStyle(.sortyProminent)
                .disabled(answers[question.id] == nil || generator.isGenerating)
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 30)
        }
    }
    
    private func selectAnswer(_ option: String, for question: HoningQuestion) {
        guard answers[question.id] != option else { return }
        HapticFeedbackManager.shared.selection()
        answers[question.id] = option
    }

    private var currentPromptSuggestion: String {
        promptSuggestions[promptSuggestionIndex % promptSuggestions.count]
    }

    private func acceptCurrentPromptSuggestion() -> Bool {
        guard prompt.isEmpty else { return false }

        prompt = currentPromptSuggestion
        promptSelection = NSRange(
            location: (currentPromptSuggestion as NSString).length,
            length: 0
        )
        HapticFeedbackManager.shared.selection()
        return true
    }
    
    private func startHoning() {
        isLoadingQuestions = true
        Task {
            do {
                questions = try await honingEngine.generateQuestions(from: prompt, config: settingsViewModel.config)
                if questions.isEmpty {
                    generateFinalPersona()
                } else {
                    HapticFeedbackManager.shared.selection()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                        isHoning = true
                    }
                }
            } catch {
                generateFinalPersona()
            }
            isLoadingQuestions = false
        }
    }
    
    private func generateFinalPersona() {
        Task {
            var richAnswers: [HoningAnswer] = []
            for (questionID, option) in answers {
                if let question = questions.first(where: { $0.id == questionID }) {
                    let richOption = "Q: \(question.text) -> A: \(option)"
                    richAnswers.append(
                        HoningAnswer(questionId: questionID, selectedOption: richOption)
                    )
                }
            }

            do {
                let result = try await generator.generatePersona(from: prompt, answers: richAnswers, config: settingsViewModel.config)
                
                let newPersona = CustomPersona(
                    name: result.name,
                    icon: result.icon,
                    description: prompt,
                    promptModifier: result.prompt,
                    instructionSuggestions: result.suggestions
                )
                
                await MainActor.run {
                    store.addPersona(newPersona)
                    selectedPersonaId = newPersona.id
                    HapticFeedbackManager.shared.success()
                    NotificationManager.shared.showHUDInfo(
                        title: "Persona Ready",
                        message: "\(newPersona.name) is saved and now active.",
                        icon: "checkmark.circle.fill",
                        iconColor: SortyDesignSystem.Colors.resolvedAccent,
                        identifier: "persona-generated"
                    )
                    dismiss()
                }
            } catch {
                HapticFeedbackManager.shared.error()
            }
        }
    }

    private var currentGenerationStatus: String {
        if !generator.generationUpdate.isEmpty {
            return generator.generationUpdate
        }
        return answers.isEmpty
            ? "Preparing a tailored organization strategy from your description."
            : "Preparing a strategy from your description and \(answers.count) refinements."
    }

    private var refinementSummary: String {
        answers.isEmpty
            ? "Description analyzed"
            : "\(answers.count) \(answers.count == 1 ? "refinement" : "refinements")"
    }

    private func generationDetail(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Color.primary.opacity(0.055),
                in: Capsule(style: .continuous)
            )
    }
}

private struct HoningOptionButton: View {
    let option: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    private var accent: Color {
        SortyDesignSystem.Colors.resolvedAccent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(option)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        isSelected
                            ? accent
                            : Color.secondary.opacity(isHovered ? 0.72 : 0.36)
                    )
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(cardFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(cardStroke, lineWidth: isSelected ? 1.5 : 1)
            }
            .shadow(
                color: accent.opacity(isSelected ? 0.10 : isHovered ? 0.07 : 0),
                radius: isHovered || isSelected ? 10 : 0,
                y: isHovered ? 4 : 2
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering && !isHovered {
                HapticFeedbackManager.shared.selection()
            }
            isHovered = hovering
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.15),
            value: isHovered
        )
        .animation(
            reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6),
            value: isSelected
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardFill: Color {
        if isSelected {
            return accent.opacity(0.11)
        }
        if isHovered {
            return accent.opacity(0.055)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    private var cardStroke: Color {
        if isSelected {
            return accent.opacity(0.82)
        }
        if isHovered {
            return accent.opacity(0.34)
        }
        return Color.secondary.opacity(0.18)
    }
}
