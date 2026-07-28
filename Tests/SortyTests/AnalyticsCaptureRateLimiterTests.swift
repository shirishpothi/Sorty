import XCTest
@testable import SortyLib

final class AnalyticsCaptureRateLimiterTests: XCTestCase {
    func testLimitsEventsWithinOneMinute() {
        var limiter = AnalyticsCaptureRateLimiter()

        for _ in 0..<120 {
            XCTAssertTrue(limiter.shouldCapture(now: 10))
        }
        XCTAssertFalse(limiter.shouldCapture(now: 10))
    }

    func testAllowsEventsAfterMinuteWindowResets() {
        var limiter = AnalyticsCaptureRateLimiter()

        for _ in 0..<120 {
            XCTAssertTrue(limiter.shouldCapture(now: 10))
        }
        XCTAssertTrue(limiter.shouldCapture(now: 70))
    }

    func testResetClearsLimits() {
        var limiter = AnalyticsCaptureRateLimiter()

        for _ in 0..<120 {
            XCTAssertTrue(limiter.shouldCapture(now: 10))
        }
        limiter.reset()

        XCTAssertTrue(limiter.shouldCapture(now: 10))
    }
}
