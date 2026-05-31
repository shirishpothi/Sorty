//
//  WorkflowSelectionStepView.swift
//  Sorty
//
//  Workflow/Persona selection step of the onboarding flow
//

import AppKit
import SwiftUI

public struct WorkflowSelectionStepView: View {
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject var customPersonaStore: CustomPersonaStore
    @State private var hasAppeared = false
    @State private var isCreatingCustom = false
    @State private var customDescription = ""
    @State private var isGenerating = false
    @State private var generationError: String?
    @State private var generatedPersona: CustomPersona?
    @State private var showingSuccess = false
    
    @StateObject private var generator = PersonaGenerator()
    
    public init() {}
    
    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
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
            
            // Right side - persona selection
            ScrollView {
                VStack(spacing: 20) {
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
                    
                    if !customPersonaStore.customPersonas.isEmpty {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(customPersonaStore.customPersonas) { persona in
                                OnboardingCustomPersonaCard(
                                    persona: persona,
                                    isSelected: personaManager.selectedCustomPersonaId == persona.id,
                                    compact: true,
                                    onDelete: {
                                        customPersonaStore.deletePersona(id: persona.id)
                                        if personaManager.selectedCustomPersonaId == persona.id {
                                            personaManager.selectedCustomPersonaId = nil
                                        }
                                    }
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        personaManager.selectCustomPersona(persona.id)
                                        isCreatingCustom = false
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                            }
                        }
                        .frame(maxWidth: 420)

                        CreatePersonaButton(
                            title: "Generate Another",
                            subtitle: "Try a different custom workflow idea",
                            isCreatingCustom: $isCreatingCustom
                        )
                        .frame(maxWidth: 420)
                    } else {
                        CreatePersonaButton(isCreatingCustom: $isCreatingCustom)
                            .frame(maxWidth: 420)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 40)
            .clipped()
            .defaultScrollAnchor(.center)
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
                            guard !isGenerating else { return }
                            dismissCustomPersonaComposer()
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
                            .fill(SortyDesignSystem.Colors.resolvedAccent.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 36))
                            .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Creating Your Persona")
                            .font(.title3.bold())
                        
                        Text("AI is analyzing your workflow description...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SortyGradientLoadingBar(width: 180, height: 10)
                        .padding(.top, 8)
                }
                .frame(minHeight: 200)
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else if showingSuccess, let persona = generatedPersona {
                // Success state - preview the generated workflow before saving it.
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [SortyDesignSystem.Colors.resolvedAccent.opacity(0.2), Color.teal.opacity(0.18)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 82, height: 82)

                        Image(systemName: persona.icon)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                    }
                    
                    VStack(spacing: 8) {
                        Text("Your Custom Workflow Is Ready")
                            .font(.title3.bold())
                        
                        Text("Review the generated persona, then use it as your default workflow for Sorty.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    OnboardingCustomPersonaCard(
                        persona: persona,
                        isSelected: true,
                        action: {}
                    )
                    .allowsHitTesting(false)

                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                showingSuccess = false
                                generatedPersona = nil
                                generationError = nil
                            }
                        } label: {
                            Text("Edit Description")
                                .frame(minWidth: 110)
                        }
                        .buttonStyle(.sortyBordered)

                        Button {
                            commitGeneratedPersona(persona)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Use This Workflow")
                            }
                        }
                        .buttonStyle(.onboardingPill)
                    }
                }
                .frame(minHeight: 320)
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
                            dismissCustomPersonaComposer()
                        } label: {
                            Text("Cancel")
                                .frame(minWidth: 80)
                        }
                        .buttonStyle(.sortyBordered)
                        
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
                    icon: result.icon,
                    description: customDescription,
                    promptModifier: result.prompt
                )
                
                await MainActor.run {
                    generatedPersona = newPersona
                    isGenerating = false
                    showingSuccess = true
                    
                    HapticFeedbackManager.shared.success()
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

    private func commitGeneratedPersona(_ persona: CustomPersona) {
        customPersonaStore.addPersona(persona)
        personaManager.selectCustomPersona(persona.id)
        generatedPersona = nil

        dismissCustomPersonaComposer(clearDescription: true)
    }

    private func dismissCustomPersonaComposer(clearDescription: Bool = true) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCreatingCustom = false
            isGenerating = false
            showingSuccess = false
            generationError = nil
            generatedPersona = nil
            if clearDescription {
                customDescription = ""
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
                        .fill(isSelected ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: persona.icon)
                        .font(.system(size: 28))
                        .foregroundStyle(isSelected ? SortyDesignSystem.Colors.resolvedAccent : .primary)
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardFill)
            )
            .systemLiquidGlassBackground(cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(cardStroke, lineWidth: isSelected ? 1.4 : 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isSelected ? "Selected Workflow" : "Use as Default", systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle") {
                action()
            }
            .disabled(isSelected)

            Divider()

            Button("Copy Workflow Name", systemImage: "doc.on.doc") {
                copyWorkflowText(persona.displayName)
            }

            Button("Copy Summary", systemImage: "text.quote") {
                copyWorkflowText(persona.description)
            }
        }
        .shadow(
            color: shadowColor,
            radius: isHovered || isSelected ? 14 : 7,
            x: 0,
            y: isHovered || isSelected ? 7 : 3
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var cardFill: Color {
        if isSelected {
            return SortyDesignSystem.Colors.resolvedAccent.opacity(0.10)
        }

        return Color.white.opacity(isHovered ? 0.13 : 0.08)
    }

    private var cardStroke: Color {
        if isSelected {
            return SortyDesignSystem.Colors.resolvedAccent.opacity(0.62)
        }

        return Color.primary.opacity(isHovered ? 0.18 : 0.09)
    }

    private var shadowColor: Color {
        if isSelected {
            return SortyDesignSystem.Colors.resolvedAccent.opacity(0.10)
        }

        return Color.black.opacity(isHovered ? 0.06 : 0.025)
    }
}

