import XCTest
@testable import SortyLib

final class ReferenceDirectoryScannerTests: XCTestCase {
    func testScanSkipsOfflineCloudPlaceholders() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ReferenceDirectoryCloudScan-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "local".write(
            to: directory.appendingPathComponent("example.txt"),
            atomically: true,
            encoding: .utf8
        )
        try Data().write(to: directory.appendingPathComponent("offline.cloud"))

        let snapshot = try await ReferenceDirectoryScanner.scan(url: directory)

        XCTAssertEqual(snapshot.totalFileCount, 1)
    }

    func testScanRejectsUnavailableDirectory() async {
        let missingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "MissingReferenceDirectory-\(UUID().uuidString)",
            isDirectory: true
        )

        do {
            _ = try await ReferenceDirectoryScanner.scan(url: missingDirectory)
            XCTFail("Expected unavailable directory scan to fail")
        } catch let error as ReferenceDirectoryScanError {
            guard case .unavailable = error else {
                return XCTFail("Expected unavailable, got \(error)")
            }
        } catch {
            XCTFail("Expected ReferenceDirectoryScanError, got \(error)")
        }
    }
}
