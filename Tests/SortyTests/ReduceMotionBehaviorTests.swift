import XCTest
@testable import SortyLib

final class ReduceMotionBehaviorTests: XCTestCase {
    @MainActor
    func testOnboardingDemoDoesNotRunAnimatedSequenceWithReduceMotion() {
        XCTAssertFalse(SimulatedDemoAnimationView.shouldRunAnimatedDemo(reduceMotion: true))
    }

    @MainActor
    func testOnboardingDemoRunsAnimatedSequenceWithoutReduceMotion() {
        XCTAssertTrue(SimulatedDemoAnimationView.shouldRunAnimatedDemo(reduceMotion: false))
    }
}
