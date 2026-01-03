//
//  OrganizationPersona.swift
//  FileOrganizer
//
//  Custom organization presets that modify AI behavior
//

import Foundation
import Combine

public enum PersonaType: String, Codable, CaseIterable, Sendable {
    case general = "general"
    case developer = "developer"
    case photographer = "photographer"
    case office = "office"
    
    public var displayName: String {
        switch self {
        case .general: return "General"
        case .developer: return "Developer Mode"
        case .photographer: return "Photographer Mode"
        case .office: return "Office Mode"
        }
    }
    
    public var description: String {
        switch self {
        case .general:
            return "Balanced organization by file type and purpose"
        case .developer:
            return "Organize by project, language, and build artifacts"
        case .photographer:
            return "Organize by date, camera, and event using EXIF data"
        case .office:
            return "Organize by client, project, and year"
        }
    }
    
    public var icon: String {
        switch self {
        case .general: return "folder"
        case .developer: return "chevron.left.forwardslash.chevron.right"
        case .photographer: return "camera"
        case .office: return "building.2"
        }
    }
    
    /// Additional prompt instructions for this persona
    public var promptModifier: String {
        switch self {
        case .general:
            return """
            ## General Organization Strategy:
            - **Primary grouping**: By file category (e.g., Documents, Images, Audio, Video, Archives)
            - **Sub-grouping**: By specific type or context (e.g., Documents/Invoices, Images/Screenshots)
            - **Date-based organization**: For time-sensitive files (e.g. photos, logs, receipts), group by Year/Month.
            - **Context clustering**: Group related files together (e.g. a project proposal and its assets).
            - **Clean up**: Move temporary files (installers, dmg, zip) to a specific 'Installers' or 'Archives' folder.
            
            Aim for a clean, intuitive structure that anybody could understand.
            """
            
        case .developer:
            return """
            
            ## Developer Mode Specialization:
            - **Primary grouping**: By programming language or technology stack
            - **Project detection**: Look for package.json, Cargo.toml, go.mod, *.xcodeproj, etc.
            - **Source organization**: Group by src/, lib/, tests/, docs/, config/
            - **Recognize build artifacts**: node_modules/, target/, build/, dist/, .cache/
            - **Version control**: Keep .git related files together
            - **Configuration**: Group dotfiles and config files
            - **Dependencies**: Separate vendor/third-party code
            
            Preferred folder structure:
            - Projects/[ProjectName]/
            - Scripts/[Language]/
            - Documentation/
            - Config/
            - Archives/
            """
            
        case .photographer:
            return """
            
            ## Photographer Mode Specialization:
            - **Primary grouping**: By date (Year/Month or Year/Event)
            - **Use EXIF data**: Extract camera model, date taken, GPS location
            - **Event detection**: Group photos taken on same day/location
            - **Camera organization**: Optionally sub-group by camera/device
            - **RAW vs Processed**: Separate RAW files from JPEGs
            - **Edited files**: Detect "_edit", "_final", "-2" suffixes
            
            Preferred folder structure:
            - Photos/[Year]/[Month] or Photos/[Year]/[Event]/
            - RAW/
            - Edited/
            - Screenshots/
            - Videos/
            
            Pay special attention to EXIF metadata if available.
            """
            
        case .office:
            return """
            
            ## Office Mode Specialization:
            - **Primary grouping**: By client or project name
            - **Document types**: Contracts, Invoices, Reports, Proposals, Correspondence
            - **Date-based subfolders**: Year/Quarter for time-sensitive documents
            - **Client detection**: Look for company names in filenames
            - **Version tracking**: Keep v1, v2, draft, final together
            
            Preferred folder structure:
            - Clients/[ClientName]/[Year]/
            - Projects/[ProjectName]/
            - Templates/
            - Archives/[Year]/
            - Finance/Invoices/, Finance/Receipts/
            - Legal/Contracts/
            
            Look for invoice numbers, client names, and project codes in filenames.
            """
        }
    }
}

/// Manager for persona settings
@MainActor
public class PersonaManager: ObservableObject {
    @Published public var selectedPersona: PersonaType = .general
    @Published public var selectedCustomPersonaId: String?
    
    @Published public var customPrompts: [PersonaType: String] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let storageKey = "selectedPersona"
    private let customPromptsKey = "customPersonaPrompts"
    private let customIdKey = "selectedCustomPersonaId"
    
    public init() {
        loadPersona()
        loadCustomPrompts()
        loadCustomPersonaId()
    }
    
    public func selectPersona(_ persona: PersonaType) {
        selectedPersona = persona
        selectedCustomPersonaId = nil
        savePersona()
        saveCustomPersonaId()
    }
    
    public func selectCustomPersona(_ id: String) {
        selectedCustomPersonaId = id
        saveCustomPersonaId()
    }
    
    public func getPrompt(for persona: PersonaType) -> String {
        if let custom = customPrompts[persona], !custom.isEmpty {
            return custom
        }
        return persona.promptModifier
    }
    
    public func saveCustomPrompt(for persona: PersonaType, prompt: String) {
        if prompt.isEmpty || prompt == persona.promptModifier {
            customPrompts.removeValue(forKey: persona)
        } else {
            customPrompts[persona] = prompt
        }
        saveCustomPrompts()
    }
    
    public func resetCustomPrompt(for persona: PersonaType) {
        customPrompts.removeValue(forKey: persona)
        saveCustomPrompts()
    }
    
    private func loadPersona() {
        if let rawValue = userDefaults.string(forKey: storageKey),
           let persona = PersonaType(rawValue: rawValue) {
            selectedPersona = persona
        }
    }
    
    private func savePersona() {
        userDefaults.set(selectedPersona.rawValue, forKey: storageKey)
    }
    
    private func loadCustomPrompts() {
        if let data = userDefaults.data(forKey: customPromptsKey),
           let decoded = try? JSONDecoder().decode([PersonaType: String].self, from: data) {
            customPrompts = decoded
        }
    }
    
    private func saveCustomPrompts() {
        if let encoded = try? JSONEncoder().encode(customPrompts) {
            userDefaults.set(encoded, forKey: customPromptsKey)
        }
    }
    
    private func loadCustomPersonaId() {
        if let id = userDefaults.string(forKey: customIdKey) {
            selectedCustomPersonaId = id
        }
    }
    
    private func saveCustomPersonaId() {
        if let id = selectedCustomPersonaId {
            userDefaults.set(id, forKey: customIdKey)
        } else {
            userDefaults.removeObject(forKey: customIdKey)
        }
    }
}
