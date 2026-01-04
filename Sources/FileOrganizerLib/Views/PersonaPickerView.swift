//
//  PersonaPickerView.swift
//  FileOrganizer
//
//  UI for selecting organization personas including custom ones
//

import SwiftUI

struct PersonaPickerView: View {
    @EnvironmentObject var personaManager: PersonaManager
    @StateObject private var customStore = CustomPersonaStore()
    @State private var hoveringPersona: PersonaType?
    @State private var hoveringCustom: String?
    @State private var showingGenerator: Bool = false
    @State private var showingEditor: Bool = false
    @State private var editingPersona: CustomPersona?
    
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
            HStack(spacing: 8) {
                ForEach(PersonaType.allCases, id: \.self) { persona in
                    PersonaButton(
                        persona: persona,
                        isSelected: personaManager.selectedPersona == persona && personaManager.selectedCustomPersonaId == nil,
                        isHovering: hoveringPersona == persona
                    ) {
                        withAnimation(.spring(response: 0.3)) {
                            personaManager.selectPersona(persona)
                            personaManager.selectedCustomPersonaId = nil
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
                
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 8) {
                    ForEach(customStore.customPersonas) { custom in
                        CustomPersonaButton(
                            persona: custom,
                            isSelected: personaManager.selectedCustomPersonaId == custom.id,
                            isHovering: hoveringCustom == custom.id,
                            onSelect: {
                                withAnimation(.spring(response: 0.3)) {
                                    personaManager.selectedCustomPersonaId = custom.id
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
            
            // Description
            Text(currentDescription)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.easeInOut, value: personaManager.selectedPersona)
            
            Divider()
                .padding(.vertical, 8)
            
            // Custom System Prompt Editor
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(personaName).foregroundColor(.purple).bold() + Text(" System Prompt")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if personaManager.selectedCustomPersonaId == nil {
                        // Standard Persona Reset
                        if let _ = personaManager.customPrompts[personaManager.selectedPersona] {
                            Button("Reset to Default") {
                                HapticFeedbackManager.shared.tap()
                                personaManager.resetCustomPrompt(for: personaManager.selectedPersona)
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                    }
                }
                
                if let customId = personaManager.selectedCustomPersonaId,
                   let index = customStore.customPersonas.firstIndex(where: { $0.id == customId }) {
                    // Editing Custom Persona
                    TextEditor(text: Binding(
                        get: { customStore.customPersonas[index].promptModifier },
                        set: { newValue in
                            var updated = customStore.customPersonas[index]
                            updated.promptModifier = newValue
                            customStore.updatePersona(updated)
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    
                    Text("Editing prompt for custom persona '\(customStore.customPersonas[index].name)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                } else {
                    // Editing Standard Persona
                    TextEditor(text: Binding(
                        get: { personaManager.getPrompt(for: personaManager.selectedPersona) },
                        set: { newValue in
                            personaManager.saveCustomPrompt(for: personaManager.selectedPersona, prompt: newValue)
                        }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 120)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    
                    Text("Customize AI instructions for '\(personaManager.selectedPersona.displayName)'")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editingPersona = nil }) {
            PersonaEditorView(store: customStore, editing: editingPersona)
        }
        .sheet(isPresented: $showingGenerator) {
            PersonaGeneratorView(store: customStore, selectedPersonaId: $personaManager.selectedCustomPersonaId)
        }
    }
    
    private var currentDescription: String {
        if let customId = personaManager.selectedCustomPersonaId,
           let custom = customStore.customPersonas.first(where: { $0.id == customId }) {
            return custom.description
        }
        return personaManager.selectedPersona.description
    }
    
    private var personaName: String {
        if let customId = personaManager.selectedCustomPersonaId,
           let custom = customStore.customPersonas.first(where: { $0.id == customId }) {
            return custom.name
        }
        return personaManager.selectedPersona.displayName
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
                            isSelected ? Color.purple : Color.secondary.opacity(isHovering ? 0.5 : 0.2),
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
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? Color.accentColor : Color.secondary.opacity(isHovering ? 0.5 : 0.2),
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
    @StateObject private var customStore = CustomPersonaStore()
    
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
           let custom = customStore.customPersonas.first(where: { $0.id == customId }) {
            return custom.icon
        }
        return personaManager.selectedPersona.icon
    }
    
    private var currentName: String {
        if let customId = personaManager.selectedCustomPersonaId,
           let custom = customStore.customPersonas.first(where: { $0.id == customId }) {
            return custom.name
        }
        return personaManager.selectedPersona.displayName
    }
}

#Preview("Persona Picker") {
    PersonaPickerView()
        .environmentObject(PersonaManager())
        .padding()
        .frame(width: 400)
}

#Preview("Compact Picker") {
    CompactPersonaPicker()
        .environmentObject(PersonaManager())
        .padding()
}
