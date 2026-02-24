
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

    func testPromptIncludesOrderedVisionAttachmentInstructions() {
        let files = [FileItem(path: "/tmp/photo1.jpg", name: "photo1", extension: "jpg", size: 128)]
        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: files,
            analyzedImageFilenames: ["photo1.jpg", "photo2.png"]
        )

        XCTAssertTrue(prompt.contains("AI VISION ATTACHMENTS"))
        XCTAssertTrue(prompt.contains("1. photo1.jpg"))
        XCTAssertTrue(prompt.contains("2. photo2.png"))
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

    func testSystemPromptRenamingSectionVariesByMode() {
        let organize = PromptBuilder.buildSystemPrompt(personaInfo: "", mode: .organize)
        XCTAssertTrue(organize.contains("Do NOT suggest renamed filenames"))
        XCTAssertFalse(organize.contains("RENAME ONLY MODE (MANDATORY)"))

        let renameOnly = PromptBuilder.buildSystemPrompt(personaInfo: "", mode: .renameOnly)
        XCTAssertTrue(renameOnly.contains("RENAME ONLY MODE (MANDATORY)"))
        XCTAssertTrue(renameOnly.contains("\"rename_confidence\""))

        let organizeAndRename = PromptBuilder.buildSystemPrompt(personaInfo: "", mode: .organizeAndRename)
        XCTAssertTrue(organizeAndRename.contains("\"rename_confidence\""))
    }

    func testSystemPromptPrefersSpacesForFolderAndRenameNaming() {
        let prompt = PromptBuilder.buildSystemPrompt(personaInfo: "", mode: .organizeAndRename)

        XCTAssertTrue(prompt.contains("Title Case with spaces preferred"))
        XCTAssertTrue(prompt.contains("Use readable words with spaces by default"))
        XCTAssertFalse(prompt.contains("Use underscores, include dates"))
    }

    func testCompactResponseContractIncludesRenameFieldsOnlyForRenameModes() {
        let files = [FileItem(path: "/tmp/a.txt", name: "a", extension: "txt", size: 1)]

        let organizePrompt = PromptBuilder.buildUltraCompactPrompt(files: files, mode: .organize, enableReasoning: false).user
        XCTAssertFalse(organizePrompt.contains("\"rename_confidence\""))

        let renamePrompt = PromptBuilder.buildUltraCompactPrompt(files: files, mode: .renameOnly, enableReasoning: false).user
        XCTAssertTrue(renamePrompt.contains("\"rename_confidence\""))
    }

    func testRenamePromptIncludesContentMetadataContext() {
        let metadata = ContentMetadata(
            textPreview: "Quarterly results and projections for Q1",
            documentTitle: "Q1 Report",
            keywords: ["finance", "quarterly", "report"],
            ocrText: "Revenue growth 22 percent"
        )
        let file = FileItem(
            path: "/tmp/document.pdf",
            name: "document",
            extension: "pdf",
            size: 100,
            isDirectory: false,
            contentMetadata: metadata
        )

        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [file],
            mode: .renameOnly,
            includeContentMetadata: true
        )

        XCTAssertTrue(prompt.contains("[Rename Context]"))
        XCTAssertTrue(prompt.contains("Q1 Report") || prompt.contains("Revenue growth"))
    }

    func testRenamePromptMakesRenamesOptionalAndReasonSpecific() {
        let file = FileItem(path: "/tmp/invoice.pdf", name: "invoice", extension: "pdf", size: 100)
        let prompt = PromptBuilder.buildOrganizationPrompt(files: [file], mode: .renameOnly)

        XCTAssertTrue(prompt.contains("Renaming is optional per file"))
        XCTAssertTrue(prompt.contains("Only include `suggested_name` and `rename_reason`"))
        XCTAssertTrue(prompt.contains("concrete and evidence-based"))
    }

    func testSystemPromptRequiresConcreteRenameJustification() {
        let prompt = PromptBuilder.buildSystemPrompt(personaInfo: "", mode: .organizeAndRename)

        XCTAssertTrue(prompt.contains("Renaming is optional per file"))
        XCTAssertTrue(prompt.contains("\"rename_reason\" must cite concrete evidence"))
    }

    func testCustomNamingTemplateVariablesAreExpandedInExamples() {
        let creationDate = ISO8601DateFormatter().date(from: "2026-02-01T10:00:00Z")
        let file = FileItem(
            path: "/tmp/receipt.pdf",
            name: "receipt",
            extension: "pdf",
            size: 4096,
            isDirectory: false,
            creationDate: creationDate
        )

        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [file],
            mode: .renameOnly,
            customNamingInstructions: "{date}_{counter}_{ext}_{size}"
        )

        XCTAssertTrue(prompt.contains("CUSTOM NAMING PREFERENCE"))
        XCTAssertTrue(prompt.contains("Examples:"))
        XCTAssertTrue(prompt.contains("2026-02-01_01_pdf"))
    }

    func testNamingStylePromptInstructionsCoverage() {
        for style in NamingStyle.allCases {
            XCTAssertFalse(style.promptInstructions.isEmpty)
        }
    }

    func testDescriptiveNamingStyleEncouragesSpaces() {
        let instructions = NamingStyle.descriptive.promptInstructions
        XCTAssertTrue(instructions.contains("with spaces"))
        XCTAssertFalse(instructions.contains("[Date]_[Subject]_[Type]"))
    }
}
