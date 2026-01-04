//
//  PersonaEditorView.swift
//  FileOrganizer
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
    @State private var showIconPicker: Bool = false
    @State private var showingGenerator: Bool = false
    @State private var generationInput: String = ""
    @StateObject private var generator = PersonaGenerator()
    
    // Edit mode
    var editingPersona: CustomPersona?
    
    init(store: CustomPersonaStore, editing persona: CustomPersona? = nil) {
        self.store = store
        self.editingPersona = persona
        
        if let persona = persona {
            _name = State(initialValue: persona.name)
            _selectedIcon = State(initialValue: persona.icon)
            _description = State(initialValue: persona.description)
            _promptModifier = State(initialValue: persona.promptModifier)
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
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button(editingPersona == nil ? "Create" : "Save") {
                    savePersona()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.return)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name & Icon
                    GroupBox("Identity") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Button(action: { showIconPicker = true }) {
                                    Image(systemName: selectedIcon)
                                        .font(.system(size: 28))
                                        .frame(width: 50, height: 50)
                                        .background(Color.accentColor.opacity(0.15))
                                        .cornerRadius(10)
                                }
                                .buttonStyle(.plain)
                                .popover(isPresented: $showIconPicker) {
                                    iconPickerPopover
                                }
                                
                                TextField("Persona Name", text: $name)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.title3)
                            }
                            
                            TextField("Short description", text: $description)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Prompt Modifier
                    GroupBox("Organization Instructions") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Define how the AI should organize files with this persona:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextEditor(text: $promptModifier)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 200)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                            
                            HStack {
                                Button("Insert Template") {
                                    insertTemplate()
                                }
                                .buttonStyle(.bordered)
                                
                                Button(action: { showingGenerator = true }) {
                                    Label("Generate with AI", systemImage: "sparkles")
                                }
                                .buttonStyle(.bordered)
                                .disabled(generator.isGenerating)
                                
                                Spacer()
                                
                                Text("\(promptModifier.count) characters")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Tips
                    GroupBox("Tips") {
                        VStack(alignment: .leading, spacing: 8) {
                            tipRow(icon: "lightbulb.fill", text: "Use markdown headers like ## to structure your prompt")
                            tipRow(icon: "folder.fill", text: "Define preferred folder structures explicitly")
                            tipRow(icon: "doc.text.magnifyingglass", text: "Mention specific file types or patterns to look for")
                            tipRow(icon: "arrow.triangle.branch", text: "Describe how to handle edge cases")
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }
        }
        .frame(width: 600, height: 600)
        .sheet(isPresented: $showingGenerator) {
            VStack(spacing: 20) {
                Text("Generate Persona")
                    .font(.headline)
                
                Text("Describe how you want your files to be organized. Be as specific as you like about file types, folder structures, and naming conventions.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                TextEditor(text: $generationInput)
                    .font(.body)
                    .frame(height: 150)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                
                if let error = generator.error {
                    Text(error.localizedDescription)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                HStack {
                    Button("Cancel") {
                        showingGenerator = false
                    }
                    
                    if generator.isGenerating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Generate") {
                            Task {
                                do {
                                    let result = try await generator.generatePersona(from: generationInput, config: settingsViewModel.config)
                                    name = result.name
                                    promptModifier = result.prompt
                                    showingGenerator = false
                                } catch {
                                    // Error is handled by generator.error publishing
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(generationInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding()
            .frame(width: 400)
        }
    }
    
    private var iconPickerPopover: some View {
        VStack(spacing: 12) {
            Text("Choose Icon")
                .font(.headline)
            
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 5), spacing: 8) {
                ForEach(personaIconOptions, id: \.self) { icon in
                    Button(action: {
                        selectedIcon = icon
                        showIconPicker = false
                    }) {
                        Image(systemName: icon)
                            .font(.system(size: 20))
                            .frame(width: 36, height: 36)
                            .background(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .frame(width: 240)
    }
    
    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
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
            existing.update(name: name, icon: selectedIcon, description: description, prompt: promptModifier)
            store.updatePersona(existing)
        } else {
            let newPersona = CustomPersona(
                name: name,
                icon: selectedIcon,
                description: description,
                promptModifier: promptModifier
            )
            store.addPersona(newPersona)
        }
    }
}

#Preview {
    PersonaEditorView(store: CustomPersonaStore())
}
