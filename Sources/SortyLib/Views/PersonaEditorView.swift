//
//  PersonaEditorView.swift
//  Sorty
//
//  UI for creating and editing custom organization personas
//

import SwiftUI

struct PersonaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    @ObservedObject var store: CustomPersonaStore
    
    @State private var name: String = ""
    @State private var selectedIcon: String = "star.fill"
    @State private var description: String = ""
    @State private var promptModifier: String = ""
    @State private var instructionSuggestions = PersonaInstructionSuggestions()
    @State private var showIconPicker: Bool = false
    @State private var automaticallySelectIcon: Bool
    @State private var showingChat: Bool = false
    @State private var identityGenerationError: String?
    @State private var showingDeleteConfirmation = false
    @StateObject private var generator = PersonaGenerator()
    
    // Edit mode
    var editingPersona: CustomPersona?
    private let onDelete: ((CustomPersona) -> Void)?
    private let onGeneratePersona: (() -> Void)?
    
    init(
        store: CustomPersonaStore,
        editing persona: CustomPersona? = nil,
        onDelete: ((CustomPersona) -> Void)? = nil,
        onGeneratePersona: (() -> Void)? = nil
    ) {
        self.store = store
        self.editingPersona = persona
        self.onDelete = onDelete
        self.onGeneratePersona = onGeneratePersona
        _automaticallySelectIcon = State(initialValue: persona == nil)
        
        if let persona = persona {
            _name = State(initialValue: persona.name)
            _selectedIcon = State(initialValue: persona.icon)
            _description = State(initialValue: persona.description)
            _promptModifier = State(initialValue: persona.promptModifier)
            _instructionSuggestions = State(initialValue: persona.instructionSuggestions)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(editingPersona == nil ? "Create Custom Persona" : "Edit Persona")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if editingPersona != nil {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.sortyBordered(intent: .destructive))
                } else {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.sortyBordered)
                    .keyboardShortcut(.escape)
                }
                
                Button(editingPersona == nil ? "Create" : "Save") {
                    savePersona()
                    dismiss()
                }
                .buttonStyle(.sortyProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    organizationInstructionsSection
                    identitySection
                    tipsSection
                }
                .padding(16)
            }
        }
        .frame(width: 700, height: 680)
        .alert("Delete Persona?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deletePersona()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(name.isEmpty ? "this persona" : "“\(name)”").")
        }
        .sheet(isPresented: $showingChat) {
            PersonaChatView(promptModifier: promptModifier)
                .environmentObject(settingsViewModel)
        }
    }

    private var organizationInstructionsSection: some View {
        editorSection(
            title: "Organization Instructions",
            icon: "text.alignleft"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Define how Sorty should organize files with this persona. These instructions also power automatic identity and icon generation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ZStack(alignment: .topLeading) {
                    if promptModifier.isEmpty {
                        Text("Describe the grouping strategy, folder structure, file-type rules, naming preferences, and edge cases…")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $promptModifier)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
                .frame(minHeight: 210)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                }

                HStack(spacing: 8) {
                    Button("Insert Template") {
                        insertTemplate()
                    }
                    .buttonStyle(.sortyBordered)

                    Button(action: openPersonaGenerator) {
                        Label("Generate Instructions…", systemImage: "sparkles")
                    }
                    .buttonStyle(.sortyBordered)
                    .disabled(generator.isGenerating)

                    Button(action: { showingChat = true }) {
                        Label("Test Persona", systemImage: "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.sortyBordered)
                    .disabled(trimmedInstructions.isEmpty)

                    Spacer()

                    Text("\(promptModifier.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .numericTextTransition(animationValue: promptModifier.count)
                }
            }
        }
    }

    private var identitySection: some View {
        editorSection(
            title: "Identity",
            icon: "person.text.rectangle"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 6) {
                        Button {
                            automaticallySelectIcon = false
                            showIconPicker = true
                        } label: {
                            Image(systemName: selectedIcon)
                                .font(.system(size: 30, weight: .semibold))
                                .frame(width: 64, height: 64)
                                .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                                .background(
                                    SortyDesignSystem.Colors.resolvedAccent.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showIconPicker) {
                            iconPickerPopover
                        }
                        .help("Choose a persona icon")

                        Text(automaticallySelectIcon ? "Automatic" : "Manual")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 76)

                    VStack(spacing: 10) {
                        TextField("Persona Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .font(.title3)

                        TextField("Short description", text: $description)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                Divider()

                HStack(spacing: 12) {
                    Toggle(
                        "Select the most relevant icon when generating",
                        isOn: $automaticallySelectIcon
                    )
                    .toggleStyle(.checkbox)
                    .font(.caption)

                    Spacer()

                    Button {
                        generateIdentityFromInstructions()
                    } label: {
                        HStack(spacing: 7) {
                            if generator.isGenerating {
                                SortyGradientCircularLoader(size: 11, lineWidth: 2)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(generator.isGenerating ? "Generating…" : "Generate from Instructions")
                        }
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .disabled(trimmedInstructions.isEmpty || generator.isGenerating)
                }

                if let identityGenerationError {
                    Label(identityGenerationError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var tipsSection: some View {
        editorSection(title: "Useful details", icon: "lightbulb.fill") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 10)],
                alignment: .leading,
                spacing: 10
            ) {
                tipRow(icon: "text.badge.checkmark", text: "Use ## headers to separate distinct rules")
                tipRow(icon: "folder.fill", text: "Show the folder hierarchy you want Sorty to create")
                tipRow(icon: "doc.text.magnifyingglass", text: "Call out relevant file types and filename patterns")
                tipRow(icon: "arrow.triangle.branch", text: "Explain how ambiguous files and edge cases should behave")
            }
        }
    }
    
    private var iconPickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose Icon")
                    .font(.headline)

                Text("\(personaIconOptions.count) icons available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 40), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(personaIconOptions, id: \.self) { icon in
                        Button {
                            automaticallySelectIcon = false
                            selectedIcon = icon
                            showIconPicker = false
                            HapticFeedbackManager.shared.selection()
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .medium))
                                .frame(width: 38, height: 38)
                                .foregroundStyle(
                                    selectedIcon == icon
                                        ? SortyDesignSystem.Colors.resolvedAccent
                                        : Color.primary
                                )
                                .background(
                                    selectedIcon == icon
                                        ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.16)
                                        : Color.primary.opacity(0.04),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(icon)
                        .accessibilityLabel(icon)
                    }
                }
            }
            .frame(maxHeight: 270)
        }
        .padding(16)
        .frame(width: 390)
        .systemLiquidGlassPopover(cornerRadius: 12)
    }

    private func editorSection<Content: View>(
        title: LocalizedStringKey,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                .frame(width: 28, height: 28)
                .background(
                    SortyDesignSystem.Colors.resolvedAccent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }

    private var trimmedInstructions: String {
        promptModifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openPersonaGenerator() {
        HapticFeedbackManager.shared.tap()
        if let onGeneratePersona {
            onGeneratePersona()
        } else {
            dismiss()
        }
    }

    private func generateIdentityFromInstructions() {
        identityGenerationError = nil

        Task {
            do {
                let result = try await generator.generateIdentity(
                    from: trimmedInstructions,
                    config: settingsViewModel.config
                )
                name = result.name
                description = result.description
                if automaticallySelectIcon {
                    selectedIcon = result.icon
                }
                HapticFeedbackManager.shared.success()
            } catch {
                identityGenerationError = error.localizedDescription
                HapticFeedbackManager.shared.error()
            }
        }
    }

    private func insertTemplate() {
        promptModifier = """
        ## [Your Persona Name] Organization Strategy
        
        ### Primary Grouping
        - Describe how files should be primarily organized
        
        ### File Type Handling
        - **Documents**: How to organize documents
        - **Images**: How to organize images
        - **Other**: How to handle other file types
        
        ### Folder Structure
        Preferred folder structure:
        - FolderA/
        - FolderB/SubfolderB1/
        
        ### Special Rules
        - Any special rules or patterns to follow
        """
    }
    
    private func savePersona() {
        if var existing = editingPersona {
            existing.update(
                name: name,
                icon: selectedIcon,
                description: description,
                prompt: promptModifier,
                instructionSuggestions: instructionSuggestions
            )
            store.updatePersona(existing)
        } else {
            let newPersona = CustomPersona(
                name: name,
                icon: selectedIcon,
                description: description,
                promptModifier: promptModifier,
                instructionSuggestions: instructionSuggestions
            )
            store.addPersona(newPersona)
        }
    }

    private func deletePersona() {
        guard let editingPersona else { return }

        if let onDelete {
            onDelete(editingPersona)
        } else {
            store.deletePersona(id: editingPersona.id)
        }

        HapticFeedbackManager.shared.error()
        NotificationManager.shared.showHUDInfo(
            title: "Persona Deleted",
            message: "\(editingPersona.name) was removed.",
            icon: "trash.fill",
            iconColor: .red,
            identifier: "persona-deleted"
        )
        dismiss()
    }
}

#Preview {
    PersonaEditorView(store: CustomPersonaStore())
        .environmentObject(SettingsViewModel())
}
