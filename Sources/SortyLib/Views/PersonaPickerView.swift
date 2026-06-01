//
//  PersonaPickerView.swift
//  Sorty
//
//  UI for selecting organization personas including custom ones
//

import SwiftUI

struct PersonaPickerView: View {
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var customStore: CustomPersonaStore
    @State private var hoveringPersona: PersonaType?
    @State private var hoveringCustom: String?
    @State private var showingGenerator: Bool = false
    @State private var showingEditor: Bool = false
    @State private var editingPersona: CustomPersona?
    @State private var localPrompt: String = ""
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Default Organization Persona")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: {
                    showingGenerator = true
                }) {
                    Label("Generate", systemImage: "sparkles")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .padding(.trailing, 8)

                Button(action: { showingEditor = true }) {
                    Label("Create", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            // Built-in personas
            LazyVGrid(columns: personaGridColumns, spacing: 8) {
                ForEach(PersonaType.allCases, id: \.self) { persona in
                    PersonaButton(
                        persona: persona,
                        isSelected: personaManager.selectedPersona == persona
                            && personaManager.selectedCustomPersonaId == nil,
                        isHovering: hoveringPersona == persona
                    ) {
                        saveChangesIfNeeded()
                        withAnimation(.spring(response: 0.3)) {
                            personaManager.selectPersona(persona)
                            personaManager.selectedCustomPersonaId = nil
                            updateLocalPrompt()
                        }
                    }
                    .onHover { hovering in
                        hoveringPersona = hovering ? persona : nil
                    }
                }
            }

            // Custom personas
            if !customStore.customPersonas.isEmpty {
                Divider()

                Text("Custom Personas")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: personaGridColumns, spacing: 8) {
                    ForEach(customStore.customPersonas) { custom in
                        CustomPersonaButton(
                            persona: custom,
                            isSelected: personaManager.selectedCustomPersonaId == custom.id,
                            isHovering: hoveringCustom == custom.id,
                            onSelect: {
                                saveChangesIfNeeded()
                                withAnimation(.spring(response: 0.3)) {
                                    personaManager.selectedCustomPersonaId = custom.id
                                    updateLocalPrompt()
                                }
                            },
                            onEdit: {
                                editingPersona = custom
                                showingEditor = true
                            },
                            onDelete: {
                                customStore.deletePersona(id: custom.id)
                                if personaManager.selectedCustomPersonaId == custom.id {
                                    personaManager.selectedCustomPersonaId = nil
                                }
                            }
                        )
                        .onHover { hovering in
                            hoveringCustom = hovering ? custom.id : nil
                        }
                    }
                }
            }

            // Built-in persona description
            if selectedCustomPersona == nil {
                Text(currentDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.easeInOut, value: personaManager.selectedPersona)
            }

            Divider()
                .padding(.vertical, 8)

            personaInstructionsEditor
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editingPersona = nil }) {
            PersonaEditorView(store: customStore, editing: editingPersona)
                .environmentObject(customStore)
        }
        .sheet(isPresented: $showingGenerator) {
            PersonaGeneratorView(
                store: customStore, selectedPersonaId: $personaManager.selectedCustomPersonaId
            )
            .environmentObject(customStore)
        }
        .onAppear {
            updateLocalPrompt()
        }
        .onChange(of: isEditorFocused) { oldValue, newValue in
            if !newValue {
                saveChangesIfNeeded()
            }
        }
        .onChange(of: personaManager.selectedCustomPersonaId) { _, _ in
            updateLocalPrompt()
        }
        .onChange(of: customStore.customPersonas) { _, _ in
            updateLocalPrompt()
        }
    }

    @ViewBuilder
    private var personaInstructionsEditor: some View {
        if let custom = selectedCustomPersona {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: custom.icon)
                        .foregroundStyle(.purple)
                        .frame(width: 22, height: 22)
                        .accessibilityHidden(true)

                    Text(custom.name)
                        .foregroundStyle(.purple)
                        .fontWeight(.semibold)
                        + Text(" System Prompt")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    Button {
                        saveChangesIfNeeded()
                        HapticFeedbackManager.shared.tap()
                        editingPersona = custom
                        showingEditor = true
                    } label: {
                        Label("Edit Persona", systemImage: "pencil")
                    }
                    .buttonStyle(.sortyBordered(intent: .primary, size: .small))
                }

                TextEditor(text: $localPrompt)
                    .focused($isEditorFocused)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .accessibilityLabel("\(custom.name) system prompt")

                Text("Edit the custom persona system prompt Sorty sends to the AI.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Additional Instructions")
                        .font(.subheadline.weight(.medium))

                    Spacer()

                    if personaManager.customPrompts[personaManager.selectedPersona] != nil {
                        Button {
                            HapticFeedbackManager.shared.tap()
                            personaManager.resetCustomPrompt(for: personaManager.selectedPersona)
                            updateLocalPrompt()
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .font(.caption)
                        .buttonStyle(.sortyBordered(intent: .destructive, size: .small))
                    }
                }

                TextEditor(text: $localPrompt)
                    .focused($isEditorFocused)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 92)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                Text("Optional. Leave empty to use \(personaManager.selectedPersona.displayName)'s built-in behavior.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func updateLocalPrompt() {
        if let custom = selectedCustomPersona {
            localPrompt = custom.promptModifier
        } else {
            localPrompt = personaManager.customPrompts[personaManager.selectedPersona] ?? ""
        }
    }

    private func saveChangesIfNeeded() {
        if let custom = selectedCustomPersona {
            guard custom.promptModifier != localPrompt else { return }

            var updated = custom
            updated.update(
                name: custom.name,
                icon: custom.icon,
                description: custom.description,
                prompt: localPrompt
            )
            customStore.updatePersona(updated)
            return
        }

        if (personaManager.customPrompts[personaManager.selectedPersona] ?? "") != localPrompt {
            personaManager.saveCustomPrompt(
                for: personaManager.selectedPersona,
                prompt: localPrompt
            )
        }
    }

    private var currentDescription: String {
        if let customId = personaManager.selectedCustomPersonaId,
            let custom = customStore.customPersonas.first(where: { $0.id == customId })
        {
            return custom.description
        }
        return personaManager.selectedPersona.description
    }

    private var personaName: String {
        if let custom = selectedCustomPersona {
            return custom.name
        }
        return personaManager.selectedPersona.displayName
    }

    private var selectedCustomPersona: CustomPersona? {
        guard let customId = personaManager.selectedCustomPersonaId else { return nil }
        return customStore.customPersonas.first(where: { $0.id == customId })
    }

    private var personaGridColumns: [GridItem] {
        let columnCount = min(
            max(PersonaType.allCases.count, customStore.customPersonas.count),
            6
        )

        return Array(
            repeating: GridItem(.flexible(), spacing: 8),
            count: columnCount
        )
    }
}

