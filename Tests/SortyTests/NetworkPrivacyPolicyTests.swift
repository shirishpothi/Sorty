import XCTest
@testable import SortyLib

final class NetworkPrivacyPolicyTests: XCTestCase {
    private var previousValue: Any?

    override func setUp() {
        super.setUp()
        previousValue = UserDefaults.standard.object(forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
        UserDefaults.standard.removeObject(forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
    }

    override func tearDown() {
        if let previousValue {
            UserDefaults.standard.set(previousValue, forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
        } else {
            UserDefaults.standard.removeObject(forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
        }
        super.tearDown()
    }

    func testInternetPrivacyModeDefaultsToDisabledWhenUnset() {
        UserDefaults.standard.removeObject(forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)
        XCTAssertFalse(NetworkPrivacyPolicy.isInternetPrivacyModeEnabled)
    }

    func testAllRequestsAllowedWhenPrivacyModeDisabled() {
        UserDefaults.standard.set(false, forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)

        let remote = URL(string: "https://api.openai.com/v1/models")!
        let localhost = URL(string: "http://localhost:11434/api/tags")!

        XCTAssertTrue(NetworkPrivacyPolicy.isRequestAllowed(url: remote))
        XCTAssertTrue(NetworkPrivacyPolicy.isRequestAllowed(url: localhost))
    }

    func testOnlyLoopbackAllowedWhenPrivacyModeEnabled() {
        UserDefaults.standard.set(true, forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)

        let localhost = URL(string: "http://localhost:11434/api/tags")!
        let loopbackV4 = URL(string: "http://127.0.0.1:11434/api/tags")!
        let loopbackV4Alt = URL(string: "http://127.0.0.2:11434/api/tags")!
        let loopbackV6 = URL(string: "http://[::1]:11434/api/tags")!
        let loopbackV6Expanded = URL(string: "http://[0:0:0:0:0:0:0:1]:11434/api/tags")!
        let remote = URL(string: "https://api.openai.com/v1/models")!
        let nonLoopbackV4 = URL(string: "http://126.0.0.1:11434/api/tags")!

        XCTAssertTrue(NetworkPrivacyPolicy.isRequestAllowed(url: localhost))
        XCTAssertTrue(NetworkPrivacyPolicy.isRequestAllowed(url: loopbackV4))
        XCTAssertTrue(NetworkPrivacyPolicy.isRequestAllowed(url: loopbackV4Alt))
        XCTAssertTrue(NetworkPrivacyPolicy.isRequestAllowed(url: loopbackV6))
        XCTAssertTrue(NetworkPrivacyPolicy.isRequestAllowed(url: loopbackV6Expanded))
        XCTAssertFalse(NetworkPrivacyPolicy.isRequestAllowed(url: nonLoopbackV4))
        XCTAssertFalse(NetworkPrivacyPolicy.isRequestAllowed(url: remote))
    }

    func testAIRequestSupportBlocksRemoteRequestsWhenPrivacyModeEnabled() throws {
        UserDefaults.standard.set(true, forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)

        let remote = URL(string: "https://api.openai.com/v1/models")!

        XCTAssertThrowsError(try AIRequestSupport.makeJSONRequest(url: remote, method: "GET")) { error in
            guard case AIClientError.apiError(let statusCode, _) = error else {
                XCTFail("Expected apiError for privacy mode block, got: \(error)")
                return
            }
            XCTAssertEqual(statusCode, 403)
        }
    }

    func testAIRequestSupportAllowsLoopbackRequestsWhenPrivacyModeEnabled() throws {
        UserDefaults.standard.set(true, forKey: NetworkPrivacyPolicy.internetPrivacyModeKey)

        let local = URL(string: "http://localhost:11434/api/tags")!

        XCTAssertNoThrow(try AIRequestSupport.makeJSONRequest(url: local, method: "GET"))
    }
}