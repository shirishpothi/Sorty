//
//  CustomPersonaTests.swift
//  SortyTests
//
//  Tests for custom persona creation and management
//

import XCTest
@testable import SortyLib

final class CustomPersonaTests: XCTestCase {
    
    // MARK: - CustomPersona Tests
    
    func testCustomPersonaCreation() {
        let persona = CustomPersona(
            name: "Test Persona",
            icon: "star.fill",
            description: "A test persona",
            promptModifier: "Organize files by test criteria"
        )
        
        XCTAssertFalse(persona.id.isEmpty)
        XCTAssertEqual(persona.name, "Test Persona")
        XCTAssertEqual(persona.icon, "star.fill")
        XCTAssertEqual(persona.description, "A test persona")
        XCTAssertEqual(persona.promptModifier, "Organize files by test criteria")
    }
    
    func testCustomPersonaUpdate() {
        var persona = CustomPersona(
            name: "Original",
            icon: "folder",
            description: "Original description",
            promptModifier: "Original prompt"
        )
        
        let originalModified = persona.modifiedAt
        
        // Small delay to ensure time difference
        Thread.sleep(forTimeInterval: 0.01)
        
        persona.update(
            name: "Updated",
            icon: "star",
            description: "Updated description",
            prompt: "Updated prompt"
        )
        
        XCTAssertEqual(persona.name, "Updated")
        XCTAssertEqual(persona.icon, "star")
        XCTAssertEqual(persona.description, "Updated description")
        XCTAssertEqual(persona.promptModifier, "Updated prompt")
        XCTAssertGreaterThan(persona.modifiedAt, originalModified)
    }
    
    func testCustomPersonaCodable() throws {
        let original = CustomPersona(
            name: "Codable Test",
            icon: "doc.fill",
            description: "Testing codable",
            promptModifier: "Some prompt"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CustomPersona.self, from: data)
        
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.icon, original.icon)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.promptModifier, original.promptModifier)
    }
    
    // MARK: - PersonaIconOptions Tests
    
    func testPersonaIconOptionsNotEmpty() {
        XCTAssertFalse(personaIconOptions.isEmpty)
        XCTAssertGreaterThanOrEqual(personaIconOptions.count, 10)
    }
    
    func testPersonaIconOptionsContainsCommonIcons() {
        XCTAssertTrue(personaIconOptions.contains("star.fill"))
        XCTAssertTrue(personaIconOptions.contains("folder.fill.badge.person.crop"))
    }
}
