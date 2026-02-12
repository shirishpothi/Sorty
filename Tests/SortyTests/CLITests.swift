//
//  CLITests.swift
//  SortyTests
//
//  Tests for CLI tools: sorty script and learnings CLI
//  These tests verify deeplink handling that maps to CLI commands
//

import Foundation
import XCTest
@testable import SortyLib

final class CLITests: XCTestCase {
    private var tempDirectory: URL!
    private var sortyScriptPath: String!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SortyCLITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        sortyScriptPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("CLI/sorty")
            .path
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: sortyScriptPath), "CLI/sorty must exist and be executable")
    }
    
    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        sortyScriptPath = nil
        try super.tearDownWithError()
    }
    
    // MARK: - sorty Script Tests
    
    func testSortyOrganizeEmitsExpectedURL() throws {
        let testFolder = tempDirectory.appendingPathComponent("Folder With Spaces")
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)
        
        let result = try runSorty(["organize", testFolder.path, "--auto", "--persona", "developer"])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(
            result.stdout,
            deeplinkURL(
                host: "organize",
                queryItems: [
                    ("autostart", "true"),
                    ("path", try canonicalPath(testFolder.path)),
                    ("persona", "developer")
                ]
            )
        )
        XCTAssertTrue(result.stderr.isEmpty)
    }
    
    func testSortyOrganizeMissingPathFails() throws {
        let result = try runSorty(["organize", "--auto"])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.contains("Missing required path"))
        XCTAssertFalse(result.stderr.contains("sorty://"))
    }
    
    func testSortyInvalidPathFails() throws {
        let missingPath = tempDirectory.appendingPathComponent("does-not-exist").path
        let result = try runSorty(["duplicates", missingPath])
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.stdout.isEmpty)
        XCTAssertTrue(result.stderr.contains("Directory does not exist"))
    }
    
    func testSortyHelpDoesNotEmitDeeplink() throws {
        let result = try runSorty(["help"])
        XCTAssertEqual(result.status, 0)
        XCTAssertTrue(result.stdout.contains("Sorty CLI"))
        XCTAssertFalse(result.stdout.contains("sorty://"))
        XCTAssertTrue(result.stderr.isEmpty)
    }
    
    func testSortyRulesAddEncodesPattern() throws {
        let pattern = "*.tmp files"
        let result = try runSorty(["rules", "add", pattern])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(
            result.stdout,
            deeplinkURL(
                host: "exclusions",
                queryItems: [
                    ("action", "add"),
                    ("pattern", pattern)
                ]
            )
        )
        XCTAssertTrue(result.stderr.isEmpty)
    }
    
    // MARK: - Deeplink Handler CLI Command Mapping Tests
    
    @MainActor
    func testDeeplinkHandlerParsesStatusCommand() throws {
        // CLI "status" command maps to health deeplink
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://health")!
        
        handler.handle(url: url)
        
        if case .health = handler.pendingDestination {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .health destination")
        }
        
        handler.clearPending()
    }
    
    @MainActor
    func testDeeplinkHandlerParsesListCommand() throws {
        // CLI "list" command maps to watched deeplink
        let handler = DeeplinkHandler.shared
        let url = URL(string: "sorty://watched")!
        
        handler.handle(url: url)
        
        if case .watched = handler.pendingDestination {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected .watched destination")
        }
        
        handler.clearPending()
    }
    
    private func runSorty(_ arguments: [String]) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [sortyScriptPath] + arguments
        
        var env = ProcessInfo.processInfo.environment
        env["SORTY_CLI_DRY_RUN"] = "1"
        process.environment = env
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        process.waitUntilExit()
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        
        let stdout = String(data: stdoutData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        return (process.terminationStatus, stdout, stderr)
    }
    
    private func deeplinkURL(host: String, queryItems: [(String, String)]) -> String {
        if queryItems.isEmpty {
            return "sorty://\(host)"
        }
        
        let query = queryItems
            .map { key, value in "\(key)=\(encodeQueryValue(value))" }
            .joined(separator: "&")
        return "sorty://\(host)?\(query)"
    }
    
    private func encodeQueryValue(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
    
    private func canonicalPath(_ path: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-c", "import os, sys; print(os.path.realpath(sys.argv[1]))", path]
        
        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "CLITests", code: Int(process.terminationStatus))
        }
        
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? path
    }
}
