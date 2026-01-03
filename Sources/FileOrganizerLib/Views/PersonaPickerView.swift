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
    @State private var showingEditor: Bool = false
    @State private var editingPersona: CustomPersona?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Organization Style")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
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
        }
        .sheet(isPresented: $showingEditor, onDismiss: { editingPersona = nil }) {
            PersonaEditorView(store: customStore, editing: editingPersona)
        }
    }
    
    private var currentDescription: String {
        if let customId = personaManager.selectedCustomPersonaId,
           let custom = customStore.customPersonas.first(where: { $0.id == customId }) {
            return custom.description
        }
        return personaManager.selectedPersona.description
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
        Button(action: onSelect) {
            VStack(spacing: 6) {
                Image(systemName: persona.icon)
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                
                Text(persona.name)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
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
        }
        .buttonStyle(.plain)
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
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: persona.icon)
                    .font(.system(size: 18))
                    .symbolRenderingMode(.hierarchical)
                
                Text(persona.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
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
        }
        .buttonStyle(.plain)
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
