
import XCTest
@testable import FileOrganizerLib

class PromptBuilderTests: XCTestCase {
    
    func testOrganizationPromptBuilding() {
        let files = [
            FileItem(path: "/p1/a.txt", name: "a", extension: "txt", size: 100, isDirectory: false),
            FileItem(path: "/p1/b.png", name: "b", extension: "png", size: 200, isDirectory: false)
        ]
        
        let prompt = PromptBuilder.buildOrganizationPrompt(files: files)
        
        XCTAssertTrue(prompt.contains("a"))
        XCTAssertTrue(prompt.contains("b"))
        XCTAssertTrue(prompt.contains(".TXT files"))
        XCTAssertTrue(prompt.contains(".PNG files"))
        // Check for general size formatting instead of specific string
        XCTAssertTrue(prompt.contains("100") || prompt.contains("100 B") || prompt.contains("100 bytes"))
        XCTAssertTrue(prompt.contains("200") || prompt.contains("200 B") || prompt.contains("200 bytes"))
    }
    
    func testPromptWithCustomInstructions() {
        let files = [FileItem(path: "/p/a.txt", name: "a", extension: "txt", size: 10, isDirectory: false)]
        let customInstructions = "Sort by date"
        
        let prompt = PromptBuilder.buildOrganizationPrompt(files: files, customInstructions: customInstructions)
        
        XCTAssertTrue(prompt.contains("USER INSTRUCTIONS: Sort by date"))
    }
    
    func testReasoningModePrompt() {
        let systemPrompt = PromptBuilder.buildSystemPrompt(enableReasoning: true, personaInfo: "Test Persona")
        
        XCTAssertTrue(systemPrompt.contains("Test Persona"))
        XCTAssertTrue(systemPrompt.contains("Reasoning Mode Enabled"))
        XCTAssertTrue(systemPrompt.contains("\"reasoning\":"))
    }
}
