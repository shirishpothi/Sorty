//
//  PromptBuilderTests.swift
//  SortyTests
//
//  Tests for PromptBuilder reference-directory context generation
//

import XCTest
@testable import SortyLib

final class PromptBuilderTests: XCTestCase {
    
    private var tempDir: URL!
    
    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PromptBuilderTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testSystemPromptUsesOneJSONOnlyContract() {
        let prompt = PromptBuilder.buildSystemPrompt(
            personaInfo: "",
            mode: .organizeAndRename,
            enableTagging: true
        )

        XCTAssertTrue(prompt.contains("The first non-whitespace character MUST be \"{\""))
        XCTAssertTrue(prompt.contains("Return exactly one valid JSON object"))
        XCTAssertFalse(prompt.contains(">>"))
        XCTAssertFalse(prompt.contains("```"))
        XCTAssertFalse(prompt.contains("..."), "Schema examples must themselves be valid JSON.")
    }

    func testSystemPromptAllowsApprovedAbsoluteStoragePaths() {
        let prompt = PromptBuilder.buildSystemPrompt(
            personaInfo: "",
            mode: .organize,
            enableTagging: true
        )

        XCTAssertTrue(prompt.contains("when the user prompt provides `VALID_STORAGE_PATHS`"))
        XCTAssertTrue(prompt.contains("one complete folder \"name\" value"))
        XCTAssertTrue(prompt.contains("copy their spelling and capitalization exactly"))
        XCTAssertFalse(prompt.contains("Folder \"name\" values MUST be a single folder name with no \"/\""))
    }

    func testCompactSystemPromptsDoNotRequestNarrationBeforeJSON() {
        let config = AIConfig(mode: .organize)
        let files = [FileItem(path: "/tmp/report.pdf", name: "report", extension: "pdf")]

        for level in [
            PromptBuilder.CompactionLevel.standard,
            .ultra,
            .summary,
            .micro
        ] {
            let prompt = PromptBuilder.promptPair(for: level, config: config, files: files).system
            XCTAssertTrue(prompt.contains("exactly one JSON object"))
            XCTAssertFalse(prompt.contains(">>"))
            XCTAssertFalse(prompt.contains("Before JSON"))
        }
    }

    func testEverySystemPromptDelegatesHierarchyToContextWithoutHiddenFolderCap() {
        let config = AIConfig(mode: .organize)
        let files = [FileItem(path: "/tmp/report.pdf", name: "report", extension: "pdf")]

        let fullPrompt = PromptBuilder.buildSystemPrompt(
            personaInfo: "",
            mode: .organize,
            enableTagging: true
        )
        XCTAssertTrue(fullPrompt.contains("There is no preset target or default maximum"))
        XCTAssertTrue(fullPrompt.contains("Direct instructions for the current task"))
        XCTAssertTrue(fullPrompt.contains("Relevant learned preferences"))
        XCTAssertTrue(fullPrompt.contains("Reference or example folders and the existing folder structure"))
        XCTAssertFalse(fullPrompt.localizedCaseInsensitiveContains("hard limit: you must output"))

        for level in [
            PromptBuilder.CompactionLevel.standard,
            .ultra,
            .summary,
            .micro
        ] {
            let prompt = PromptBuilder.promptPair(for: level, config: config, files: files).system
            XCTAssertTrue(prompt.localizedCaseInsensitiveContains("do not apply a preset folder-count limit"), "Missing hierarchy discretion in \(level)")
            XCTAssertTrue(prompt.localizedCaseInsensitiveContains("direct user instructions"), "Missing user priority in \(level)")
            XCTAssertTrue(prompt.localizedCaseInsensitiveContains("learnings"), "Missing learnings context in \(level)")
            XCTAssertTrue(prompt.localizedCaseInsensitiveContains("existing structure"), "Missing existing-folder context in \(level)")
        }
    }

    func testCustomHierarchyInstructionsArePreservedAsMandatoryRequirements() {
        let instructions = "Create exactly 24 top-level folders and keep the hierarchy flat."
        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [FileItem(path: "/tmp/report.pdf", name: "report", extension: "pdf")],
            customInstructions: instructions
        )

