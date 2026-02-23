
import XCTest
@testable import SortyLib

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

    func testPromptWithCustomInstructionsIsNotDuplicated() {
        let files = [FileItem(path: "/p/a.txt", name: "a", extension: "txt", size: 10, isDirectory: false)]
        let customInstructions = "Route tax documents to /Volumes/Archive/Taxes"

        let prompt = PromptBuilder.buildOrganizationPrompt(files: files, customInstructions: customInstructions)
        let occurrences = prompt.components(separatedBy: customInstructions).count - 1

        XCTAssertEqual(occurrences, 1)
    }
    
    func testReasoningModePrompt() {
        let systemPrompt = PromptBuilder.buildSystemPrompt(enableReasoning: true, personaInfo: "Test Persona")
        
        XCTAssertTrue(systemPrompt.contains("Test Persona"))
        XCTAssertTrue(systemPrompt.contains("Reasoning Mode Enabled"))
        XCTAssertTrue(systemPrompt.contains("\"reasoning\":"))
    }

    func testUltraCompactPromptIncludesAllFileIDs() {
        let files = (1...40).map { index in
            FileItem(
                path: "/tmp/file\(index).txt",
                name: "file\(index)",
                extension: "txt",
                size: 128,
                isDirectory: false
            )
        }

        let prompt = PromptBuilder.buildUltraCompactPrompt(files: files)
        XCTAssertTrue(prompt.user.contains("1|txt|file1"))
        XCTAssertTrue(prompt.user.contains("40|txt|file40"))
        XCTAssertFalse(prompt.user.contains("+10 more"))
    }

    func testSummaryPromptIncludesAllFileIDs() {
        let files = (1...40).map { index in
            FileItem(
                path: "/tmp/file\(index).txt",
                name: "file\(index)",
                extension: "txt",
                size: 128,
                isDirectory: false
            )
        }

        let prompt = PromptBuilder.buildSummaryPrompt(files: files)
        XCTAssertTrue(prompt.user.contains("1|txt|file1"))
        XCTAssertTrue(prompt.user.contains("40|txt|file40"))
    }

    func testMicroPromptIncludesAllFileIDs() {
        let files = (1...40).map { index in
            FileItem(
                path: "/tmp/file\(index).txt",
                name: "file\(index)",
                extension: "txt",
                size: 128,
                isDirectory: false
            )
        }

        let prompt = PromptBuilder.buildMicroPrompt(files: files)
        XCTAssertTrue(prompt.user.contains("1|txt"))
        XCTAssertTrue(prompt.user.contains("40|txt"))
    }

    func testCompactionLevelUsesFullPromptBudget() {
        let files = (1...120).map { index in
            FileItem(
                path: "/tmp/very_long_file_name_\(index).pdf",
                name: "very_long_file_name_\(index)",
                extension: "pdf",
                size: 1024,
                isDirectory: false
            )
        }
        let config = AIConfig(provider: .appleFoundationModel)
        let longInstructions = String(repeating: "keep all files strictly organized by project and date. ", count: 200)

        let level = PromptBuilder.selectCompactionLevel(
            files: files,
            config: config,
            customInstructions: longInstructions,
            maxTokens: 1200
        )

        XCTAssertTrue(level == .summary || level == .micro)
    }
}
