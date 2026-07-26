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
    @State private var showingInstructionsInfo: Bool = false
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
            PersonaEditorView(
                store: customStore,
                editing: editingPersona,
                onDelete: { persona in
                    customStore.deletePersona(id: persona.id)
                    if personaManager.selectedCustomPersonaId == persona.id {
                        personaManager.selectedCustomPersonaId = nil
                    }
                }
            )
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

                    instructionsInfoButton(
                        text: "These instructions are saved with \(custom.name) and apply whenever you use this persona. Use them for preferences such as folder count, hierarchy depth, or grouping rules.",
                        accessibilityLabel: "\(custom.name) instruction information"
                    )

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
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(alignment: .topLeading) {
                        Text(localPrompt.isEmpty ? " " : localPrompt + " ")
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .foregroundColor(.clear)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 70, maxHeight: 320)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: localPrompt)
                    .accessibilityLabel("\(custom.name) system prompt")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Additional Instructions")
                        .font(.subheadline.weight(.medium))

                    instructionsInfoButton(
                        text: "These instructions are saved with \(personaManager.selectedPersona.displayName) and apply whenever you use this persona. Use them for preferences such as folder count, hierarchy depth, or grouping rules.",
                        accessibilityLabel: "Additional instruction information"
                    )

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
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(alignment: .topLeading) {
                        Text(localPrompt.isEmpty ? " " : localPrompt + " ")
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .foregroundColor(.clear)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 70, maxHeight: 320)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: localPrompt)
            }
        }
    }

    private func instructionsInfoButton(
        text: LocalizedStringKey,
        accessibilityLabel: LocalizedStringKey
    ) -> some View {
        Button {
            HapticFeedbackManager.shared.tap()
            showingInstructionsInfo.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingInstructionsInfo, arrowEdge: .bottom) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 300, alignment: .leading)
                .systemLiquidGlassPopover(cornerRadius: 12)
        }
        .help("About these instructions")
        .accessibilityLabel(accessibilityLabel)
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
                .fill(
                    isSelected ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.15) : Color.clear
                )
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
    @State private var isHovering = false

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
            HStack(spacing: 9) {
                Image(systemName: currentIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SortyDesignSystem.Colors.resolvedAccent)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                Text(currentName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .systemLiquidGlassBackground(cornerRadius: 12)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        SortyDesignSystem.Colors.resolvedAccent.opacity(isHovering ? 0.36 : 0.18),
                        lineWidth: 1
                    )
            }
            .shadow(
                color: SortyDesignSystem.Colors.resolvedAccent.opacity(isHovering ? 0.16 : 0.05),
                radius: isHovering ? 9 : 4,
                y: isHovering ? 4 : 2
            )
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isHovering)
        }
        .menuStyle(.borderlessButton)
        .onHover { hovering in
            guard hovering != isHovering else { return }
            isHovering = hovering
            if hovering {
                HapticFeedbackManager.shared.light()
            }
        }
        .help("Organization style: \(currentName). \(currentDescription)")
        .accessibilityLabel("Organization style")
        .accessibilityValue(currentName)
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

    private var currentDescription: String {
        if let customId = personaManager.selectedCustomPersonaId,
            let custom = customStore.customPersonas.first(where: { $0.id == customId })
        {
            return custom.description
        }
        return personaManager.selectedPersona.description
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