        XCTAssertTrue(prompt.contains("MANDATORY USER REQUIREMENTS"))
        XCTAssertTrue(prompt.contains("USER INSTRUCTIONS: \(instructions)"))
        XCTAssertTrue(prompt.contains("Follow them LITERALLY"))
    }

    func testDirectInstructionsAreDistinguishedFromSupportingOrganizationContext() {
        let directInstructions = "Use no more than four top-level folders."
        let assembledContext = """
        \(PromptBuilder.wrapDirectUserInstructions(directInstructions))

        <learnings_context>
        Prefer detailed project folders.
        </learnings_context>
        """
        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [FileItem(path: "/tmp/report.pdf", name: "report", extension: "pdf")],
            customInstructions: assembledContext
        )

        XCTAssertTrue(prompt.contains("<user_instructions>\n\(directInstructions)\n</user_instructions>"))
        XCTAssertTrue(prompt.contains("Content inside `<user_instructions>` comes directly from the user and has highest priority"))
        XCTAssertTrue(prompt.contains("MUST NOT override direct user or persona instructions"))
    }

    func testFastModePromptOmitsPerFileMetadataAndContent() {
        let file = FileItem(
            path: "/tmp/Reports/quarterly.pdf",
            name: "quarterly",
            extension: "pdf",
            size: 4_096,
            creationDate: Date(timeIntervalSince1970: 1_700_000_000),
            modificationDate: Date(timeIntervalSince1970: 1_710_000_000),
            contentMetadata: ContentMetadata(textPreview: "Confidential revenue details"),
            finderComment: "Finance team review",
            finderTags: ["Important"]
        )

        let prompt = PromptBuilder.buildOrganizationPrompt(
            files: [file],
            includeFileMetadata: false,
            includeContentMetadata: false
        )

        XCTAssertTrue(prompt.contains("quarterly.pdf"))
        XCTAssertTrue(prompt.contains("## FAST MODE"))
        XCTAssertFalse(prompt.contains("created:"))
        XCTAssertFalse(prompt.contains("[Tags]"))
        XCTAssertFalse(prompt.contains("Finance team review"))
        XCTAssertFalse(prompt.contains("Confidential revenue details"))
        XCTAssertFalse(prompt.contains("## FILE METADATA"))
    }
    
    // MARK: - Empty Input
    
    func testEmptyPathsReturnsEmpty() {
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [])
        XCTAssertTrue(result.isEmpty)
    }
    
    func testMissingDirectorySkipped() {
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: ["/nonexistent/path/\(UUID().uuidString)"])
        XCTAssertTrue(result.isEmpty)
    }
    
    // MARK: - Single Directory
    
    func testSingleDirectoryWithSubfolders() throws {
        let sub1 = tempDir.appendingPathComponent("Photos")
        let sub2 = tempDir.appendingPathComponent("Documents")
        try FileManager.default.createDirectory(at: sub1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sub2, withIntermediateDirectories: true)
        
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [tempDir.path])
        
        XCTAssertTrue(result.contains("REFERENCE MODEL DIRECTORIES"))
        XCTAssertTrue(result.contains("Documents"))
        XCTAssertTrue(result.contains("Photos"))
        XCTAssertTrue(result.contains("reference examples only"))
    }
    
    func testSingleDirectoryEmpty() throws {
        // tempDir exists but has no subdirectories
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [tempDir.path])
        XCTAssertTrue(result.isEmpty, "Empty directory should produce empty context")
    }
    
    // MARK: - Multi-Directory
    
    func testMultipleDirectories() throws {
        let dir1 = tempDir.appendingPathComponent("Reference1")
        let dir2 = tempDir.appendingPathComponent("Reference2")
        try FileManager.default.createDirectory(at: dir1.appendingPathComponent("Work"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2.appendingPathComponent("Personal"), withIntermediateDirectories: true)
        
        let result = PromptBuilder.buildReferenceDirectoryContext(paths: [dir1.path, dir2.path])
        
        XCTAssertTrue(result.contains("Reference1"))
        XCTAssertTrue(result.contains("Reference2"))
        XCTAssertTrue(result.contains("Work"))
        XCTAssertTrue(result.contains("Personal"))
    }
    
    // MARK: - Truncation
    
    func testTruncationAtMaxEntries() throws {
        // Create more subfolders than the cap
        let maxEntries = 5
        for i in 0..<10 {
            let sub = tempDir.appendingPathComponent("Folder\(String(format: "%02d", i))")
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        }
        
        let result = PromptBuilder.buildReferenceDirectoryContext(
            paths: [tempDir.path],
            maxEntriesPerDirectory: maxEntries
        )
        
        XCTAssertTrue(result.contains("truncated"))
        // Count the number of "  - " entries
        let entryCount = result.components(separatedBy: "  - ").count - 1
        XCTAssertEqual(entryCount, maxEntries)
    }
    
    // MARK: - Depth Limit
    
    func testDepthLimit() throws {
        let deep = tempDir
            .appendingPathComponent("L1")
            .appendingPathComponent("L2")
            .appendingPathComponent("L3")
            .appendingPathComponent("L4")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        
        // maxDepth=2 should capture L1, L1/L2 but not L1/L2/L3 or deeper
        let result = PromptBuilder.buildReferenceDirectoryContext(
            paths: [tempDir.path],
            maxDepth: 2
        )
        
        XCTAssertTrue(result.contains("L1"))
        XCTAssertTrue(result.contains("L1/L2"))
        XCTAssertFalse(result.contains("L3"))
        XCTAssertFalse(result.contains("L4"))
    }
    
    func testMixedValidAndInvalidPaths() throws {
        let validDir = tempDir.appendingPathComponent("ValidRef")
        try FileManager.default.createDirectory(at: validDir.appendingPathComponent("Projects"), withIntermediateDirectories: true)
        
        let result = PromptBuilder.buildReferenceDirectoryContext(
            paths: ["/nonexistent/\(UUID().uuidString)", validDir.path]
        )
        
        XCTAssertTrue(result.contains("Projects"))
        XCTAssertTrue(result.contains("REFERENCE MODEL DIRECTORIES"))
    }

    func testDirectoryManifestContextIncludesRelativePathsAndExtensionSummary() throws {
        let invoicesDir = tempDir.appendingPathComponent("Invoices")
        try FileManager.default.createDirectory(at: invoicesDir, withIntermediateDirectories: true)

        let invoiceFile = invoicesDir.appendingPathComponent("march.pdf")
        let noteFile = tempDir.appendingPathComponent("notes.txt")
        try Data("pdf".utf8).write(to: invoiceFile)
        try "hello".write(to: noteFile, atomically: true, encoding: .utf8)

        let files = [
            FileItem(path: invoiceFile.path, name: "march", extension: "pdf", size: 3),
            FileItem(path: noteFile.path, name: "notes", extension: "txt", size: 5)
        ]

        let context = PromptBuilder.buildDirectoryManifestContext(
            baseDirectoryURL: tempDir,
            files: files
        )

        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("SOURCE FOLDER CONTEXT") ?? false)
        XCTAssertTrue(context?.contains("Invoices/march.pdf") ?? false)
        XCTAssertTrue(context?.contains("notes.txt") ?? false)
        XCTAssertTrue(context?.contains("pdf:1") ?? false)
        XCTAssertTrue(context?.contains("txt:1") ?? false)
    }

    func testDirectoryManifestContextReturnsNilWhenNoFiles() {
        let context = PromptBuilder.buildDirectoryManifestContext(
            baseDirectoryURL: tempDir,
            files: []
        )

        XCTAssertNil(context)
    }

    func testDirectoryManifestContextTruncatesWhenExceedingMaxEntries() {
        let files = (1...5).map { index in
            FileItem(
                path: tempDir.appendingPathComponent("item\(index).txt").path,
                name: "item\(index)",
                extension: "txt",
                size: 1
            )
        }

        let context = PromptBuilder.buildDirectoryManifestContext(
            baseDirectoryURL: tempDir,
            files: files,
            maxEntries: 3
        )

        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("... and 2 more files in scope") ?? false)
        XCTAssertTrue(context?.contains("item1.txt") ?? false)
        XCTAssertTrue(context?.contains("item3.txt") ?? false)
        XCTAssertFalse(context?.contains("item5.txt") ?? true)
    }

    func testDirectoryManifestContextFallsBackToFilenameOutsideBaseDirectory() {
        let externalFilePath = "/tmp/external-report.pdf"
        let context = PromptBuilder.buildDirectoryManifestContext(
            baseDirectoryURL: tempDir,
            files: [
                FileItem(path: externalFilePath, name: "external-report", extension: "pdf", size: 128)
            ]
        )

        XCTAssertNotNil(context)
        XCTAssertTrue(context?.contains("external-report.pdf") ?? false)
    }
}
