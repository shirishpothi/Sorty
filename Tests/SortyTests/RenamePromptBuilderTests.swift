import XCTest
@testable import SortyLib

final class RenamePromptBuilderTests: XCTestCase {
    func testRenameOnlyPromptUsesCurrentFolderAndNoFolderStructure() {
        let file = FileItem(path: "/tmp/Scan_0042.pdf", name: "Scan_0042", extension: "pdf", size: 1024, isDirectory: false)

        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [file],
            mode: .renameOnly,
            namingStyle: .descriptive,
            renameNamingOptions: .default,
            enableSmartRename: true,
            includeContentMetadata: true
        )

        XCTAssertTrue(prompt.contains("single root folder named '.'"))
        XCTAssertTrue(prompt.contains("DO NOT suggest any folder structure"))
    }

    func testRenameOnlyPromptIgnoresOrganizationRoutingContext() {
        let file = FileItem(path: "/tmp/Scan_0042.pdf", name: "Scan_0042", extension: "pdf", size: 1024, isDirectory: false)

        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [file],
            mode: .renameOnly,
            storageLocationsContext: "VALID_STORAGE_PATHS: /Archive",
            existingFoldersContext: "Existing folders: Receipts, Projects"
        )

        XCTAssertFalse(prompt.contains("VALID_STORAGE_PATHS"))
        XCTAssertFalse(prompt.contains("Existing folders"))
        XCTAssertTrue(prompt.contains("single folder named '.'"))
    }

    func testPromptIncludesSeparatorLanguageAndCustomInstructions() {
        let file = FileItem(path: "/tmp/scan.pdf", name: "scan", extension: "pdf", size: 1024, isDirectory: false)
        let options = RenameNamingOptions(separator: .spaces, caseStyle: .title, maxFilenameLength: 70, outputLanguage: "German", datePolicy: .alwaysWhenReliable)

        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [file],
            mode: .renameOnly,
            namingStyle: .custom,
            renameNamingOptions: options,
            customNamingInstructions: "Use client name before document type.",
            enableSmartRename: true,
            includeContentMetadata: true
        )

        XCTAssertTrue(prompt.contains("Spaces are valid macOS filename characters"))
        XCTAssertTrue(prompt.contains("Output language: German"))
        XCTAssertTrue(prompt.contains("Maximum filename length, including extension: 70"))
        XCTAssertTrue(prompt.contains("Use client name before document type."))
    }

    func testPromptIncludesMeaningfulContentMetadataForRenaming() {
        let metadata = ContentMetadata(
            textPreview: "Service Agreement between Acme Co and Example LLC signed March 19 2026.",
            documentTitle: "Signed Service Agreement",
            pageCount: 8,
            detectedKeywords: ["agreement", "signed"]
        )
        let file = FileItem(
            path: "/tmp/scan.pdf",
            name: "scan",
            extension: "pdf",
            size: 1024,
            isDirectory: false,
            contentMetadata: metadata
        )

        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [file],
            mode: .renameOnly,
            enableSmartRename: true,
            includeContentMetadata: true
        )

        XCTAssertTrue(prompt.contains("[Rename Context]"))
        XCTAssertTrue(prompt.contains("Signed Service Agreement"))
        XCTAssertTrue(prompt.contains("Service Agreement between Acme Co"))
        XCTAssertTrue(prompt.contains("Pages: 8"))
    }
}