struct OnboardingCustomPersonaCard: View {
    let persona: CustomPersona
    let isSelected: Bool
    var compact: Bool = false
    var onDelete: (() -> Void)?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            HapticFeedbackManager.shared.tap()
            action()
        } label: {
            Group {
                if compact {
                    compactBody
                } else {
                    fullBody
                }
            }
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .padding(compact ? 14 : 18)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isHovered ? 0.13 : 0.08),
                                (isSelected ? SortyDesignSystem.Colors.resolvedAccent : Color.teal).opacity(isSelected ? 0.12 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .systemLiquidGlassBackground(cornerRadius: 18)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.62) : Color.primary.opacity(isHovered ? 0.18 : 0.09),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
            .shadow(
                color: (isSelected ? SortyDesignSystem.Colors.resolvedAccent : Color.black).opacity(isHovered || isSelected ? 0.10 : 0.025),
                radius: isHovered || isSelected ? 16 : 7,
                x: 0,
                y: isHovered || isSelected ? 8 : 3
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isSelected ? "Selected Workflow" : "Use as Default", systemImage: isSelected ? "checkmark.circle.fill" : "checkmark.circle") {
                HapticFeedbackManager.shared.tap()
                action()
            }
            .disabled(isSelected)

            Divider()

            Button("Copy Workflow Name", systemImage: "doc.on.doc") {
                copyWorkflowText(persona.name)
            }

            if !persona.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Copy Description", systemImage: "text.quote") {
                    copyWorkflowText(persona.description)
                }
            }

            Button("Copy Prompt", systemImage: "doc.text") {
                copyWorkflowText(persona.promptModifier)
            }

            if let onDelete {
                Divider()

                Button(role: .destructive) {
                    HapticFeedbackManager.shared.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        onDelete()
                    }
                } label: {
                    Label("Delete Workflow", systemImage: "trash")
                }
            }
        }
        .onHover { hovering in
            if hovering && !isHovered {
                HapticFeedbackManager.shared.selection()
            }
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.18), value: isHovered)
    }

    private var fullBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [SortyDesignSystem.Colors.resolvedAccent.opacity(0.22), Color.teal.opacity(0.16)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 58, height: 58)

                    Image(systemName: persona.icon)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(isSelected ? SortyDesignSystem.Colors.resolvedAccent : .primary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(persona.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        Text(isSelected ? "Selected" : "Custom")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? SortyDesignSystem.Colors.resolvedAccent : .secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isSelected ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.14) : Color.secondary.opacity(0.12))
                            )
                    }

                    Text(isSelected ? "Sorty will use this custom workflow by default." : "Custom workflow ready to use as your default persona.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !persona.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\"\(persona.description)\"")
                    .font(.callout)
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Label("AI-generated persona", systemImage: "sparkles")
                Label(isSelected ? "Default workflow" : "Ready to select", systemImage: isSelected ? "checkmark.circle.fill" : "arrow.up.right.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // Matches the built-in OnboardingPersonaCard's compact 2-column layout.
    private var compactBody: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(compactIconFill)
                    .frame(width: 60, height: 60)

                Image(systemName: persona.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(isSelected ? SortyDesignSystem.Colors.resolvedAccent : .primary)
            }

            VStack(spacing: 4) {
                Text(persona.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(isSelected ? "Selected workflow" : "Custom workflow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var compactIconFill: AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(SortyDesignSystem.Colors.resolvedAccent.opacity(0.18))
        }

        return AnyShapeStyle(
            LinearGradient(
                colors: [SortyDesignSystem.Colors.resolvedAccent.opacity(0.18), Color.teal.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

struct CreatePersonaButton: View {
    let title: String
    let subtitle: String
    @Binding var isCreatingCustom: Bool
    @State private var isHovered = false

    init(
        title: String = "Create Your Own",
        subtitle: String = "Describe your ideal organization style",
        isCreatingCustom: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isCreatingCustom = isCreatingCustom
    }
    
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
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(subtitle)
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
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isHovered ? 0.13 : 0.08))
            )
            .systemLiquidGlassBackground(cornerRadius: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(isHovered ? 0.18 : 0.09), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .shadow(
            color: Color.black.opacity(isHovered ? 0.06 : 0.025),
            radius: isHovered ? 14 : 7,
            x: 0,
            y: isHovered ? 7 : 3
        )
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

@MainActor
private func copyWorkflowText(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    HapticFeedbackManager.shared.selection()
}

// MARK: - Preview

#Preview {
    WorkflowSelectionStepView()
        .environmentObject(PersonaManager())
        .environmentObject(SettingsViewModel())
    .environmentObject(CustomPersonaStore())
}
