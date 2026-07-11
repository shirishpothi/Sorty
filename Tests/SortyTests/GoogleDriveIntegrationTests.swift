import XCTest
@testable import SortyLib

final class GoogleDriveIntegrationTests: XCTestCase {
    private actor RequestRecorder {
        private(set) var requests: [URLRequest] = []

        func record(_ request: URLRequest) {
            requests.append(request)
        }

        func lastRequest() -> URLRequest? {
            requests.last
        }
    }

    private struct MockTransport: ProviderHTTPTransport {
        let recorder: RequestRecorder

        func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            await recorder.record(request)
            let body = Data(#"{"id":"file-123","name":"Report","starred":true,"parents":["folder-2"]}"#.utf8)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        }
    }

    func testSetStarredUsesMetadataPatchAndSharedDriveSupport() async throws {
        let recorder = RequestRecorder()
        let integration = GoogleDriveIntegration(
            accessToken: "secret-token",
            transport: MockTransport(recorder: recorder)
        )

        let item = try await integration.setStarred(true, fileID: "file-123")

        let recordedRequest = await recorder.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        XCTAssertEqual(request.httpMethod, "PATCH")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertTrue(request.url?.absoluteString.contains("supportsAllDrives=true") == true)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Bool])
        XCTAssertEqual(json["starred"], true)
        XCTAssertEqual(item.starred, true)
    }

    func testMoveUsesSingleParentPatch() async throws {
        let recorder = RequestRecorder()
        let integration = GoogleDriveIntegration(
            accessToken: "secret-token",
            transport: MockTransport(recorder: recorder)
        )

        _ = try await integration.moveItem(
            fileID: "file-123",
            fromParentID: "folder-1",
            toParentID: "folder-2"
        )

        let recordedRequest = await recorder.lastRequest()
        let request = try XCTUnwrap(recordedRequest)
        let components = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["addParents"], "folder-2")
        XCTAssertEqual(query["removeParents"], "folder-1")
        XCTAssertEqual(query["supportsAllDrives"], "true")
    }
}
