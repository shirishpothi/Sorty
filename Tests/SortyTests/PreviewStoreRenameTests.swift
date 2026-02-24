import XCTest
@testable import SortyLib

@MainActor
final class PreviewStoreRenameTests: XCTestCase {

    private func makeFile(_ name: String, ext: String = "txt", folder: String = "/tmp") -> FileItem {
        FileItem(
            path: "\(folder)/\(name).\(ext)",
            name: name,
            extension: ext,
            size: 100,
            isDirectory: false
        )
    }

    func testUpdateRenameSanitizesAndPersists() {
        let file = makeFile("draft")
        let folder = FolderSuggestion(folderName: "Docs", files: [file])
        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")
        let store = PreviewStore(plan: plan)

        let success = store.updateRename(fileID: file.id, folderID: folder.id, newName: "  final:name.pdf  ")
        XCTAssertTrue(success)

        let mapping = store.plan.suggestions[0].renameMapping(for: file)
        XCTAssertEqual(mapping?.suggestedName, "final-name.txt")
    }

    func testUpdateRenameRejectsConflictingFilename() {
        let fileA = makeFile("a")
        let fileB = makeFile("b")
        var folder = FolderSuggestion(folderName: "Docs", files: [fileA, fileB])
        folder.updateRename(for: fileA, newName: "invoice.txt")
        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")
        let store = PreviewStore(plan: plan)

        let success = store.updateRename(fileID: fileB.id, folderID: folder.id, newName: "invoice.txt")
        XCTAssertFalse(success)
    }

    func testUpdateRenameNoOpDoesNotCreateMapping() {
        let file = makeFile("notes")
        let folder = FolderSuggestion(folderName: "Docs", files: [file])
        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")
        let store = PreviewStore(plan: plan)

        let success = store.updateRename(fileID: file.id, folderID: folder.id, newName: "notes.txt")
        XCTAssertFalse(success)
        XCTAssertNil(store.plan.suggestions[0].renameMapping(for: file))
    }

    func testRejectRenameClearsSuggestion() {
        let file = makeFile("draft")
        var folder = FolderSuggestion(folderName: "Docs", files: [file])
        folder.updateRename(for: file, newName: "final.txt", reason: "Cleaner")
        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")
        let store = PreviewStore(plan: plan)

        store.rejectRename(fileID: file.id, folderID: folder.id)

        let mapping = store.plan.suggestions[0].renameMapping(for: file)
        XCTAssertNotNil(mapping)
        XCTAssertFalse(mapping?.hasRename ?? true)
        XCTAssertNil(mapping?.suggestedName)
    }

    func testAcceptAllAndRejectAllRenames() {
        let fileA = makeFile("draft_a")
        let fileB = makeFile("draft_b")
        var folder = FolderSuggestion(folderName: "Docs", files: [fileA, fileB])
        folder.updateRename(for: fileA, newName: "final_a.txt", reason: "A")
        folder.updateRename(for: fileB, newName: "final_b.txt", reason: "B")
        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")
        let store = PreviewStore(plan: plan)

        store.rejectAllRenames()
        XCTAssertFalse(store.plan.suggestions[0].renameMapping(for: fileA)?.hasRename ?? true)
        XCTAssertFalse(store.plan.suggestions[0].renameMapping(for: fileB)?.hasRename ?? true)

        store.acceptAllRenames()
        XCTAssertEqual(store.plan.suggestions[0].renameMapping(for: fileA)?.suggestedName, "final_a.txt")
        XCTAssertEqual(store.plan.suggestions[0].renameMapping(for: fileB)?.suggestedName, "final_b.txt")
    }

    func testRenameSummaryIncludesLowConfidenceSkip() {
        let file = makeFile("image", ext: "jpg")
        let mapping = FileRenameMapping(
            originalFile: file,
            suggestedName: nil,
            renameReason: "AI unsure",
            renameConfidence: 0.2
        )
        let folder = FolderSuggestion(folderName: "Photos", files: [file], fileRenameMappings: [mapping])
        let plan = OrganizationPlan(suggestions: [folder], unorganizedFiles: [], notes: "")
        let store = PreviewStore(plan: plan)

        let entries = store.renameSummaryEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].isLowConfidenceSkip)
        XCTAssertEqual(entries[0].newName, file.displayName)
    }
}