// MARK: - Custom Persona Button

struct CustomPersonaButton: View {
    let persona: CustomPersona
    let isSelected: Bool
    let isHovering: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: persona.icon)
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)

            Text(persona.name)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.purple.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected
                                ? Color.purple : Color.secondary.opacity(isHovering ? 0.5 : 0.2),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .foregroundColor(isSelected ? .purple : .primary)
        .scaleEffect(isHovering && !isSelected ? 1.02 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Edit", action: onEdit)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

struct PersonaButton: View {
    let persona: PersonaType
    let isSelected: Bool
    let isHovering: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: persona.icon)
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)

            Text(persona.displayName)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected
                                ? SortyDesignSystem.Colors.resolvedAccent
                                : Color.secondary.opacity(isHovering ? 0.5 : 0.2),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        )
        .foregroundColor(isSelected ? .accentColor : .primary)
        .scaleEffect(isHovering && !isSelected ? 1.02 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            action()
        }
        .accessibilityLabel("\(persona.displayName) organization style")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Compact inline picker for the ready-to-organize screen
struct CompactPersonaPicker: View {
    @EnvironmentObject var personaManager: PersonaManager
    @EnvironmentObject var customStore: CustomPersonaStore

    var body: some View {
        Menu {
            Section("Built-in") {
                ForEach(PersonaType.allCases, id: \.self) { persona in
                    Button {
                        personaManager.selectPersona(persona)
                        personaManager.selectedCustomPersonaId = nil
                    } label: {
                        Label {
                            VStack(alignment: .leading) {
                                Text(persona.displayName)
                                Text(persona.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } icon: {
                            Image(systemName: persona.icon)
                        }
                    }
                }
            }

            if !customStore.customPersonas.isEmpty {
                Section("Custom") {
                    ForEach(customStore.customPersonas) { custom in
                        Button {
                            personaManager.selectedCustomPersonaId = custom.id
                        } label: {
                            Label(custom.name, systemImage: custom.icon)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: currentIcon)
                    .font(.system(size: 12))
                Text(currentName)
                    .font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .menuStyle(.borderlessButton)
    }

    private var currentIcon: String {
        if let customId = personaManager.selectedCustomPersonaId,
            let custom = customStore.customPersonas.first(where: { $0.id == customId })
        {
            return custom.icon
        }
        return personaManager.selectedPersona.icon
    }

    private var currentName: String {
        if let customId = personaManager.selectedCustomPersonaId,
            let custom = customStore.customPersonas.first(where: { $0.id == customId })
        {
            return custom.name
        }
        return personaManager.selectedPersona.displayName
    }
}

#Preview("Persona Picker") {
    PersonaPickerView()
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .padding()
        .frame(width: 400)
}

#Preview("Compact Picker") {
    CompactPersonaPicker()
        .environmentObject(PersonaManager())
        .environmentObject(CustomPersonaStore())
        .padding()
}
