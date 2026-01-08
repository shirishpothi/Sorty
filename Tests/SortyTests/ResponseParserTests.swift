
import XCTest
@testable import SortyLib

class ResponseParserTests: XCTestCase {
    
    func testValidJSONParsing() throws {
        let json = """
        {
          "folders": [
            {
              "name": "Images",
              "description": "Photo files",
              "reasoning": "Detected image extensions",
              "files": ["vacation.jpg", "profile.png"]
            }
          ],
          "notes": "Organized by file type"
        }
        """
        
        let files = [
            FileItem(path: "/path/vacation.jpg", name: "vacation", extension: "jpg", size: 100, isDirectory: false),
            FileItem(path: "/path/profile.png", name: "profile", extension: "png", size: 200, isDirectory: false),
            FileItem(path: "/path/notes.txt", name: "notes", extension: "txt", size: 50, isDirectory: false)
        ]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        XCTAssertEqual(plan.suggestions.count, 1)
        XCTAssertEqual(plan.suggestions.first?.folderName, "Images")
        XCTAssertEqual(plan.suggestions.first?.files.count, 2)
        XCTAssertEqual(plan.notes, "Organized by file type")
    }
    
    func testMarkdownWrappedJSONParsing() throws {
        let json = """
        ```json
        {
          "folders": [
            {
              "name": "Docs",
              "files": ["report.pdf"]
            }
          ]
        }
        ```
        """
        
        let files = [FileItem(path: "/path/report.pdf", name: "report", extension: "pdf", size: 100, isDirectory: false)]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        XCTAssertEqual(plan.suggestions.count, 1)
        XCTAssertEqual(plan.suggestions.first?.folderName, "Docs")
    }
    
    func testUnorganizedFilesParsing() throws {
        let json = """
        {
          "folders": [],
          "unorganized": [
            {
              "filename": "unknown.xyz",
              "reason": "Unknown file type"
            }
          ]
        }
        """
        
        let files = [FileItem(path: "/path/unknown.xyz", name: "unknown", extension: "xyz", size: 100, isDirectory: false)]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        XCTAssertEqual(plan.unorganizedDetails.count, 1)
        XCTAssertEqual(plan.unorganizedDetails.first?.filename, "unknown.xyz")
        XCTAssertEqual(plan.unorganizedFiles.count, 1)
    }


    func testParsingWithTags() throws {
        let json = """
        {
          "folders": [
            {
              "name": "TaggedDocs",
              "files": [
                {
                  "filename": "invoice.pdf",
                  "tags": ["Finance", "2024"]
                }
              ]
            }
          ]
        }
        """
        
        let files = [
            FileItem(path: "/path/invoice.pdf", name: "invoice", extension: "pdf", size: 100, isDirectory: false)
        ]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        XCTAssertEqual(plan.suggestions.count, 1)
        let suggestion = plan.suggestions.first!
        XCTAssertEqual(suggestion.folderName, "TaggedDocs")
        
        // Check tags
        let tags = suggestion.tags(for: files[0])
        XCTAssertEqual(tags.count, 2)
        XCTAssertTrue(tags.contains("Finance"))
        XCTAssertTrue(tags.contains("2024"))
    }


    func testParsingWithFileRenameSuggestions() throws {
        let json = """
        {
          "folders": [
            {
              "name": "Documents",
              "files": [
                {
                  "filename": "old_name.pdf",
                  "suggested_name": "Invoice_2024_Jan.pdf",
                  "rename_reason": "More descriptive name with date"
                }
              ]
            }
          ]
        }
        """
        
        let files = [
            FileItem(path: "/path/old_name.pdf", name: "old_name", extension: "pdf", size: 1000, isDirectory: false)
        ]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        XCTAssertEqual(plan.suggestions.count, 1)
        let suggestion = plan.suggestions.first!
        
        // Check rename mapping
        XCTAssertEqual(suggestion.fileRenameMappings.count, 1)
        let mapping = suggestion.fileRenameMappings.first!
        XCTAssertEqual(mapping.suggestedName, "Invoice_2024_Jan.pdf")
        XCTAssertEqual(mapping.renameReason, "More descriptive name with date")
    }
    
    func testParsingWithMultipleTagsPerFile() throws {
        let json = """
        {
          "folders": [
            {
              "name": "Projects",
              "files": [
                {
                  "filename": "project.pdf",
                  "tags": ["Work", "Important", "2024", "Q1"]
                }
              ]
            }
          ]
        }
        """
        
        let files = [
            FileItem(path: "/path/project.pdf", name: "project", extension: "pdf", size: 500, isDirectory: false)
        ]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        let tags = plan.suggestions.first!.tags(for: files[0])
        XCTAssertEqual(tags.count, 4)
        XCTAssertTrue(tags.contains("Work"))
        XCTAssertTrue(tags.contains("Important"))
        XCTAssertTrue(tags.contains("2024"))
        XCTAssertTrue(tags.contains("Q1"))
    }
    
    func testParsingWithBothRenameAndTags() throws {
        let json = """
        {
          "folders": [
            {
              "name": "Finances",
              "files": [
                {
                  "filename": "scan.pdf",
                  "suggested_name": "Receipt_Amazon_2024-01.pdf",
                  "rename_reason": "Descriptive name",
                  "tags": ["Receipt", "Amazon", "2024"]
                }
              ]
            }
          ]
        }
        """
        
        let files = [
            FileItem(path: "/path/scan.pdf", name: "scan", extension: "pdf", size: 800, isDirectory: false)
        ]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        let suggestion = plan.suggestions.first!
        
        // Check rename
        XCTAssertEqual(suggestion.fileRenameMappings.count, 1)
        XCTAssertEqual(suggestion.fileRenameMappings.first?.suggestedName, "Receipt_Amazon_2024-01.pdf")
        
        // Check tags
        let tags = suggestion.tags(for: files[0])
        XCTAssertEqual(tags.count, 3)
        XCTAssertTrue(tags.contains("Receipt"))
    }
    
    func testParsingFilesWithoutTags() throws {
        let json = """
        {
          "folders": [
            {
              "name": "NoTags",
              "files": ["simple.txt"]
            }
          ]
        }
        """
        
        let files = [
            FileItem(path: "/path/simple.txt", name: "simple", extension: "txt", size: 100, isDirectory: false)
        ]
        
        let plan = try ResponseParser.parseResponse(json, originalFiles: files)
        
        let tags = plan.suggestions.first!.tags(for: files[0])
        XCTAssertTrue(tags.isEmpty)
    }
}
