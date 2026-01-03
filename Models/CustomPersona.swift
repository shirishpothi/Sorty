//
//  CustomPersona.swift
//  FileOrganizer
//
//  Model and manager for user-created custom personas
//

import Foundation

// MARK: - Custom Persona Model

/// A user-created organization persona
public struct CustomPersona: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var icon: String
    public var description: String
    public var promptModifier: String
    public let createdAt: Date
    public var modifiedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "star.fill",
        description: String = "",
        promptModifier: String = ""
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.promptModifier = promptModifier
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    public mutating func update(name: String, icon: String, description: String, prompt: String) {
        self.name = name
        self.icon = icon
        self.description = description
        self.promptModifier = prompt
        self.modifiedAt = Date()
    }
}

// MARK: - Custom Persona Store

/// Manager for persisting custom personas
public class CustomPersonaStore: ObservableObject {
    @Published public var customPersonas: [CustomPersona] = []
    
    private let userDefaults = UserDefaults.standard
    private let storageKey = "customPersonas"
    
    public init() {
        loadPersonas()
    }
    
    public func addPersona(_ persona: CustomPersona) {
        customPersonas.append(persona)
        savePersonas()
    }
    
    public func updatePersona(_ persona: CustomPersona) {
        if let index = customPersonas.firstIndex(where: { $0.id == persona.id }) {
            customPersonas[index] = persona
            savePersonas()
        }
    }
    
    public func deletePersona(id: String) {
        customPersonas.removeAll { $0.id == id }
        savePersonas()
    }
    
    public func persona(named name: String) -> CustomPersona? {
        customPersonas.first { $0.name.lowercased() == name.lowercased() }
    }
    
    private func loadPersonas() {
        guard let data = userDefaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CustomPersona].self, from: data) else {
            return
        }
        customPersonas = decoded
    }
    
    private func savePersonas() {
        if let encoded = try? JSONEncoder().encode(customPersonas) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}

// MARK: - Available Icons

public let personaIconOptions: [String] = [
    "star.fill",
    "leaf.fill",
    "paintbrush.fill",
    "music.note",
    "film.fill",
    "gamecontroller.fill",
    "book.fill",
    "briefcase.fill",
    "house.fill",
    "graduationcap.fill",
    "heart.fill",
    "cart.fill",
    "airplane",
    "car.fill",
    "hammer.fill",
    "wrench.and.screwdriver.fill",
    "scissors",
    "pencil",
    "doc.text.fill",
    "folder.fill.badge.person.crop",
    "tray.2.fill",
    "archivebox.fill",
    "cube.fill",
    "wand.and.stars",
    "sparkles"
]
