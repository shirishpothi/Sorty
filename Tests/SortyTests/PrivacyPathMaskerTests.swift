import XCTest
@testable import SortyLib

final class PrivacyPathMaskerTests: XCTestCase {

    func testExtractsUsernameFromUsersDirectoryPath() {
        let path = "/Users/shirishpothi/Downloads/AyuGram Desktop"

        let segments = PrivacyPathMasker.userPathSegments(in: path, currentUsername: "ignored-user")

        XCTAssertEqual(segments?.leading, "/Users/")
        XCTAssertEqual(segments?.username, "shirishpothi")
        XCTAssertEqual(segments?.trailing, "/Downloads/AyuGram Desktop")
    }

    func testExtractsUsernameFromUsersDirectoryPathCaseInsensitive() {
        let path = "/users/John/Documents"

        let segments = PrivacyPathMasker.userPathSegments(in: path, currentUsername: "ignored-user")

        XCTAssertEqual(segments?.leading, "/users/")
        XCTAssertEqual(segments?.username, "John")
        XCTAssertEqual(segments?.trailing, "/Documents")
    }

    func testExtractsCurrentUsernameFromNonUsersPathSegment() {
        let path = "/home/shirishpothi/Documents"

        let segments = PrivacyPathMasker.userPathSegments(in: path, currentUsername: "shirishpothi")

        XCTAssertEqual(segments?.leading, "/home/")
        XCTAssertEqual(segments?.username, "shirishpothi")
        XCTAssertEqual(segments?.trailing, "/Documents")
    }

    func testDoesNotMaskUsernameInsideLargerSegment() {
        let path = "/tmp/shirishpothi_backup/files"

        let segments = PrivacyPathMasker.userPathSegments(in: path, currentUsername: "shirishpothi")

        XCTAssertNil(segments)
    }

    func testRedactedPathReplacesUsernameSegment() {
        let path = "/Users/shirishpothi/Downloads/AyuGram Desktop"

        let redacted = PrivacyPathMasker.redactedPath(path)

        XCTAssertEqual(redacted, "/Users/[REDACTED_USER]/Downloads/AyuGram Desktop")
    }
}
