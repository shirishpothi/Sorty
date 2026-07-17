import Foundation
import XCTest
@testable import SortyLib

final class SparkleTrafficLightSkipStoreTests: XCTestCase {
    func testSkippedVersionsRemainScopedToTheSelectedVersion() throws {
        let suiteName = "test.sparkle-traffic-light-skip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SparkleTrafficLightSkipStore(userDefaults: defaults)

        store.markSkipped(version: "100")

        XCTAssertTrue(store.contains(version: "100"))
        XCTAssertFalse(store.contains(version: "101"))
    }

    func testClearingOneSkippedVersionPreservesOtherVersions() throws {
        let suiteName = "test.sparkle-traffic-light-skip.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SparkleTrafficLightSkipStore(userDefaults: defaults)

        store.markSkipped(version: "100")
        store.markSkipped(version: "101")
        store.clearSkipped(version: "100")

        XCTAssertFalse(store.contains(version: "100"))
        XCTAssertTrue(store.contains(version: "101"))
    }
}
