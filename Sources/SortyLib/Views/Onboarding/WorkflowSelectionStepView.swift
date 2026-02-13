//
//  WorkflowSelectionStepView.swift
//  Sorty
//
//  Workflow/Persona selection step of the onboarding flow
//

import SwiftUI

public struct WorkflowSelectionStepView: View {
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var customPersonaStore: CustomPersonaStore
    @State private var hasAppeared = false
    @State private var showingPersonaGenerator = false
    @State private var isCreatingCustom = false
    @State private var customDescription = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedPersona: CustomPersona?
    @State private var showingSuccess = false
    
    @StateObject private var generator = PersonaGenerator()
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left side - explanation
            VStack(alignment: .leading, spacing: 24) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.teal)
                    
                    Text("Choose Your Workflow")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                    
                    Text("Select a persona that matches how you work. This helps the AI understand your organization preferences.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("You can change this anytime in Settings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .frame(maxWidth: 350)
                .opacity(hasAppeared ? 1 : 0)
                .offset(x: hasAppeared ? 0 : -20)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.1), value: hasAppeared)
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 60)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            // Right side - persona selection
            VStack(spacing: 20) {
                Spacer()
                
                Text("Select Default Persona")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                // Built-in personas grid - 2x2 layout
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(PersonaType.allCases, id: \.self) { persona in
                        OnboardingPersonaCard(
                            persona: persona,
                            isSelected: personaManager.selectedPersona == persona && personaManager.selectedCustomPersonaId == nil
                        ) {
                            HapticFeedbackManager.shared.selection()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                personaManager.selectPersona(persona)
                                personaManager.selectedCustomPersonaId = nil
                                isCreatingCustom = false
                            }
                        }
                    }
                }
                .frame(maxWidth: 420)
                
                // Divider with "or"
                HStack {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                    Text("or")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 1)
                }
                .frame(maxWidth: 420)
                
                // Show "Create Your Own" button
                CreatePersonaButton(isCreatingCustom: $isCreatingCustom)
                    .frame(maxWidth: 420)
                
                // Show generated/selected custom persona if any
                if let persona = generatedPersona {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(persona.name)
                                .font(.headline)
                            Text("Custom persona created successfully")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green.opacity(0.1))
                    )
                    .frame(maxWidth: 420)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .opacity(hasAppeared ? 1 : 0)
            .offset(x: hasAppeared ? 0 : 20)
            .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.2), value: hasAppeared)
        }
        .overlay {
            // Modal overlay for custom persona creation
            if isCreatingCustom {
                ZStack {
                    // Dimmed background - click to dismiss
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isCreatingCustom = false
                                customDescription = ""
                                generationError = nil
                            }
                        }
                    
                    // Modal content
                    customPersonaCreationView
                        .frame(maxWidth: 450)
                        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isCreatingCustom)
        .onAppear {
            withAnimation { hasAppeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workflow Selection Step")
    }
    
    @ViewBuilder
    private var customPersonaCreationView: some View {
        VStack(spacing: 20) {
            if isGenerating {
                // Generating state - animated loading
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.accentColor)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Creating Your Persona")
                            .font(.title3.bold())
                        
                        Text("AI is analyzing your workflow description...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding(.top, 8)
                }
                .frame(minHeight: 200)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if showingSuccess, let persona = generatedPersona {
                // Success state - shown briefly before closing
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(Color.green.opacity(0.15))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.green)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Persona Created!")
                            .font(.title3.bold())
                        
                        Text("\"\(persona.name)\" is now your default workflow")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(minHeight: 200)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                // Input form state
                VStack(spacing: 16) {
                    // Header
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.secondary.opacity(0.1))
                                .frame(width: 60, height: 60)
                            
                            Image(systemName: "sparkles")
                                .font(.system(size: 28))
                                .foregroundStyle(.primary)
                        }
                        
                        Text("Create Custom Persona")
                            .font(.headline)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Describe how you want your files organized:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        TextEditor(text: $customDescription)
                            .font(.body)
                            .frame(height: 80)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                            )
                        
                        Text("Example: \"I'm a photographer. Organize my photos by year, then event name, with RAW files separate from JPEGs.\"")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .italic()
                    }
                    
                    if let error = generationError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isCreatingCustom = false
                                customDescription = ""
                                generationError = nil
                            }
                        } label: {
                            Text("Cancel")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.bordered)
                        
                        Button {
                            generateCustomPersona()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Generate")
                            }
                        }
                        .buttonStyle(.onboardingPill)
                        .disabled(customDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isGenerating)
    }
    
    private func generateCustomPersona() {
        isGenerating = true
        generationError = nil
        
        Task {
            do {
                let result = try await generator.generatePersona(
                    from: customDescription,
                    answers: [],
                    config: settingsViewModel.config
                )
                
                let newPersona = CustomPersona(
                    name: result.name,
                    description: customDescription,
                    promptModifier: result.prompt
                )
                
                await MainActor.run {
                    // Save the persona
                    customPersonaStore.addPersona(newPersona)
                    
                    // Select it
                    personaManager.selectedCustomPersonaId = newPersona.id
                    
                    // Update UI - show success state
                    generatedPersona = newPersona
                    isGenerating = false
                    showingSuccess = true
                    
                    HapticFeedbackManager.shared.success()
                    
                    // Auto-close after showing success
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isCreatingCustom = false
                            showingSuccess = false
                            customDescription = ""
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    generationError = error.localizedDescription
                    isGenerating = false
                    HapticFeedbackManager.shared.error()
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct OnboardingPersonaCard: View {
    let persona: PersonaType
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: persona.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(isSelected ? Color.accentColor : .primary)
                }
                
                VStack(spacing: 4) {
                    Text(persona.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(persona.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(isHovered ? 0.3 : 0.1), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

struct CreatePersonaButton: View {
    @Binding var isCreatingCustom: Bool
    @State private var isHovered = false
    
    var body: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isCreatingCustom = true
            }
            HapticFeedbackManager.shared.selection()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundStyle(.primary)
                }
                
                VStack(spacing: 4) {
                    Text("Create Your Own")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("Describe your ideal organization style")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.secondary.opacity(isHovered ? 0.3 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Preview

#Preview {
    WorkflowSelectionStepView()
        .environmentObject(PersonaManager())
        .environmentObject(SettingsViewModel())
    .environmentObject(CustomPersonaStore())
}
